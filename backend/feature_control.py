"""Platform subscription policy and tenant-scoped expense reporting."""
import csv
from decimal import Decimal
from io import StringIO

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel, StrictBool
from sqlalchemy import Boolean, String, func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Mapped, Session, mapped_column

from main import Base, User, current, db, role
from platform_api import AdminUser, _audit, _requires_admin
from trial_api import state as subscription_state
from v2_api import Expense

router = APIRouter(prefix='/api', tags=['Feature Control'])
FEATURES = {
    'expense_analysis': ('Expense analysis', 'free', True, True),
    'expense_csv': ('Expense CSV export', 'paid', True, True),
    'payment_gateway': ('Payment gateway', 'paid', False, False),
}


class FeaturePolicy(Base):
    __tablename__ = 'platform_feature_policy'
    key: Mapped[str] = mapped_column(String(40), primary_key=True)
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False)


class FeatureUpdate(BaseModel):
    enabled: StrictBool


def feature_catalog(session: Session):
    overrides = {policy.key: policy.enabled for policy in session.scalars(select(FeaturePolicy))}
    return [
        dict(key=key, label=label, access=access, available=available,
             enabled=True if access == 'free' else overrides.get(key, default))
        for key, (label, access, default, available) in FEATURES.items()
    ]


def tenant_features(session: Session, user: User):
    status = subscription_state(session, user.tenant_id)['status']
    return {
        'subscription_status': status,
        'features': [
            dict(feature, allowed=feature['available'] and feature['enabled']
                 and (feature['access'] == 'free' or status == 'paid'))
            for feature in feature_catalog(session)
        ],
    }


@router.get('/platform/feature-controls')
def get_controls(admin: AdminUser = Depends(_requires_admin), session: Session = Depends(db)):
    return feature_catalog(session)


@router.put('/platform/feature-controls/{key}')
def set_control(key: str, change: FeatureUpdate, admin: AdminUser = Depends(_requires_admin),
                session: Session = Depends(db)):
    if key not in FEATURES:
        raise HTTPException(404, 'Unknown feature')
    if FEATURES[key][1] == 'free':
        raise HTTPException(409, 'Expense analysis is always included')
    setting = update(FeaturePolicy).where(FeaturePolicy.key == key).values(enabled=change.enabled)
    if not session.execute(setting).rowcount:
        try:
            with session.begin_nested():
                session.add(FeaturePolicy(key=key, enabled=change.enabled))
                session.flush()
        except IntegrityError:
            # Another administrator created this policy while the request was running.
            if not session.execute(setting).rowcount:
                raise
    _audit(session, admin, 'update_feature_policy', f'{key}:{"enabled" if change.enabled else "disabled"}')
    session.commit()
    return feature_catalog(session)


@router.get('/owner-features')
def owner_features(user: User = Depends(current), session: Session = Depends(db)):
    role(user, 'owner', 'manager')
    return tenant_features(session, user)


def expense_categories(session: Session, tenant_id: int, period: str):
    query = (select(Expense.category, func.sum(Expense.amount), func.count(Expense.id))
             .where(Expense.tenant_id == tenant_id, Expense.period == period)
             .group_by(Expense.category)
             .order_by(func.sum(Expense.amount).desc(), Expense.category.asc()))
    return [{'category': category, 'amount': f'{amount:.2f}', 'entries': count}
            for category, amount, count in session.execute(query)]


def check_period(period: str):
    from re import fullmatch
    if not fullmatch(r'[0-9]{4}-(0[1-9]|1[0-2])', period):
        raise HTTPException(422, 'Select a valid month')


@router.get('/expense-analysis')
def expense_analysis(period: str, user: User = Depends(current), session: Session = Depends(db)):
    role(user, 'owner', 'manager')
    check_period(period)
    categories = expense_categories(session, user.tenant_id, period)
    total = sum((Decimal(row['amount']) for row in categories), Decimal(0))
    return {'period': period, 'categories': categories, 'total': f'{total:.2f}'}


@router.get('/expense-analysis/export')
def export_expenses(period: str, user: User = Depends(current), session: Session = Depends(db)):
    role(user, 'owner', 'manager')
    check_period(period)
    export = next(feature for feature in tenant_features(session, user)['features']
                  if feature['key'] == 'expense_csv')
    if not export['allowed']:
        raise HTTPException(403, 'Expense CSV export requires an active subscription and administrator access')
    output = StringIO()
    writer = csv.writer(output)
    writer.writerow(['Category', 'Amount (INR)', 'Entries'])
    for row in expense_categories(session, user.tenant_id, period):
        category = row['category']
        if category.lstrip().startswith(('=', '+', '-', '@')) or category.startswith(('\t', '\r', '\n')):
            category = "'" + category
        writer.writerow([category, row['amount'], row['entries']])
    return Response(output.getvalue(), media_type='text/csv', headers={
        'Content-Disposition': f'attachment; filename="expenses-{period}.csv"',
        'Cache-Control': 'private, no-store',
    })

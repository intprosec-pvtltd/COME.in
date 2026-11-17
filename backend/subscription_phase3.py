"""Phase 3 verified-payment reconciliation and one-bill-per-period guard.

Only the existing platform administrator review can activate a paid entitlement.
The activation journal and Subscription status are committed atomically in the
existing SQLAlchemy database, with idempotent retry after QR-ledger approval.
"""
from datetime import date, datetime, timezone
from calendar import monthrange
from fastapi import HTTPException
from sqlalchemy import ForeignKey, String, DateTime, UniqueConstraint, select
from sqlalchemy.orm import Mapped, mapped_column
from main import Base, SessionLocal, engine
from platform_api import Subscription, SubscriptionInvoice, _subscription, _tenant
from trial_api import OrganizationTrial

class VerifiedSubscriptionActivation(Base):
    __tablename__ = 'ss_verified_activations'
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    tenant_id: Mapped[int] = mapped_column(ForeignKey('tenants.id'), nullable=False, index=True)
    invoice_id: Mapped[str] = mapped_column(String(64), nullable=False, unique=True)
    period: Mapped[str] = mapped_column(String(7), nullable=False)
    paid_until: Mapped[str] = mapped_column(String(10), nullable=False)
    activated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    admin_id: Mapped[int] = mapped_column(nullable=False)
    __table_args__ = (UniqueConstraint('tenant_id', 'period', name='uq_ss_verified_tenant_period'),)

def prepare_schema():
    Base.metadata.create_all(engine, tables=[VerifiedSubscriptionActivation.__table__])

def active_paid_until(session, tenant_id):
    rows = session.scalars(select(VerifiedSubscriptionActivation.paid_until).where(
        VerifiedSubscriptionActivation.tenant_id==int(tenant_id))).all()
    return max(rows) if rows else None

def legacy_invoice_exists(owner_id,period):
    with SessionLocal() as s:
        return s.scalar(select(SubscriptionInvoice.id).where(
            SubscriptionInvoice.tenant_id==int(owner_id),
            SubscriptionInvoice.period==period).limit(1)) is not None

def activate_verified_payment(payment, admin_id):
    """Idempotent. Payment must already be approved in QR ledger by a real admin.

    A failed SQLAlchemy commit leaves the QR approval eligible for retry;
    invoice is marked paid but subscription is not reported activated.
    """
    if payment.get('status')!='approved' or not payment.get('bank_verified'):
        raise ValueError('Independent bank verification required')
    owner_id=int(payment['owner_id'])
    period=payment['period']
    if not isinstance(period,str) or not __import__('re').fullmatch(r'\d{4}-(0[1-9]|1[0-2])',period):
        raise ValueError('Invalid billing period')
    paid_until=date(int(period[:4]),int(period[5:]),monthrange(int(period[:4]),int(period[5:]))[1]).isoformat()
    with SessionLocal() as s:
        existing=s.get(VerifiedSubscriptionActivation,payment['id'])
        if existing:
            return {'status':'activated','paid_until':existing.paid_until,'already_applied':True}
        if legacy_invoice_exists(owner_id,period):
            raise ValueError('Legacy invoice exists for same owner and period; reconciliation required')
        _tenant(s,owner_id)
        other=s.scalar(select(VerifiedSubscriptionActivation).where(
            VerifiedSubscriptionActivation.tenant_id==owner_id,
            VerifiedSubscriptionActivation.period==period))
        if other:
            raise ValueError('This owner and billing period already has an activation')
        trial=s.get(OrganizationTrial,owner_id)
        if trial is not None and trial.status=='suspended':
            raise ValueError('Suspended organization requires separate administrator review')
        sub=_subscription(s,owner_id)
        sub.status='active'
        if trial is not None:
            trial.status='paid'
        s.add(VerifiedSubscriptionActivation(
            id=payment['id'],invoice_id=payment['invoice_id'],tenant_id=owner_id,
            period=period,paid_until=paid_until,activated_at=datetime.now(timezone.utc),
            admin_id=int(admin_id)))
        s.commit()
    return {'status':'activated','paid_until':paid_until,'already_applied':False}

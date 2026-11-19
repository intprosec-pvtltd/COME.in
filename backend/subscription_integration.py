"""Bound adapters for the existing Stay Sync / COME.in authentication domains.
Only mount when both platform and mobile authentication have been verified.
Separate SQLite ledger in Phase 2; legacy billing/trial records remain untouched.
"""
import os
from pathlib import Path
from fastapi import Depends, Header, HTTPException, Request
from sqlalchemy.orm import Session
from main import app, db, current, SessionLocal, User, engine
from platform_api import _requires_admin, _owner_counts, _tenant
from staysync_subscriptions import BillingStore, create_router
from subscription_phase3 import prepare_schema, legacy_invoice_exists, activate_verified_payment
from platform_api import SubscriptionInvoice
from sqlalchemy import select
from decimal import Decimal


def subscription_principal(request: Request, authorization: str | None = Header(default=None), session: Session = Depends(db)):
    if not authorization or not authorization.startswith('Bearer '):
        raise HTTPException(401, 'Sign in required')
    # Each validator performs signature, expiry and account-status checks.
    try:
        admin = _requires_admin(authorization=authorization, session=session)
    except HTTPException as exc:
        if exc.status_code not in (401, 503):
            raise
    else:
        return {'id': str(admin.id), 'role': 'platform_admin'}

    # Falls back to the existing owner JWT validator. Wrong-scope tokens
    # never grant owner privileges; current() verifies the token fully.
    user = current(request=request, authorization=authorization, session=session)
    if not isinstance(user, User) or user.role != 'owner':
        raise HTTPException(403, 'PG owner access required')
    return {'id': str(user.id), 'role': 'owner', 'owner_id': str(user.tenant_id)}


def subscription_counts(owner_id: str):
    with SessionLocal() as session:
        tenant = _tenant(session, int(owner_id))
        counts = _owner_counts(session, tenant)
        # Existing platform billing policy excludes explicitly exempt
        # residents. These are billable registered residents, not live
        # occupancy/punch-in measurements.
        return int(counts['total_beds']), int(counts['billable_residents'])


def legacy_owner_invoice(owner_id: str):
    # Read-only: the historical platform invoice remains the authoritative bill.
    with SessionLocal() as session:
        record = session.scalar(select(SubscriptionInvoice).where(
            SubscriptionInvoice.tenant_id == int(owner_id)).order_by(
            SubscriptionInvoice.period.desc(), SubscriptionInvoice.id.desc()).limit(1))
        if record is None:
            return None
        cents = int((Decimal(str(record.subtotal)) * 100).quantize(Decimal('1')))
        return {'id':record.id,'period':record.period,'status':record.status,
                'amount_cents':cents,'residents':record.billable_residents,
                'payment_reference':record.payment_reference or ''}


def mount_subscription_router():
    base = Path(os.getenv('STAYSYNC_SUBSCRIPTION_MEDIA_DIR', './subscription_media'))
    db_path = os.getenv('STAYSYNC_SUBSCRIPTION_DB', './staysync_subscriptions.db')
    prepare_schema()
    store = BillingStore(db_path=db_path, media_dir=str(base))
    store.attach_durable_qr(engine)  # persists across deployments if DATABASE_URL is persistent
    app.include_router(create_router(store, subscription_principal, subscription_counts,
                                     legacy_guard=legacy_invoice_exists,
                                     activate_payment=activate_verified_payment,
                                     legacy_invoice_provider=legacy_owner_invoice))
    return store

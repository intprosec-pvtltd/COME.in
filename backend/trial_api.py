"""COME.in organization-scoped, administrator-controlled trial entitlements.

Additive schema. No automatic grants. The central platform administrator alone
may activate/extend/suspend/convert a trial. Existing paid subscriptions are
honoured. Enable TRIAL_ENFORCEMENT_ENABLED after staging validation.
"""
import os
from datetime import datetime, timedelta, timezone
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field
from sqlalchemy import ForeignKey, Integer, String, DateTime, select
from sqlalchemy.orm import Mapped, mapped_column, Session
import jwt

from main import Base, db, User, Tenant, SessionLocal, SECRET, current
from platform_api import _requires_admin, _audit, _tenant, _subscription, Subscription, AdminUser

router = APIRouter(tags=['Organization Trials'])

TRIAL_DAYS = 15

def now():
    return datetime.now(timezone.utc)

class OrganizationTrial(Base):
    __tablename__ = 'organization_trials'
    tenant_id: Mapped[int] = mapped_column(ForeignKey('tenants.id'), primary_key=True)
    status: Mapped[str] = mapped_column(String(24), nullable=False, default='pending')
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    duration_days: Mapped[int] = mapped_column(Integer, nullable=False, default=TRIAL_DAYS)
    extension_days: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now, onupdate=now)

class ReasonIn(BaseModel):
    reason: str = Field(min_length=8, max_length=300)

class ExtendIn(ReasonIn):
    days: int = Field(ge=1, le=30)

class PaidIn(ReasonIn):
    payment_verified: bool = False

def aware(dt):
    if dt is None: return None
    return dt.replace(tzinfo=timezone.utc) if dt.tzinfo is None else dt.astimezone(timezone.utc)

def state(session: Session, tenant_id: int):
    record = session.get(OrganizationTrial, tenant_id)
    sub = session.get(Subscription, tenant_id)
    # Phase 3 QR-paid entitlements have an explicit paid-until date. A legacy
    # pre-existing paid subscription without a QR activation remains grandfathered.
    from sqlalchemy import text as _sql_text
    entitlement_ends = None
    try:
        entitlement_ends = session.execute(_sql_text(
            'SELECT MAX(paid_until) FROM ss_verified_activations WHERE tenant_id=:tenant'),
            {'tenant':tenant_id}).scalar()
    except Exception:
        session.rollback()  # older instances before Phase 3 migration
    qr_expired = bool(entitlement_ends and entitlement_ends < now().date().isoformat())
    # Grandfather pre-existing paid customers, but do not grant a paid status
    # from a trial record alone.
    if sub and sub.status == 'active' and (not record or record.status != 'suspended') and not qr_expired:
        status = 'paid'
    elif qr_expired:
        status = 'paid_expired'
    elif not record:
        status = 'pending'
    elif record.status == 'suspended':
        status = 'suspended'
    elif record.status == 'paid':
        status = 'paid' if sub and sub.status == 'active' else 'pending'
    elif record.status == 'trial_active':
        status = 'trial_expired' if not record.expires_at or aware(record.expires_at) <= now() else 'trial_active'
    else:
        status = record.status
    ends = aware(record.expires_at) if record else None
    remains = max(0, int(((ends - now()).total_seconds() + 86399) // 86400)) if status == 'trial_active' and ends else 0
    return {'tenant_id':tenant_id,'status':status,'trial_days':TRIAL_DAYS,
            'started_at':aware(record.started_at).isoformat() if record and record.started_at else None,
            'expires_at':ends.isoformat() if ends else None,
            'days_remaining':remains,'extension_days':record.extension_days if record else 0,
            'paid_until':entitlement_ends,
            'enforcement_enabled':os.getenv('TRIAL_ENFORCEMENT_ENABLED','false').lower() == 'true'}

def record_for(session, tenant_id):
    item=session.get(OrganizationTrial,tenant_id)
    if item is None:
        item=OrganizationTrial(tenant_id=tenant_id, status='pending')
        session.add(item)
        session.flush()
    return item

@router.get('/api/trial/me')
def my_trial(user:User=Depends(current), s:Session=Depends(db)):
    return state(s,user.tenant_id)

@router.get('/api/platform/trials')
def all_trials(admin:AdminUser=Depends(_requires_admin),s:Session=Depends(db)):
    tenants=s.scalars(select(Tenant).order_by(Tenant.id.desc())).all()
    return [{'business_name':t.name,**state(s,t.id)} for t in tenants]

@router.post('/api/platform/trials/{tenant_id}/activate')
def activate(tenant_id:int,data:ReasonIn,admin:AdminUser=Depends(_requires_admin),s:Session=Depends(db)):
    _tenant(s,tenant_id)
    item=record_for(s,tenant_id)
    if item.started_at is not None or item.status!='pending':
        raise HTTPException(409,'Trial has already been activated or is not pending')
    if s.get(Subscription,tenant_id) and s.get(Subscription,tenant_id).status=='active':
        raise HTTPException(409,'Paid organization does not need a trial')
    item.started_at=now();item.expires_at=item.started_at+timedelta(days=TRIAL_DAYS);item.status='trial_active'
    sub=_subscription(s,tenant_id);sub.status='trial';sub.trial_until=item.expires_at.date().isoformat()
    _audit(s,admin,'trial_activate',f'tenant:{tenant_id};reason:{data.reason[:90]}')
    s.commit();return state(s,tenant_id)

@router.post('/api/platform/trials/{tenant_id}/extend')
def extend(tenant_id:int,data:ExtendIn,admin:AdminUser=Depends(_requires_admin),s:Session=Depends(db)):
    _tenant(s,tenant_id)
    item=s.get(OrganizationTrial,tenant_id)
    if not item or not item.started_at or item.status!='trial_active':
        raise HTTPException(409,'Only previously activated trials can be extended')
    if item.extension_days+data.days>60:
        raise HTTPException(409,'Maximum total extension is 60 days')
    item.expires_at=max(now(),aware(item.expires_at))+timedelta(days=data.days)
    item.extension_days+=data.days
    _subscription(s,tenant_id).trial_until=item.expires_at.date().isoformat()
    _audit(s,admin,'trial_extend',f'tenant:{tenant_id};days:{data.days};reason:{data.reason[:90]}')
    s.commit();return state(s,tenant_id)

@router.post('/api/platform/trials/{tenant_id}/suspend')
def suspend(tenant_id:int,data:ReasonIn,admin:AdminUser=Depends(_requires_admin),s:Session=Depends(db)):
    _tenant(s,tenant_id)
    item=record_for(s,tenant_id)
    if item.status=='suspended':raise HTTPException(409,'Already suspended')
    if s.get(Subscription,tenant_id) and s.get(Subscription,tenant_id).status=='active':
        raise HTTPException(409,'Paid accounts require the existing subscription management workflow')
    item.status='suspended'
    _audit(s,admin,'trial_suspend',f'tenant:{tenant_id};reason:{data.reason[:90]}')
    s.commit();return state(s,tenant_id)

@router.post('/api/platform/trials/{tenant_id}/resume')
def resume(tenant_id:int,data:ReasonIn,admin:AdminUser=Depends(_requires_admin),s:Session=Depends(db)):
    _tenant(s,tenant_id)
    item=s.get(OrganizationTrial,tenant_id)
    if not item or item.status!='suspended':raise HTTPException(409,'Trial is not suspended')
    # Suspended days count toward the original expiry; admin can extend separately.
    item.status='trial_active' if item.started_at else 'pending'
    _audit(s,admin,'trial_resume',f'tenant:{tenant_id};reason:{data.reason[:90]}')
    s.commit();return state(s,tenant_id)

@router.post('/api/platform/trials/{tenant_id}/convert')
def convert(tenant_id:int,data:PaidIn,admin:AdminUser=Depends(_requires_admin),s:Session=Depends(db)):
    _tenant(s,tenant_id)
    if not data.payment_verified:raise HTTPException(422,'Confirm independently verified payment before paid activation')
    item=record_for(s,tenant_id)
    if item.status=='suspended':raise HTTPException(409,'Suspended organization must be reviewed first')
    sub=_subscription(s,tenant_id)
    sub.status='active';item.status='paid'
    _audit(s,admin,'trial_convert_paid',f'tenant:{tenant_id};reason:{data.reason[:90]}')
    s.commit();return state(s,tenant_id)

# Restrict only selected new management writes, never resident rent/receipts,
# essential communication, account deletion, sign-in or history export.
# This feature is opt-in to protect existing customers during migration.
MANAGED_PREFIXES=('/api/v3/entities/properties','/api/v3/entities/rooms',
                  '/api/v3/entities/staff','/api/v3/entities/residents',
                  '/api/v3/entities/property','/api/v3/entities/room',
                  '/api/v3/entities/resident','/api/v3/entities/booking')

async def enforcement_middleware(request:Request,call_next):
    if os.getenv('TRIAL_ENFORCEMENT_ENABLED','false').lower() != 'true' or request.method not in ('POST','PUT','PATCH','DELETE'):
        return await call_next(request)
    path=request.url.path
    if not any(path == prefix or path.startswith(prefix+'/') for prefix in MANAGED_PREFIXES):
        return await call_next(request)
    authorization=request.headers.get('authorization','')
    if not authorization.startswith('Bearer '):return await call_next(request)
    try:
        payload=jwt.decode(authorization[7:],SECRET,algorithms=['HS256'])
        with SessionLocal() as s:
            user=s.get(User,int(payload['sub']))
            if user and user.tenant_id==payload.get('tenant') and user.role in ('owner','manager'):
                status=state(s,user.tenant_id)['status']
                if status not in ('trial_active','paid'):
                    from fastapi.responses import JSONResponse
                    return JSONResponse(status_code=403,content={'detail':f'Organization access: {status}. Contact IntProSec platform administrator.'})
    except (jwt.PyJWTError,ValueError,KeyError,TypeError):
        pass  # Existing route authentication still handles bad tokens.
    return await call_next(request)

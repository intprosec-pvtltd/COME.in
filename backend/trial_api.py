"""COME.in organization-scoped, administrator-controlled trial entitlements.

Additive schema. No automatic grants. The central platform administrator alone
may activate/extend/suspend/convert a trial. Existing paid subscriptions are
honoured. Enable TRIAL_ENFORCEMENT_ENABLED after staging validation.
"""
import os
from datetime import datetime, timedelta, timezone
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field
from sqlalchemy import ForeignKey, Integer, String, DateTime, UniqueConstraint, select
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

class TrialReminder(Base):
    """Unique reminders, preventing duplicates across workers or restarts."""
    __tablename__ = 'staysync_trial_reminders'
    id: Mapped[int] = mapped_column(primary_key=True)
    tenant_id: Mapped[int] = mapped_column(ForeignKey('tenants.id'), nullable=False)
    milestone: Mapped[int] = mapped_column(Integer, nullable=False)
    at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    __table_args__ = (UniqueConstraint('tenant_id','milestone',name='uq_staysync_trial_reminder'),)


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
    if record and record.status == 'suspended':
        status = 'suspended'
    elif sub and sub.status == 'active' and not qr_expired:
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
            'subscription_suspended':bool(record and record.status == 'suspended' and sub and sub.status == 'paused'),
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

@router.post('/api/trial/start')
def start_trial(user: User = Depends(current), s: Session = Depends(db)):
    """One-time self-serve trial, tied to organization rather than device."""
    if user.role != 'owner':
        raise HTTPException(403, 'Only the PG owner may start a trial')
    tenant_id = user.tenant_id
    record = record_for(s, tenant_id)
    if record.started_at is not None or record.status != 'pending':
        raise HTTPException(409, 'Your organization already used its free trial')
    sub = s.get(Subscription, tenant_id)
    if sub and sub.status == 'active':
        raise HTTPException(409, 'Your organization already has a paid subscription')
    record.started_at = now()
    record.expires_at = record.started_at + timedelta(days=TRIAL_DAYS)
    record.status = 'trial_active'
    sub = _subscription(s, tenant_id)
    sub.status = 'trial'
    sub.trial_until = record.expires_at.date().isoformat()
    s.commit()
    return state(s, tenant_id)


def run_due_reminders():
    """Create in-app/FCM owner alerts; scheduler should call periodically.

    A DB unique key makes each milestone idempotent. On free instances this
    worker runs only while the service is awake; do not promise exact timing.
    """
    from sqlalchemy.exc import IntegrityError
    from v3_api import Alert
    from push_notifications import PushJob
    sent = 0
    with SessionLocal() as s:
        active = s.scalars(select(OrganizationTrial).where(OrganizationTrial.status == 'trial_active')).all()
        for trial in active:
            if not trial.expires_at: continue
            seconds = (aware(trial.expires_at) - now()).total_seconds()
            days = max(0, int((seconds + 86399) // 86400))
            milestone = next((m for m in (0,1,3,7) if days <= m), None)
            if milestone is None: continue
            # One message only per run: the nearest relevant milestone.
            if s.scalar(select(TrialReminder.id).where(TrialReminder.tenant_id==trial.tenant_id,
                         TrialReminder.milestone==milestone)):
                continue
            owners = s.scalars(select(User).where(User.tenant_id==trial.tenant_id,User.role=='owner')).all()
            try:
                with s.begin_nested():
                    s.add(TrialReminder(tenant_id=trial.tenant_id,milestone=milestone))
                    s.flush()
                    for user in owners:
                        text = ('Your free trial has ended. Pay to restore access.' if days == 0
                                else f'Your Stay Sync trial ends in {days} day(s). View your subscription.')
                        item = Alert(tenant_id=trial.tenant_id,user_id=user.id,
                          audience='owners',title='Stay Sync subscription reminder',
                          body=text,destination='ownerSubscription')
                        s.add(item);s.flush()
                        if os.getenv('PUSH_ENABLED') == '1':
                            s.add(PushJob(alert_id=item.id))
                    sent += 1
            except IntegrityError:
                continue
        s.commit()
    return sent


@router.post('/api/platform/trials/run-reminders')
def trigger_reminders(admin: AdminUser = Depends(_requires_admin)):
    return {'reminders_created':run_due_reminders()}


def start_reminder_worker():
    """Best-effort scheduler; for guaranteed daily delivery use an external cron."""
    if os.getenv('TRIAL_REMINDERS_ENABLED','false').lower() != 'true':
        return
    import threading, time, logging
    def worker():
        while True:
            try:run_due_reminders()
            except Exception:logging.getLogger('staysync.trials').exception('Reminder generation failed')
            time.sleep(4*3600)
    threading.Thread(target=worker,daemon=True,name='staysync-trial-reminders').start()


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
    from subscription_phase3 import active_paid_until
    paid_until=active_paid_until(s,tenant_id)
    if not paid_until or paid_until < now().date().isoformat():
        raise HTTPException(409,'A verified active payment is required before paid activation')
    item=record_for(s,tenant_id)
    if item.status=='suspended':raise HTTPException(409,'Suspended organization must be reviewed first')
    sub=_subscription(s,tenant_id)
    sub.status='active';item.status='paid'
    _audit(s,admin,'trial_convert_paid',f'tenant:{tenant_id};reason:{data.reason[:90]}')
    s.commit();return state(s,tenant_id)


@router.post('/api/platform/trials/{tenant_id}/end-subscription')
def end_paid_subscription(tenant_id:int,data:ReasonIn,admin:AdminUser=Depends(_requires_admin),s:Session=Depends(db)):
    """Admin-only prospective access suspension. Retains payment and billing history."""
    _tenant(s,tenant_id)
    sub=s.get(Subscription,tenant_id)
    if not sub or sub.status!='active':
        raise HTTPException(409,'Only active paid subscriptions may be ended')
    item=record_for(s,tenant_id)
    if item.status=='suspended':
        raise HTTPException(409,'Already suspended')
    sub.status='paused'
    item.status='suspended'
    _audit(s,admin,'subscription_end_by_admin',f'tenant:{tenant_id};reason:{data.reason[:90]}')
    s.commit()
    return state(s,tenant_id)

@router.post('/api/platform/trials/{tenant_id}/resume-subscription')
def resume_paid_subscription(tenant_id:int,data:ReasonIn,admin:AdminUser=Depends(_requires_admin),s:Session=Depends(db)):
    """Restore only previously admin-suspended paid entitlements; never create free access."""
    _tenant(s,tenant_id)
    sub=s.get(Subscription,tenant_id)
    item=s.get(OrganizationTrial,tenant_id)
    if not sub or sub.status!='paused' or not item or item.status!='suspended':
        raise HTTPException(409,'There is no admin-suspended paid subscription to resume')
    from subscription_phase3 import active_paid_until
    until=active_paid_until(s,tenant_id)
    if not until:
        raise HTTPException(409,'Paid-through date unavailable; review payment history before resuming')
    if until < now().date().isoformat():
        raise HTTPException(409,'Paid subscription has expired; require verified renewal')
    sub.status='active'
    item.status='paid'
    _audit(s,admin,'subscription_resume_by_admin',f'tenant:{tenant_id};reason:{data.reason[:90]}')
    s.commit()
    return state(s,tenant_id)

# Server gate: all owner/manager business APIs, not only selected writes.
# Keep bootstrapping, billing, trial selection, authentication, receipts and
# password recovery reachable while payment is required. Disabled by default
# until staging confirms payment activation and old-account migration.
EXEMPT_PREFIXES = (
    '/api/login','/api/health','/api/trial/','/api/platform/',
    '/api/owner-subscriptions/','/api/v3/state','/api/v3/password',
    '/api/v3/logout','/api/v3/profile','/api/v3/receipt',
    '/api/v3/receipts','/api/v3/export','/api/v3/push-tokens',
    '/api/reset','/api/forgot','/api/recovery','/api/v3/phone/',
)

async def enforcement_middleware(request:Request,call_next):
    if os.getenv('TRIAL_ENFORCEMENT_ENABLED','false').lower() != 'true':
        return await call_next(request)
    path=request.url.path
    if not path.startswith('/api/') or any(path == p.rstrip('/') or path.startswith(p) for p in EXEMPT_PREFIXES):
        return await call_next(request)
    auth=request.headers.get('authorization','')
    if not auth.startswith('Bearer '): return await call_next(request)
    try:
        payload=jwt.decode(auth[7:],SECRET,algorithms=['HS256'])
        with SessionLocal() as s:
            user=s.get(User,int(payload['sub']))
            if user and user.tenant_id==payload.get('tenant') and user.role in ('owner','manager'):
                status=state(s,user.tenant_id)['status']
                if status not in ('trial_active','paid'):
                    from fastapi.responses import JSONResponse
                    return JSONResponse(status_code=402,content={
                        'detail':'Your free trial or subscription has ended. Complete payment to continue.',
                        'code':'subscription_payment_required','subscription_status':status,
                        'payment_route':'/api/owner-subscriptions/me'})
    except (jwt.PyJWTError,ValueError,KeyError,TypeError):
        pass  # Normal authentication errors remain the responsibility of routes.
    return await call_next(request)

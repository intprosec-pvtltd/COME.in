"""FCM push outbox for committed PG-scoped V3 alerts.

No keys in source. Enable with PUSH_ENABLED=1, FIREBASE_SERVICE_ACCOUNT_JSON,
install firebase-admin. The outbox persists retries while the API is running.
"""
import json
import logging
import os
import threading
import time
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import ForeignKey, String, Integer, UniqueConstraint, select
from sqlalchemy.orm import Mapped, mapped_column, Session

from main import Base, db, current, User, SessionLocal
from v3_api import Alert, meta
from platform_api import PlatformUserAccess, _requires_admin, AdminUser

logger = logging.getLogger('staysync.push')
router = APIRouter(prefix='/api/v3', tags=['Push notifications'])

class PushDevice(Base):
    __tablename__ = 'staysync_push_devices'
    id: Mapped[int] = mapped_column(primary_key=True)
    tenant_id: Mapped[int] = mapped_column(ForeignKey('tenants.id'), index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey('users.id'), index=True)
    token: Mapped[str] = mapped_column(String(4096), unique=True)
    platform: Mapped[str] = mapped_column(String(20), default='android')
    active: Mapped[int] = mapped_column(Integer, default=1)
    updated_at: Mapped[str] = mapped_column(String(50), default=lambda: datetime.now(timezone.utc).isoformat())

class PushJob(Base):
    __tablename__ = 'staysync_push_jobs'
    id: Mapped[int] = mapped_column(primary_key=True)
    alert_id: Mapped[int] = mapped_column(ForeignKey('comein_v3_alerts.id'), unique=True)
    status: Mapped[str] = mapped_column(String(20), default='pending')
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    retry_after: Mapped[int] = mapped_column(Integer, default=0)
    delivered: Mapped[int] = mapped_column(Integer, default=0)
    failed: Mapped[int] = mapped_column(Integer, default=0)

class PushDelivery(Base):
    __tablename__ = 'staysync_push_deliveries'
    id: Mapped[int] = mapped_column(primary_key=True)
    alert_id: Mapped[int] = mapped_column(ForeignKey('comein_v3_alerts.id'), index=True)
    device_id: Mapped[int] = mapped_column(ForeignKey('staysync_push_devices.id'), index=True)
    status: Mapped[str] = mapped_column(String(20), default='pending')
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    __table_args__ = (UniqueConstraint('alert_id','device_id'),)

class TokenIn(BaseModel):
    token: str = Field(min_length=30, max_length=4096)
    platform: str = Field(default='android', pattern='^(android|ios)$')

@router.post('/push-tokens')
def register_token(data: TokenIn, u: User = Depends(current), s: Session = Depends(db)):
    # Token is unique: move it away from any previous signed-in account.
    row = s.scalar(select(PushDevice).where(PushDevice.token == data.token))
    if row is None:
        row = PushDevice(tenant_id=u.tenant_id, user_id=u.id, token=data.token, platform=data.platform)
        s.add(row)
    else:
        row.tenant_id, row.user_id, row.platform = u.tenant_id, u.id, data.platform
        row.active = 1
        row.updated_at = datetime.now(timezone.utc).isoformat()
    s.commit()
    return {'registered': True}

@router.delete('/push-tokens')
def unregister_token(data: TokenIn, u: User = Depends(current), s: Session = Depends(db)):
    row = s.scalar(select(PushDevice).where(PushDevice.token == data.token,
                                             PushDevice.user_id == u.id,
                                             PushDevice.tenant_id == u.tenant_id))
    if row:
        row.active = 0
        s.commit()
    return {'removed': True}

def eligible(s, alert, user):
    if user.tenant_id != alert.tenant_id: return False
    access = s.get(PlatformUserAccess, user.id)
    if access is not None and not access.is_active: return False
    if alert.user_id is not None and alert.user_id != user.id: return False
    if alert.audience == 'owners' and user.role not in ('owner','manager'): return False
    if alert.audience not in ('all','owners', user.role): return False
    md = meta(s, alert.tenant_id, 'alert_meta', alert.id)
    if md.get('created_by') == user.id: return False
    pid = md.get('property_id')
    if pid is not None and user.role in ('resident','staff'):
        kind = 'resident_meta' if user.role == 'resident' else 'staff_meta'
        if int(meta(s, user.tenant_id, kind, user.id).get('property_id', -1)) != int(pid):
            return False
    return True

def _fcm():
    import firebase_admin
    from firebase_admin import credentials, messaging
    try:
        firebase_admin.get_app()
    except ValueError:
        raw=os.environ['FIREBASE_SERVICE_ACCOUNT_JSON']
        firebase_admin.initialize_app(credentials.Certificate(json.loads(raw)))
    return messaging

def _process_job(session, job, messaging):
    alert = session.get(Alert, job.alert_id)
    if alert is None:
        job.status = 'done'; return
    recipients = session.scalars(select(User).where(User.tenant_id == alert.tenant_id)).all()
    users = {u.id: u for u in recipients if eligible(session, alert, u)}
    devices = session.scalars(select(PushDevice).where(PushDevice.tenant_id == alert.tenant_id, PushDevice.active == 1)).all()
    any_failed=False
    for device in devices:
        if device.user_id not in users: continue
        delivery = session.scalar(select(PushDelivery).where(PushDelivery.alert_id == alert.id,
                                                              PushDelivery.device_id == device.id))
        if delivery is None:
            delivery=PushDelivery(alert_id=alert.id,device_id=device.id)
            session.add(delivery);session.flush()
        if delivery.status == 'sent': continue
        try:
            md=meta(session,alert.tenant_id,'alert_meta',alert.id)
            messaging.send(messaging.Message(
                token=device.token,
                notification=messaging.Notification(title=alert.title[:100], body=alert.body[:150]),
                data={'destination':str(alert.destination),'property_id':str(md.get('property_id') or '')},
                android=messaging.AndroidConfig(priority='high',
                    notification=messaging.AndroidNotification(channel_id='staysync_alerts',sound='default'))))
            delivery.status='sent';job.delivered += 1
        except Exception as e:
            delivery.status='failed';job.failed += 1;any_failed=True
            logger.warning('Push delivery failed: alert=%s device=%s type=%s',alert.id,device.id,type(e).__name__)
        finally:
            delivery.attempts += 1
    job.attempts += 1
    if any_failed and job.attempts < 5:
        job.status='retry'
        job.retry_after=int(time.time())+min(900, 20*(2**job.attempts))
    else: job.status='done'

def _worker():
    while True:
        try:
            messaging=_fcm()
            with SessionLocal() as s:
                jobs=s.scalars(select(PushJob).where(PushJob.status.in_(['pending','retry']),
                    PushJob.retry_after <= int(time.time())).order_by(PushJob.id).limit(25)).all()
                for job in jobs:
                    _process_job(s,job,messaging)
                s.commit()
        except Exception as e:
            logger.warning('Push worker deferred: %s',type(e).__name__)
        time.sleep(5)

_worker_started = False

def start_push_worker():
    global _worker_started
    if _worker_started: return
    if os.environ.get('PUSH_ENABLED') != '1' or not os.environ.get('FIREBASE_SERVICE_ACCOUNT_JSON'):
        logger.info('Push delivery disabled until Firebase credentials are configured')
        return
    _worker_started=True
    threading.Thread(target=_worker,name='StaySyncPushWorker',daemon=True).start()

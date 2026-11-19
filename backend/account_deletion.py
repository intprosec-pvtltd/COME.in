"""Guarded, irreversible deletion of *eligible* accounts only.

A user with legal/financial/identity references cannot be removed by this
endpoint. Do not use cascading database deletion for these records.
"""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import MetaData, Table, select, func, delete
from sqlalchemy.orm import Session
from main import db, current, User
from platform_api import _requires_admin, PlatformUserAccess, AdminUser, _audit
from v3_api import Document, audit as owner_audit, commit

router = APIRouter(tags=['Account erasure'])

# Only empty, pure access/assignment data is safe to delete with an account.
_SAFE_ROWS = {'platform_user_access', 'platform_resident_assignments',
              'platform_billing_exclusions', 'staysync_push_devices'}
# These documents store account-local preferences/metadata, not content history.
_SAFE_DOCUMENT_KINDS = {'profile', 'onboarding', 'resident_meta', 'security', 'staff_meta'}

class EraseConfirm(BaseModel):
    confirm_email: str


def review(session: Session, target: User):
    """Discover all physical SQL foreign keys rather than assuming a fixed schema."""
    blockers, technical = {}, []
    metadata = MetaData()
    metadata.reflect(bind=session.bind)
    if 'users' not in metadata.tables:
        raise HTTPException(503, 'Database structure unavailable')
    for table in metadata.tables.values():
        if table.name == 'users':
            continue
        for fk in table.foreign_key_constraints:
            for element in fk.elements:
                if element.column.table.name != 'users':
                    continue
                column = element.parent
                count = session.scalar(select(func.count()).select_from(table).where(column == target.id)) or 0
                if count:
                    if table.name in _SAFE_ROWS:
                        technical.append((table, column))
                    else:
                        blockers[table.name] = blockers.get(table.name, 0) + count
    # Document JSON records have no formal foreign key: audit their known user keys.
    # Restrict key matching to user-owned kinds; generic document IDs (rooms, alerts)
    # can numerically collide with a user's ID.
    docs = session.scalars(select(Document).where(Document.tenant_id == target.tenant_id,
                                                    Document.kind.in_(_SAFE_DOCUMENT_KINDS),
                                                    Document.key == str(target.id))).all()
    unsafe_docs = [d for d in docs if d.kind not in _SAFE_DOCUMENT_KINDS]
    if unsafe_docs:
        blockers['linked_app_documents'] = len(unsafe_docs)
    # An owner cannot be removed if that would leave an organization without an owner.
    if target.role == 'owner':
        remaining = session.scalars(select(User).where(User.tenant_id == target.tenant_id,
                                       User.role == 'owner', User.id != target.id)).all()
        if not any((session.get(PlatformUserAccess, other.id) is None or
                    session.get(PlatformUserAccess, other.id).is_active) for other in remaining):
            blockers['last_active_pg_owner'] = 1
    return blockers, technical, [d for d in docs if d.kind in _SAFE_DOCUMENT_KINDS]


def preview_user(session, user):
    blockers, _, _ = review(session, user)
    return {'id': user.id, 'role': user.role,
            'eligible': not bool(blockers), 'blockers': blockers,
            'requires_deactivation': True,
            'message': ('Deletion blocked to preserve linked records. Deactivate instead.'
                        if blockers else 'Eligible for permanent deletion after deactivation.')}


def erase(session, user, confirm_email, actor=None):
    if confirm_email.strip().lower() != user.email.lower():
        raise HTTPException(422, 'Enter the exact account email to confirm deletion')
    access = session.get(PlatformUserAccess, user.id)
    if access is None or access.is_active:
        raise HTTPException(409, 'Deactivate this account before permanent deletion')
    blockers, technical, safe_docs = review(session, user)
    if blockers:
        raise HTTPException(409, {'message': 'Cannot delete an account with linked records', 'blockers': blockers})
    # Device delivery receipts depend on device rows. Erase only this user's
    # delivery telemetry before their device registrations.
    from push_notifications import PushDevice, PushDelivery
    devices = session.scalars(select(PushDevice).where(PushDevice.user_id == user.id)).all()
    for device in devices:
        session.execute(delete(PushDelivery).where(PushDelivery.device_id == device.id))
    for table, column in technical:
        session.execute(delete(table).where(column == user.id))
    for document in safe_docs:
        session.delete(document)
    # Actor-only audit: no duplicate PII. The user ID is retained for accountability.
    if actor is not None:
        _audit(session, actor, 'permanent_account_deletion', f'user:{user.id}/tenant:{user.tenant_id}')
    session.delete(user)
    session.commit()
    return {'deleted': True, 'user_id': user.id}

@router.get('/api/platform/users/{user_id}/deletion-review')
def admin_preview(user_id: int, admin: AdminUser = Depends(_requires_admin), s: Session = Depends(db)):
    target = s.get(User, user_id)
    if not target: raise HTTPException(404, 'Account not found')
    return preview_user(s, target)

@router.delete('/api/platform/users/{user_id}')
def admin_delete(user_id: int, data: EraseConfirm, admin: AdminUser = Depends(_requires_admin), s: Session = Depends(db)):
    target = s.get(User, user_id)
    if not target: raise HTTPException(404, 'Account not found')
    return erase(s, target, data.confirm_email, actor=admin)

@router.get('/api/v3/residents/{resident_id}/deletion-review')
def owner_preview(resident_id: int, u: User = Depends(current), s: Session = Depends(db)):
    if u.role != 'owner': raise HTTPException(403, 'PG owner access required')
    target = s.get(User, resident_id)
    if not target or target.tenant_id != u.tenant_id or target.role != 'resident':
        raise HTTPException(404, 'Resident not found')
    return preview_user(s, target)

@router.delete('/api/v3/residents/{resident_id}')
def owner_delete(resident_id: int, data: EraseConfirm, u: User = Depends(current), s: Session = Depends(db)):
    if u.role != 'owner': raise HTTPException(403, 'PG owner access required')
    target = s.get(User, resident_id)
    if not target or target.tenant_id != u.tenant_id or target.role != 'resident':
        raise HTTPException(404, 'Resident not found')
    owner_audit(s, u, 'permanent_resident_deletion', {'resident_id': target.id})
    return erase(s, target, data.confirm_email)

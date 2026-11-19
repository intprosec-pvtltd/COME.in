"""COME.in private resident identity-proof workflow.

This is DOCUMENT REVIEW, not government identity verification or DigiLocker.
Only resident uploader and owner/manager of the same PG tenant can see proof.
Binary content is persisted in PostgreSQL (not Render ephemeral disk).
"""
from datetime import datetime, timezone
from risk_checks import inspect_file, sha256
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Response
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel, Field
from sqlalchemy import LargeBinary, String, Integer, ForeignKey, DateTime, select
from sqlalchemy.orm import Mapped, mapped_column, Session
from main import Base, db, current, User, role

router = APIRouter(prefix='/api/identity', tags=['Resident identity documents'])
MAX_BYTES = 5 * 1024 * 1024

class ResidentProof(Base):
    __tablename__ = 'comein_resident_identity_proofs'
    id: Mapped[int] = mapped_column(primary_key=True)
    tenant_id: Mapped[int] = mapped_column(ForeignKey('tenants.id'), index=True)
    resident_id: Mapped[int] = mapped_column(ForeignKey('users.id'), index=True)
    filename: Mapped[str] = mapped_column(String(180))
    mime: Mapped[str] = mapped_column(String(80))
    content: Mapped[bytes] = mapped_column(LargeBinary)
    size: Mapped[int] = mapped_column(Integer)
    status: Mapped[str] = mapped_column(String(20), default='pending')
    review_note: Mapped[str] = mapped_column(String(500), default='')
    reviewed_by: Mapped[Optional[int]] = mapped_column(ForeignKey('users.id'), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    reviewed_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)

def _record(p, other_hashes=(), stored_risk=None):
    result = stored_risk or inspect_file(p.content, p.mime, other_hashes, perform_ocr=False)
    return {'id': p.id, 'resident_id': p.resident_id, 'filename': p.filename,
            'mime': p.mime, 'size': p.size, 'status': p.status,
            'review_note': p.review_note, 'risk_level': result['risk_level'],
            'risk_flags': result['risk_flags'], 'review_notes': result.get('review_notes', []),
            'analysis_status': result.get('analysis_status', 'legacy_unverified'),
            'ai_generated_verified': False, 'authenticity_verified': False,
            'created_at': p.created_at.isoformat() if p.created_at else '',
            'reviewed_at': p.reviewed_at.isoformat() if p.reviewed_at else None}

def _get_proof(s, u, identifier):
    p = s.scalar(select(ResidentProof).where(ResidentProof.id == identifier,
                                           ResidentProof.tenant_id == u.tenant_id))
    if not p or (u.role not in ('owner', 'manager') and p.resident_id != u.id):
        raise HTTPException(404, 'Document not found')
    return p

@router.post('/proofs', status_code=201)
async def submit_proof(file: UploadFile = File(...), u: User = Depends(current), s: Session = Depends(db)):
    role(u, 'resident')
    mime = (file.content_type or '').lower()
    data = await file.read(MAX_BYTES + 1)
    if not data or len(data) > MAX_BYTES:
        raise HTTPException(413, 'Select a document smaller than 5 MB')
    valid = (mime == 'image/jpeg' and data.startswith(b'\xff\xd8\xff') or
             mime == 'image/png' and data.startswith(b'\x89PNG\r\n\x1a\n') or
             mime == 'application/pdf' and data.startswith(b'%PDF-'))
    if not valid:
        raise HTTPException(415, 'Only valid JPG, PNG and PDF documents are accepted')
    # Serialize submissions for this resident on PostgreSQL. This prevents two
    # parallel uploads from bypassing the single-active-submission rule.
    # SQLite does not implement SELECT FOR UPDATE; production uses PostgreSQL.
    s.scalar(select(User).where(User.id == u.id,
             User.tenant_id == u.tenant_id).with_for_update())
    latest = s.scalar(select(ResidentProof).where(
        ResidentProof.tenant_id == u.tenant_id,
        ResidentProof.resident_id == u.id
    ).order_by(ResidentProof.id.desc()).limit(1))
    if latest and latest.status != 'rejected':
        raise HTTPException(409, 'A document is already submitted. You can upload again only after rejection.')
    # Rejected records remain available for audit. A replacement becomes the
    # only current proof; prior records are never overwritten.
    name = (file.filename or 'identity-proof').replace('\\', '/').split('/')[-1][:180]
    p = ResidentProof(tenant_id=u.tenant_id, resident_id=u.id, filename=name,
                      mime=mime, content=data, size=len(data))
    s.add(p)
    s.flush()
    # V31 records risk findings once, without OCR on every account refresh.
    # Compare only this PG tenant's prior documents, bounded for CPU/memory.
    from v3_api import put, meta
    previous = s.scalars(select(ResidentProof).where(
        ResidentProof.tenant_id == u.tenant_id,
        ResidentProof.id != p.id).order_by(ResidentProof.id.desc()).limit(60)).all()
    prior_hashes = [sha256(item.content) for item in previous]
    prior_visual = [meta(s, u.tenant_id, 'identity_risk_v31', item.id).get('visual_hash')
                    for item in previous]
    result = await run_in_threadpool(
        inspect_file, data, mime, prior_hashes,
        known_visual_hashes=prior_visual, document_kind='identity')
    put(s, u.tenant_id, 'identity_risk_v31', p.id, result)
    # Show a new notice in the existing PG owner notification feed.
    from v3_api import alert
    from v3_api import meta
    pg_id=int(meta(s,u.tenant_id,'resident_meta',u.id).get('property_id',0) or 0)
    alert(s, u, 'Resident ID proof submitted',
          f'{u.name} submitted an identity document for review.',
          'residents', audience='owners', property_id=pg_id, entity_id=u.id)
    s.commit()
    s.refresh(p)
    return _record(p, stored_risk=result)

@router.get('/proofs/me')
def my_proofs(u: User = Depends(current), s: Session = Depends(db)):
    role(u, 'resident')
    proofs = s.scalars(select(ResidentProof).where(
        ResidentProof.tenant_id == u.tenant_id).order_by(ResidentProof.id.desc())).all()
    from v3_api import meta
    other = [sha256(p.content) for p in proofs if p.resident_id != u.id]
    return [_record(p, other, meta(s, u.tenant_id, 'identity_risk_v31', p.id) or None)
            for p in proofs if p.resident_id == u.id]

@router.get('/residents/{resident_id}/proofs')
def resident_proofs(resident_id: int, u: User = Depends(current), s: Session = Depends(db)):
    role(u, 'owner', 'manager')
    resident = s.scalar(select(User).where(User.id == resident_id,
        User.tenant_id == u.tenant_id, User.role == 'resident'))
    if not resident:
        raise HTTPException(404, 'Resident not found')
    proofs = s.scalars(select(ResidentProof).where(
        ResidentProof.tenant_id == u.tenant_id).order_by(ResidentProof.id.desc())).all()
    from v3_api import meta
    other = [sha256(p.content) for p in proofs if p.resident_id != resident_id]
    return [_record(p, other, meta(s, u.tenant_id, 'identity_risk_v31', p.id) or None)
            for p in proofs if p.resident_id == resident_id]

@router.get('/proofs/{identifier}/file')
def view_document(identifier: int, u: User = Depends(current), s: Session = Depends(db)):
    p = _get_proof(s, u, identifier)
    # No public URL, CDN or external storage. Never cache ID proof on shared clients.
    return Response(content=p.content, media_type=p.mime,
        headers={'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff',
                 'Content-Disposition': 'attachment; filename="identity-proof"'})

class ProofReview(BaseModel):
    decision: str = Field(pattern='^(approved|rejected)$')
    note: str = Field(default='', max_length=500)

@router.post('/proofs/{identifier}/review')
def review_proof(identifier: int, data: ProofReview,
                 u: User = Depends(current), s: Session = Depends(db)):
    role(u, 'owner', 'manager')
    p = _get_proof(s, u, identifier)
    newest = s.scalar(select(ResidentProof).where(
        ResidentProof.tenant_id == u.tenant_id,
        ResidentProof.resident_id == p.resident_id
    ).order_by(ResidentProof.id.desc()).limit(1))
    if p.status != 'pending' or not newest or newest.id != p.id:
        raise HTTPException(409, 'Only the latest pending document may be reviewed')
    p.status = data.decision
    p.review_note = data.note.strip()
    p.reviewed_by = u.id
    p.reviewed_at = datetime.now(timezone.utc)
    s.commit()
    s.refresh(p)
    from v3_api import meta
    return _record(p, stored_risk=meta(s, u.tenant_id, 'identity_risk_v31', p.id) or None)


# Additive resident profile photograph workflow. Identity documents and portraits
# are kept separate, private, and are never published to a community feed.
class ResidentPortrait(Base):
    __tablename__ = 'staysync_resident_portraits'
    id: Mapped[int] = mapped_column(primary_key=True)
    tenant_id: Mapped[int] = mapped_column(ForeignKey('tenants.id'), index=True)
    resident_id: Mapped[int] = mapped_column(ForeignKey('users.id'), index=True)
    mime: Mapped[str] = mapped_column(String(30))
    content: Mapped[bytes] = mapped_column(LargeBinary)
    status: Mapped[str] = mapped_column(String(20), default='pending')
    note: Mapped[str] = mapped_column(String(500), default='')
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


def portrait_record(item):
    return {'id': item.id, 'resident_id': item.resident_id,
            'status': item.status, 'mime': item.mime, 'review_note': item.note,
            'created_at': item.created_at.isoformat() if item.created_at else ''}


def selected_portrait(s, tenant_id, resident_id):
    return s.scalar(select(ResidentPortrait).where(
        ResidentPortrait.tenant_id == tenant_id,
        ResidentPortrait.resident_id == resident_id).order_by(ResidentPortrait.id.desc()).limit(1))


@router.post('/portrait', status_code=201)
async def upload_portrait(file: UploadFile = File(...), u: User = Depends(current), s: Session = Depends(db)):
    role(u, 'resident')
    mime = (file.content_type or '').lower()
    data = await file.read(2 * 1024 * 1024 + 1)
    if not data or len(data) > 2 * 1024 * 1024:
        raise HTTPException(413, 'Choose a photo smaller than 2 MB')
    if not (mime == 'image/jpeg' and data.startswith(b'\xff\xd8\xff') or
            mime == 'image/png' and data.startswith(b'\x89PNG\r\n\x1a\n')):
        raise HTTPException(415, 'Please upload a JPG or PNG photograph')
    s.scalar(select(User).where(User.id == u.id, User.tenant_id == u.tenant_id).with_for_update())
    previous = selected_portrait(s, u.tenant_id, u.id)
    if previous and previous.status == 'pending':
        raise HTTPException(409, 'Your previous photograph is awaiting review')
    item = ResidentPortrait(tenant_id=u.tenant_id, resident_id=u.id,
                            mime=mime, content=data)
    s.add(item)
    from v3_api import alert, meta
    pid=int(meta(s,u.tenant_id,'resident_meta',u.id).get('property_id',0) or 0)
    alert(s,u,'Resident photograph submitted',
          f'{u.name} uploaded a profile photograph for review.',
          'residents',audience='owners',property_id=pid,entity_id=u.id)
    s.commit()
    s.refresh(item)
    return portrait_record(item)


@router.get('/portrait/me')
def my_portrait(u: User = Depends(current), s: Session = Depends(db)):
    role(u, 'resident')
    item=selected_portrait(s,u.tenant_id,u.id)
    return portrait_record(item) if item else None


@router.get('/residents/{resident_id}/portrait')
def resident_portrait(resident_id: int,u: User = Depends(current), s: Session = Depends(db)):
    role(u, 'owner', 'manager')
    resident=s.scalar(select(User).where(User.id==resident_id,User.tenant_id==u.tenant_id,User.role=='resident'))
    if not resident: raise HTTPException(404,'Resident not found')
    item=selected_portrait(s,u.tenant_id,resident_id)
    return portrait_record(item) if item else None


@router.get('/portrait/{identifier}/file')
def portrait_file(identifier: int,u: User = Depends(current),s: Session = Depends(db)):
    item=s.scalar(select(ResidentPortrait).where(
        ResidentPortrait.id==identifier,ResidentPortrait.tenant_id==u.tenant_id))
    if not item or (u.role not in ('owner','manager') and item.resident_id != u.id):
        raise HTTPException(404,'Photograph not found')
    return Response(item.content,media_type=item.mime,headers={
        'Cache-Control':'no-store','X-Content-Type-Options':'nosniff',
        'Content-Disposition':'attachment; filename="resident-portrait"'})


@router.post('/portrait/{identifier}/review')
def review_portrait(identifier: int,decision: ProofReview,u: User = Depends(current),s: Session = Depends(db)):
    role(u, 'owner', 'manager')
    item=s.scalar(select(ResidentPortrait).where(
        ResidentPortrait.id==identifier,ResidentPortrait.tenant_id==u.tenant_id))
    if not item or item.status!='pending' or selected_portrait(s,u.tenant_id,item.resident_id).id!=item.id:
        raise HTTPException(409,'Only the latest pending photograph can be reviewed')
    item.status=decision.decision
    item.note=decision.note.strip()
    s.commit()
    return portrait_record(item)


def identity_progress(s: Session, u: User):
    """Post-password-change onboarding state, scoped to authenticated resident."""
    if u.role!='resident':return None
    from v3_api import meta
    required=bool(meta(s,u.tenant_id,'onboarding',u.id).get('documents_required',False))
    proof=s.scalar(select(ResidentProof).where(
        ResidentProof.tenant_id==u.tenant_id,
        ResidentProof.resident_id==u.id).order_by(ResidentProof.id.desc()).limit(1))
    photo=selected_portrait(s,u.tenant_id,u.id)
    return {'required':required,
        'photo_submitted':photo is not None and photo.status!='rejected',
        'proof_submitted':proof is not None and proof.status!='rejected',
        'needs_submission':required and (photo is None or photo.status=='rejected' or proof is None or proof.status=='rejected')}

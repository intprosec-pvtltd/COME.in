"""Stay Sync Manage — owner subscription billing and manual QR payment workflow.

Integration is deliberately fail-closed: create_router requires the existing
project's authenticated-principal resolver and resident/bed count adapter.
Never mount this router with demo or anonymous dependencies.
"""
from __future__ import annotations

import io
import logging
import json
import os
import sqlite3
import threading
import uuid
from datetime import datetime, timezone
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path
from typing import Callable

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

MAX_IMAGE_BYTES = 5 * 1024 * 1024
MAX_QR_BYTES = 2 * 1024 * 1024


def utcnow() -> str:
    return datetime.now(timezone.utc).isoformat()


def cents(value: object) -> int:
    d = Decimal(str(value))
    if not d.is_finite() or d < 0 or d > Decimal('1000000'):
        raise ValueError('Invalid rate')
    return int((d * 100).quantize(Decimal('1'), rounding=ROUND_HALF_UP))


def rupees(value: int) -> str:
    return f'{Decimal(value)/100:.2f}'


def detected_image(data: bytes) -> str | None:
    if data.startswith(b'\x89PNG\r\n\x1a\n'):
        return 'image/png'
    if data[:3] == b'\xff\xd8\xff' and data.endswith(b'\xff\xd9'):
        return 'image/jpeg'
    return None


class BillingStore:
    def __init__(self, db_path: str, media_dir: str):
        self.db_path = str(Path(db_path).resolve())
        self.media_dir = Path(media_dir).resolve()
        Path(self.db_path).parent.mkdir(parents=True, exist_ok=True)
        self.media_dir.mkdir(parents=True, exist_ok=True)
        self.lock = threading.RLock()
        with self.connect() as db:
            db.executescript('''
                CREATE TABLE IF NOT EXISTS ss_pricing (
                    singleton INTEGER PRIMARY KEY CHECK(singleton=1),
                    bed_rate_cents INTEGER NOT NULL, resident_rate_cents INTEGER NOT NULL,
                    updated_at TEXT NOT NULL, updated_by TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS ss_qr (
                    singleton INTEGER PRIMARY KEY CHECK(singleton=1),
                    filename TEXT NOT NULL, media_type TEXT NOT NULL,
                    beneficiary TEXT NOT NULL, upi_id TEXT NOT NULL,
                    enabled INTEGER NOT NULL, updated_at TEXT NOT NULL, updated_by TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS ss_invoices (
                    id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, period TEXT NOT NULL,
                    beds INTEGER NOT NULL, residents INTEGER NOT NULL,
                    bed_rate_cents INTEGER NOT NULL, resident_rate_cents INTEGER NOT NULL,
                    amount_cents INTEGER NOT NULL, status TEXT NOT NULL,
                    created_at TEXT NOT NULL, UNIQUE(owner_id,period)
                );
                CREATE TABLE IF NOT EXISTS ss_submissions (
                    id TEXT PRIMARY KEY, invoice_id TEXT NOT NULL REFERENCES ss_invoices(id),
                    owner_id TEXT NOT NULL, utr TEXT NOT NULL, proof_file TEXT NOT NULL,
                    proof_media_type TEXT NOT NULL, status TEXT NOT NULL,
                    submitted_at TEXT NOT NULL, reviewed_at TEXT, reviewed_by TEXT, remarks TEXT,
                    UNIQUE(owner_id,utr)
                );
                CREATE TABLE IF NOT EXISTS ss_audit (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    actor TEXT NOT NULL, action TEXT NOT NULL, subject TEXT NOT NULL,
                    details TEXT NOT NULL, at TEXT NOT NULL
                );
            ''')
            columns={r[1] for r in db.execute('PRAGMA table_info(ss_submissions)').fetchall()}
            if 'bank_verified' not in columns:
                db.execute('ALTER TABLE ss_submissions ADD COLUMN bank_verified INTEGER NOT NULL DEFAULT 0')
            if 'activation_status' not in columns:
                db.execute("ALTER TABLE ss_submissions ADD COLUMN activation_status TEXT NOT NULL DEFAULT 'not_applicable'")
            if 'activation_error' not in columns:
                db.execute("ALTER TABLE ss_submissions ADD COLUMN activation_error TEXT")

    def connect(self):
        db = sqlite3.connect(self.db_path, timeout=20)
        db.row_factory = sqlite3.Row
        db.execute('PRAGMA foreign_keys=ON')
        db.execute('PRAGMA busy_timeout=20000')
        return db

    @staticmethod
    def obj(row):
        return dict(row) if row is not None else None

    def audit(self, db, actor: str, action: str, subject: str, details: object):
        db.execute('INSERT INTO ss_audit(actor,action,subject,details,at) VALUES(?,?,?,?,?)',
                   (actor, action, subject, json.dumps(details), utcnow()))

    def set_pricing(self, actor: str, bed_rate: object, resident_rate: object):
        # The bed-based rate is retained as a compatibility input only.
        # Enforce resident-only billing even for older API clients.
        b, r = 0, cents(resident_rate)
        with self.lock, self.connect() as db:
            db.execute('INSERT INTO ss_pricing VALUES(1,?,?,?,?) ON CONFLICT(singleton) DO UPDATE SET '
                       'bed_rate_cents=excluded.bed_rate_cents,resident_rate_cents=excluded.resident_rate_cents,'
                       'updated_at=excluded.updated_at,updated_by=excluded.updated_by',
                       (b, r, utcnow(), actor))
            self.audit(db, actor, 'pricing_updated', 'pricing', {'bed_rate_cents': b, 'resident_rate_cents': r})
        return {'bed_rate': rupees(b), 'resident_rate': rupees(r)}

    def pricing(self):
        with self.connect() as db:
            row = db.execute('SELECT * FROM ss_pricing WHERE singleton=1').fetchone()
        if row is None:
            return None
        return {'bed_rate': rupees(0), 'resident_rate': rupees(row['resident_rate_cents'])}

    def set_qr(self, actor, data, beneficiary, upi_id):
        if not data or len(data) > MAX_QR_BYTES:
            raise ValueError('QR image must be 1 byte to 2 MB')
        mime = detected_image(data)
        if not mime:
            raise ValueError('QR must be a PNG or JPEG image')
        extension = '.png' if mime == 'image/png' else '.jpg'
        name = uuid.uuid4().hex + extension
        (self.media_dir / name).write_bytes(data)
        with self.lock, self.connect() as db:
            old = db.execute('SELECT filename FROM ss_qr WHERE singleton=1').fetchone()
            db.execute('INSERT INTO ss_qr VALUES(1,?,?,?,?,1,?,?) ON CONFLICT(singleton) DO UPDATE SET '
                       'filename=excluded.filename,media_type=excluded.media_type,beneficiary=excluded.beneficiary,'
                       'upi_id=excluded.upi_id,enabled=1,updated_at=excluded.updated_at,updated_by=excluded.updated_by',
                       (name, mime, beneficiary, upi_id, utcnow(), actor))
            self.audit(db, actor, 'qr_updated', 'qr', {'beneficiary': beneficiary, 'upi_id': upi_id})
        # Keep old image for a historical forensic trail instead of deleting it.
        return self.qr()

    def qr(self):
        with self.connect() as db:
            row = db.execute('SELECT * FROM ss_qr WHERE singleton=1').fetchone()
        if row is None:
            return None
        d = dict(row)
        d.pop('filename', None)
        return d

    def qr_path(self):
        with self.connect() as db:
            row = db.execute('SELECT filename,media_type,enabled FROM ss_qr WHERE singleton=1').fetchone()
        if not row or not row['enabled']:
            raise LookupError('Payment QR has not been enabled')
        return self.media_dir / row['filename'], row['media_type']

    def set_qr_enabled(self, actor, enabled: bool):
        with self.lock, self.connect() as db:
            changed = db.execute('UPDATE ss_qr SET enabled=?,updated_at=?,updated_by=? WHERE singleton=1',
                                 (int(enabled), utcnow(), actor)).rowcount
            if not changed:
                raise LookupError('No QR uploaded')
            self.audit(db, actor, 'qr_enabled_changed', 'qr', {'enabled': enabled})
        return self.qr()

    def issue_invoice(self, owner_id: str, period: str, beds: int, residents: int, legacy_guard=None):
        if not (isinstance(beds, int) and isinstance(residents, int)) or min(beds, residents) < 0:
            raise ValueError('Invalid bed/resident count')
        if len(period) != 7 or period[4] != '-' or not period[:4].isdigit() or not period[5:].isdigit() or not 1 <= int(period[5:]) <= 12:
            raise ValueError('Period must be YYYY-MM')
        with self.lock, self.connect() as db:
            existing = db.execute('SELECT * FROM ss_invoices WHERE owner_id=? AND period=?', (owner_id,period)).fetchone()
            if existing:
                return dict(existing)
            if legacy_guard and legacy_guard(owner_id, period):
                raise ValueError('Existing legacy invoice for this owner/month; do not double bill')
            pricing = db.execute('SELECT * FROM ss_pricing WHERE singleton=1').fetchone()
            if pricing is None:
                raise LookupError('Admin must configure pricing first')
            # Bed count remains a snapshot of capacity, not a billable item.
            amount = residents * pricing['resident_rate_cents']
            invoice_id = uuid.uuid4().hex
            db.execute('INSERT INTO ss_invoices VALUES(?,?,?,?,?,?,?,?,?,?)',
                       (invoice_id,owner_id,period,beds,residents,0,
                        pricing['resident_rate_cents'],amount,'unpaid',utcnow()))
            self.audit(db,'system','invoice_created',invoice_id,{'owner_id':owner_id,'period':period,'amount_cents':amount})
            return dict(db.execute('SELECT * FROM ss_invoices WHERE id=?',(invoice_id,)).fetchone())

    def invoices(self, owner_id=None):
        with self.connect() as db:
            if owner_id is None:
                rows = db.execute('SELECT * FROM ss_invoices ORDER BY period DESC,created_at DESC').fetchall()
            else:
                rows = db.execute('SELECT * FROM ss_invoices WHERE owner_id=? ORDER BY period DESC',(owner_id,)).fetchall()
        return [dict(x) for x in rows]

    def submit(self, owner_id, invoice_id, utr, data):
        utr = utr.strip().upper()
        if not 6 <= len(utr) <= 64 or not all(c.isalnum() or c in '-_/' for c in utr):
            raise ValueError('Invalid UTR/reference number')
        if not data or len(data) > MAX_IMAGE_BYTES:
            raise ValueError('Proof must be 1 byte to 5 MB')
        mime = detected_image(data)
        if not mime:
            raise ValueError('Proof must be a PNG or JPEG')
        with self.lock, self.connect() as db:
            invoice = db.execute('SELECT * FROM ss_invoices WHERE id=? AND owner_id=?',(invoice_id,owner_id)).fetchone()
            if not invoice:
                raise LookupError('Invoice not found for this owner')
            if invoice['status'] == 'paid':
                raise ValueError('Invoice already paid')
            if db.execute("SELECT 1 FROM ss_submissions WHERE invoice_id=? AND status='pending'",(invoice_id,)).fetchone():
                raise ValueError('A payment is already awaiting review')
            if db.execute('SELECT 1 FROM ss_submissions WHERE owner_id=? AND utr=?',(owner_id,utr)).fetchone():
                raise ValueError('Reference already submitted')
            name=uuid.uuid4().hex+('.png' if mime=='image/png' else '.jpg')
            (self.media_dir/name).write_bytes(data)
            sid=uuid.uuid4().hex
            db.execute('INSERT INTO ss_submissions(id,invoice_id,owner_id,utr,proof_file,proof_media_type,status,submitted_at) VALUES(?,?,?,?,?,?,?,?)',
                       (sid,invoice_id,owner_id,utr,name,mime,'pending',utcnow()))
            self.audit(db,owner_id,'payment_submitted',sid,{'invoice_id':invoice_id})
        return {'id':sid,'status':'pending'}

    def submissions(self, owner_id=None):
        with self.connect() as db:
            if owner_id is None:
                rows=db.execute('SELECT * FROM ss_submissions ORDER BY submitted_at DESC').fetchall()
            else:
                rows=db.execute('SELECT * FROM ss_submissions WHERE owner_id=? ORDER BY submitted_at DESC',(owner_id,)).fetchall()
        return [{k:v for k,v in dict(r).items() if k!='proof_file'} for r in rows]

    def proof_path(self,sid,owner_id=None):
        with self.connect() as db:
            if owner_id is None:
                row=db.execute('SELECT proof_file,proof_media_type FROM ss_submissions WHERE id=?',(sid,)).fetchone()
            else:
                row=db.execute('SELECT proof_file,proof_media_type FROM ss_submissions WHERE id=? AND owner_id=?',(sid,owner_id)).fetchone()
        if not row:
            raise LookupError('Proof not found')
        return self.media_dir / row['proof_file'],row['proof_media_type']

    def review(self,actor,sid,approve:bool,remarks:str,bank_verified:bool=False):
        with self.lock,self.connect() as db:
            submission=db.execute('SELECT * FROM ss_submissions WHERE id=?',(sid,)).fetchone()
            if not submission:
                raise LookupError('Submission not found')
            if submission['status']!='pending':
                raise ValueError('Submission already reviewed')
            if approve and not bank_verified:
                raise ValueError('Bank credit must be independently verified before approval')
            if approve:
                invoice=db.execute('SELECT status FROM ss_invoices WHERE id=?',(submission['invoice_id'],)).fetchone()
                if invoice['status']=='paid':
                    raise ValueError('Invoice already paid')
            status='approved' if approve else 'rejected'
            db.execute("UPDATE ss_submissions SET status=?,reviewed_at=?,reviewed_by=?,remarks=?,bank_verified=?,activation_status=? WHERE id=?",
                       (status,utcnow(),actor,remarks[:500],int(approve and bank_verified),
                        'pending' if approve else 'not_applicable',sid))
            if approve:
                db.execute("UPDATE ss_invoices SET status='paid' WHERE id=?",(submission['invoice_id'],))
            self.audit(db,actor,'payment_reviewed',sid,{'status':status})
            return {'id':sid,'status':status,'activation_status':'pending' if approve else 'not_applicable'}

    def approved_payment(self,sid):
        with self.connect() as db:
            row=db.execute('SELECT s.id,s.invoice_id,s.owner_id,s.status,s.bank_verified,i.period FROM ss_submissions s JOIN ss_invoices i ON i.id=s.invoice_id WHERE s.id=?',(sid,)).fetchone()
            return dict(row) if row else None

    def mark_activation(self,sid,status,error=None):
        if status not in ('activated','pending'):raise ValueError('Invalid activation status')
        with self.lock,self.connect() as db:
            db.execute("UPDATE ss_submissions SET activation_status=?,activation_error=? WHERE id=? AND status='approved'",
                       (status,(error or '')[:300] if status=='pending' else None,sid))


class Rates(BaseModel):
    # Optional for new clients; accepted but ignored for old clients.
    bed_rate: Decimal = Field(default=Decimal('0'),ge=0,le=1000000)
    resident_rate: Decimal = Field(ge=0,le=1000000)


class QRState(BaseModel):
    enabled: bool


class Review(BaseModel):
    approve: bool
    bank_verified: bool = False
    remarks: str = Field(default='',max_length=500)


def create_router(store:BillingStore, principal_dependency:Callable, count_provider:Callable[[str],tuple[int,int]], legacy_guard=None, activate_payment=None):
    """principal_dependency MUST return {'id':str,'role':'platform_admin'|'owner', 'owner_id':str optional}.
    count_provider(owner_id) MUST use existing authoritative app records and exclude inactive residents.
    Both must be implemented by the host application before mounting this router.
    """
    router=APIRouter(prefix='/api/owner-subscriptions',tags=['Owner subscriptions'])

    def owner_or_admin(p=Depends(principal_dependency)):
        if not isinstance(p,dict) or p.get('role') not in ('platform_admin','owner') or not p.get('id'):
            raise HTTPException(403,'Unauthorized role')
        if p['role']=='owner' and not p.get('owner_id'):
            raise HTTPException(403,'Missing owner mapping')
        return p

    def admin(p=Depends(owner_or_admin)):
        if p['role']!='platform_admin':
            raise HTTPException(403,'Platform administrator required')
        return p

    def owner(p=Depends(owner_or_admin)):
        if p['role']!='owner':
            raise HTTPException(403,'PG owner required')
        return p

    @router.get('/admin/settings')
    def settings(p=Depends(admin)):
        return {'pricing':store.pricing(),'qr':store.qr()}

    @router.put('/admin/pricing')
    def pricing(body:Rates,p=Depends(admin)):
        return store.set_pricing(p['id'],body.bed_rate,body.resident_rate)

    @router.post('/admin/qr')
    async def qr_upload(beneficiary:str=Form(...),upi_id:str=Form(...),qr:UploadFile=File(...),p=Depends(admin)):
        if not beneficiary.strip() or len(beneficiary)>120 or not upi_id.strip() or len(upi_id)>120:
            raise HTTPException(400,'Beneficiary and UPI ID required')
        data=await qr.read(MAX_QR_BYTES+1)
        try:
            return store.set_qr(p['id'],data,beneficiary.strip(),upi_id.strip())
        except ValueError as exc:
            raise HTTPException(400,str(exc)) from exc

    @router.put('/admin/qr/status')
    def qr_status(body:QRState,p=Depends(admin)):
        try:return store.set_qr_enabled(p['id'],body.enabled)
        except LookupError as exc:raise HTTPException(404,str(exc)) from exc

    @router.get('/payment-qr')
    def qr_image(p=Depends(owner_or_admin)):
        try:path,mime=store.qr_path()
        except LookupError as exc:raise HTTPException(404,str(exc)) from exc
        return FileResponse(path,media_type=mime,headers={'Cache-Control':'private, no-store','X-Content-Type-Options':'nosniff'})

    @router.get('/me')
    def my_subscription(p=Depends(owner)):
        return {'pricing':store.pricing(),'qr':store.qr(),'invoices':store.invoices(p['owner_id']),
                'payments':store.submissions(p['owner_id'])}

    @router.post('/me/invoice/{period}')
    def owner_invoice(period:str,p=Depends(owner)):
        try:
            beds,residents=count_provider(p['owner_id'])
            return store.issue_invoice(p['owner_id'],period,beds,residents,legacy_guard=legacy_guard)
        except (LookupError,ValueError,TypeError) as exc:
            raise HTTPException(400,str(exc)) from exc

    @router.post('/me/payments')
    async def submit_payment(invoice_id:str=Form(...),utr:str=Form(...),proof:UploadFile=File(...),p=Depends(owner)):
        data=await proof.read(MAX_IMAGE_BYTES+1)
        try:return store.submit(p['owner_id'],invoice_id,utr,data)
        except LookupError as exc:raise HTTPException(404,str(exc)) from exc
        except ValueError as exc:raise HTTPException(400,str(exc)) from exc

    @router.get('/admin/invoices')
    def all_invoices(p=Depends(admin)):
        return store.invoices()

    @router.get('/admin/payments')
    def all_payments(p=Depends(admin)):
        return store.submissions()

    @router.get('/admin/payments/{sid}/proof')
    def payment_proof(sid:str,p=Depends(admin)):
        try:path,mime=store.proof_path(sid)
        except LookupError as exc:raise HTTPException(404,str(exc)) from exc
        return FileResponse(path,media_type=mime,headers={'Cache-Control':'private, no-store','X-Content-Type-Options':'nosniff'})

    @router.put('/admin/payments/{sid}/review')
    def review(sid:str,body:Review,p=Depends(admin)):
        try:
            if body.approve and legacy_guard:
                pay=store.approved_payment(sid)
                # For pending submissions, resolve period from invoice before approval.
                if pay and legacy_guard(pay['owner_id'],pay['period']):
                    raise ValueError('Legacy invoice exists for this owner/month; reconcile before approval')
            result=store.review(p['id'],sid,body.approve,body.remarks,bank_verified=body.bank_verified)
            if body.approve and activate_payment:
                result['activation']=_reconcile(sid,p['id'])
            return result
        except LookupError as exc:raise HTTPException(404,str(exc)) from exc
        except ValueError as exc:raise HTTPException(409,str(exc)) from exc

    def _reconcile(sid,admin_id):
        payment=store.approved_payment(sid)
        if not payment or payment['status']!='approved':
            raise HTTPException(409,'Payment is not approved')
        if not activate_payment:
            return {'status':'pending','detail':'Activation bridge not configured'}
        try:
            outcome=activate_payment(payment,admin_id)
            store.mark_activation(sid,'activated')
            return outcome
        except Exception:
            logging.getLogger(__name__).exception("Subscription activation failed for submission %s",sid)
            # Fail closed: payment stays approved, but entitlement is not claimed
            # active. Admin can retry after resolving the reported integration issue.
            store.mark_activation(sid,'pending','Activation failed; review backend log and retry')
            return {'status':'pending','detail':'Activation failed; administrator retry required'}

    @router.post('/admin/payments/{sid}/reconcile')
    def retry_activation(sid:str,p=Depends(admin)):
        return _reconcile(sid,p['id'])

    return router

"""Isolated payment-review integration test, using an empty temporary SQLite DB."""
import io
import os
import tempfile
import sys
from datetime import datetime, timezone
from decimal import Decimal
from pathlib import Path


def test_invoice_mismatch_is_advisory_and_bank_gate_remains(monkeypatch):
    with tempfile.TemporaryDirectory() as tmp:
        monkeypatch.setenv('DATABASE_URL', 'sqlite:///' + str(Path(tmp) / 'test.db'))
        monkeypatch.setenv('SECRET_KEY', 'test-only-payment-v31-secret-longer-than-32bytes')
        monkeypatch.setenv('DEMO_SEED', 'false')
        # Isolate FastAPI/SQLAlchemy global engine between temporary DB tests.
        for name in ('main', 'v2_api', 'v3_api', 'identity_api', 'platform_api'):
            sys.modules.pop(name, None)
        from fastapi.testclient import TestClient
        import main
        import jwt
        import risk_checks
        import v3_api
        from main import Tenant, User, Invoice, SessionLocal, passwords
        from PIL import Image
        from v3_api import meta

        v3_api.STORAGE = Path(tmp) / 'files'
        with SessionLocal() as s:
            tenant = Tenant(name='Test PG')
            s.add(tenant)
            s.flush()
            owner = User(tenant_id=tenant.id, name='Owner', email='owner-pay@test.invalid',
                         role='owner', password_hash=passwords.hash('TestPassword123!'), room='')
            resident = User(tenant_id=tenant.id, name='Resident', email='resident-pay@test.invalid',
                            role='resident', password_hash=passwords.hash('TestPassword123!'), room='')
            s.add_all([owner, resident]);s.flush()
            invoice = Invoice(tenant_id=tenant.id, resident_id=resident.id, period='2026-11',
                              amount=Decimal('3000'), paid=Decimal('0'), due_date='2026-11-30')
            s.add(invoice);s.commit()
            tid, uid, oid, iid = tenant.id, resident.id, owner.id, invoice.id
        def auth(uid):
            t = jwt.encode({'sub':str(uid),'tenant':tid,
                'iat':int(datetime.now(timezone.utc).timestamp())},
                os.environ['SECRET_KEY'], algorithm='HS256')
            return {'Authorization':'Bearer '+t}
        old_ocr = risk_checks._ocr_text
        risk_checks._ocr_text = lambda *_: ('INR 2000.00 ref 123456789012', 'completed')
        client = TestClient(main.app)
        try:
            img = Image.new('RGB',(60,60),'white')
            buf = io.BytesIO(); img.save(buf, format='PNG')
            uploaded = client.post('/api/v3/files/payment', headers=auth(uid),
                files={'file':('receipt.png',buf.getvalue(),'image/png')})
            assert uploaded.status_code == 201, uploaded.text
            fid = uploaded.json()['id']
            pay = client.post('/api/v3/payments',headers=auth(uid),json={
                'invoice_id':iid,'amount':'3000.00','reference':'123456789012','file_id':fid})
            assert pay.status_code == 201, pay.text
            with SessionLocal() as s:
                risk = meta(s, tid, 'payment_meta', pay.json()['id'])
                assert risk['risk_level'] == 'review_required'
                assert any('amount does not match' in f for f in risk['risk_flags'])
                assert not risk['authenticity_verified']
            # An OCR result must never bypass the manual owner bank-credit gate.
            refused = client.post(f"/api/v3/payments/{pay.json()['id']}/review",
                headers=auth(oid), json={'decision':'approved','bank_confirmed':False})
            assert refused.status_code == 422, refused.text
            # A flagged upload additionally requires explicit risk acknowledgement.
            no_ack = client.post(f"/api/v3/payments/{pay.json()['id']}/review",
                headers=auth(oid), json={'decision':'approved','bank_confirmed':True})
            assert no_ack.status_code == 422, no_ack.text
            # Pending submissions must reserve the outstanding balance; do not double-submit.
            duplicate_pending = client.post('/api/v3/payments',headers=auth(uid),json={
                'invoice_id':iid,'amount':'3000.00','reference':'NEWREFERENCE123','file_id':fid})
            assert duplicate_pending.status_code == 409, duplicate_pending.text
            current = client.get('/api/v3/state',headers=auth(uid))
            assert current.status_code == 200, current.text
            assert any(p['status']=='pending' and p['invoice_id']==iid for p in current.json()['payments'])
            approved = client.post(f"/api/v3/payments/{pay.json()['id']}/review",
                headers=auth(oid), json={'decision':'approved','bank_confirmed':True,
                                         'risk_acknowledged':True})
            assert approved.status_code == 200, approved.text
            new_state = client.get('/api/v3/state',headers=auth(uid))
            assert new_state.status_code == 200
            assert any(p['status']=='approved' and p['invoice_id']==iid and
                p['risk_acknowledged'] for p in new_state.json()['payments'])
        finally:
            client.close()
            risk_checks._ocr_text = old_ocr
            main.engine.dispose()

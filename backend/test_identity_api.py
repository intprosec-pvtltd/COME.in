"""Run with: pytest -q test_identity_api.py
API authorization and tenant isolation smoke checks. No real ID documents.
"""
import io
import os
import importlib
import tempfile
from pathlib import Path

def test_resident_proof_is_tenant_scoped(monkeypatch):
    with tempfile.TemporaryDirectory() as tmp:
        monkeypatch.setenv('DATABASE_URL', 'sqlite:///' + str(Path(tmp) / 'test.db'))
        monkeypatch.setenv('SECRET_KEY', 'test-only-do-not-use-in-production')
        monkeypatch.setenv('DEMO_SEED', 'false')
        from fastapi.testclient import TestClient
        import main
        from main import SessionLocal, Tenant, User, passwords
        import jwt
        from datetime import datetime, timezone
        with SessionLocal() as s:
            a = Tenant(name='PG A'); b = Tenant(name='PG B')
            s.add_all([a,b]);s.flush()
            people = [
                User(tenant_id=a.id,name='A owner',email='owner-a@test.invalid',role='owner',password_hash=passwords.hash('Aa123456!'),room=''),
                User(tenant_id=a.id,name='A resident',email='resident-a@test.invalid',role='resident',password_hash=passwords.hash('Aa123456!'),room=''),
                User(tenant_id=b.id,name='B owner',email='owner-b@test.invalid',role='owner',password_hash=passwords.hash('Aa123456!'),room=''),
                User(tenant_id=b.id,name='B resident',email='resident-b@test.invalid',role='resident',password_hash=passwords.hash('Aa123456!'),room=''),
            ]
            s.add_all(people);s.commit()
            identities = [(u.id,u.tenant_id) for u in people]
        def headers(index):
            uid,tid=identities[index]
            token=jwt.encode({'sub':str(uid),'tenant':tid,'iat':int(datetime.now(timezone.utc).timestamp())},
                             os.environ['SECRET_KEY'], algorithm='HS256')
            return {'Authorization':'Bearer '+token}
        client=TestClient(main.app)
        try:
            payload=b'\x89PNG\r\n\x1a\n' + b'fake-test-data'
            r=client.post('/api/identity/proofs',headers=headers(1), files={'file':('proof.png',payload,'image/png')})
            assert r.status_code==201,r.text
            fid=r.json()['id']
            assert client.get('/api/identity/proofs/me',headers=headers(1)).json()[0]['id']==fid
            assert client.get(f'/api/identity/residents/{identities[1][0]}/proofs',headers=headers(0)).status_code==200
            assert client.get(f'/api/identity/residents/{identities[1][0]}/proofs',headers=headers(2)).status_code==404
            assert client.get(f'/api/identity/proofs/{fid}/file',headers=headers(3)).status_code==404
            assert client.post(f'/api/identity/proofs/{fid}/review',headers=headers(1),json={'decision':'approved'}).status_code==403
            assert client.post(f'/api/identity/proofs/{fid}/review',headers=headers(0),json={'decision':'approved'}).status_code==200
            assert client.post(f'/api/identity/proofs/{fid}/review',headers=headers(0),json={'decision':'rejected'}).status_code==409
            assert client.get(f'/api/identity/proofs/{fid}/file',headers=headers(0)).content==payload

            # Once approved, the resident must not submit another proof.
            assert client.post('/api/identity/proofs',headers=headers(1),
                files={'file':('another.png',payload,'image/png')}).status_code==409

            # A second resident's pending upload is also locked until rejection.
            second = client.post('/api/identity/proofs',headers=headers(3),
                files={'file':('second.png',payload,'image/png')})
            assert second.status_code==201,second.text
            sid=second.json()['id']
            assert client.post('/api/identity/proofs',headers=headers(3),
                files={'file':('repeat.png',payload,'image/png')}).status_code==409
            reject=client.post(f'/api/identity/proofs/{sid}/review',headers=headers(2),
                json={'decision':'rejected','note':'Please submit a clearer image'})
            assert reject.status_code==200,reject.text
            assert reject.json()['review_note']=='Please submit a clearer image'
            replacement=client.post('/api/identity/proofs',headers=headers(3),
                files={'file':('replacement.png',payload,'image/png')})
            assert replacement.status_code==201,replacement.text
            newest=client.get('/api/identity/proofs/me',headers=headers(3)).json()[0]
            assert newest['id']==replacement.json()['id']
            assert newest['status']=='pending'
            assert client.post(f'/api/identity/proofs/{sid}/review',headers=headers(2),
                json={'decision':'approved'}).status_code==409
        finally:
            client.close()
            main.engine.dispose()

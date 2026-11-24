"""Authenticated display-photo smoke tests. Run with existing project dependencies installed."""
import io
import os
import sys
import tempfile
from pathlib import Path
from datetime import datetime, timezone


def test_display_photos_permissions_and_persistence(monkeypatch):
    from PIL import Image
    import jwt
    from fastapi.testclient import TestClient
    with tempfile.TemporaryDirectory() as tmp:
        monkeypatch.setenv('DATABASE_URL', 'sqlite:///' + str(Path(tmp) / 'photos.db'))
        monkeypatch.setenv('SECRET_KEY', 'photo-test-key-32-characters-long')
        monkeypatch.setenv('DEMO_SEED', 'false')
        names = ('main', 'v2_api', 'v3_api', 'identity_api', 'platform_api', 'account_deletion', 'push_notifications', 'phone_auth')
        original = {name: sys.modules.get(name) for name in names}
        for name in names: sys.modules.pop(name, None)
        try:
            import main
            from main import SessionLocal, Tenant, User, passwords
            from identity_api import DisplayPhoto
            from sqlalchemy import select
            with SessionLocal() as s:
                t1, t2 = Tenant(name='Test PG'), Tenant(name='Other PG')
                s.add_all([t1, t2]); s.flush()
                users = [
                    User(tenant_id=t1.id, name='Owner', email='photo-owner@test.invalid', role='owner', room='', password_hash=passwords.hash('Password123!')),
                    User(tenant_id=t1.id, name='Resident', email='photo-resident@test.invalid', role='resident', room='', password_hash=passwords.hash('Password123!')),
                    User(tenant_id=t2.id, name='Other', email='photo-other@test.invalid', role='owner', room='', password_hash=passwords.hash('Password123!')),
                ]
                s.add_all(users); s.flush()
                ids = [(u.id, u.tenant_id) for u in users]; s.commit()
            def headers(idx):
                uid, tenant = ids[idx]
                token = jwt.encode({'sub':str(uid),'tenant':tenant,'iat':int(datetime.now(timezone.utc).timestamp())}, os.environ['SECRET_KEY'],algorithm='HS256')
                return {'Authorization':'Bearer '+token}
            image = Image.new('RGB', (64, 48), 'purple')
            stream = io.BytesIO(); image.save(stream, format='PNG'); payload = stream.getvalue()
            client = TestClient(main.app)
            url = f'/api/identity/display-photos/user/{ids[1][0]}'
            assert client.get(url).status_code == 401
            assert client.post(url, headers=headers(0), files={'file':('a.png',payload,'image/png')}).status_code == 403
            assert client.post(url, headers=headers(1), files={'file':('broken.png',b'not-image','image/png')}).status_code == 415
            uploaded = client.post(url, headers=headers(1), files={'file':('face.png',payload,'image/png')})
            assert uploaded.status_code == 200, uploaded.text
            assert uploaded.json()['revision'] == 1
            assert client.get(url, headers=headers(1)).headers['content-type'] == 'image/jpeg'
            assert client.get(url, headers=headers(0)).status_code == 200
            assert client.get(url, headers=headers(2)).status_code == 404 or client.get(url, headers=headers(2)).status_code == 403
            assert client.get('/api/v3/state', headers=headers(1)).json()['profile']['photo_revision'] == 1
            pu = '/api/identity/display-photos/property/0'
            assert client.post(pu, headers=headers(1),files={'file':('pg.png',payload,'image/png')}).status_code == 403
            assert client.post(pu, headers=headers(0),files={'file':('pg.png',payload,'image/png')}).status_code == 200
            assert client.get('/api/v3/state', headers=headers(0)).json()['properties'][0]['photo_revision'] == 1
            with SessionLocal() as s:
                assert s.scalar(select(DisplayPhoto).where(DisplayPhoto.tenant_id==ids[0][1],DisplayPhoto.kind=='property')).content
            assert client.delete(url, headers=headers(1)).status_code == 200
            assert client.get(url, headers=headers(1)).status_code == 404
        finally:
            if 'client' in locals():
                client.close()
            if 'main' in locals():
                main.engine.dispose()
            for name in names: sys.modules.pop(name, None)
            for name, module in original.items():
                if module is not None: sys.modules[name] = module

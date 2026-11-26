from decimal import Decimal

from fastapi.testclient import TestClient
from sqlalchemy import select

from main import Invoice, SessionLocal, Tenant, User, app, passwords
from platform_api import AdminUser
from v3_api import Document


def test_active_resident_direct_deletion(monkeypatch):
    monkeypatch.setenv('PLATFORM_ADMIN_JWT_SECRET', 'test-signing-key-for-admin-only-123456')
    client = TestClient(app)
    with SessionLocal() as s:
        tenants = [Tenant(name=name) for name in ('QA One', 'QA Two')]
        s.add_all(tenants)
        s.flush()
        users = []
        for name, role, tenant in [('owner', 'owner', tenants[0]), ('web', 'resident', tenants[0]),
                                   ('admin-target', 'resident', tenants[0]), ('linked', 'resident', tenants[0]),
                                   ('other', 'resident', tenants[1])]:
            user = User(tenant_id=tenant.id, role=role, email=name+'@example.test', name=name,
                        room='', password_hash=passwords.hash('SyntheticPass123!'))
            s.add(user)
            users.append(user)
        s.flush()
        owner, web, admin_target, linked, other = [user.id for user in users]
        s.add(Document(tenant_id=tenants[0].id, kind='profile', key=str(web), payload={'phone':'synthetic'}))
        s.add(Invoice(tenant_id=tenants[0].id, resident_id=linked, period='2026-11', amount=Decimal('100'),
                      paid=Decimal('0'), due_date='2026-11-30'))
        s.add(AdminUser(name='QA Admin', email='admin@example.test', is_active=1,
                        password_hash=passwords.hash('SyntheticPass123!')))
        s.commit()

    def login(email, url='/api/login', key='token'):
        resp = client.post(url, json={'email':email+'@example.test','password':'SyntheticPass123!'})
        return {'Authorization':'Bearer '+resp.json()[key]}

    owner_headers = login('owner')
    admin_headers = login('admin','/api/platform/auth/login','access_token')
    resident_headers = login('web')
    def erase(path, email, headers):
        return client.request('DELETE', path, json={'confirm_email':email+'@example.test'}, headers=headers)

    web_path = f'/api/v3/residents/{web}'
    assert client.get(web_path+'/deletion-review', headers=owner_headers).json()['requires_deactivation'] is False
    assert erase(web_path, 'web', resident_headers).status_code == 403
    assert erase(f'/api/v3/residents/{other}', 'other', owner_headers).status_code == 404
    assert erase(f'/api/v3/residents/{linked}', 'linked', owner_headers).status_code == 409
    assert erase(web_path, 'wrong', owner_headers).status_code == 422
    assert erase(web_path, 'web', owner_headers).status_code == 200
    assert client.get('/api/me', headers=resident_headers).status_code == 401
    assert erase(f'/api/platform/users/{admin_target}', 'admin-target', admin_headers).status_code == 200
    with SessionLocal() as s:
        assert s.get(User, web) is None
        assert s.get(User, admin_target) is None
        assert s.get(User, linked) is not None
        assert s.scalar(select(Document).where(Document.kind=='profile',Document.key==str(web))) is None


def test_admin_deletes_eligible_owner_and_rejects_stale_session(monkeypatch):
    monkeypatch.setenv('PLATFORM_ADMIN_JWT_SECRET', 'test-signing-key-for-admin-only-123456')
    password = 'OwnerDeletionQA123!'
    with SessionLocal() as s:
        tenant = Tenant(name='Owner deletion QA')
        s.add(tenant)
        s.flush()
        roles = {}
        for label in ('remaining', 'removable'):
            user = User(tenant_id=tenant.id, role='owner', email=f'{label}@owner-qa.example.test',
                        name=label, room='', password_hash=passwords.hash(password))
            s.add(user)
            s.flush()
            roles[label] = user.id
        tenant_id = tenant.id
        s.add(AdminUser(name='Owner Deletion QA', email='admin@owner-qa.example.test', is_active=1,
                        password_hash=passwords.hash(password)))
        s.commit()

    client = TestClient(app)
    owner_login = {'email':'removable@owner-qa.example.test','password':password}
    admin = client.post('/api/platform/auth/login', json={
        'email':'admin@owner-qa.example.test','password':password
    }).json()['access_token']
    stale = client.post('/api/login', json=owner_login).json()['token']
    admin_headers = {'Authorization':'Bearer '+admin}
    old_headers = {'Authorization':'Bearer '+stale}
    removed = client.request('DELETE', f'/api/platform/users/{roles["removable"]}',
                             json={'confirm_email':owner_login['email']}, headers=admin_headers)
    assert removed.status_code == 200, removed.text
    assert client.post('/api/login', json=owner_login).status_code == 401
    remaining = client.request('DELETE', f'/api/platform/users/{roles["remaining"]}',
                              json={'confirm_email':'remaining@owner-qa.example.test'}, headers=admin_headers)
    assert remaining.status_code == 409
    assert remaining.json()['detail']['blockers']['last_active_pg_owner'] == 1
    with SessionLocal() as s:
        assert s.get(User, roles['removable']) is None
        s.add(User(id=roles['removable'], tenant_id=tenant_id, role='owner',
                   email='replacement@owner-qa.example.test', name='Replacement', room='',
                   password_hash=passwords.hash(password)))
        s.commit()
    assert client.get('/api/me', headers=old_headers).status_code == 401
    replacement = client.post('/api/login', json={
        'email':'replacement@owner-qa.example.test','password':password
    }).json()['token']
    assert client.get('/api/me', headers={'Authorization':'Bearer '+replacement}).status_code == 200

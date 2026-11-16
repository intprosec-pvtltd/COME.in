"""Run separately from backend: python -m pytest -q tests/test_platform_admin_users.py
Uses temporary SQLite; never accesses production or local pg_dev.db.
"""
from pathlib import Path
import pytest
from fastapi.testclient import TestClient


def test_profile_and_user_management(tmp_path, monkeypatch):
    monkeypatch.setenv('DATABASE_URL', 'sqlite:///' + str(tmp_path / 'admin_management.sqlite'))
    monkeypatch.setenv('DEMO_SEED', 'false')
    monkeypatch.setenv('PLATFORM_ADMIN_JWT_SECRET', 'P' * 48)
    monkeypatch.setenv('SECRET_KEY', 'S' * 48)
    import main
    from platform_api import AdminUser, install_schema
    install_schema()
    with main.SessionLocal() as s:
        s.add(AdminUser(email='admin@test.invalid', name='Test Admin',
                        password_hash=main.passwords.hash('correct-password-123'), is_active=1))
        s.commit()
    c = TestClient(main.app)
    login = c.post('/api/platform/auth/login', json={'email': 'admin@test.invalid', 'password':'correct-password-123'})
    assert login.status_code == 200, login.text
    headers = {'Authorization': 'Bearer ' + login.json()['access_token']}
    assert c.get('/api/platform/users').status_code == 401
    assert c.get('/api/platform/profile', headers=headers).status_code == 200
    assert c.put('/api/platform/profile', headers=headers, json={'name':'Renamed Admin', 'email':'newadmin@test.invalid', 'current_password':'bad'}).status_code == 403
    profile = c.put('/api/platform/profile', headers=headers, json={'name':'Renamed Admin', 'email':'newadmin@test.invalid', 'current_password':'correct-password-123'})
    assert profile.status_code == 200, profile.text
    assert profile.json()['email'] == 'newadmin@test.invalid'
    owner = c.post('/api/platform/owners', headers=headers, json={'business_name':'Test PG', 'owner_name':'Owner', 'owner_email':'owner@test.invalid', 'temporary_password':'temporary-password-123'})
    assert owner.status_code == 201, owner.text
    users = c.get('/api/platform/users', headers=headers)
    assert users.status_code == 200
    u = next(u for u in users.json() if u['email'] == 'owner@test.invalid')
    assert 'password_hash' not in u
    data = dict(name='Owner New',email='owner@test.invalid',role='owner',room='',is_active=False)
    # Last owner must not be disabled.
    blocked = c.put(f'/api/platform/users/{u["id"]}', headers=headers, json=data)
    assert blocked.status_code == 409, blocked.text
    data['name']='Owner Updated'
    data['is_active']=True
    ok = c.put(f'/api/platform/users/{u["id"]}', headers=headers, json=data)
    assert ok.status_code == 200, ok.text
    assert ok.json()['name']=='Owner Updated'
    pw = c.post('/api/platform/profile/password', headers=headers, json={'current_password':'correct-password-123', 'new_password':'different-new-password-123'})
    assert pw.status_code == 200, pw.text
    assert c.post('/api/platform/auth/login',json={'email':'newadmin@test.invalid','password':'correct-password-123'}).status_code == 401
    assert c.post('/api/platform/auth/login',json={'email':'newadmin@test.invalid','password':'different-new-password-123'}).status_code == 200

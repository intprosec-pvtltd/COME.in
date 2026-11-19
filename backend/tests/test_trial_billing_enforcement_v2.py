"""One-time trials, payment gating, reminders, and tenant privacy."""
from datetime import timedelta
import os
from fastapi.testclient import TestClient


def test_owner_trial_expiry_payment_gate_and_reminders(tmp_path, monkeypatch):
    monkeypatch.setenv('DATABASE_URL','sqlite:///'+str(tmp_path/'trial_gate.sqlite'))
    monkeypatch.setenv('SECRET_KEY','x'*48)
    monkeypatch.setenv('PLATFORM_ADMIN_JWT_SECRET','y'*48)
    monkeypatch.setenv('DEMO_SEED','false')
    monkeypatch.setenv('TRIAL_ENFORCEMENT_ENABLED','true')
    import main
    from trial_api import OrganizationTrial, TrialReminder, now, run_due_reminders
    from v3_api import Alert
    import uuid
    with main.SessionLocal() as db:
        tenant=main.Tenant(name='Trial gate '+uuid.uuid4().hex[:8]);db.add(tenant);db.flush()
        owner=main.User(tenant_id=tenant.id,role='owner',name='Trial owner',
            email=f'trial-{uuid.uuid4().hex}@test.local',password_hash=main.passwords.hash('test-pass-12345'),room='')
        db.add(owner);db.commit(); tid=tenant.id; email=owner.email; uid=owner.id
    client=TestClient(main.app)
    response=client.post('/api/login',json={'email':email,'password':'test-pass-12345'})
    assert response.status_code==200,response.text
    token=response.json()['token'];headers={'Authorization':'Bearer '+token}
    first=client.get('/api/trial/me',headers=headers)
    assert first.status_code==200 and first.json()['status']=='pending'
    active=client.post('/api/trial/start',headers=headers)
    assert active.status_code==200,active.text
    assert active.json()['status']=='trial_active'
    assert client.post('/api/trial/start',headers=headers).status_code==409
    # 7-day reminder: only PG owner; repeat execution cannot double-send.
    with main.SessionLocal() as db:
        trial=db.get(OrganizationTrial,tid)
        trial.expires_at=now()+timedelta(days=6, hours=12)
        db.commit()
    assert run_due_reminders()>=1
    assert run_due_reminders()>=0
    with main.SessionLocal() as db:
        reminders=db.query(TrialReminder).filter_by(tenant_id=tid).all()
        assert len(reminders)==1 and reminders[0].milestone==7
        alerts=db.query(Alert).filter_by(tenant_id=tid).all()
        assert len(alerts)==1 and alerts[0].user_id==uid
        trial=db.get(OrganizationTrial,tid)
        trial.expires_at=now()-timedelta(seconds=30)
        db.commit()
    # Payment must be accessible, business operations blocked server-side.
    assert client.get('/api/trial/me',headers=headers).json()['status']=='trial_expired'
    assert client.get('/api/v3/state',headers=headers).status_code==200
    blocked=client.post('/api/v3/entities/room',headers=headers,json={})
    assert blocked.status_code==402,blocked.text
    assert blocked.json()['code']=='subscription_payment_required'
    assert client.get('/api/owner-subscriptions/me',headers=headers).status_code==200
    assert client.post('/api/trial/start',headers=headers).status_code==409

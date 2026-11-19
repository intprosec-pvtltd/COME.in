"""Admin-only 15-day trial lifecycle on isolated SQLite, no production data."""
from datetime import timedelta
from fastapi.testclient import TestClient


def test_trial_management_is_admin_only(tmp_path, monkeypatch):
    monkeypatch.setenv('DATABASE_URL', 'sqlite:///' + str(tmp_path / 'trial.sqlite').replace('\\','/'))
    monkeypatch.setenv('DEMO_SEED', 'false')
    monkeypatch.setenv('PLATFORM_ADMIN_JWT_SECRET', 'T' * 48)
    monkeypatch.setenv('SECRET_KEY', 'Q' * 48)
    monkeypatch.setenv('TRIAL_ENFORCEMENT_ENABLED', 'true')
    import main
    from platform_api import AdminUser
    from trial_api import OrganizationTrial, now, state
    with main.SessionLocal() as s:
        s.add(AdminUser(email='root@trial.test',name='Trial Admin',
              password_hash=main.passwords.hash('very-secure-admin-password'),is_active=1))
        s.commit()
    c=TestClient(main.app)
    response=c.post('/api/platform/auth/login',json={
        'email':'root@trial.test','password':'very-secure-admin-password'})
    assert response.status_code==200,response.text
    headers={'Authorization':'Bearer '+response.json()['access_token']}
    owner=c.post('/api/platform/owners',headers=headers,json={
        'business_name':'Trial Test PG','owner_name':'Trial Owner','owner_email':'owner@trial.test',
        'temporary_password':'secure-temporary-password'})
    assert owner.status_code==201,owner.text
    tid=owner.json()['id']
    assert c.get('/api/platform/trials').status_code==401
    assert c.post(f'/api/platform/trials/{tid}/activate',json={'reason':'authorized activation'}).status_code==401
    listing=c.get('/api/platform/trials',headers=headers)
    assert listing.status_code==200
    assert next(x for x in listing.json() if x['tenant_id']==tid)['status']=='pending'
    activation=c.post(f'/api/platform/trials/{tid}/activate',headers=headers,json={'reason':'approved first pilot'})
    assert activation.status_code==200,activation.text
    assert activation.json()['status']=='trial_active'
    assert activation.json()['days_remaining']==15
    assert c.post(f'/api/platform/trials/{tid}/activate',headers=headers,json={'reason':'try restarting trial'}).status_code==409
    extension=c.post(f'/api/platform/trials/{tid}/extend',headers=headers,json={'days':7,'reason':'approved pilot extension'})
    assert extension.status_code==200,extension.text
    assert extension.json()['extension_days']==7
    assert c.post(f'/api/platform/trials/{tid}/extend',headers=headers,json={'days':60,'reason':'too many days'}).status_code==422
    suspension=c.post(f'/api/platform/trials/{tid}/suspend',headers=headers,json={'reason':'review requested'})
    assert suspension.status_code==200
    assert suspension.json()['status']=='suspended'
    assert c.post(f'/api/platform/trials/{tid}/convert',headers=headers,json={'reason':'payment not verified','payment_verified':True}).status_code==409
    resume=c.post(f'/api/platform/trials/{tid}/resume',headers=headers,json={'reason':'review completed'})
    assert resume.status_code==200
    with main.SessionLocal() as s:
        item=s.get(OrganizationTrial,tid)
        item.expires_at=now()-timedelta(hours=1)
        s.commit()
        assert state(s,tid)['status']=='trial_expired'
    assert c.post(f'/api/platform/trials/{tid}/convert',headers=headers,json={'reason':'invoice paid','payment_verified':False}).status_code==422
    paid=c.post(f'/api/platform/trials/{tid}/convert',headers=headers,json={'reason':'verified external bank payment','payment_verified':True})
    assert paid.status_code==409,paid.text  # No paid activation without a verified journal
    assert paid.json()['detail'].startswith('A verified active payment')
    assert c.get('/api/platform/trials',headers=headers).status_code==200

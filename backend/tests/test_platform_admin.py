"""Run with: pytest -q tests/test_platform_admin.py (from backend directory).
Uses temporary SQLite; does not modify your development database.
"""
import importlib
import os
from pathlib import Path
from decimal import Decimal
import pytest
from fastapi.testclient import TestClient


def test_platform_admin_isolated_and_billing(tmp_path, monkeypatch):
    monkeypatch.setenv('DATABASE_URL','sqlite:///'+str(tmp_path/'test_admin.db').replace('\\','/'))
    monkeypatch.setenv('DEMO_SEED','false')
    monkeypatch.setenv('PLATFORM_ADMIN_JWT_SECRET','a'*48)
    monkeypatch.setenv('SECRET_KEY','b'*48)
    import main
    from platform_api import AdminUser
    from v2_api import Room
    from platform_api import install_schema
    install_schema()
    with main.SessionLocal() as s:
        s.add(AdminUser(email='admin@test.local',name='Administrator',password_hash=main.passwords.hash('different-very-secure-password'),is_active=1));s.commit()
    c=TestClient(main.app)
    denied=c.get('/api/platform/overview')
    assert denied.status_code==401
    assert c.post('/api/platform/auth/login',json={'email':'admin@test.local','password':'bad'}).status_code==401
    token=c.post('/api/platform/auth/login',json={'email':'admin@test.local','password':'different-very-secure-password'}).json()['access_token']
    auth={'Authorization':'Bearer '+token}
    r=c.post('/api/platform/owners',headers=auth,json={'business_name':'My PG Group','owner_name':'Owner Example','owner_email':'owner@example.test','temporary_password':'long-temporary-password'})
    assert r.status_code==201,r.text
    tid=r.json()['id']
    p1=c.post(f'/api/platform/owners/{tid}/properties',headers=auth,json={'name':'North Campus PG','address':'North street'})
    p2=c.post(f'/api/platform/owners/{tid}/properties',headers=auth,json={'name':'South Campus PG','address':'South street'})
    assert p1.status_code==201 and p2.status_code==201
    with main.SessionLocal() as s:
        for i,room in enumerate(['101','102']):s.add(Room(tenant_id=tid,name=room,beds=3))
        resident=main.User(tenant_id=tid,name='Resident A',email='resident@example.test',password_hash=main.passwords.hash('long-test-password'),role='resident',room='101')
        s.add(resident);s.commit();rid=resident.id
        rooms=s.query(Room).filter_by(tenant_id=tid).all()
    for room,property_id in zip(rooms,[p1.json()['id'],p2.json()['id']]):
        assert c.put(f'/api/platform/owners/{tid}/properties/{property_id}/rooms/{room.id}',headers=auth).status_code==200
    assert c.put(f'/api/platform/owners/{tid}/properties/{p1.json()["id"]}/residents/{rid}',headers=auth).status_code==200
    detail=c.get(f'/api/platform/owners/{tid}',headers=auth).json()
    assert detail['pg_count']==2 and detail['total_beds']==6 and detail['total_residents']==1
    assert detail['properties'][0]['beds']==3 and detail['properties'][0]['residents']==1
    assert detail['subscription']['estimated_monthly']=='39.00'
    assert c.post(f'/api/platform/owners/{tid}/invoices',headers=auth,json={'period':'2026-11'}).status_code==409  # trial
    assert c.put(f'/api/platform/owners/{tid}/subscription',headers=auth,json={'price_per_resident':'29.00','status':'active','trial_until':'','billing_notes':'launch offer'}).status_code==200
    i=c.post(f'/api/platform/owners/{tid}/invoices',headers=auth,json={'period':'2026-11'})
    assert i.status_code==201,i.text
    assert i.json()['subtotal']=='29.00' and i.json()['billable_residents']==1
    assert c.post(f'/api/platform/owners/{tid}/invoices',headers=auth,json={'period':'2026-11'}).status_code==409
    assert c.post(f'/api/platform/invoices/{i.json()["id"]}/issue',headers=auth).status_code==200
    paid=c.post(f'/api/platform/invoices/{i.json()["id"]}/confirm-manual-payment',headers=auth,json={'payment_reference':'VERIFIED-UTR-0001'})
    assert paid.status_code==200 and paid.json()['status']=='paid'
    assert c.get('/api/platform/overview',headers=auth).json()['confirmed_collected']=='29.00'
    # Existing PG owner token cannot call platform admin endpoints.
    ot=c.post('/api/login',json={'email':'owner@example.test','password':'long-temporary-password'}).json()['token']
    assert c.get('/api/platform/overview',headers={'Authorization':'Bearer '+ot}).status_code==401

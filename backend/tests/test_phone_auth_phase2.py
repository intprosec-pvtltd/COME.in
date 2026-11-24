"""Integration tests with real database/authentication and a mocked SMS transport."""
import os, sys, tempfile, uuid, time
from pathlib import Path
root = Path(tempfile.mkdtemp(prefix='ss-phone-test-'))
os.environ.update(DATABASE_URL='sqlite:///'+str(root/'db.sqlite'),
 SECRET_KEY='test-jwt-key-not-for-production-123456789', DEMO_SEED='true',
 PHONE_OTP_SECRET='test-otp-key-not-for-production-123456789',
 COMEIN_PRIVATE_STORAGE=str(root/'private'), COMEIN_CHAT_STORAGE=str(root/'chat'),
 STAYSYNC_SUBSCRIPTION_DB=str(root/'subscriptions.sqlite'), STAYSYNC_SUBSCRIPTION_MEDIA_DIR=str(root/'billing'),
 TRIAL_ENFORCEMENT_ENABLED='false', PUSH_ENABLED='0')
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select
from main import app, SessionLocal, User, passwords
import phone_auth as pa
from v3_api import meta, put
client=TestClient(app)
P='/api/v3/phone'

@pytest.fixture(autouse=True)
def transport(monkeypatch):
    sent={}
    monkeypatch.setattr(pa,'sms_config',lambda: ('test','test','test',''))
    monkeypatch.setattr(pa,'send_sms',lambda phone,code:sent.update({phone:code}))
    monkeypatch.setenv('PHONE_OTP_SECRET','test-otp-key-not-for-production-123456789')
    monkeypatch.setenv('ALLOW_LEGACY_EMAIL_REGISTRATION','false')
    return sent

def req(path,data,status=200):
    r=client.post(P+path,json=data);assert r.status_code==status,r.text;return r.json()

def headers(token):return {'Authorization':'Bearer '+token}

def legacy(email,pwd='Demo123!'):
    r=client.post('/api/login',json={'email':email,'password':pwd});assert r.status_code==200,r.text;return r.json()['token']

def create_verified(phone,transport,password='Before123!',email=None):
    email=email or f'{uuid.uuid4().hex}@test.pg'
    req('/register/request',{'phone':phone});code=transport[pa.normalize_phone(phone)]
    data={'phone':phone,'code':code,'name':'Test Owner','email':email,'property_name':'New PG','password':password}
    return req('/register',data,201),email,data

def test_phone_normalization():
    assert pa.normalize_phone('98765 43210')=='+919876543210'
    assert pa.normalize_phone('919876543210')=='+919876543210'
    assert pa.normalize_phone('+91 (98765) 43210')=='+919876543210'
    from fastapi import HTTPException
    for bad in ['abc','1234567890','+910987654321','+00123']:
        with pytest.raises(HTTPException):pa.normalize_phone(bad)

def test_verified_registration_login_and_legacy_guard(transport):
    phone='9876500001'
    req('/login',{'phone':phone,'password':'Before123!'},401)
    req('/register/request',{'phone':phone});code=transport['+91'+phone]
    email='registration@test.pg';data={'phone':phone,'code':code,'name':'New Owner','email':email,'property_name':'Verified PG','password':'Before123!'}
    wrong='000000' if code!='000000' else '111111'
    req('/register',{**data,'code':wrong},400)
    row=req('/register',data,201)
    req('/register',{**data,'email':'duplicate@test.pg'},409)
    login=req('/login',{'phone':'+91'+phone,'password':'Before123!'})
    assert login['user']['id']==row['id'];assert login['user']['role']=='owner'
    profile=client.get('/api/v3/profile',headers=headers(login['token'])).json()
    assert profile['verified_login_phone']=='+91'+phone
    assert client.post('/api/v3/register',json={k:v for k,v in data.items() if k!='code'}).status_code==410
    assert client.post('/api/login',json={'email':phone,'password':'Before123!'}).status_code==401
    assert legacy(email,'Before123!')

def test_existing_account_activation_preserves_id_and_hash(transport):
    phone='9876500002';email='owner@demo.pg';password='Demo123!'
    with SessionLocal() as s:
        u=s.scalar(select(User).where(User.email==email));old_id=u.id;old_hash=u.password_hash;old_tenant=u.tenant_id
    payload={'email':email,'password':password,'phone':phone}
    req('/enroll/request',{**payload,'password':'wrong'},401)
    req('/enroll/request',payload);code=transport['+91'+phone]
    req('/enroll/request',payload,429)
    req('/enroll/confirm',{**payload,'code':code})
    req('/enroll/confirm',{**payload,'code':code},409)
    with SessionLocal() as s:
        u=s.get(User,old_id);assert u.password_hash==old_hash and u.tenant_id==old_tenant
        assert s.get(pa.VerifiedPhone,old_id).phone=='+91'+phone
    result=req('/login',{'phone':phone,'password':password});assert result['user']['id']==old_id
    # Contact changes cannot change the trusted login number.
    h=headers(result['token']);assert client.patch('/api/v3/profile',headers=h,json={'phone':'9876500999'}).status_code==200
    req('/login',{'phone':'9876500999','password':password},401)
    assert req('/login',{'phone':phone,'password':password})['user']['id']==old_id

def test_reset_otp_single_use_and_revoke_sessions(transport,monkeypatch):
    phone='9876500003';row,email,_=create_verified(phone,transport)
    old=req('/login',{'phone':phone,'password':'Before123!'})['token']
    result=req('/forgot-password',{'phone':phone});assert result['expires_in']==300 and result['resend_after']==30
    code=transport['+91'+phone];wrong='000000' if code!='000000' else '111111'
    req('/reset/verify',{'phone':phone,'code':wrong},400)
    grant=req('/reset/verify',{'phone':phone,'code':code})['reset_token'];assert grant not in code
    req('/reset/verify',{'phone':phone,'code':code},400)
    req('/reset-password',{'phone':'9876500004','reset_token':grant,'new_password':'After123!'},400)
    req('/reset-password',{'phone':phone,'reset_token':grant,'new_password':'After123!'})
    req('/reset-password',{'phone':phone,'reset_token':grant,'new_password':'Another123!'},400)
    assert client.get('/api/v3/profile',headers=headers(old)).status_code==401
    req('/login',{'phone':phone,'password':'Before123!'},401)
    assert req('/login',{'phone':phone,'password':'After123!'})['user']['id']==row['id']
    # The legacy email reset must not bypass verified phone ownership.
    monkeypatch.setenv('SMTP_HOST','configured-test');monkeypatch.setenv('SMTP_FROM','test@test.pg')
    import v3_api
    monkeypatch.setattr(v3_api,'send_recovery_email',lambda *_:pytest.fail('Verified account must use SMS'))
    assert client.post('/api/v3/forgot-password',json={'email':email}).status_code==200
    assert client.post('/api/v3/reset-password',json={'email':email,'code':'123456','new_password':'Bypass123!'}).status_code==400

def test_unknown_recovery_and_expired_code(transport):
    unknown='9876500005';response=req('/forgot-password',{'phone':unknown})
    assert response['ok'] and '+91'+unknown not in transport
    req('/reset/verify',{'phone':unknown,'code':'123456'},400)
    phone='9876500006';_,_,data=create_verified(phone,transport)
    req('/forgot-password',{'phone':phone});code=transport['+91'+phone]
    with SessionLocal() as s:
        b=pa.binding(s,'+91'+phone);r=s.get(pa.PhoneChallenge,pa.challenge_key('+91'+phone,'reset',str(b.user_id)));r.expires=time.time()-1;s.commit()
    req('/reset/verify',{'phone':phone,'code':code},400)

def test_attempt_limit_and_rate_limit(transport):
    phone='9876500007';create_verified(phone,transport)
    req('/forgot-password',{'phone':phone});code=transport['+91'+phone];wrong='000000' if code!='000000' else '111111'
    for _ in range(5):req('/reset/verify',{'phone':phone,'code':wrong},400)
    req('/reset/verify',{'phone':phone,'code':code},400)
    for _ in range(10):req('/login',{'phone':phone,'password':'bad'},401)
    req('/login',{'phone':phone,'password':'Before123!'},429)

def test_duplicate_phone_and_invited_resident(transport):
    phone='9876500008';owner_h=headers(legacy('owner@demo.pg'))
    email='invited-phone@test.pg'
    invite=client.post('/api/v3/residents/invite',headers=owner_h,json={'name':'Phone Resident','email':email,'phone':phone})
    assert invite.status_code==201,invite.text
    data={'email':email,'phone':phone,'password':invite.json()['temporary_password']}
    req('/enroll/request',data);req('/enroll/confirm',{**data,'code':transport['+91'+phone]})
    session=req('/login',{'phone':phone,'password':data['password']});assert session['user']['role']=='resident'
    assert session['user']['id']==invite.json()['id']
    state=client.get('/api/v3/state',headers=headers(session['token']));assert state.status_code==200,state.text
    assert state.json()['profile']['must_change_password'] is True
    transport.clear();req('/forgot-password',{'phone':phone});assert '+91'+phone not in transport
    req('/enroll/request',{'email':'resident@demo.pg','password':'Demo123!','phone':phone},409)

def test_community_role_server_side_and_scope():
    owner=headers(legacy('owner@demo.pg'));resident=headers(legacy('resident@demo.pg'))
    msg=client.post('/api/v3/messages',headers=owner,json={'body':'Owner notice','author_role':'resident'});assert msg.status_code==201,msg.text
    mid=msg.json()['id'];rows=client.get('/api/v3/messages?property_id=0',headers=resident).json();row=next(x for x in rows if x['id']==mid)
    assert row['author_role']=='owner' and row['author_room']==''
    msg=client.post('/api/v3/messages',headers=resident,json={'body':'Resident message','author_role':'owner'});assert msg.status_code==201,msg.text
    rows=client.get('/api/v3/messages?property_id=0',headers=owner).json();row=next(x for x in rows if x['id']==msg.json()['id'])
    assert row['author_role']=='resident' and row['author_room']=='204'

import os,sys,tempfile,uuid
from pathlib import Path
os.environ['DATABASE_URL']='sqlite:///'+str(Path(tempfile.mkdtemp())/'tests.db')
os.environ['SECRET_KEY']='integration-test-key-at-least-32-characters'
os.environ['DEMO_SEED']='true'
os.environ['COMEIN_PRIVATE_STORAGE']=tempfile.mkdtemp()
os.environ['COMEIN_CHAT_STORAGE']=tempfile.mkdtemp()
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import pytest
from fastapi.testclient import TestClient
from main import app,SessionLocal,User,Invoice,passwords,Tenant
from v3_api import Document
from decimal import Decimal
client=TestClient(app)
def login(email='owner@demo.pg',password='Demo123!'):
 r=client.post('/api/login',json={'email':email,'password':password});assert r.status_code==200,r.text
 return {'Authorization':'Bearer '+r.json()['token']}
@pytest.fixture
def owner():return login()
@pytest.fixture
def resident():return login('resident@demo.pg')
def req(method,path,headers,data=None,expected=200):
 r=client.request(method,'/api'+path,headers=headers,json=data);assert r.status_code==expected,r.text;return r.json()
def create(kind,data,h):return req('POST','/v3/entities/'+kind,h,data,201)['id']

def test_state_is_authenticated():
 assert client.get('/api/v3/state').status_code==401

def test_dashboard_is_record_based(owner):
 d=req('GET','/v3/state',owner);assert d['profile']['role']=='owner';assert len(d['invoices'])>=1;assert d['properties'][0]['id']==0

def test_resident_cannot_create_owner_entities(resident):
 req('POST','/v3/entities/property',resident,{'name':'Forbidden'},403)
 assert req('GET','/v3/state',resident)['residents']==[]

def test_property_rooms_capacity_and_allocation(owner):
 pid=create('property',{'name':'Maple House','city':'Bengaluru','address':'HSR','upi':'maple@upi'},owner)
 rid=create('room',{'name':'101','beds':2,'floor':'Ground','property_id':pid},owner)
 person={'name':'Kiran Example','email':'kiran-'+uuid.uuid4().hex+'@test.pg','room':'101','bed':1,'property_id':pid}
 invite=req('POST','/v3/residents/invite',owner,person,201)
 uid=invite['id']
 assert invite['temporary_password'] and invite['must_change_password'] is True
 req('POST','/v3/residents/invite',owner,{**person,'email':'dup-'+uuid.uuid4().hex+'@test.pg'},409)
 req('PUT',f'/v3/entities/room/{rid}',owner,{'name':'101','beds':1,'floor':'Floor 1','property_id':0},409)
 req('PUT',f'/v3/entities/resident/{uid}',owner,{**person,'bed':2})
 req('PUT',f'/v3/entities/room/{rid}',owner,{'name':'101','beds':1,'property_id':pid},409)
 req('PUT',f'/v3/entities/property/{pid}',owner,{'name':'Maple House','archived':True},409)

def test_real_payment_submission_approval_and_receipt(owner,resident):
 d=req('GET','/v3/state',resident);invoice=next(i for i in d['invoices'] if Decimal(i['outstanding'])>=100)
 png=b'\x89PNG\r\n\x1a\n'+b'proof'
 f=client.post('/api/v3/files/payment',headers=resident,files={'file':('proof.png',png,'image/png')});assert f.status_code==201,f.text
 p=req('POST','/v3/payments',resident,{'invoice_id':invoice['id'],'amount':'100','reference':'PAY-'+uuid.uuid4().hex,'file_id':f.json()['id']},201)['id']
 req('POST',f'/v3/payments/{p}/review',owner,{'decision':'approved','bank_confirmed':False},422)
 req('POST',f'/v3/payments/{p}/review',owner,{'decision':'approved','bank_confirmed':True})
 req('POST',f'/v3/payments/{p}/review',owner,{'decision':'approved','bank_confirmed':True},409)
 receipt=req('GET',f'/receipts/{p}',resident);assert receipt['amount']=='100.00';assert receipt['status']=='approved'
 after=req('GET','/v3/state',resident);assert next(i for i in after['invoices']if i['id']==invoice['id'])['paid']=='100.00'

def test_rejection_reason_and_duplicate_reference(owner,resident):
 inv=req('GET','/v3/state',resident)['invoices'][0]
 reference='REF-'+uuid.uuid4().hex;p=req('POST','/v3/payments',resident,{'invoice_id':inv['id'],'amount':'10','reference':reference},201)['id']
 req('POST','/v3/payments',resident,{'invoice_id':inv['id'],'amount':'10','reference':reference},409)
 req('POST',f'/v3/payments/{p}/review',owner,{'decision':'rejected'},422)
 req('POST',f'/v3/payments/{p}/review',owner,{'decision':'rejected','reason':'Reference not found'})
 req('GET',f'/receipts/{p}',resident,expected=404)

def test_financial_overpayment_is_rejected(resident):
 inv=req('GET','/v3/state',resident)['invoices'][0]
 req('POST','/v3/payments',resident,{'invoice_id':inv['id'],'amount':'999999','reference':'OVERPAY123'},409)

def test_private_upload_type_and_ownership(resident,owner):
 r=client.post('/api/v3/files/payment',headers=resident,files={'file':('fake.png',b'not a png','image/png')});assert r.status_code==415
 r=client.post('/api/v3/files/payment',headers=resident,files={'file':('x.exe',b'bad','application/octet-stream')});assert r.status_code==415
 r=client.post('/api/v3/files/payment',headers=resident,files={'file':('proof.pdf',b'%PDF-1.4 test','application/pdf')});assert r.status_code==201
 fid=r.json()['id'];assert client.get('/api/v3/files/'+str(fid),headers=owner).status_code==200
 assert client.get('/api/v3/files/'+str(fid)).status_code==401

def test_complaint_assignment_history_and_staff_access(owner,resident):
 tid=create('complaint',{'category':'Electrical','description':'The room fan is not working','priority':'High'},resident)
 staff=req('GET','/v3/state',owner)['staff'][0]
 req('PATCH',f'/v3/complaints/{tid}',owner,{'status':'in_progress','assigned_to':staff['id'],'note':'Assigned repair'})
 req('PATCH',f'/v3/complaints/{tid}',owner,{'status':'resolved','assigned_to':staff['id'],'note':'Fan repaired'})
 row=next(t for t in req('GET','/v3/state',resident)['complaints']if t['id']==tid);assert len(row['history'])==3;assert row['status']=='resolved'
 sh=login('staff@demo.pg');assert any(t['id']==tid for t in req('GET','/v3/state',sh)['complaints'])

def test_facilities_notices_meals_expenses_bookings(owner):
 f=create('facility',{'title':'Water maintenance','details':'Today 2 to 4 PM','category':'water','status':'scheduled'},owner)
 req('PUT',f'/v3/entities/facility/{f}',owner,{'title':'Water restored','details':'Supply is available','category':'water','status':'restored'})
 n=create('notice',{'title':'Welcome meetup','body':'Meet in common area at six','important':True},owner)
 req('PUT',f'/v3/entities/notice/{n}',owner,{'title':'Welcome meetup','body':'Meet in common area at six','status':'archived'})
 create('meal',{'day':'Monday','breakfast':'Idli','lunch':'Rice','dinner':'Chapati'},owner)
 create('expense',{'period':'2026-11','description':'Fan repair','category':'Maintenance','amount':'500'},owner)
 b=create('booking',{'name':'New Enquirer','phone':'9876543210','room':'101'},owner)
 req('PUT',f'/v3/entities/booking/{b}',owner,{'name':'New Enquirer','phone':'9876543210','room':'101','status':'Contacted'})
 d=req('GET','/v3/state',owner);assert any(e['description']=='Fan repair'for e in d['expenses']);assert any(x['status']=='Contacted'for x in d['bookings'])

def test_chat_edit_unsend_delete_for_me_and_ownership(owner,resident):
 mid=req('POST','/v3/messages',resident,{'body':'Hello everyone'},201)['id']
 req('PATCH',f'/v3/messages/{mid}',owner,{'body':'Unauthorized'},403)
 req('PATCH',f'/v3/messages/{mid}',resident,{'body':'Hello neighbors'})
 req('DELETE',f'/v3/messages/{mid}',resident)
 assert all(m['id']!=mid for m in req('GET','/v3/messages',resident))
 assert any(m['id']==mid and m['edited'] for m in req('GET','/v3/messages',owner))
 req('DELETE',f'/v3/messages/{mid}?for_everyone=true',owner,expected=403)
 other=req('POST','/v3/messages',owner,{'body':'Owner update','reply':'Hello neighbors'},201)['id']
 req('DELETE',f'/v3/messages/{other}?for_everyone=true',owner)
 assert next(m for m in req('GET','/v3/messages',resident)if m['id']==other)['deleted'] is True

def test_chat_attachments_have_authenticated_download(owner,resident):
 upload=client.post('/api/community/attachments',headers=resident,files={'file':('hello.txt',b'Hello community','text/plain')});assert upload.status_code==201,upload.text
 fid=upload.json()['id'];assert client.get('/api/community/attachments/'+str(fid),headers=owner).content==b'Hello community'
 assert client.get('/api/community/attachments/'+str(fid)).status_code==401

def test_profile_and_notification_preferences(owner):
 req('PATCH','/v3/profile',owner,{'name':'Demo Owner Updated','appearance':'Dark','notifications':{'Rent reminders':False}})
 d=req('GET','/v3/state',owner);assert d['profile']['name']=='Demo Owner Updated';assert d['profile']['preferences']['appearance']=='Dark'
 if d['notifications']:req('POST',f"/v3/read/alert/{d['notifications'][0]['id']}",owner)

def test_tenant_isolation_and_registration():
 name='owner-'+uuid.uuid4().hex+'@test.pg'
 r=client.post('/api/v3/register',json={'name':'Other Owner','email':name,'phone':'9876543210','password':'Another123!','role':'owner','property_name':'Other PG'});assert r.status_code==201,r.text
 h=login(name,'Another123!');d=req('GET','/v3/state',h);assert d['residents']==[];assert d['invoices']==[]
 req('GET','/receipts/1',h,expected=404)
 code=req('GET','/v3/joining-code',h)['code'];newmail='resident-'+uuid.uuid4().hex+'@test.pg'
 r=client.post('/api/v3/register',json={'name':'New Resident','email':newmail,'phone':'9876543210','password':'Resident123!','role':'resident','joining_code':code});assert r.status_code==422,r.text
 invitation=req('POST','/v3/residents/invite',h,{'name':'New Resident','email':newmail,'phone':'9876543210','property_id':0},201)
 temp=invitation['temporary_password'];assert invitation['must_change_password'] is True
 new_resident=login(newmail,temp)
 initial=req('GET','/v3/state',new_resident)
 assert initial['profile']['tenant']['name']=='Other PG'
 assert initial['profile']['must_change_password'] is True
 req('POST','/v3/password',new_resident,{'current_password':temp,'new_password':'ResidentAfter123!'})
 assert req('GET','/v3/state',login(newmail,'ResidentAfter123!'))['profile']['must_change_password'] is False

def test_logout_revokes_token():
 h=login();req('POST','/v3/logout',h);req('GET','/v3/state',h,expected=401)

def test_password_change_invalidates_old_sessions():
 email='security-'+uuid.uuid4().hex+'@test.pg';client.post('/api/v3/register',json={'name':'Security Owner','email':email,'phone':'9876543210','password':'Before123!','role':'owner','property_name':'Security PG'})
 h=login(email,'Before123!');req('POST','/v3/password',h,{'current_password':'Before123!','new_password':'After123!'})
 req('GET','/v3/state',h,expected=401);assert req('GET','/v3/state',login(email,'After123!'))['profile']['email']==email

def test_migration_is_idempotent_and_non_destructive():
 from main import Base,engine
 with SessionLocal() as s:before=len(s.query(User).all())
 from migrate_v3 import migrate
 migrate();migrate()
 with SessionLocal() as s:assert len(s.query(User).all())==before

def test_in_app_reminder(owner,resident):
 rid=req('GET','/v3/state',resident)['profile']['id'];req('POST',f'/v3/reminders/{rid}',owner)
 assert any(n['title']=='Rent reminder' for n in req('GET','/v3/state',resident)['notifications'])

def test_phone_login_after_profile_update():
 email='phone-'+uuid.uuid4().hex+'@test.pg';phone='919876001234'
 r=client.post('/api/v3/register',json={'name':'Phone Owner','email':email,'phone':phone,'password':'Phone123!','role':'owner','property_name':'Phone PG'});assert r.status_code==201
 assert req('GET','/v3/state',login(phone,'Phone123!'))['profile']['email']==email

def test_other_tenant_cannot_read_private_proof(resident):
 f=client.post('/api/v3/files/payment',headers=resident,files={'file':('proof.pdf',b'%PDF-1.4 private','application/pdf')});assert f.status_code==201
 email='private-'+uuid.uuid4().hex+'@test.pg';client.post('/api/v3/register',json={'name':'Private Owner','email':email,'phone':'8888000011','password':'Private123!','role':'owner','property_name':'Private PG'})
 assert client.get('/api/v3/files/'+str(f.json()['id']),headers=login(email,'Private123!')).status_code==404

def test_email_reset_code_delivery_and_validation(monkeypatch):
 import v3_api
 email='reset-'+uuid.uuid4().hex+'@test.pg'
 client.post('/api/v3/register',json={'name':'Reset Owner','email':email,'phone':'9888001122','password':'Before123!','role':'owner','property_name':'Reset PG'})
 monkeypatch.setenv('SMTP_HOST','configured-test-host');monkeypatch.setenv('SMTP_FROM','noreply@test.pg');sent={}
 def send(to,code):sent.update(email=to,code=code)
 monkeypatch.setattr(v3_api,'send_recovery_email',send)
 response=client.post('/api/v3/forgot-password',json={'email':email});assert response.status_code==200
 assert sent['email']==email
 assert client.post('/api/v3/reset-password',json={'email':email,'code':'xxxxxx','new_password':'After123!'}).status_code==400
 assert client.post('/api/v3/reset-password',json={'email':email,'code':sent['code'],'new_password':'After123!'}).status_code==200
 assert req('GET','/v3/state',login(email,'After123!'))['profile']['email']==email
 assert client.post('/api/v3/reset-password',json={'email':email,'code':sent['code'],'new_password':'Again123!'}).status_code==400

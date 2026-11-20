"""COME.in mobile design implementation; additive tables and existing domain models.
No existing columns or data are removed. Run migrate_v3.py before upgrading.
"""
import hashlib, json, os, secrets, uuid, re
from datetime import datetime, timezone, timedelta
from decimal import Decimal
from pathlib import Path
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Header
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field, ValidationError
from sqlalchemy import JSON, String, Integer, ForeignKey, UniqueConstraint, select
from sqlalchemy.orm import Mapped, mapped_column, Session
from sqlalchemy.exc import IntegrityError
from main import Base, engine, db, current, role, tenant_get, User, Tenant, Notice, Ticket, Invoice, Payment, passwords, invoice_out
from v2_api import Room, Facility, ChatMessage, ChatAttachment, Meal, Expense, receipt

router=APIRouter(prefix='/api/v3',tags=['COME.in V3'])
def now():return datetime.now(timezone.utc)
def iso(value):return (value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value).isoformat()
class Document(Base):
 __tablename__='comein_v3_documents'
 id:Mapped[int]=mapped_column(primary_key=True)
 tenant_id:Mapped[int]=mapped_column(ForeignKey('tenants.id'),index=True)
 kind:Mapped[str]=mapped_column(String(40),index=True)
 key:Mapped[str]=mapped_column(String(120))
 payload:Mapped[dict]=mapped_column(JSON,default=dict)
 __table_args__=(UniqueConstraint('tenant_id','kind','key'),)
class PrivateFile(Base):
 __tablename__='comein_v3_files'
 id:Mapped[int]=mapped_column(primary_key=True)
 tenant_id:Mapped[int]=mapped_column(ForeignKey('tenants.id'),index=True)
 author_id:Mapped[int]=mapped_column(ForeignKey('users.id'))
 purpose:Mapped[str]=mapped_column(String(20))
 filename:Mapped[str]=mapped_column(String(180))
 mime:Mapped[str]=mapped_column(String(80))
 key:Mapped[str]=mapped_column(String(40),unique=True)
 size:Mapped[int]=mapped_column(Integer)
class Alert(Base):
 __tablename__='comein_v3_alerts'
 id:Mapped[int]=mapped_column(primary_key=True)
 tenant_id:Mapped[int]=mapped_column(ForeignKey('tenants.id'),index=True)
 user_id:Mapped[Optional[int]]=mapped_column(ForeignKey('users.id'),nullable=True)
 audience:Mapped[str]=mapped_column(String(20),default='all')
 title:Mapped[str]=mapped_column(String(180))
 body:Mapped[str]=mapped_column(String(1000))
 destination:Mapped[str]=mapped_column(String(40))
 created_at:Mapped[str]=mapped_column(String(50),default=lambda:iso(now()))

def doc(s,tenant,kind,key):return s.scalar(select(Document).where(Document.tenant_id==tenant,Document.kind==kind,Document.key==str(key)))
def meta(s,tenant,kind,key):
 d=doc(s,tenant,kind,key);return dict(d.payload) if d else {}
def put(s,tenant,kind,key,data):
 d=doc(s,tenant,kind,key)
 if d:d.payload=dict(data)
 else:s.add(Document(tenant_id=tenant,kind=kind,key=str(key),payload=dict(data)))
 return data
def owner(u):role(u,'owner','manager')
def alert(s,u,title,body,destination,user_id=None,audience='all',property_id=None,entity_id=None):
 a=Alert(tenant_id=u.tenant_id,user_id=user_id,audience=audience,title=title,body=body[:1000],destination=destination)
 s.add(a)
 s.flush()
 if os.environ.get('PUSH_ENABLED') == '1':
  from push_notifications import PushJob
  s.add(PushJob(alert_id=a.id))
 if property_id is not None or entity_id is not None:
  s.flush()
  put(s,u.tenant_id,'alert_meta',a.id,{'property_id':property_id,'entity_id':entity_id,'created_by':u.id})
def audit(s,u,action,details):put(s,u.tenant_id,'audit',uuid.uuid4().hex,{'actor':u.id,'action':action,'details':details,'at':iso(now())})
def commit(s):
 try:s.commit()
 except IntegrityError:s.rollback();raise HTTPException(409,'This record conflicts with an existing record. Refresh and try again.')
def property_exists(s,u,pid):
 if pid and (not doc(s,u.tenant_id,'property',pid) or doc(s,u.tenant_id,'property',pid).payload.get('archived')):
  raise HTTPException(404,'Active property not found')
def property_name(s,u,pid):
 property_exists(s,u,pid)
 return next((p['name'] for p in property_rows(s,u) if p['id']==pid), 'Unknown PG')
def message_property(s,u,message):
 return int(meta(s,u.tenant_id,'message_meta',message.id).get('property_id',0))
def chat_access(s,u,pid):
 property_exists(s,u,pid)
 if u.role in ('resident','staff') and int(meta(s,u.tenant_id,'resident_meta' if u.role=='resident' else 'staff_meta',u.id).get('property_id',0) or 0)!=pid:
  raise HTTPException(403,'This community belongs to another PG')
def visible_property(s,u,pid):
 return u.role!='resident' or int(meta(s,u.tenant_id,'resident_meta',u.id).get('property_id',0))==int(pid)
def visible_alert(s,u,a):
 md=meta(s,u.tenant_id,'alert_meta',a.id)
 return 'property_id' not in md or visible_property(s,u,md['property_id'])
def safe_file(s,u,fid,purpose):
 if not fid:return
 f=tenant_get(s,PrivateFile,fid,u.tenant_id)
 if f.author_id!=u.id or f.purpose!=purpose:raise HTTPException(403,'This attachment cannot be used here')
def safe_email(v):
 v=v.strip().lower()
 if '@' not in v or '.' not in v.split('@')[-1]:raise HTTPException(422,'Enter a valid email address')
 return v
def security_check(u,payload,authorization,session):
 key=hashlib.sha256(authorization.encode()).hexdigest()
 if doc(session,u.tenant_id,'revoked',key):raise HTTPException(401,'Session has ended. Sign in again.')
 before=meta(session,u.tenant_id,'security',u.id).get('changed_at',0)
 if payload.get('iat',0)<before:raise HTTPException(401,'Password changed. Sign in again.')

def profile_out(s,u):
 from identity_api import photo_revision
 t=s.get(Tenant,u.tenant_id);prefs=meta(s,u.tenant_id,'profile',u.id)
 return {'id':u.id,'name':u.name,'email':u.email,'role':u.role,'room':u.room,'phone':prefs.get('phone',''),'photo_revision':photo_revision(s,u.tenant_id,'user',u.id),'preferences':prefs,'must_change_password':bool(meta(s,u.tenant_id,'onboarding',u.id).get('must_change',False)),'tenant':{'id':t.id,'name':t.name}}
@router.get('/profile')
def profile(u:User=Depends(current),s:Session=Depends(db)):return profile_out(s,u)
@router.patch('/profile')
def edit_profile(data:dict,u:User=Depends(current),s:Session=Depends(db)):
 if 'appearance' in data and data['appearance'] not in ('Light','Dark','System'):raise HTTPException(422,'Invalid appearance')
 if 'notifications' in data and (not isinstance(data['notifications'],dict) or any(not isinstance(v,bool) for v in data['notifications'].values())):raise HTTPException(422,'Notification preferences must contain boolean values')
 name=str(data.get('name',u.name)).strip();email=safe_email(str(data.get('email',u.email)))
 if not 2<=len(name)<=120:raise HTTPException(422,'Name must contain 2–120 characters')
 u.name=name;u.email=email
 prefs=meta(s,u.tenant_id,'profile',u.id)
 for k in ('phone','appearance','notifications'):
  if k in data:prefs[k]=data[k]
 put(s,u.tenant_id,'profile',u.id,prefs);commit(s);return profile_out(s,u)
class ChangePassword(BaseModel):
 current_password:str
 new_password:str=Field(min_length=8,max_length=128)
@router.post('/password')
def password(data:ChangePassword,u:User=Depends(current),s:Session=Depends(db)):
 if not passwords.verify(data.current_password,u.password_hash):raise HTTPException(400,'Current password is incorrect')
 was_first_login=bool(meta(s,u.tenant_id,'onboarding',u.id).get('must_change',False))
 u.password_hash=passwords.hash(data.new_password)
 prior=meta(s,u.tenant_id,'onboarding',u.id)
 put(s,u.tenant_id,'onboarding',u.id,{**prior,'must_change':False,
      'documents_required':prior.get('documents_required',False) or (was_first_login and u.role=='resident')})
 put(s,u.tenant_id,'security',u.id,{'changed_at':now().timestamp()});audit(s,u,'password_change',{});commit(s);return {'ok':True,'reauthenticate':True}
@router.post('/logout')
def logout(authorization:str=Header(...),u:User=Depends(current),s:Session=Depends(db)):
 put(s,u.tenant_id,'revoked',hashlib.sha256(authorization.encode()).hexdigest(),{'at':iso(now())});commit(s);return {'ok':True}
class Registration(BaseModel):
 name:str=Field(min_length=2,max_length=120)
 email:str
 phone:str=Field(min_length=7,max_length=20)
 password:str=Field(min_length=8,max_length=128)
 role:str=Field(default='owner',pattern='^owner$')
 property_name:str=''
 joining_code:str=''
@router.post('/register',status_code=201)
def register(data:Registration,s:Session=Depends(db)):
 email=safe_email(data.email)
 if s.scalar(select(User).where(User.email==email)):raise HTTPException(409,'Email is already registered')
 if data.role!='owner':raise HTTPException(403,'Residents must be invited by their PG owner.')
 if len(data.property_name.strip())<2:raise HTTPException(422,'Enter the property name')
 t=Tenant(name=data.property_name.strip(),primary_color='#3B1E3F');s.add(t);s.flush()
 u=User(tenant_id=t.id,name=data.name.strip(),email=email,password_hash=passwords.hash(data.password),role='owner',room='');s.add(u);s.flush()
 put(s,t.id,'profile',u.id,{'phone':data.phone});commit(s)
 return {'id':u.id,'message':'Owner account created. Sign in to continue.'}

class OwnerResidentInvite(BaseModel):
 name:str=Field(min_length=2,max_length=120)
 email:str
 phone:str=Field(default='',max_length=20)
 room:str=Field(default='',max_length=30)
 property_id:int=0
 bed:int=Field(default=0,ge=0)
 monthly_rent:Decimal=Field(default=Decimal('0'),ge=0,le=10000000,max_digits=12,decimal_places=2)

def issue_temporary_access(s,u,resident):
 # Password is shown only in the response; only its Argon2 hash is persisted.
 token=secrets.token_urlsafe(15)
 resident.password_hash=passwords.hash(token)
 put(s,u.tenant_id,'onboarding',resident.id,{'must_change':True,'expires':(now()+timedelta(days=3)).timestamp(),'created_by':u.id})
 return token

@router.post('/residents/invite',status_code=201)
def invite_resident(data:OwnerResidentInvite,u:User=Depends(current),s:Session=Depends(db)):
 role(u,'owner')
 mail=safe_email(data.email)
 if s.scalar(select(User).where(User.email==mail)):raise HTTPException(409,'Email is already registered')
 property_exists(s,u,data.property_id)
 if data.room.strip():
  if data.bed:allocation_check(s,u,data.room.strip(),data.bed,data.property_id)
  else:
   available=s.scalar(select(Room).where(Room.tenant_id==u.tenant_id,Room.name==data.room.strip()))
   if not available or meta(s,u.tenant_id,'room_meta',available.id).get('property_id',0)!=data.property_id:raise HTTPException(404,'Room not found in this PG')
 else:
  if data.bed:raise HTTPException(422,'Select a room before assigning a bed')
 resident=User(tenant_id=u.tenant_id,name=data.name.strip(),email=mail,role='resident',room=data.room.strip(),password_hash='')
 s.add(resident);s.flush()
 temp=issue_temporary_access(s,u,resident)
 put(s,u.tenant_id,'profile',resident.id,{'phone':data.phone})
 put(s,u.tenant_id,'resident_meta',resident.id,{'property_id':data.property_id,'bed':data.bed,'monthly_rent':str(data.monthly_rent)})
 audit(s,u,'resident_invited',{'resident_id':resident.id})
 commit(s)
 return {'id':resident.id,'name':resident.name,'email':resident.email,'temporary_password':temp,'expires_in_hours':72,'must_change_password':True}

class ResidentAccessChange(BaseModel):
 active:bool

@router.patch('/residents/{resident_id}/access')
def change_resident_access(resident_id:int,data:ResidentAccessChange,u:User=Depends(current),s:Session=Depends(db)):
 role(u,'owner')
 resident=tenant_get(s,User,resident_id,u.tenant_id)
 if resident.role!='resident':raise HTTPException(404,'Resident not found')
 from platform_api import PlatformUserAccess
 access=s.get(PlatformUserAccess,resident.id)
 if access is None:
  access=PlatformUserAccess(user_id=resident.id,is_active=int(data.active));s.add(access)
 else:access.is_active=int(data.active)
 audit(s,u,'resident_access_changed',{'resident_id':resident.id,'active':data.active})
 commit(s)
 return {'id':resident.id,'active':data.active,'message':'Resident account activated' if data.active else 'Resident account deactivated. History is preserved.'}

@router.post('/residents/{resident_id}/reset-access')
def reissue_resident_access(resident_id:int,u:User=Depends(current),s:Session=Depends(db)):
 role(u,'owner')
 resident=tenant_get(s,User,resident_id,u.tenant_id)
 if resident.role!='resident':raise HTTPException(404,'Resident not found')
 temp=issue_temporary_access(s,u,resident)
 audit(s,u,'resident_access_reissued',{'resident_id':resident.id})
 commit(s)
 return {'id':resident.id,'name':resident.name,'email':resident.email,'temporary_password':temp,'expires_in_hours':72,'must_change_password':True}

class RecoveryRequest(BaseModel):
 email:str
class ResetRequest(BaseModel):
 email:str
 code:str=Field(min_length=6,max_length=6)
 new_password:str=Field(min_length=8,max_length=128)

def recovery_digest(code):
 from main import SECRET
 return hashlib.sha256((SECRET+code).encode()).hexdigest()

def send_recovery_email(email,code):
  """Send reset code over HTTPS on Render Free; preserve SMTP fallback for other hosts."""
  from email.message import EmailMessage
  sender=os.getenv('RESET_EMAIL_FROM','').strip() or os.getenv('SMTP_FROM','').strip() or os.getenv('SMTP_USER','').strip()
  key=os.getenv('RESEND_API_KEY','').strip()
  mailjet_key=os.getenv('MAILJET_API_KEY','').strip()
  mailjet_secret=os.getenv('MAILJET_SECRET_KEY','').strip()
  mailjet_sender=os.getenv('MAILJET_FROM_EMAIL','').strip()
  mailjet_ready=bool(mailjet_key and mailjet_secret and mailjet_sender)
  if not (mailjet_ready or (sender and (key or os.getenv('SMTP_HOST','').strip()))):
   raise HTTPException(503,'Email recovery is not configured. Contact your PG administrator.')
  subject='Stay Sync Manage password reset code'
  body=(f'Your Stay Sync Manage password reset code is {code}. '
        'It expires in 15 minutes. If you did not request this, ignore this email.')
  if mailjet_ready:
   import base64, urllib.request, urllib.error
   auth=base64.b64encode(f'{mailjet_key}:{mailjet_secret}'.encode('utf-8')).decode('ascii')
   payload={'Messages':[{'From':{'Email':mailjet_sender,'Name':os.getenv('MAILJET_FROM_NAME','Stay Sync Manage').strip() or 'Stay Sync Manage'},
                         'To':[{'Email':email}], 'Subject':subject, 'TextPart':body}]}
   request=urllib.request.Request('https://api.mailjet.com/v3.1/send',
       data=json.dumps(payload).encode('utf-8'),method='POST',
       headers={'Authorization':f'Basic {auth}','Content-Type':'application/json',
                'User-Agent':'StaySyncManage/1.0'})
   try:
    with urllib.request.urlopen(request,timeout=15) as response:
     if not 200<=response.status<300:
      raise RuntimeError('Mailjet rejected email request')
     result=json.loads(response.read().decode('utf-8'))
    messages=result.get('Messages',[])
    if not messages or any(m.get('Status')!='success' for m in messages):
     raise RuntimeError('Mailjet did not accept email message')
    return
   except Exception as exc:
    # Never return provider credentials or password reset codes to the caller.
    import logging
    logging.getLogger(__name__).warning('Mailjet recovery delivery failed (%s)',
        getattr(getattr(exc,'code',None),'value',None) or getattr(exc,'code',type(exc).__name__))
    raise HTTPException(503,'Recovery email could not be delivered. Try again later.') from exc
  if key:
   import urllib.request, urllib.error
   payload=json.dumps({'from':sender,'to':[email],'subject':subject,'text':body}).encode('utf-8')
   request=urllib.request.Request('https://api.resend.com/emails',data=payload,method='POST',headers={
    'Authorization':f'Bearer {key}','Content-Type':'application/json','User-Agent':'StaySyncManage/1.0'})
   try:
    with urllib.request.urlopen(request,timeout=15) as response:
     if not 200<=response.status<300:raise RuntimeError('Email provider rejected the request')
    return
   except Exception as exc:
    raise HTTPException(503,'Recovery email could not be delivered. Try again later.') from exc
  import smtplib,ssl
  message=EmailMessage();message['From']=sender;message['To']=email;message['Subject']=subject
  message.set_content(body)
  try:
   port=int(os.getenv('SMTP_PORT','587'))
   with smtplib.SMTP(os.environ['SMTP_HOST'],port,timeout=15) as smtp:
    smtp.starttls(context=ssl.create_default_context())
    if os.getenv('SMTP_USER'):smtp.login(os.environ['SMTP_USER'],os.getenv('SMTP_PASSWORD',''))
    smtp.send_message(message)
  except Exception as exc:
   raise HTTPException(503,'Recovery email could not be delivered. Try again later.') from exc

@router.post('/forgot-password')
def forgot(data:RecoveryRequest,s:Session=Depends(db)):
 if not ((os.getenv('MAILJET_API_KEY') and os.getenv('MAILJET_SECRET_KEY') and os.getenv('MAILJET_FROM_EMAIL')) or ((os.getenv('RESEND_API_KEY') or os.getenv('SMTP_HOST')) and (os.getenv('RESET_EMAIL_FROM') or os.getenv('SMTP_FROM') or os.getenv('SMTP_USER')))):raise HTTPException(503,'Email recovery is not configured. Contact your PG administrator.')
 email=safe_email(data.email);u=s.scalar(select(User).where(User.email==email))
 if u:
  old=meta(s,u.tenant_id,'recovery',u.id)
  if now().timestamp()-old.get('requested_at',0)<60:raise HTTPException(429,'Wait a minute before requesting another code.')
  code=str(secrets.randbelow(1000000)).zfill(6)
  put(s,u.tenant_id,'recovery',u.id,{'digest':recovery_digest(code),'expires':(now()+timedelta(minutes=15)).timestamp(),'requested_at':now().timestamp(),'attempts':0})
  send_recovery_email(u.email,code);commit(s)
 return {'ok':True,'message':'If the account exists, a reset code has been emailed.'}

@router.post('/reset-password')
def reset_password(data:ResetRequest,s:Session=Depends(db)):
 u=s.scalar(select(User).where(User.email==safe_email(data.email)))
 md=meta(s,u.tenant_id,'recovery',u.id) if u else {}
 if not u or md.get('expires',0)<now().timestamp() or md.get('attempts',0)>=5:raise HTTPException(400,'The reset code is invalid or expired.')
 if not secrets.compare_digest(md.get('digest',''),recovery_digest(data.code)):
  md['attempts']=md.get('attempts',0)+1;put(s,u.tenant_id,'recovery',u.id,md);commit(s);raise HTTPException(400,'The reset code is invalid or expired.')
 u.password_hash=passwords.hash(data.new_password);put(s,u.tenant_id,'security',u.id,{'changed_at':now().timestamp()});put(s,u.tenant_id,'recovery',u.id,{'expires':0,'attempts':5});commit(s)
 return {'ok':True}

@router.get('/joining-code')
def joining_code(property_id:int=0,u:User=Depends(current),s:Session=Depends(db)):
 owner(u);property_exists(s,u,property_id)
 # Preserve previously issued primary-PG codes so existing invitations do not silently change.
 if property_id==0:
  legacy=s.scalar(select(Document).where(Document.tenant_id==u.tenant_id,Document.kind=='joining_code'))
  if legacy:return {'code':legacy.key,'property_id':0,'property_name':property_name(s,u,0),
                    'message':'Owner approval and invitation are still required.'}
 # Per-property codes identify a PG, but remain owner-controlled invitation references.
 # Never authenticate or admit an account based solely on this code.
 key=f'property:{property_id}'
 item=meta(s,u.tenant_id,'property_joining_code',key)
 if not item:
  item={'code':secrets.token_hex(6).upper(),'property_id':property_id}
  put(s,u.tenant_id,'property_joining_code',key,item);commit(s)
 return {'code':item['code'],'property_id':property_id,'property_name':property_name(s,u,property_id),
         'message':'Share only with approved residents. A joining code does not replace an owner invitation.'}


def property_rows(s,u):
 from identity_api import photo_revision
 t=s.get(Tenant,u.tenant_id)
 primary={'id':0,'name':t.name,'city':'','address':'','upi':t.upi_id,'archived':False,**meta(s,u.tenant_id,'primary_property',0)}
 rows=[primary]+[dict(d.payload,id=int(d.key)) for d in s.scalars(select(Document).where(Document.tenant_id==u.tenant_id,Document.kind=='property')).all()]
 return [dict(p,photo_revision=photo_revision(s,u.tenant_id,'property',p['id'])) for p in rows]
def user_rows(s,u,role_name):
 from identity_api import photo_revision
 from platform_api import PlatformUserAccess
 rows=s.scalars(select(User).where(User.tenant_id==u.tenant_id,User.role==role_name)).all()
 return [dict(id=r.id,name=r.name,email=r.email,room=r.room,photo_revision=photo_revision(s,u.tenant_id,'user',r.id),**meta(s,u.tenant_id,'profile',r.id),**meta(s,u.tenant_id,'resident_meta' if role_name=='resident' else 'staff_meta',r.id),is_active=(bool(s.get(PlatformUserAccess,r.id).is_active) if s.get(PlatformUserAccess,r.id) else True)) for r in rows]
def chat_rows(s,u,property_id=None):
 messages=s.scalars(select(ChatMessage).where(ChatMessage.tenant_id==u.tenant_id).order_by(ChatMessage.id.desc())).all();members={r.id:r for r in s.scalars(select(User).where(User.tenant_id==u.tenant_id))};names={i:r.name for i,r in members.items()};out=[]
 for m in reversed(messages):
  md=meta(s,u.tenant_id,'message_meta',m.id)
  if u.id in md.get('hidden_by',[]):continue
  pid=int(md.get('property_id',0))
  if not visible_property(s,u,pid) or (property_id is not None and pid!=property_id):continue
  out.append({'property_id':pid,'id':m.id,'author_id':m.author_id,'author':names.get(m.author_id,'Former member'),'author_phone':meta(s,u.tenant_id,'profile',m.author_id).get('phone','') if m.author_id in members else '', 'author_room':members[m.author_id].room if m.author_id in members and members[m.author_id].role=='resident' else '', 'body':'' if m.deleted else m.body,'deleted':bool(m.deleted),'created_at':iso(m.created_at),'edited':md.get('edited',False),'reply':md.get('reply',''),'attachments':[] if m.deleted else [{'id':a.id,'filename':a.filename,'content_type':a.content_type,'url':f'/api/community/attachments/{a.id}'} for a in s.scalars(select(ChatAttachment).where(ChatAttachment.message_id==m.id,ChatAttachment.tenant_id==u.tenant_id))]})
 return out[-200:]

class RoomTransferInput(BaseModel):
 room_id:int
 bed:int=Field(ge=1)
 reason:str=Field(min_length=3,max_length=300)

@router.post('/residents/{resident_id}/transfer-room')
def transfer_room(resident_id:int,data:RoomTransferInput,u:User=Depends(current),s:Session=Depends(db)):
 owner(u)
 person=s.scalar(select(User).where(User.id==resident_id,User.tenant_id==u.tenant_id,User.role=='resident').with_for_update())
 if person is None:raise HTTPException(404,'Resident not found')
 room=s.scalar(select(Room).where(Room.id==data.room_id,Room.tenant_id==u.tenant_id).with_for_update())
 if room is None:raise HTTPException(404,'Target room not found')
 property_id=meta(s,u.tenant_id,'room_meta',room.id).get('property_id',0)
 allocation_check(s,u,room.name,data.bed,property_id,exclude=resident_id)
 old=meta(s,u.tenant_id,'resident_meta',resident_id)
 prior={'room':person.room,'bed':old.get('bed',0),'property_id':old.get('property_id',0)}
 target={'room':room.name,'bed':data.bed,'property_id':property_id}
 if prior==target:raise HTTPException(409,'Resident is already assigned to that bed')
 old['property_id']=property_id
 old['bed']=data.bed
 old['transfer_history']=[*old.get('transfer_history',[]),{'from':prior,'to':target,'reason':data.reason.strip(),'by':u.id,'at':iso(now())}]
 person.room=room.name
 put(s,u.tenant_id,'resident_meta',resident_id,old)
 audit(s,u,'room_transfer',{'resident_id':resident_id,'from':prior,'to':target,'reason':data.reason.strip()})
 alert(s,u,'Room assignment updated',f'Your accommodation has changed to {room.name}, bed {data.bed}.','accommodation',user_id=resident_id)
 commit(s)
 return {'ok':True,'allocation':target}

def payment_risk_out(s:Session, tenant_id:int, payment:Payment)->dict:
 """Read-only risk summary; old records are explicitly marked not analyzed."""
 md=meta(s,tenant_id,'payment_meta',payment.id)
 if 'analysis_status' not in md and 'risk_level' not in md:
  return {**md, 'risk_acknowledged':bool(md.get('risk_acknowledged',False)), 'risk_level':'not_analyzed', 'analysis_status':'legacy_not_analyzed',
          'risk_flags':[], 'review_notes':['This submission predates document analysis or has no stored analysis. Verify bank credit independently.'],
          'authenticity_verified':False}
 return {'risk_acknowledged':False,'risk_level':'unverified','analysis_status':'not_requested','risk_flags':[],
         'review_notes':[], 'authenticity_verified':False, **md}

def meal_rows(s,u):
 pid=int(meta(s,u.tenant_id,'resident_meta',u.id).get('property_id',0)) if u.role=='resident' else None
 records=[dict(d.payload,id=int(d.key)) for d in s.scalars(select(Document).where(Document.tenant_id==u.tenant_id,Document.kind=='property_meal')).all()]
 if pid is None or pid==0:
  override_days={x.get('day') for x in records if x.get('property_id')==0}
  records.extend(dict(id=m.id,day=m.day,breakfast=m.breakfast,lunch=m.lunch,dinner=m.dinner,property_id=0)
      for m in s.scalars(select(Meal).where(Meal.tenant_id==u.tenant_id)).all() if m.day not in override_days)
 return [m for m in records if pid is None or int(m.get('property_id',0))==pid]

def payment_destination(s,u,pid):
 property_exists(s,u,pid)
 if pid==0:
  t=s.get(Tenant,u.tenant_id)
  legacy={'upi_id':t.upi_id,'bank_holder':t.bank_holder,'bank_name':t.bank_name,
          'bank_account_masked':'****'+t.bank_account[-4:] if t.bank_account else '',
          'bank_account':t.bank_account,
          'ifsc':t.ifsc,'qr_file_id':meta(s,u.tenant_id,'owner_payment_qr','current').get('file_id')}
 else:
  legacy={}
 settings=meta(s,u.tenant_id,'property_payment',pid)
 merged={**legacy,**settings}
 if merged.get('bank_account'):
  merged['bank_account_masked']='****'+merged['bank_account'][-4:]
 merged['property_id']=pid
 merged['property_name']=property_name(s,u,pid)
 merged['configured']=bool(merged.get('upi_id') or merged.get('qr_file_id') or merged.get('bank_account_masked'))
 return merged

class PropertyPaymentInput(BaseModel):
 property_id:int=Field(ge=0)
 upi_id:str=Field(default='',max_length=100)
 bank_holder:str=Field(default='',max_length=120)
 bank_name:str=Field(default='',max_length=120)
 bank_account:str=Field(default='',max_length=40)
 ifsc:str=Field(default='',max_length=20)

@router.get('/property-payment')
def get_property_payment(property_id:int=0,u:User=Depends(current),s:Session=Depends(db)):
 pid=property_id if u.role in ('owner','manager') else int(meta(s,u.tenant_id,'resident_meta',u.id).get('property_id',0))
 if u.role not in ('owner','manager','resident'):raise HTTPException(403,'Not permitted')
 if u.role=='resident' and property_id!=pid:raise HTTPException(403,'Not your PG payment account')
 return payment_destination(s,u,pid)

@router.put('/property-payment')
def update_property_payment(data:PropertyPaymentInput,u:User=Depends(current),s:Session=Depends(db)):
 owner(u);property_exists(s,u,data.property_id)
 existing=payment_destination(s,u,data.property_id)
 changed={k:getattr(data,k).strip() for k in ('upi_id','bank_holder','bank_name','ifsc')}
 # A blank account number means retain the existing one; never return full account digits.
 account=data.bank_account.strip()
 if account:
  if not account.isdigit() or len(account)>40:raise HTTPException(422,'Invalid bank account number')
  changed['bank_account_masked']='****'+account[-4:]
  # Existing application persists sensitive bank data on the primary Tenant;
  # retain that established storage model for primary, but never expose full digits in JSON.
  if data.property_id==0:s.get(Tenant,u.tenant_id).bank_account=account
  else:changed['bank_account']=account
 changed['qr_file_id']=existing.get('qr_file_id')
 if data.property_id==0:
  legacy_tenant=s.get(Tenant,u.tenant_id)
  for field in ('upi_id','bank_holder','bank_name','ifsc'):
   setattr(legacy_tenant,field,changed[field])
 put(s,u.tenant_id,'property_payment',data.property_id,changed)
 audit(s,u,'property_payment_updated',{'property_id':data.property_id})
 commit(s)
 return payment_destination(s,u,data.property_id)

@router.get('/state')
def state(u:User=Depends(current),s:Session=Depends(db)):
 role(u,'owner','manager','resident','staff');is_owner=u.role in ('owner','manager')
 inv=s.scalars(select(Invoice).where(Invoice.tenant_id==u.tenant_id,*([] if is_owner else [Invoice.resident_id==u.id]))).all() if u.role!='staff' else []
 pay=s.scalars(select(Payment).where(Payment.tenant_id==u.tenant_id,*([] if is_owner else [Payment.resident_id==u.id]))).all() if u.role!='staff' else []
 tickets=s.scalars(select(Ticket).where(Ticket.tenant_id==u.tenant_id,*([Ticket.resident_id==u.id] if u.role=='resident' else [Ticket.assigned_to==u.id] if u.role=='staff' else []))).all()
 notices=s.scalars(select(Notice).where(Notice.tenant_id==u.tenant_id).order_by(Notice.id.desc())).all()
 facilities=s.scalars(select(Facility).where(Facility.tenant_id==u.tenant_id).order_by(Facility.id.desc())).all()
 notice_read=meta(s,u.tenant_id,'notice_read',u.id).get('ids',[]);alert_read=meta(s,u.tenant_id,'alert_read',u.id).get('ids',[])
 alerts=s.scalars(select(Alert).where(Alert.tenant_id==u.tenant_id).order_by(Alert.id.desc()).limit(200)).all()
 t=s.get(Tenant,u.tenant_id)
 resident_property=meta(s,u.tenant_id,'resident_meta',u.id).get('property_id',0)
 accommodation_property=next((p['name'] for p in property_rows(s,u) if p['id']==resident_property),t.name)
 from identity_api import identity_progress
 identity_onboarding=identity_progress(s,u) if u.role=='resident' else None
 return {'files':[{'id':f.id,'filename':f.filename,'mime':f.mime} for f in s.scalars(select(PrivateFile).where(PrivateFile.tenant_id==u.tenant_id)) if f.author_id==u.id or is_owner or u.role=='staff' and any(meta(s,u.tenant_id,'ticket_meta',t.id).get('file_id')==f.id for t in tickets)],'profile':profile_out(s,u),'properties':property_rows(s,u) if is_owner else [],'rooms':[dict(id=r.id,name=r.name,beds=r.beds,**meta(s,u.tenant_id,'room_meta',r.id)) for r in s.scalars(select(Room).where(Room.tenant_id==u.tenant_id))] if is_owner else [],'residents':user_rows(s,u,'resident') if is_owner else [],'staff':user_rows(s,u,'staff') if is_owner else [],'invoices':[invoice_out(i) for i in inv],'payments':[dict(id=p.id,invoice_id=p.invoice_id,resident_id=p.resident_id,amount=str(p.amount),reference=p.reference,status=p.status,created_at=iso(p.created_at),**payment_risk_out(s,u.tenant_id,p)) for p in pay],'complaints':[dict(id=t.id,resident_id=t.resident_id,category=t.category,description=t.description,status=t.status,assigned_to=t.assigned_to,**meta(s,u.tenant_id,'ticket_meta',t.id)) for t in tickets],'notices':[dict(id=n.id,title=n.title,body=n.body,category=n.category,status=n.status,read=n.id in notice_read,created_at=iso(n.created_at),**meta(s,u.tenant_id,'notice_meta',n.id)) for n in notices if visible_property(s,u,meta(s,u.tenant_id,'notice_meta',n.id).get('property_id',0))],'facilities':[dict(id=f.id,title=f.title,details=f.details,category=f.category,status=f.status,**meta(s,u.tenant_id,'facility_meta',f.id)) for f in facilities if visible_property(s,u,meta(s,u.tenant_id,'facility_meta',f.id).get('property_id',0))],'expenses':[dict(id=e.id,period=e.period,description=e.description,category=e.category,amount=str(e.amount),**meta(s,u.tenant_id,'expense_meta',e.id)) for e in s.scalars(select(Expense).where(Expense.tenant_id==u.tenant_id))] if is_owner else [],'bookings':[dict(d.payload,id=int(d.key)) for d in s.scalars(select(Document).where(Document.tenant_id==u.tenant_id,Document.kind=='booking'))] if is_owner else [],'meals':meal_rows(s,u),'messages':chat_rows(s,u) if u.role!='staff' else [],'members':[],'identity_onboarding':identity_onboarding,'notifications':[dict(id=a.id,title=a.title,body=a.body,destination=a.destination,entity_id=meta(s,u.tenant_id,'alert_meta',a.id).get('entity_id'),property_id=meta(s,u.tenant_id,'alert_meta',a.id).get('property_id'),created_at=a.created_at,read=a.id in alert_read) for a in alerts if (a.user_id is None or a.user_id==u.id) and (a.audience=='all' or a.audience==u.role or a.audience=='owners' and is_owner) and visible_alert(s,u,a) and int(meta(s,u.tenant_id,'alert_meta',a.id).get('created_by',-1))!=u.id],'payment_methods':payment_destination(s,u,resident_property if u.role=='resident' else 0),'property_payment_methods':[payment_destination(s,u,int(p['id'])) for p in property_rows(s,u) if p.get('archived')!=True] if is_owner else [],'accommodation':{'property':accommodation_property,'room':u.room,**meta(s,u.tenant_id,'resident_meta',u.id)}}

class PropertyInput(BaseModel):
 name:str=Field(min_length=2,max_length=120)
 city:str=Field(default='',max_length=100)
 address:str=Field(default='',max_length=500)
 upi:str=Field(default='',max_length=100)
 archived:bool=False
class RoomInput(BaseModel):
 name:str=Field(min_length=1,max_length=50)
 floor:str='Ground'
 beds:int=Field(ge=1,le=100)
 property_id:int=0
class PersonInput(BaseModel):
 name:str=Field(min_length=2,max_length=120)
 email:str
 phone:str=''
 password:str=Field(default='',max_length=128)
 room:str=''
 property_id:int=0
 bed:int=Field(default=0,ge=0)
 job:str='Maintenance'
 monthly_rent:Decimal=Field(default=Decimal('0'),ge=0,le=10000000,max_digits=12,decimal_places=2)
class ExpenseInput(BaseModel):
 period:str=Field(pattern=r'^\d{4}-(0[1-9]|1[0-2])$')
 description:str=Field(min_length=2,max_length=300)
 category:str=Field(min_length=2,max_length=40)
 amount:Decimal=Field(gt=0,max_digits=12,decimal_places=2)
 property_id:int=0
class BookingInput(BaseModel):
 name:str=Field(min_length=2,max_length=120)
 phone:str=Field(min_length=7,max_length=20)
 room:str=''
 status:str=Field(default='Enquiry',pattern='^(Enquiry|Contacted|Closed|Cancelled)$')
 property_id:int=0
class FacilityInput(BaseModel):
 property_id:int=Field(default=0,ge=0)
 title:str=Field(min_length=3,max_length=160)
 details:str=Field(min_length=3,max_length=2500)
 category:str=Field(pattern='^(water|power|wifi|maintenance|other)$')
 status:str=Field(pattern='^(scheduled|outage|maintenance|restored|normal)$')
class NoticeInput(BaseModel):
 property_id:int=Field(default=0,ge=0)
 title:str=Field(min_length=3,max_length=160)
 body:str=Field(min_length=3,max_length=4000)
 category:str='general'
 status:str=Field(default='active',pattern='^(active|archived)$')
 important:bool=False
class MealInput(BaseModel):
 day:str=Field(pattern='^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)$')
 breakfast:str=Field(min_length=1,max_length=250)
 lunch:str=Field(min_length=1,max_length=250)
 dinner:str=Field(min_length=1,max_length=250)
 property_id:int=Field(default=0,ge=0)
class ComplaintInput(BaseModel):
 category:str=Field(min_length=2,max_length=50)
 description:str=Field(min_length=5,max_length=2000)
 priority:str=Field(default='Medium',pattern='^(Low|Medium|High|Urgent)$')
 file_id:Optional[int]=None
class ComplaintUpdate(BaseModel):
 status:str=Field(pattern='^(submitted|assigned|in_progress|resolved|reopened)$')
 assigned_to:Optional[int]=None
 note:str=Field(min_length=2,max_length=1000)

def allocation_check(s,u,room_name,bed,property_id,exclude=None):
 if not room_name:
  if bed:raise HTTPException(422,'Choose a room before assigning a bed')
  return
 rooms=s.scalars(select(Room).where(Room.tenant_id==u.tenant_id,Room.name==room_name).with_for_update()).all()
 r=next((r for r in rooms if meta(s,u.tenant_id,'room_meta',r.id).get('property_id',0)==property_id),None)
 if not r:raise HTTPException(422,'Choose a room in the selected property')
 users=s.scalars(select(User).where(User.tenant_id==u.tenant_id,User.role=='resident',User.room==room_name)).all()
 occupants=[p for p in users if p.id!=exclude and meta(s,u.tenant_id,'resident_meta',p.id).get('property_id',0)==property_id]
 if len(occupants)>=r.beds:raise HTTPException(409,'Room is full')
 if bed<1 or bed>r.beds:raise HTTPException(422,'Choose a valid bed number')
 if any(meta(s,u.tenant_id,'resident_meta',p.id).get('bed')==bed for p in occupants):raise HTTPException(409,'Bed is already occupied')

SCHEMAS={'property':PropertyInput,'room':RoomInput,'resident':PersonInput,'staff':PersonInput,'expense':ExpenseInput,'booking':BookingInput,'facility':FacilityInput,'notice':NoticeInput,'meal':MealInput,'complaint':ComplaintInput}
@router.post('/entities/{kind}',status_code=201)
def create_entity(kind:str,data:dict,u:User=Depends(current),s:Session=Depends(db)):
 return save_entity(kind,0,data,u,s,creating=True)
@router.put('/entities/{kind}/{identifier}')
def update_entity(kind:str,identifier:int,data:dict,u:User=Depends(current),s:Session=Depends(db)):
 return save_entity(kind,identifier,data,u,s,creating=False)
def save_entity(kind,identifier,data,u,s,creating):
 if kind not in SCHEMAS:raise HTTPException(404,'Unknown record type')
 if kind=='complaint':role(u,'resident')
 else:owner(u)
 if kind=='resident' and creating:raise HTTPException(422,'Use owner resident invitation to generate and share temporary access.')
 try:d=SCHEMAS[kind].model_validate(data).model_dump()
 except ValidationError as err:raise HTTPException(422,str(err))
 if 'property_id' in d:property_exists(s,u,d['property_id'])
 if kind in ('property','booking'):
  if creating:
   identifier=secrets.randbelow(2**30)+1
  elif kind=='property' and identifier==0:
   t=s.get(Tenant,u.tenant_id);t.name=d['name'];t.upi_id=d['upi'];put(s,u.tenant_id,'primary_property',0,d);audit(s,u,'property_edit',d);commit(s);return {'id':0}
  elif not doc(s,u.tenant_id,kind,identifier):raise HTTPException(404,'Record not found')
  if kind=='property' and d['archived']:
   rooms=s.scalars(select(Room).where(Room.tenant_id==u.tenant_id)).all()
   if any(meta(s,u.tenant_id,'room_meta',r.id).get('property_id',0)==identifier for r in rooms):raise HTTPException(409,'Move rooms and residents before archiving the property')
  put(s,u.tenant_id,kind,identifier,d)
 elif kind=='room':
  r=Room(tenant_id=u.tenant_id,name=d['name'],beds=d['beds']) if creating else tenant_get(s,Room,identifier,u.tenant_id)
  if not creating:
   old_property=meta(s,u.tenant_id,'room_meta',r.id).get('property_id',0)
   occupants=[p for p in user_rows(s,u,'resident') if p['room']==r.name and p.get('property_id',0)==old_property]
   if len(occupants)>d['beds'] or any(p.get('bed',0)>d['beds'] for p in occupants):raise HTTPException(409,'Move residents before reducing occupied bed capacity')
   if occupants and d['property_id']!=old_property:raise HTTPException(409,'An occupied room cannot be moved to another property')
   for p in occupants:s.get(User,p['id']).room=d['name']
  duplicate=s.scalars(select(Room).where(Room.tenant_id==u.tenant_id,Room.name==d['name'])).all()
  if any(x.id!=r.id and meta(s,u.tenant_id,'room_meta',x.id).get('property_id',0)==d['property_id'] for x in duplicate):raise HTTPException(409,'Room already exists in this property')
  r.name=d['name'];r.beds=d['beds'];s.add(r);s.flush();identifier=r.id;put(s,u.tenant_id,'room_meta',identifier,{'floor':d['floor'],'property_id':d['property_id']})
 elif kind in ('resident','staff'):
  if creating and kind=='staff' and len(d['password'])<8:raise HTTPException(422,'Initial password must be at least 8 characters')
  mail=safe_email(d['email'])
  if kind=='resident':allocation_check(s,u,d['room'],d['bed'],d['property_id'],None if creating else identifier)
  r=User(tenant_id=u.tenant_id,name=d['name'],email=mail,role=kind,password_hash=passwords.hash(d['password']) if kind=='staff' else '',room=d['room']) if creating else tenant_get(s,User,identifier,u.tenant_id)
  if not creating and r.role!=kind:raise HTTPException(404,'Person not found')
  r.name=d['name'];r.email=mail;r.room=d['room'];s.add(r);s.flush();identifier=r.id
  if creating and kind=='resident':issue_temporary_access(s,u,r)
  pm=meta(s,u.tenant_id,'profile',identifier);pm['phone']=d['phone'];put(s,u.tenant_id,'profile',identifier,pm)
  put(s,u.tenant_id,kind+'_meta',identifier,{**meta(s,u.tenant_id,kind+'_meta',identifier),**{k:d[k] for k in ('property_id','bed','job')},**({'monthly_rent':str(d['monthly_rent'])} if kind=='resident' else {})})
 elif kind=='expense':
  vals={k:d[k] for k in ('period','description','category','amount')};r=Expense(tenant_id=u.tenant_id,**vals) if creating else tenant_get(s,Expense,identifier,u.tenant_id)
  for k,v in vals.items():setattr(r,k,v)
  s.add(r);s.flush();identifier=r.id;put(s,u.tenant_id,'expense_meta',identifier,{'property_id':d['property_id']})
 elif kind=='facility':
  pid=d.pop('property_id')
  r=Facility(tenant_id=u.tenant_id,**d) if creating else tenant_get(s,Facility,identifier,u.tenant_id)
  for k,v in d.items():setattr(r,k,v)
  s.add(r);s.flush();identifier=r.id;md=meta(s,u.tenant_id,'facility_meta',identifier)
  if not creating and int(md.get('property_id',0))!=pid:raise HTTPException(409,'Facility cannot be moved between PGs')
  md['property_id']=pid
  md['history']=[*md.get('history',[]),{'status':d['status'],'at':iso(now())}]
  put(s,u.tenant_id,'facility_meta',identifier,md)
  alert(s,u,'Facility update',f'{property_name(s,u,pid)}: {d["title"]}','facilities',property_id=pid,entity_id=identifier)
 elif kind=='notice':
  important=d.pop('important');pid=d.pop('property_id')
  r=Notice(tenant_id=u.tenant_id,**d) if creating else tenant_get(s,Notice,identifier,u.tenant_id)
  for k,v in d.items():setattr(r,k,v)
  s.add(r);s.flush();identifier=r.id
  old=meta(s,u.tenant_id,'notice_meta',identifier)
  if not creating and int(old.get('property_id',0))!=pid:raise HTTPException(409,'Announcement cannot be moved between PGs')
  put(s,u.tenant_id,'notice_meta',identifier,{**old,'important':important,'property_id':pid})
  alert(s,u,'Announcement',f'{property_name(s,u,pid)}: {d["title"]}','announcements',property_id=pid,entity_id=identifier)
 elif kind=='meal':
  pid=d['property_id']
  all_meals=s.scalars(select(Document).where(Document.tenant_id==u.tenant_id,Document.kind=='property_meal')).all()
  existing=next((x for x in all_meals if int(x.payload.get('property_id',0))==pid and x.payload.get('day')==d['day']),None)
  if creating:
   identifier=int(existing.key) if existing else secrets.randbelow(2**30)+1
  else:
   existing=doc(s,u.tenant_id,'property_meal',identifier)
   if not existing:
    # Legacy primary meal record may be edited without modifying other properties.
    old=s.get(Meal,identifier)
    if pid!=0 or not old or old.tenant_id!=u.tenant_id:raise HTTPException(404,'Meal not found for this PG')
   elif int(existing.payload.get('property_id',0))!=pid:
    raise HTTPException(409,'A meal cannot be moved to a different PG')
  put(s,u.tenant_id,'property_meal',identifier,d)
 elif kind=='complaint':
  safe_file(s,u,d['file_id'],'complaint');pid=int(meta(s,u.tenant_id,'resident_meta',u.id).get('property_id',0))
  r=Ticket(tenant_id=u.tenant_id,resident_id=u.id,category=d['category'],description=d['description'],status='submitted');s.add(r);s.flush();identifier=r.id
  put(s,u.tenant_id,'ticket_meta',identifier,{'priority':d['priority'],'property_id':pid,'file_id':d['file_id'],'history':[{'status':'submitted','note':'Complaint submitted','at':iso(now())}]})
  alert(s,u,'New complaint',f'{property_name(s,u,pid)} · Complaint #{identifier} · {d["category"]}: {d["description"][:120]}','complaints',audience='owners',property_id=pid,entity_id=identifier)
 audit(s,u,kind+('_create' if creating else '_update'),{'id':identifier});commit(s);return {'id':identifier}
@router.patch('/complaints/{identifier}')
def change_complaint(identifier:int,data:ComplaintUpdate,u:User=Depends(current),s:Session=Depends(db)):
 role(u,'owner','manager','staff');t=tenant_get(s,Ticket,identifier,u.tenant_id)
 if u.role=='staff' and (t.assigned_to!=u.id or data.assigned_to!=u.id):raise HTTPException(403,'Only your assigned tasks can be updated')
 if data.assigned_to:
  staff=tenant_get(s,User,data.assigned_to,u.tenant_id)
  if staff.role!='staff':raise HTTPException(422,'Choose a staff member')
 t.status=data.status;t.assigned_to=data.assigned_to;md=meta(s,u.tenant_id,'ticket_meta',t.id);md['history']=[*md.get('history',[]),{'status':data.status,'note':data.note,'at':iso(now())}];put(s,u.tenant_id,'ticket_meta',t.id,md);alert(s,u,'Complaint updated',f'{property_name(s,u,int(md.get("property_id",0)))} · Complaint #{t.id}: {data.note}','complaints',user_id=t.resident_id,property_id=int(md.get('property_id',0)),entity_id=t.id);audit(s,u,'complaint_update',{'id':t.id});commit(s);return {'ok':True}
class ProofInput(BaseModel):
 invoice_id:int
 amount:Decimal=Field(gt=0,max_digits=12,decimal_places=2)
 reference:Optional[str]=Field(default=None,max_length=120)
 file_id:Optional[int]=None
@router.post('/payments',status_code=201)
def payment(data:ProofInput,u:User=Depends(current),s:Session=Depends(db)):
 role(u,'resident');i=tenant_get(s,Invoice,data.invoice_id,u.tenant_id)
 if i.resident_id!=u.id:raise HTTPException(403,'Not your invoice')
 pending_total=sum((q.amount for q in s.scalars(select(Payment).where(
  Payment.tenant_id==u.tenant_id,Payment.invoice_id==i.id,Payment.status=='pending'))),Decimal('0'))
 if data.amount>i.amount-i.paid-pending_total:raise HTTPException(409,'Amount exceeds balance after pending verification')
 reference=(data.reference or '').strip() or 'PROOF-'+uuid.uuid4().hex.upper()[:20]
 if len(reference)<6:raise HTTPException(422,'Invalid reference')
 if s.scalar(select(Payment).where(Payment.tenant_id==u.tenant_id,Payment.reference==reference,Payment.status!='rejected')):raise HTTPException(409,'Reference already submitted')
 safe_file(s,u,data.file_id,'payment')
 from risk_checks import inspect_file
 risk={'risk_level':'review_required','risk_flags':['No proof attached'], 'analysis_status':'not_requested', 'authenticity_verified':False, 'ai_generated_verified':False}
 if data.file_id:
  f=tenant_get(s,PrivateFile,data.file_id,u.tenant_id)
  raw=(STORAGE/f.key).read_bytes() if (STORAGE/f.key).is_file() else b''
  # Compare submitted payment file fingerprints within the same PG tenant.
  previous=[meta(s,u.tenant_id,'payment_meta',q.id) for q in s.scalars(
   select(Payment).where(Payment.tenant_id==u.tenant_id).order_by(Payment.id.desc()).limit(100))]
  known=[item.get('sha256') for item in previous]
  visual=[item.get('visual_hash') for item in previous]
  risk=inspect_file(raw,f.mime,filter(None,known),
       known_visual_hashes=filter(None,visual),document_kind='payment',
       expected_amount=data.amount,expected_reference=reference)
  if not raw:
   risk['risk_flags'].append('Uploaded payment proof was not accessible for analysis')
   risk['risk_level']='review_required'
 p=Payment(tenant_id=u.tenant_id,resident_id=u.id,invoice_id=i.id,amount=data.amount,reference=reference);s.add(p);s.flush()
 put(s,u.tenant_id,'payment_meta',p.id,{'file_id':data.file_id,**risk})
 alert(s,u,'Payment submitted',f'{u.name}: {data.amount}','payments',audience='owners');commit(s);return {'id':p.id,'risk_level':risk['risk_level'],'analysis_status':risk.get('analysis_status','not_requested')}
class Review(BaseModel):
 decision:str=Field(pattern='^(approved|rejected)$')
 reason:str=''
 bank_confirmed:bool=False
 risk_acknowledged:bool=False
@router.post('/payments/{identifier}/review')
def review(identifier:int,data:Review,u:User=Depends(current),s:Session=Depends(db)):
 role(u,'owner');p=s.scalar(select(Payment).where(Payment.id==identifier,Payment.tenant_id==u.tenant_id).with_for_update())
 if not p:raise HTTPException(404,'Payment not found')
 if p.status!='pending':raise HTTPException(409,'Payment already reviewed')
 i=s.scalar(select(Invoice).where(Invoice.id==p.invoice_id,Invoice.tenant_id==u.tenant_id).with_for_update())
 if data.decision=='approved':
  if payment_risk_out(s,u.tenant_id,p).get('risk_level')=='review_required' and not data.risk_acknowledged:
   raise HTTPException(422,'Risk flags must be reviewed and acknowledged before approval')
  if not data.bank_confirmed:raise HTTPException(422,'Confirm bank credit first')
  if i.paid+p.amount>i.amount:raise HTTPException(409,'Payment exceeds the remaining balance')
  i.paid+=p.amount
 elif len(data.reason.strip())<3:raise HTTPException(422,'Give a rejection reason')
 p.status=data.decision;md=meta(s,u.tenant_id,'payment_meta',p.id);md.update(reason=data.reason,reviewed_by=u.id,reviewed_at=iso(now()),risk_acknowledged=bool(data.risk_acknowledged) if data.decision=='approved' else False);put(s,u.tenant_id,'payment_meta',p.id,md);alert(s,u,'Payment '+p.status,data.reason or str(p.amount),'rent',user_id=p.resident_id);audit(s,u,'payment_review',{'id':p.id,'decision':p.status});commit(s);return {'ok':True}
@router.post('/read/{kind}/{identifier}')
def read_item(kind:str,identifier:int,u:User=Depends(current),s:Session=Depends(db)):
 if kind not in ('notice','alert'):raise HTTPException(404,'Unknown type')
 model=Notice if kind=='notice' else Alert;row=tenant_get(s,model,identifier,u.tenant_id)
 if kind=='notice' and not visible_property(s,u,meta(s,u.tenant_id,'notice_meta',identifier).get('property_id',0)):
  raise HTTPException(404,'Announcement not found')
 if kind=='alert':
  allowed=(row.user_id is None or row.user_id==u.id) and (row.audience=='all' or row.audience==u.role or row.audience=='owners' and u.role in ('owner','manager'))
  if not allowed or not visible_alert(s,u,row):raise HTTPException(404,'Notification not found')
 md=meta(s,u.tenant_id,kind+'_read',u.id);md['ids']=list(set(md.get('ids',[])+[identifier]));put(s,u.tenant_id,kind+'_read',u.id,md);commit(s);return {'ok':True}
class ChatInput(BaseModel):
 property_id:int=Field(default=0,ge=0)
 body:str=Field(min_length=1,max_length=2000)
 reply:str=Field(default='',max_length=300)
@router.get('/community-members')
def community_members(property_id:int,u:User=Depends(current),s:Session=Depends(db)):
 """Return only members assigned to a PG; no cross-property membership leakage."""
 role(u,'owner','manager','resident','staff')
 chat_access(s,u,property_id)
 from platform_api import PlatformUserAccess
 result=[]
 for member in s.scalars(select(User).where(User.tenant_id==u.tenant_id)):
  access=s.get(PlatformUserAccess,member.id)
  if access is not None and not access.is_active:continue
  if member.role in ('owner','manager'):
   # Organization owner/manager may participate in each of its communities.
   result.append({'id':member.id,'name':member.name,'role':member.role,'property_id':property_id})
  elif member.role in ('resident','staff'):
   assignment=meta(s,u.tenant_id,'resident_meta' if member.role=='resident' else 'staff_meta',member.id)
   if int(assignment.get('property_id',0) or 0)==property_id:
    result.append({'id':member.id,'name':member.name,'role':member.role,'property_id':property_id})
 return result

@router.get('/community-capabilities')
def community_capabilities(u:User=Depends(current)):
 role(u,'owner','manager','resident')
 return {'property_scoped':True,'message_schema_version':2}

@router.get('/messages')
def messages(property_id:int=0,u:User=Depends(current),s:Session=Depends(db)):
 role(u,'owner','manager','resident');chat_access(s,u,property_id);return chat_rows(s,u,property_id)
@router.post('/messages',status_code=201)
def send_message(data:ChatInput,u:User=Depends(current),s:Session=Depends(db)):
 role(u,'owner','manager','resident');text=data.body.strip();pid=data.property_id
 chat_access(s,u,pid)
 if not text:raise HTTPException(422,'Message cannot be blank')
 m=ChatMessage(tenant_id=u.tenant_id,author_id=u.id,body=text);s.add(m);s.flush();put(s,u.tenant_id,'message_meta',m.id,{'reply':data.reply,'property_id':pid})
 for recipient in s.scalars(select(User).where(User.tenant_id==u.tenant_id,User.id!=u.id,User.role.in_(['owner','manager','resident']))):
  if recipient.role=='resident' and int(meta(s,u.tenant_id,'resident_meta',recipient.id).get('property_id',0))!=pid:continue
  alert(s,u,'New community message',f'{property_name(s,u,pid)} · {u.name}: {text[:90]}','community',user_id=recipient.id,property_id=pid,entity_id=m.id)
 commit(s);return {'id':m.id}
@router.patch('/messages/{identifier}')
def edit_message(identifier:int,data:ChatInput,u:User=Depends(current),s:Session=Depends(db)):
 m=tenant_get(s,ChatMessage,identifier,u.tenant_id);editable(m,u)
 chat_access(s,u,message_property(s,u,m))
 m.body=data.body.strip()
 if not m.body:raise HTTPException(422,'Message cannot be blank')
 md=meta(s,u.tenant_id,'message_meta',m.id);md['edited']=True;put(s,u.tenant_id,'message_meta',m.id,md);commit(s);return {'ok':True}
def editable(m,u):
 if m.author_id!=u.id:raise HTTPException(403,'Only the sender may change this message')
 if m.deleted:raise HTTPException(409,'Message has been unsent')
 when=m.created_at.replace(tzinfo=timezone.utc) if m.created_at.tzinfo is None else m.created_at
 if now()-when>timedelta(minutes=15):raise HTTPException(409,'The 15 minute edit/unsend window has ended')
@router.delete('/messages/{identifier}')
def delete_message(identifier:int,for_everyone:bool=False,u:User=Depends(current),s:Session=Depends(db)):
 role(u,'owner','manager','resident');m=tenant_get(s,ChatMessage,identifier,u.tenant_id)
 chat_access(s,u,message_property(s,u,m))
 if for_everyone:editable(m,u);m.deleted=1;m.body=''
 else:
  md=meta(s,u.tenant_id,'message_meta',m.id);md['hidden_by']=list(set(md.get('hidden_by',[])+[u.id]));put(s,u.tenant_id,'message_meta',m.id,md)
 commit(s);return {'ok':True}
STORAGE=Path(os.getenv('COMEIN_PRIVATE_STORAGE',str(Path(__file__).parent/'private_uploads')))
class PaymentQrInput(BaseModel):
 file_id:int
 property_id:int=Field(default=0,ge=0)
@router.put('/payment-qr')
def update_owner_payment_qr(data:PaymentQrInput,u:User=Depends(current),s:Session=Depends(db)):
 owner(u);property_exists(s,u,data.property_id)
 safe_file(s,u,data.file_id,'owner_qr')
 settings=meta(s,u.tenant_id,'property_payment',data.property_id)
 settings['qr_file_id']=data.file_id
 put(s,u.tenant_id,'property_payment',data.property_id,settings)
 if data.property_id==0:
  put(s,u.tenant_id,'owner_payment_qr','current',{'file_id':data.file_id})
  s.get(Tenant,u.tenant_id).qr_image_url=''
 audit(s,u,'owner_payment_qr_updated',{'file_id':data.file_id,'property_id':data.property_id})
 commit(s)
 return {'ok':True,'qr_file_id':data.file_id,'property_id':data.property_id}

@router.post('/files/{purpose}',status_code=201)
async def upload(purpose:str,file:UploadFile=File(...),u:User=Depends(current),s:Session=Depends(db)):
 if purpose not in ('payment','complaint','owner_qr'):raise HTTPException(404,'Unsupported attachment purpose')
 role(u,'owner') if purpose=='owner_qr' else role(u,'resident')
 mime=file.content_type or '';allowed={'image/png','image/jpeg','image/webp','application/pdf'}
 if purpose in ('complaint','owner_qr'):allowed.remove('application/pdf')
 if mime not in allowed:raise HTTPException(415,'Unsupported file type')
 data=await file.read(5*1024*1024+1)
 if not data or len(data)>5*1024*1024:raise HTTPException(413,'Use a non-empty file smaller than 5 MB')
 valid=(mime=='image/png' and data.startswith(b'\x89PNG\r\n\x1a\n') or mime=='image/jpeg' and data.startswith(b'\xff\xd8\xff') or mime=='image/webp' and data[:4]==b'RIFF' and data[8:12]==b'WEBP' or mime=='application/pdf' and data.startswith(b'%PDF-'))
 if not valid:raise HTTPException(415,'File bytes do not match the declared type')
 key=uuid.uuid4().hex;STORAGE.mkdir(parents=True,exist_ok=True);path=STORAGE/key;path.write_bytes(data)
 try:
  f=PrivateFile(tenant_id=u.tenant_id,author_id=u.id,purpose=purpose,filename=Path(file.filename or 'attachment').name[:180],mime=mime,key=key,size=len(data));s.add(f);s.flush();identifier=f.id;commit(s)
 except Exception:path.unlink(missing_ok=True);raise
 return {'id':identifier,'name':f.filename,'size':f.size,'content_type':mime}
@router.get('/files/{identifier}')
def download(identifier:int,u:User=Depends(current),s:Session=Depends(db)):
 f=tenant_get(s,PrivateFile,identifier,u.tenant_id)
 permitted=(f.author_id==u.id or u.role in ('owner','manager'))
 if f.purpose=='owner_qr' and u.role=='resident':
  rp=int(meta(s,u.tenant_id,'resident_meta',u.id).get('property_id',0))
  permitted=(payment_destination(s,u,rp).get('qr_file_id')==f.id)
 if u.role=='staff' and f.purpose=='complaint':
  assigned=s.scalars(select(Ticket).where(Ticket.tenant_id==u.tenant_id,Ticket.assigned_to==u.id)).all();permitted=any(meta(s,u.tenant_id,'ticket_meta',t.id).get('file_id')==f.id for t in assigned)
 if not permitted:raise HTTPException(403,'This attachment is private')
 path=STORAGE/f.key
 if not path.is_file():raise HTTPException(404,'File no longer available')
 return FileResponse(path,media_type=f.mime,filename=f.filename)

def lookup_phone(s,value):
 normalized=re.sub(r'\D','',value)
 if not normalized:return None
 matches=[s.get(User,d.key) for d in s.scalars(select(Document).where(Document.kind=='profile')) if re.sub(r'\D','',str(d.payload.get('phone','')))==normalized]
 return matches[0] if len(matches)==1 else None

@router.post('/reminders/{resident_id}')
def rent_reminder(resident_id:int,u:User=Depends(current),s:Session=Depends(db)):
 owner(u);r=tenant_get(s,User,resident_id,u.tenant_id)
 if r.role!='resident':raise HTTPException(404,'Resident not found')
 invoices=s.scalars(select(Invoice).where(Invoice.tenant_id==u.tenant_id,Invoice.resident_id==r.id)).all()
 balance=sum((i.amount-i.paid for i in invoices),Decimal(0))
 alert(s,u,'Rent reminder',f'Your outstanding rent is INR {balance}. Please review My rent.','rent',user_id=r.id)
 audit(s,u,'rent_reminder',{'resident_id':r.id,'balance':str(balance)});commit(s);return {'ok':True,'delivery':'in_app'}

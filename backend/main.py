"""PG Platform MVP API. SQLite is development-only; PostgreSQL supported via DATABASE_URL."""
import os
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import Optional
from fastapi import FastAPI, HTTPException, Depends, Header, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from sqlalchemy import create_engine, String, Integer, ForeignKey, DateTime, Numeric, Text, select, UniqueConstraint
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker, Session
from pwdlib import PasswordHash
import jwt
from dotenv import load_dotenv
load_dotenv()
URL=os.getenv('DATABASE_URL','sqlite:///./pg_dev.db')
engine=create_engine(URL,connect_args={'check_same_thread':False} if URL.startswith('sqlite') else {},pool_pre_ping=True)
SessionLocal=sessionmaker(engine,expire_on_commit=False)
class Base(DeclarativeBase): pass
class Tenant(Base):
 __tablename__='tenants'
 id:Mapped[int]=mapped_column(primary_key=True)
 name:Mapped[str]=mapped_column(String(120))
 primary_color:Mapped[str]=mapped_column(String(10),default='#FFDD00')
 upi_id:Mapped[str]=mapped_column(String(100),default='')
 qr_image_url:Mapped[str]=mapped_column(String(500),default='')
 bank_holder:Mapped[str]=mapped_column(String(120),default='')
 bank_name:Mapped[str]=mapped_column(String(120),default='')
 bank_account:Mapped[str]=mapped_column(String(40),default='')
 ifsc:Mapped[str]=mapped_column(String(30),default='')
class User(Base):
 __tablename__='users'
 id:Mapped[int]=mapped_column(primary_key=True)
 tenant_id:Mapped[int]=mapped_column(ForeignKey('tenants.id'),index=True)
 name:Mapped[str]=mapped_column(String(120))
 email:Mapped[str]=mapped_column(String(160),unique=True)
 password_hash:Mapped[str]=mapped_column(String(300))
 role:Mapped[str]=mapped_column(String(20))
 room:Mapped[str]=mapped_column(String(30),default='')
class Notice(Base):
 __tablename__='notices'
 id:Mapped[int]=mapped_column(primary_key=True)
 tenant_id:Mapped[int]=mapped_column(ForeignKey('tenants.id'),index=True)
 title:Mapped[str]=mapped_column(String(160))
 body:Mapped[str]=mapped_column(Text)
 category:Mapped[str]=mapped_column(String(40),default='general')
 status:Mapped[str]=mapped_column(String(40),default='active')
 created_at:Mapped[datetime]=mapped_column(DateTime(timezone=True),default=lambda:datetime.now(timezone.utc))
class Ticket(Base):
 __tablename__='tickets'
 id:Mapped[int]=mapped_column(primary_key=True)
 tenant_id:Mapped[int]=mapped_column(ForeignKey('tenants.id'),index=True)
 resident_id:Mapped[int]=mapped_column(ForeignKey('users.id'))
 category:Mapped[str]=mapped_column(String(50))
 description:Mapped[str]=mapped_column(Text)
 status:Mapped[str]=mapped_column(String(30),default='submitted')
 assigned_to:Mapped[Optional[int]]=mapped_column(ForeignKey('users.id'),nullable=True)
class Invoice(Base):
 __tablename__='invoices'
 id:Mapped[int]=mapped_column(primary_key=True)
 tenant_id:Mapped[int]=mapped_column(ForeignKey('tenants.id'),index=True)
 resident_id:Mapped[int]=mapped_column(ForeignKey('users.id'))
 period:Mapped[str]=mapped_column(String(7))
 amount:Mapped[Decimal]=mapped_column(Numeric(12,2))
 paid:Mapped[Decimal]=mapped_column(Numeric(12,2),default=0)
 due_date:Mapped[str]=mapped_column(String(10))
 __table_args__=(UniqueConstraint('tenant_id','resident_id','period'),)
class Payment(Base):
 __tablename__='payments'
 id:Mapped[int]=mapped_column(primary_key=True)
 tenant_id:Mapped[int]=mapped_column(ForeignKey('tenants.id'),index=True)
 invoice_id:Mapped[int]=mapped_column(ForeignKey('invoices.id'))
 resident_id:Mapped[int]=mapped_column(ForeignKey('users.id'))
 amount:Mapped[Decimal]=mapped_column(Numeric(12,2))
 reference:Mapped[str]=mapped_column(String(120))
 status:Mapped[str]=mapped_column(String(30),default='pending')
 created_at:Mapped[datetime]=mapped_column(DateTime(timezone=True),default=lambda:datetime.now(timezone.utc))
class Credentials(BaseModel):
 email:str
 password:str
class NewNotice(BaseModel):
 title:str=Field(min_length=3,max_length=160)
 body:str=Field(min_length=3,max_length=4000)
 category:str='general'
class NewTicket(BaseModel):
 category:str
 description:str=Field(min_length=5,max_length=2000)
class TicketUpdate(BaseModel):
 status:str
 assigned_to:Optional[int]=None
class PaymentSubmission(BaseModel):
 invoice_id:int
 amount:Decimal=Field(gt=0)
 reference:str=Field(min_length=4,max_length=120)
class VerifyPayment(BaseModel):
 decision:str
class InvoiceCreate(BaseModel):
 resident_id:int
 period:str=Field(pattern=r'^\d{4}-\d{2}$')
 amount:Decimal=Field(gt=0)
 due_date:str
class BankUpdate(BaseModel):
 upi_id:str=''
 qr_image_url:str=''
 bank_holder:str=''
 bank_name:str=''
 bank_account:str=''
 ifsc:str=''
passwords=PasswordHash.recommended()
SECRET=os.getenv('SECRET_KEY','development-only-not-for-production')
app=FastAPI(title='COME.in PG Platform API',version='0.1.0')
app.add_middleware(CORSMiddleware,allow_origins=os.getenv('CORS_ORIGINS','http://localhost:5173').split(','),allow_credentials=True,allow_methods=['*'],allow_headers=['*'])
def db():
 with SessionLocal() as session: yield session
def current(request:Request,authorization:Optional[str]=Header(None),session:Session=Depends(db)):
 if not authorization or not authorization.startswith('Bearer '):raise HTTPException(401,'Login required')
 try: payload=jwt.decode(authorization[7:],SECRET,algorithms=['HS256']); user=session.get(User,int(payload['sub']))
 except (jwt.PyJWTError,ValueError,KeyError):raise HTTPException(401,'Invalid or expired session')
 if not user or user.tenant_id!=payload.get('tenant'):raise HTTPException(401,'Invalid session')
 if 'security_check' in globals():security_check(user,payload,authorization,session)
 if 'meta' in globals():
  onboarding=meta(session,user.tenant_id,'onboarding',user.id)
  if onboarding.get('must_change') and request.url.path not in ('/api/v3/state','/api/v3/password','/api/v3/logout'):
   raise HTTPException(403,'Change your temporary password before using the app.')
 return user
def role(u,*roles):
 if u.role not in roles:raise HTTPException(403,'Insufficient permission')
def tenant_get(session,model,identifier,tenant):
 obj=session.get(model,identifier)
 if not obj or obj.tenant_id!=tenant:raise HTTPException(404,'Not found')
 return obj
def money(v):return str(v)
def invoice_out(i):return dict(id=i.id,resident_id=i.resident_id,period=i.period,amount=money(i.amount),paid=money(i.paid),due_date=i.due_date,outstanding=money(i.amount-i.paid))
@app.get('/api/health')
def health():return {'status':'ok','version':'0.1.0'}
@app.post('/api/login')
def login(data:Credentials,session:Session=Depends(db)):
 u=session.scalar(select(User).where(User.email==data.email.strip().lower()))
 if not u and 'lookup_phone' in globals():u=lookup_phone(session,data.email)
 if not u or not passwords.verify(data.password,u.password_hash):raise HTTPException(401,'Invalid credentials')
 if 'meta' in globals():
  onboard=meta(session,u.tenant_id,'onboarding',u.id)
  if onboard.get('must_change') and onboard.get('expires',0)<datetime.now(timezone.utc).timestamp():raise HTTPException(403,'Temporary password expired. Request new access from your PG owner.')
 token=jwt.encode({'sub':str(u.id),'tenant':u.tenant_id,'iat':datetime.now(timezone.utc).timestamp(),'jti':os.urandom(16).hex(),'exp':datetime.now(timezone.utc)+timedelta(hours=8)},SECRET,algorithm='HS256')
 return {'token':token,'user':{'id':u.id,'name':u.name,'role':u.role,'room':u.room},'tenant_id':u.tenant_id}
@app.get('/api/me')
def me(u:User=Depends(current),session:Session=Depends(db)):
 t=session.get(Tenant,u.tenant_id)
 return {'id':u.id,'name':u.name,'role':u.role,'room':u.room,'tenant':{'id':t.id,'name':t.name,'primary_color':t.primary_color}}
@app.get('/api/residents')
def residents(u:User=Depends(current),session:Session=Depends(db)):
 role(u,'owner','manager')
 return [{'id':x.id,'name':x.name,'room':x.room,'email':x.email,'role':x.role} for x in session.scalars(select(User).where(User.tenant_id==u.tenant_id,User.role=='resident')).all()]
@app.get('/api/notices')
def notices(u:User=Depends(current),session:Session=Depends(db)):
 return [{'id':n.id,'title':n.title,'body':n.body,'category':n.category,'status':n.status,'created_at':n.created_at.isoformat()} for n in session.scalars(select(Notice).where(Notice.tenant_id==u.tenant_id).order_by(Notice.id.desc())).all()]
@app.post('/api/notices',status_code=201)
def notice_create(data:NewNotice,u:User=Depends(current),session:Session=Depends(db)):
 role(u,'owner','manager');n=Notice(tenant_id=u.tenant_id,**data.model_dump());session.add(n);session.commit();return {'id':n.id}
@app.get('/api/tickets')
def tickets(u:User=Depends(current),session:Session=Depends(db)):
 query=select(Ticket).where(Ticket.tenant_id==u.tenant_id)
 if u.role=='resident':query=query.where(Ticket.resident_id==u.id)
 if u.role=='staff':query=query.where(Ticket.assigned_to==u.id)
 return [{'id':t.id,'resident_id':t.resident_id,'category':t.category,'description':t.description,'status':t.status,'assigned_to':t.assigned_to} for t in session.scalars(query.order_by(Ticket.id.desc())).all()]
@app.post('/api/tickets',status_code=201)
def ticket_create(data:NewTicket,u:User=Depends(current),session:Session=Depends(db)):
 role(u,'resident');t=Ticket(tenant_id=u.tenant_id,resident_id=u.id,**data.model_dump());session.add(t);session.commit();return {'id':t.id}
@app.patch('/api/tickets/{ticket_id}')
def ticket_update(ticket_id:int,data:TicketUpdate,u:User=Depends(current),session:Session=Depends(db)):
 role(u,'owner','manager','staff');t=tenant_get(session,Ticket,ticket_id,u.tenant_id)
 if u.role=='staff' and t.assigned_to!=u.id:raise HTTPException(403,'Not assigned')
 if data.status not in ('submitted','assigned','in_progress','resolved','reopened'):raise HTTPException(400,'Invalid status')
 if data.assigned_to is not None:
  role(u,'owner','manager');assigned=tenant_get(session,User,data.assigned_to,u.tenant_id)
  if assigned.role!='staff':raise HTTPException(400,'Must assign staff')
  t.assigned_to=assigned.id
 t.status=data.status;session.commit();return {'ok':True}
@app.get('/api/invoices')
def invoices(u:User=Depends(current),session:Session=Depends(db)):
 query=select(Invoice).where(Invoice.tenant_id==u.tenant_id)
 if u.role=='resident':query=query.where(Invoice.resident_id==u.id)
 elif u.role=='staff':raise HTTPException(403,'Not permitted')
 return [invoice_out(i) for i in session.scalars(query.order_by(Invoice.id.desc())).all()]
@app.post('/api/invoices',status_code=201)
def create_invoice(data:InvoiceCreate,u:User=Depends(current),session:Session=Depends(db)):
 role(u,'owner','manager');r=tenant_get(session,User,data.resident_id,u.tenant_id)
 if r.role!='resident':raise HTTPException(400,'Must choose resident')
 i=Invoice(tenant_id=u.tenant_id,**data.model_dump());session.add(i)
 try:session.commit()
 except Exception:session.rollback();raise HTTPException(409,'Invoice already exists or invalid')
 return invoice_out(i)
@app.get('/api/payment-methods')
def payment_methods(u:User=Depends(current),session:Session=Depends(db)):
 t=session.get(Tenant,u.tenant_id)
 return {'upi_id':t.upi_id,'qr_image_url':t.qr_image_url,'bank_holder':t.bank_holder,'bank_name':t.bank_name,'bank_account_masked':('****'+t.bank_account[-4:]) if t.bank_account else '', 'ifsc':t.ifsc}
@app.put('/api/payment-methods')
def update_payment_methods(data:BankUpdate,u:User=Depends(current),session:Session=Depends(db)):
 role(u,'owner');t=session.get(Tenant,u.tenant_id)
 for k,v in data.model_dump().items():setattr(t,k,v)
 session.commit();return {'ok':True,'warning':'In production require step-up authentication and audit log'}
@app.post('/api/payments',status_code=201)
def submit_payment(data:PaymentSubmission,u:User=Depends(current),session:Session=Depends(db)):
 role(u,'resident');i=tenant_get(session,Invoice,data.invoice_id,u.tenant_id)
 if i.resident_id!=u.id:raise HTTPException(403,'Not your invoice')
 if data.amount>i.amount-i.paid:raise HTTPException(400,'Amount exceeds outstanding balance')
 duplicate=session.scalar(select(Payment).where(Payment.tenant_id==u.tenant_id,Payment.reference==data.reference,Payment.status!='rejected'))
 if duplicate:raise HTTPException(409,'Reference already submitted')
 p=Payment(tenant_id=u.tenant_id,invoice_id=i.id,resident_id=u.id,amount=data.amount,reference=data.reference);session.add(p);session.commit();return {'id':p.id,'status':'pending'}
@app.get('/api/payments')
def payments(u:User=Depends(current),session:Session=Depends(db)):
 role(u,'owner','manager','resident');query=select(Payment).where(Payment.tenant_id==u.tenant_id)
 if u.role=='resident':query=query.where(Payment.resident_id==u.id)
 return [{'id':p.id,'invoice_id':p.invoice_id,'resident_id':p.resident_id,'amount':money(p.amount),'reference':p.reference,'status':p.status} for p in session.scalars(query.order_by(Payment.id.desc())).all()]
@app.post('/api/payments/{payment_id}/verify')
def verify(payment_id:int,data:VerifyPayment,u:User=Depends(current),session:Session=Depends(db)):
 role(u,'owner');p=tenant_get(session,Payment,payment_id,u.tenant_id)
 if p.status!='pending':raise HTTPException(409,'Payment already reviewed')
 if data.decision not in ('approved','rejected'):raise HTTPException(400,'Choose approved or rejected')
 i=tenant_get(session,Invoice,p.invoice_id,u.tenant_id)
 if data.decision=='approved':
  if i.paid+p.amount>i.amount:raise HTTPException(409,'Overpayment')
  i.paid+=p.amount
 p.status=data.decision;session.commit();return {'status':p.status,'invoice':invoice_out(i)}
@app.get('/api/summary')
def summary(u:User=Depends(current),session:Session=Depends(db)):
 role(u,'owner','manager');res=session.scalars(select(User).where(User.tenant_id==u.tenant_id,User.role=='resident')).all();inv=session.scalars(select(Invoice).where(Invoice.tenant_id==u.tenant_id)).all();issues=session.scalars(select(Ticket).where(Ticket.tenant_id==u.tenant_id,Ticket.status!='resolved')).all()
 return {'residents':len(res),'billed':money(sum((i.amount for i in inv),Decimal(0))),'collected':money(sum((i.paid for i in inv),Decimal(0))),'outstanding':money(sum((i.amount-i.paid for i in inv),Decimal(0))),'open_tickets':len(issues)}
Base.metadata.create_all(engine)
if os.getenv('DEMO_SEED','false').lower()=='true':
 with SessionLocal() as s:
  if not s.scalar(select(Tenant).limit(1)):
   t=Tenant(name='Sunrise Residency',upi_id='owner@upi',bank_holder='Demo Owner',primary_color='#FFDD00');s.add(t);s.flush()
   for name,email,role_name,room in [('Demo Owner','owner@demo.pg','owner',''),('Rahul Kumar','resident@demo.pg','resident','204'),('Arjun Technician','staff@demo.pg','staff','')]:
    u=User(tenant_id=t.id,name=name,email=email,role=role_name,room=room,password_hash=passwords.hash('Demo123!'));s.add(u);s.flush()
    if role_name=='resident':resident_id=u.id
   s.add(Notice(tenant_id=t.id,title='Water supply interrupted',body='Water unavailable since 7 AM. Estimated restoration 10:30 AM.',category='water'))
   s.add(Invoice(tenant_id=t.id,resident_id=resident_id,period='2026-10',amount=Decimal('8500'),paid=Decimal('0'),due_date='2026-10-31'))
   s.commit()

# V2 additive modules; original MVP endpoints and tables remain available.
from v2_api import router as v2_router
app.include_router(v2_router)
# Create additive V2 tables after importing their models (development SQLite only).
Base.metadata.create_all(engine)

# V3 mobile implementation: additive models and authenticated endpoints.
from v3_api import router as v3_router, security_check, lookup_phone, meta
app.include_router(v3_router)
Base.metadata.create_all(engine)

# COME.in V21 platform administration - separate IntProSec privileged API.
from platform_api import router as platform_router, install_schema as install_platform_schema
install_platform_schema()
app.include_router(platform_router)


# Resident ID proof (manual review; DigiLocker disabled).
from identity_api import router as identity_router
app.include_router(identity_router)
Base.metadata.create_all(engine)


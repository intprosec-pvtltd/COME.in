"""V2 owner, resident, facility, and tenant-isolated community APIs.
Loaded after main.py's original models have been defined. SQLite dev migrations are additive.
"""
from datetime import datetime, timezone
from decimal import Decimal
from typing import Optional
import re
import os
import uuid
from pathlib import Path
from fastapi import UploadFile, File
from fastapi.responses import FileResponse
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import ForeignKey, String, Text, DateTime, Integer, select, func, and_
from sqlalchemy.orm import Mapped, mapped_column, Session
from sqlalchemy.exc import IntegrityError
from main import Base, engine, db, current, role, tenant_get, User, Tenant, Ticket, Invoice, Payment, Notice, passwords, invoice_out

router = APIRouter(prefix='/api')
def now(): return datetime.now(timezone.utc)

class Room(Base):
 __tablename__='pg_rooms'
 id:Mapped[int]=mapped_column(primary_key=True)
 tenant_id:Mapped[int]=mapped_column(ForeignKey('tenants.id'),index=True)
 name:Mapped[str]=mapped_column(String(50))
 beds:Mapped[int]=mapped_column(Integer,default=1)

class Facility(Base):
 __tablename__='pg_facilities'
 id:Mapped[int]=mapped_column(primary_key=True)
 tenant_id:Mapped[int]=mapped_column(ForeignKey('tenants.id'),index=True)
 category:Mapped[str]=mapped_column(String(30))
 title:Mapped[str]=mapped_column(String(160))
 details:Mapped[str]=mapped_column(Text,default='')
 status:Mapped[str]=mapped_column(String(30),default='outage')
 created_at:Mapped[datetime]=mapped_column(DateTime(timezone=True),default=now)

class ChatMessage(Base):
 __tablename__='pg_chat_messages'
 id:Mapped[int]=mapped_column(primary_key=True)
 tenant_id:Mapped[int]=mapped_column(ForeignKey('tenants.id'),index=True)
 author_id:Mapped[int]=mapped_column(ForeignKey('users.id'))
 body:Mapped[str]=mapped_column(Text)
 deleted:Mapped[int]=mapped_column(Integer,default=0)
 created_at:Mapped[datetime]=mapped_column(DateTime(timezone=True),default=now)

class ChatAttachment(Base):
 __tablename__='pg_chat_attachments'
 id:Mapped[int]=mapped_column(primary_key=True)
 tenant_id:Mapped[int]=mapped_column(ForeignKey('tenants.id'),index=True)
 message_id:Mapped[int]=mapped_column(ForeignKey('pg_chat_messages.id'),index=True)
 filename:Mapped[str]=mapped_column(String(200))
 storage_key:Mapped[str]=mapped_column(String(100),unique=True)
 content_type:Mapped[str]=mapped_column(String(100))
 byte_count:Mapped[int]=mapped_column(Integer)

class Meal(Base):
 __tablename__='pg_meals'
 id:Mapped[int]=mapped_column(primary_key=True)
 tenant_id:Mapped[int]=mapped_column(ForeignKey('tenants.id'),index=True)
 day:Mapped[str]=mapped_column(String(12))
 breakfast:Mapped[str]=mapped_column(String(250),default='')
 lunch:Mapped[str]=mapped_column(String(250),default='')
 dinner:Mapped[str]=mapped_column(String(250),default='')

Base.metadata.create_all(engine)

class ResidentCreate(BaseModel):
 name:str=Field(min_length=2,max_length=120)
 email:str=Field(min_length=5,max_length=160)
 password:str=Field(min_length=8,max_length=128)
 room:str=Field(default='',max_length=30)
class ResidentEdit(BaseModel):
 name:str=Field(min_length=2,max_length=120)
 room:str=Field(default='',max_length=30)
class RoomInput(BaseModel):
 name:str=Field(min_length=1,max_length=50)
 beds:int=Field(ge=1,le=100)
class FacilityInput(BaseModel):
 category:str=Field(pattern='^(water|power|wifi|maintenance|other)$')
 title:str=Field(min_length=3,max_length=160)
 details:str=Field(default='',max_length=2500)
 status:str=Field(pattern='^(outage|maintenance|restored|normal)$')
class FacilityStatus(BaseModel):
 status:str=Field(pattern='^(outage|maintenance|restored|normal)$')
class MessageInput(BaseModel):
 body:str=Field(min_length=1,max_length=2000)
class MealInput(BaseModel):
 day:str=Field(pattern='^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)$')
 breakfast:str=Field(default='',max_length=250)
 lunch:str=Field(default='',max_length=250)
 dinner:str=Field(default='',max_length=250)
class ProfileEdit(BaseModel):
 name:str=Field(min_length=2,max_length=120)
class TenantEdit(BaseModel):
 name:str=Field(min_length=2,max_length=120)
 primary_color:str=Field(pattern=r'^#[0-9a-fA-F]{6}$')

def owner(u):role(u,'owner','manager')
def room_out(r):return {'id':r.id,'name':r.name,'beds':r.beds}
def facility_out(f):return {'id':f.id,'category':f.category,'title':f.title,'details':f.details,'status':f.status,'created_at':f.created_at.replace(tzinfo=timezone.utc).isoformat() if f.created_at.tzinfo is None else f.created_at.isoformat()}

@router.get('/owner/rent-status')
def rent_status(period:Optional[str]=None,u:User=Depends(current),s:Session=Depends(db)):
 owner(u)
 if period and not re.fullmatch(r'\d{4}-(0[1-9]|1[0-2])',period):raise HTTPException(422,'Invalid YYYY-MM period')
 residents=s.scalars(select(User).where(User.tenant_id==u.tenant_id,User.role=='resident').order_by(User.name)).all()
 invoices=s.scalars(select(Invoice).where(Invoice.tenant_id==u.tenant_id,*([Invoice.period==period] if period else []))).all()
 by_res={}
 for inv in invoices:by_res.setdefault(inv.resident_id,[]).append(inv)
 rows=[]
 totals={'billed':Decimal(0),'collected':Decimal(0),'outstanding':Decimal(0),'paid_count':0,'pending_count':0,'partial_count':0,'unbilled_count':0}
 for r in residents:
  records=by_res.get(r.id,[])
  billed=sum((x.amount for x in records),Decimal(0)); paid=sum((x.paid for x in records),Decimal(0)); due=billed-paid
  status='unbilled' if not records else ('paid' if due<=0 else ('partial' if paid>0 else 'pending'))
  totals[f'{status}_count']+=1
  totals['billed']+=billed;totals['collected']+=paid;totals['outstanding']+=due
  rows.append({'id':r.id,'name':r.name,'room':r.room,'email':r.email,'billed':str(billed),'paid':str(paid),'outstanding':str(due),'status':status,'invoices':[invoice_out(x) for x in records]})
 return {'period':period,'totals':{k:(str(v) if isinstance(v,Decimal) else v) for k,v in totals.items()},'residents':rows}

@router.post('/residents',status_code=201)
def resident_create(data:ResidentCreate,u:User=Depends(current),s:Session=Depends(db)):
 owner(u);raise HTTPException(403,'Use /api/v3/residents/invite to create resident accounts.')
 mail=data.email.strip().lower()
 if '@' not in mail:raise HTTPException(422,'Invalid email')
 if s.scalar(select(User).where(User.email==mail)):raise HTTPException(409,'Email already registered')
 v=User(tenant_id=u.tenant_id,name=data.name.strip(),email=mail,password_hash=passwords.hash(data.password),role='resident',room=data.room.strip());s.add(v);s.commit()
 return {'id':v.id,'name':v.name,'email':v.email,'room':v.room}
@router.put('/residents/{rid}')
def resident_edit(rid:int,data:ResidentEdit,u:User=Depends(current),s:Session=Depends(db)):
 owner(u);v=tenant_get(s,User,rid,u.tenant_id)
 if v.role!='resident':raise HTTPException(404,'Resident not found')
 v.name=data.name.strip();v.room=data.room.strip();s.commit();return {'ok':True}

@router.get('/rooms')
def rooms(u:User=Depends(current),s:Session=Depends(db)):
 data=s.scalars(select(Room).where(Room.tenant_id==u.tenant_id).order_by(Room.name)).all()
 residents=s.scalars(select(User).where(User.tenant_id==u.tenant_id,User.role=='resident')).all()
 return [dict(**room_out(r),occupied=sum(x.room==r.name for x in residents)) for r in data]
@router.post('/rooms',status_code=201)
def room_create(data:RoomInput,u:User=Depends(current),s:Session=Depends(db)):
 owner(u)
 if s.scalar(select(Room).where(Room.tenant_id==u.tenant_id,Room.name==data.name.strip())):raise HTTPException(409,'Room already exists')
 r=Room(tenant_id=u.tenant_id,name=data.name.strip(),beds=data.beds);s.add(r);s.commit();return room_out(r)
@router.put('/rooms/{rid}')
def room_edit(rid:int,data:RoomInput,u:User=Depends(current),s:Session=Depends(db)):
 owner(u);r=tenant_get(s,Room,rid,u.tenant_id);r.name=data.name.strip();r.beds=data.beds;s.commit();return room_out(r)

@router.get('/facilities')
def facilities(u:User=Depends(current),s:Session=Depends(db)):
 return [facility_out(x) for x in s.scalars(select(Facility).where(Facility.tenant_id==u.tenant_id).order_by(Facility.id.desc()).limit(100)).all()]
@router.post('/facilities',status_code=201)
def facility_create(data:FacilityInput,u:User=Depends(current),s:Session=Depends(db)):
 owner(u);f=Facility(tenant_id=u.tenant_id,**data.model_dump());s.add(f);s.commit();return facility_out(f)
@router.patch('/facilities/{fid}')
def facility_change(fid:int,data:FacilityStatus,u:User=Depends(current),s:Session=Depends(db)):
 owner(u);f=tenant_get(s,Facility,fid,u.tenant_id);f.status=data.status;s.commit();return facility_out(f)

@router.get('/community/messages')
def messages(after_id:int=Query(default=0,ge=0),u:User=Depends(current),s:Session=Depends(db)):
 role(u,'owner','manager','resident')
 query=select(ChatMessage).where(ChatMessage.tenant_id==u.tenant_id,ChatMessage.id>after_id).order_by(ChatMessage.id.desc()).limit(200)
 rows=list(reversed(s.scalars(query).all())); authors={x.id:x.name for x in s.scalars(select(User).where(User.tenant_id==u.tenant_id)).all()}
 return [{'id':m.id,'author_id':m.author_id,'author':authors.get(m.author_id,'Former member'),'body':'[Removed by owner]' if m.deleted else m.body,'deleted':bool(m.deleted),'created_at':m.created_at.replace(tzinfo=timezone.utc).isoformat() if m.created_at.tzinfo is None else m.created_at.isoformat(), 'attachments':[{'id':a.id,'filename':a.filename,'content_type':a.content_type,'size':a.byte_count,'url':f'/api/community/attachments/{a.id}'} for a in s.scalars(select(ChatAttachment).where(ChatAttachment.message_id==m.id,ChatAttachment.tenant_id==u.tenant_id)).all()] if not m.deleted else []} for m in rows]
@router.post('/community/messages',status_code=201)
def send_message(data:MessageInput,u:User=Depends(current),s:Session=Depends(db)):
 role(u,'owner','manager','resident');text=data.body.strip()
 if not text:raise HTTPException(422,'Message is empty')
 msg=ChatMessage(tenant_id=u.tenant_id,author_id=u.id,body=text);s.add(msg);s.commit();return {'id':msg.id}
# Local private attachments are suitable for development only. Production should use
# authenticated object storage, malware scanning, encryption, retention and quotas.
CHAT_STORAGE = Path(os.getenv('COMEIN_CHAT_STORAGE', str(Path(__file__).resolve().parent / 'chat_uploads')))
CHAT_ALLOWED = {'image/jpeg','image/png','image/webp','application/pdf','text/plain'}
CHAT_LIMIT = 10 * 1024 * 1024

@router.post('/community/attachments',status_code=201)
async def upload_community_attachment(file:UploadFile=File(...),u:User=Depends(current),s:Session=Depends(db)):
 role(u,'owner','manager','resident')
 mime=(file.content_type or '').lower()
 if mime not in CHAT_ALLOWED:raise HTTPException(415,'Unsupported file type (JPEG, PNG, WebP, PDF, TXT only)')
 filename=Path(file.filename or 'attachment').name[:200]
 chunks=[];size=0
 while True:
  chunk=await file.read(1024*1024)
  if not chunk:break
  size+=len(chunk)
  if size>CHAT_LIMIT:raise HTTPException(413,'File exceeds 10 MB limit')
  chunks.append(chunk)
 if size==0:raise HTTPException(422,'Cannot upload an empty file')
 # Check bytes, not just client provided MIME type.
 data=b''.join(chunks)
 if mime=='image/jpeg' and not data.startswith(b'\xff\xd8\xff'):raise HTTPException(415,'Invalid JPEG')
 if mime=='image/png' and not data.startswith(b'\x89PNG\r\n\x1a\n'):raise HTTPException(415,'Invalid PNG')
 if mime=='image/webp' and not (data[:4]==b'RIFF' and data[8:12]==b'WEBP'):raise HTTPException(415,'Invalid WebP')
 if mime=='application/pdf' and not data.startswith(b'%PDF-'):raise HTTPException(415,'Invalid PDF')
 key=uuid.uuid4().hex
 folder=CHAT_STORAGE / str(u.tenant_id)
 folder.mkdir(parents=True,exist_ok=True)
 path=folder/key
 path.write_bytes(data)
 try:
  msg=ChatMessage(tenant_id=u.tenant_id,author_id=u.id,body=f'Attachment: {filename}')
  s.add(msg);s.flush()
  attachment=ChatAttachment(tenant_id=u.tenant_id,message_id=msg.id,filename=filename,storage_key=key,content_type=mime,byte_count=size)
  s.add(attachment);s.commit();s.refresh(attachment)
 except Exception:
  s.rollback();path.unlink(missing_ok=True);raise
 return {'id':attachment.id,'message_id':msg.id,'filename':filename,'content_type':mime,'size':size}

@router.get('/community/attachments/{attachment_id}')
def get_community_attachment(attachment_id:int,u:User=Depends(current),s:Session=Depends(db)):
 role(u,'owner','manager','resident')
 a=tenant_get(s,ChatAttachment,attachment_id,u.tenant_id)
 msg=tenant_get(s,ChatMessage,a.message_id,u.tenant_id)
 if msg.deleted:raise HTTPException(404,'Attachment unavailable')
 path=CHAT_STORAGE / str(u.tenant_id) / a.storage_key
 if not path.is_file():raise HTTPException(404,'Attachment unavailable')
 return FileResponse(path,media_type=a.content_type,filename=a.filename,content_disposition_type='attachment')

@router.delete('/community/messages/{mid}')
def remove_message(mid:int,u:User=Depends(current),s:Session=Depends(db)):
 role(u,'owner','manager');m=tenant_get(s,ChatMessage,mid,u.tenant_id);m.deleted=1;m.body='';s.commit();return {'ok':True}

@router.get('/meals')
def meals(u:User=Depends(current),s:Session=Depends(db)):
 return [{'id':m.id,'day':m.day,'breakfast':m.breakfast,'lunch':m.lunch,'dinner':m.dinner} for m in s.scalars(select(Meal).where(Meal.tenant_id==u.tenant_id)).all()]
@router.put('/meals')
def meal_save(data:MealInput,u:User=Depends(current),s:Session=Depends(db)):
 owner(u);m=s.scalar(select(Meal).where(Meal.tenant_id==u.tenant_id,Meal.day==data.day))
 if not m:m=Meal(tenant_id=u.tenant_id,day=data.day);s.add(m)
 for k in ('breakfast','lunch','dinner'):setattr(m,k,getattr(data,k))
 s.commit();return {'ok':True}

@router.patch('/profile')
def update_profile(data:ProfileEdit,u:User=Depends(current),s:Session=Depends(db)):
 u.name=data.name.strip();s.commit();return {'ok':True,'name':u.name}
@router.patch('/tenant')
def update_tenant(data:TenantEdit,u:User=Depends(current),s:Session=Depends(db)):
 role(u,'owner');t=s.get(Tenant,u.tenant_id);t.name=data.name.strip();t.primary_color=data.primary_color;s.commit();return {'ok':True}

@router.get('/receipts/{payment_id}')
def receipt(payment_id:int,u:User=Depends(current),s:Session=Depends(db)):
 role(u,'owner','manager','resident')
 p=tenant_get(s,Payment,payment_id,u.tenant_id)
 if p.status!='approved':raise HTTPException(404,'Receipt is not available until owner approval')
 if u.role=='resident' and p.resident_id!=u.id:raise HTTPException(403,'Not your receipt')
 t=s.get(Tenant,u.tenant_id);r=s.get(User,p.resident_id);inv=s.get(Invoice,p.invoice_id)
 return {'receipt_number':f'PG-{u.tenant_id}-{p.id:06d}','pg_name':t.name,'resident':r.name,'period':inv.period,'amount':str(p.amount),'reference':p.reference,'payment_id':p.id,'status':p.status,'recorded_at':p.created_at.isoformat()}


# Additive COME.in owner expense and financial reporting module.
from decimal import Decimal
from sqlalchemy import Numeric, func, select
from pydantic import Field

class Expense(Base):
    __tablename__ = 'comein_expenses'
    id: Mapped[int] = mapped_column(primary_key=True)
    tenant_id: Mapped[int] = mapped_column(ForeignKey('tenants.id'), index=True)
    period: Mapped[str] = mapped_column(String(7), index=True)
    category: Mapped[str] = mapped_column(String(40))
    description: Mapped[str] = mapped_column(String(300))
    amount: Mapped[Decimal] = mapped_column(Numeric(12, 2))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)

class ExpenseCreate(BaseModel):
    period: str = Field(pattern=r'^\d{4}-(0[1-9]|1[0-2])$')
    category: str = Field(min_length=2, max_length=40)
    description: str = Field(min_length=2, max_length=300)
    amount: Decimal = Field(gt=0, max_digits=12, decimal_places=2)

@router.post('/reports/expenses', status_code=201)
def create_expense(data: ExpenseCreate, u: User = Depends(current), s: Session = Depends(db)):
    role(u, 'owner', 'manager')
    row = Expense(tenant_id=u.tenant_id, **data.model_dump())
    s.add(row)
    s.commit()
    s.refresh(row)
    return {'id': row.id, 'status': 'recorded'}

@router.get('/reports/analytics')
def analytics(period: str = Query(pattern=r'^\d{4}-(0[1-9]|1[0-2])$'), u: User = Depends(current), s: Session = Depends(db)):
    role(u, 'owner', 'manager')
    invoices = s.scalars(select(Invoice).where(Invoice.tenant_id == u.tenant_id, Invoice.period == period)).all()
    expenses = s.scalars(select(Expense).where(Expense.tenant_id == u.tenant_id, Expense.period == period).order_by(Expense.created_at.desc())).all()
    collected = sum((i.paid for i in invoices), Decimal('0'))
    billed = sum((i.amount for i in invoices), Decimal('0'))
    spent = sum((e.amount for e in expenses), Decimal('0'))
    occupants = s.scalars(select(User).where(User.tenant_id == u.tenant_id, User.role == 'resident')).all()
    rooms = s.scalars(select(Room).where(Room.tenant_id == u.tenant_id)).all()
    beds = sum((r.beds for r in rooms), 0)
    paid = sum(1 for i in invoices if i.paid >= i.amount)
    pending = sum(1 for i in invoices if i.paid == 0)
    partial = sum(1 for i in invoices if 0 < i.paid < i.amount)
    return {
        'period': period, 'billed': str(billed), 'collected': str(collected),
        'outstanding': str(billed-collected), 'expenses': str(spent),
        'net_cash_flow': str(collected-spent),
        'collection_percent': round(float(collected/billed*100), 1) if billed else 0,
        'occupied_beds': len(occupants), 'total_beds': beds,
        'occupancy_percent': round(len(occupants)/beds*100, 1) if beds else 0,
        'paid_invoices': paid, 'pending_invoices': pending, 'partial_invoices': partial,
        'expense_rows': [{'id':e.id,'category':e.category,'description':e.description,'amount':str(e.amount),'created_at':e.created_at.isoformat()} for e in expenses]
    }


@router.get('/notifications/feed')
def notification_feed(u:User=Depends(current),s:Session=Depends(db)):
 """Authenticated, tenant-scoped in-app alert feed (not background push)."""
 role(u,'owner','manager','resident')
 feed=[]
 notices=s.scalars(select(Notice).where(Notice.tenant_id==u.tenant_id).order_by(Notice.id.desc()).limit(25)).all()
 for n in notices:
  feed.append({'id':f'notice-{n.id}','type':'announcement','title':n.title,'body':n.body,
               'created_at':n.created_at.replace(tzinfo=timezone.utc).isoformat() if n.created_at.tzinfo is None else n.created_at.isoformat()})
 fac=s.scalars(select(Facility).where(Facility.tenant_id==u.tenant_id).order_by(Facility.id.desc()).limit(25)).all()
 for f in fac:
  feed.append({'id':f'facility-{f.id}','type':'outage','title':f.title,'body':f'{f.category}: {f.details}',
               'status':f.status,'created_at':f.created_at.replace(tzinfo=timezone.utc).isoformat() if f.created_at.tzinfo is None else f.created_at.isoformat()})
 msgs=s.scalars(select(ChatMessage).where(ChatMessage.tenant_id==u.tenant_id,
                 ChatMessage.author_id!=u.id, ChatMessage.deleted==0).order_by(ChatMessage.id.desc()).limit(25)).all()
 for m in msgs:
  feed.append({'id':f'message-{m.id}','type':'community','title':'New community message',
               'body':m.body[:160],'created_at':m.created_at.replace(tzinfo=timezone.utc).isoformat() if m.created_at.tzinfo is None else m.created_at.isoformat()})
 feed.sort(key=lambda r:r['created_at'],reverse=True)
 return feed[:75]

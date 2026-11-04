"""COME.in platform-admin API extension for the *uploaded* v0.1 backend.

Separate privilege domain from PG-owner JWTs; no demo admin passwords or public
bootstrap route. All writes audited. Subscription invoices are accounting records,
not gateway transactions. See README_PLATFORM_ADMIN.md before production use.
"""
import os
import re
from datetime import datetime, timedelta, timezone
from decimal import Decimal, ROUND_HALF_UP

import jwt
from fastapi import APIRouter, Depends, HTTPException, Header
from pydantic import BaseModel, Field
from sqlalchemy import ForeignKey, String, Integer, Numeric, DateTime, UniqueConstraint, select
from sqlalchemy.orm import Mapped, mapped_column, Session

from main import Base, engine, db, User, Tenant, passwords
from v2_api import Room
# The current COME.in V20 backend stores PGs and room/resident-to-property
# assignments as V3 JSON Documents. Older uploaded MVPs lack v3_api.
try:
    from v3_api import Document as V3Document, meta as v3_meta, put as v3_put
    V3_AVAILABLE = True
except ImportError:
    V3Document = None
    V3_AVAILABLE = False

router = APIRouter(prefix='/api/platform', tags=['Platform Admin'])


def utcnow():
    return datetime.now(timezone.utc)


class AdminUser(Base):
    __tablename__ = 'platform_admin_users'
    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(160), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(120))
    password_hash: Mapped[str] = mapped_column(String(300))
    is_active: Mapped[int] = mapped_column(Integer, default=1)


class PGProperty(Base):
    __tablename__ = 'platform_pg_properties'
    id: Mapped[int] = mapped_column(primary_key=True)
    tenant_id: Mapped[int] = mapped_column(ForeignKey('tenants.id'), index=True)
    name: Mapped[str] = mapped_column(String(150))
    address: Mapped[str] = mapped_column(String(350), default='')
    is_active: Mapped[int] = mapped_column(Integer, default=1)


class RoomAssignment(Base):
    __tablename__ = 'platform_room_assignments'
    room_id: Mapped[int] = mapped_column(ForeignKey('pg_rooms.id'), primary_key=True)
    property_id: Mapped[int] = mapped_column(ForeignKey('platform_pg_properties.id'), index=True)


class ResidentAssignment(Base):
    __tablename__ = 'platform_resident_assignments'
    resident_id: Mapped[int] = mapped_column(ForeignKey('users.id'), primary_key=True)
    property_id: Mapped[int] = mapped_column(ForeignKey('platform_pg_properties.id'), index=True)


class Subscription(Base):
    __tablename__ = 'platform_subscriptions'
    tenant_id: Mapped[int] = mapped_column(ForeignKey('tenants.id'), primary_key=True)
    price_per_resident: Mapped[Decimal] = mapped_column(Numeric(12, 2), default=Decimal('39.00'))
    currency: Mapped[str] = mapped_column(String(3), default='INR')
    status: Mapped[str] = mapped_column(String(20), default='trial')
    trial_until: Mapped[str] = mapped_column(String(10), default='')
    billing_notes: Mapped[str] = mapped_column(String(500), default='')


class SubscriptionInvoice(Base):
    __tablename__ = 'platform_subscription_invoices'
    id: Mapped[int] = mapped_column(primary_key=True)
    tenant_id: Mapped[int] = mapped_column(ForeignKey('tenants.id'), index=True)
    period: Mapped[str] = mapped_column(String(7))
    billable_residents: Mapped[int] = mapped_column(Integer)
    unit_rate: Mapped[Decimal] = mapped_column(Numeric(12, 2))
    subtotal: Mapped[Decimal] = mapped_column(Numeric(12, 2))
    status: Mapped[str] = mapped_column(String(20), default='draft')
    payment_reference: Mapped[str] = mapped_column(String(120), default='')
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    __table_args__ = (UniqueConstraint('tenant_id', 'period', name='uq_platform_subscription_tenant_period'),)


class ResidentBillingOverride(Base):
    __tablename__ = 'platform_billing_exclusions'
    resident_id: Mapped[int] = mapped_column(ForeignKey('users.id'), primary_key=True)
    reason: Mapped[str] = mapped_column(String(250), default='')


class AdminAudit(Base):
    __tablename__ = 'platform_admin_audit'
    id: Mapped[int] = mapped_column(primary_key=True)
    admin_id: Mapped[int] = mapped_column(ForeignKey('platform_admin_users.id'))
    action: Mapped[str] = mapped_column(String(80))
    target: Mapped[str] = mapped_column(String(160))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class LoginIn(BaseModel):
    email: str
    password: str


class OwnerCreate(BaseModel):
    owner_name: str = Field(min_length=2, max_length=120)
    owner_email: str = Field(min_length=5, max_length=160)
    temporary_password: str = Field(min_length=12, max_length=128)
    business_name: str = Field(min_length=2, max_length=120)


class PropertyIn(BaseModel):
    name: str = Field(min_length=2, max_length=150)
    address: str = Field(default='', max_length=350)


class SubscriptionIn(BaseModel):
    price_per_resident: Decimal = Field(ge=0, le=100000, max_digits=12, decimal_places=2)
    status: str = Field(pattern=r'^(trial|active|past_due|paused|cancelled)$')
    trial_until: str = Field(default='', max_length=10)
    billing_notes: str = Field(default='', max_length=500)


class ExclusionIn(BaseModel):
    excluded: bool
    reason: str = Field(default='', max_length=250)


class InvoicePaidIn(BaseModel):
    payment_reference: str = Field(min_length=4, max_length=120)


class InvoicePeriodIn(BaseModel):
    period: str = Field(pattern=r'^\d{4}-(0[1-9]|1[0-2])$')


def _admin_secret():
    secret = os.getenv('PLATFORM_ADMIN_JWT_SECRET', '')
    if len(secret) < 32:
        raise HTTPException(503, 'Configure PLATFORM_ADMIN_JWT_SECRET (32+ characters)')
    return secret


def _requires_admin(authorization: str | None = Header(default=None), session: Session = Depends(db)):
    if not authorization or not authorization.startswith('Bearer '):
        raise HTTPException(401, 'Platform administrator sign-in required')
    try:
        payload = jwt.decode(authorization[7:], _admin_secret(), algorithms=['HS256'], audience='comein-platform-admin')
        if payload.get('scope') != 'platform_admin':
            raise ValueError('Wrong token scope')
        admin = session.get(AdminUser, int(payload['sub']))
    except (jwt.PyJWTError, ValueError, KeyError, TypeError):
        raise HTTPException(401, 'Invalid or expired admin session')
    if not admin or not admin.is_active:
        raise HTTPException(401, 'Admin account is inactive')
    return admin


def _audit(s, admin, action, target):
    s.add(AdminAudit(admin_id=admin.id, action=action, target=target))


def _tenant(s, tenant_id):
    t = s.get(Tenant, tenant_id)
    if not t:
        raise HTTPException(404, 'PG owner not found')
    return t


def _property(s, tenant_id, prop_id):
    if V3_AVAILABLE:
        _tenant(s, tenant_id)
        if prop_id == 0:
            return {'id': 0, 'name': s.get(Tenant, tenant_id).name}
        doc = s.scalar(select(V3Document).where(
            V3Document.tenant_id == tenant_id,
            V3Document.kind == 'property',
            V3Document.key == str(prop_id),
        ))
        if not doc or doc.payload.get('archived'):
            raise HTTPException(404, 'Property not found for owner')
        return doc.payload
    p = s.get(PGProperty, prop_id)
    if not p or p.tenant_id != tenant_id:
        raise HTTPException(404, 'Property not found for owner')
    return p


def _subscription(s, tenant_id):
    row = s.get(Subscription, tenant_id)
    if not row:
        row = Subscription(tenant_id=tenant_id, price_per_resident=Decimal('39.00'))
        s.add(row)
        s.flush()
    return row


def _minor(v):
    return str(Decimal(v).quantize(Decimal('.01'), rounding=ROUND_HALF_UP))


def _owner_counts(s, t):
    residents = s.scalars(select(User).where(User.tenant_id == t.id, User.role == 'resident')).all()
    rooms = s.scalars(select(Room).where(Room.tenant_id == t.id)).all()
    exclusions = {x.resident_id for x in s.scalars(select(ResidentBillingOverride).where(ResidentBillingOverride.resident_id.in_([r.id for r in residents]))).all()} if residents else set()
    if V3_AVAILABLE:
        primary_meta = v3_meta(s, t.id, 'primary_property', 0)
        properties = [{'id': 0, 'name': primary_meta.get('name', t.name), 'address': primary_meta.get('address',''), 'active':True}]
        for d in s.scalars(select(V3Document).where(V3Document.tenant_id == t.id, V3Document.kind == 'property')).all():
            if d.payload.get('archived', False):
                continue
            properties.append({'id':int(d.key), 'name':d.payload.get('name','Unnamed PG'), 'address':d.payload.get('address',''), 'active':True})
        room_assignments = {r.id:int(v3_meta(s,t.id,'room_meta',r.id).get('property_id',0) or 0) for r in rooms}
        resident_assignments = {r.id:int(v3_meta(s,t.id,'resident_meta',r.id).get('property_id',0) or 0) for r in residents}
    else:
        properties = [{'id':p.id,'name':p.name,'address':p.address,'active':bool(p.is_active)} for p in s.scalars(select(PGProperty).where(PGProperty.tenant_id == t.id).order_by(PGProperty.id)).all() if p.is_active]
        room_assignments = {x.room_id:x.property_id for x in s.scalars(select(RoomAssignment).where(RoomAssignment.room_id.in_([r.id for r in rooms]))).all()} if rooms else {}
        resident_assignments = {x.resident_id:x.property_id for x in s.scalars(select(ResidentAssignment).where(ResidentAssignment.resident_id.in_([r.id for r in residents]))).all()} if residents else {}
    result = []
    for p in properties:
        assigned_rooms = [r for r in rooms if room_assignments.get(r.id) == p['id']]
        assigned_residents = [r for r in residents if resident_assignments.get(r.id) == p['id']]
        result.append({**p, 'rooms':len(assigned_rooms), 'beds':sum(r.beds for r in assigned_rooms), 'residents':len(assigned_residents), 'billable_residents':sum(r.id not in exclusions for r in assigned_residents)})
    ids = {p['id'] for p in properties}
    unassigned_rooms = len([r for r in rooms if room_assignments.get(r.id) not in ids])
    unassigned_residents = len([r for r in residents if resident_assignments.get(r.id) not in ids])
    total_beds = sum(r.beds for r in rooms)
    return {'properties':result, 'pg_count':len(properties), 'total_rooms':len(rooms), 'total_beds':total_beds, 'total_residents':len(residents), 'billable_residents':len(residents)-len(exclusions), 'unassigned_rooms':unassigned_rooms, 'unassigned_residents':unassigned_residents, 'occupancy_percent':round(len(residents)/total_beds*100,1) if total_beds else None, 'rooms': [{'id':r.id,'name':r.name,'beds':r.beds,'property_id':room_assignments.get(r.id)} for r in rooms], 'residents':[{'id':r.id,'name':r.name,'email':r.email,'room':r.room,'property_id':resident_assignments.get(r.id),'billable':r.id not in exclusions} for r in residents]}


def _owner_out(s, t, detail=False):
    owners=s.scalars(select(User).where(User.tenant_id==t.id, User.role=='owner')).all()
    sub=_subscription(s,t.id)
    c=_owner_counts(s,t)
    billed=Decimal(c['billable_residents'])*sub.price_per_resident
    out={'id':t.id,'business_name':t.name,'owners':[{'id':u.id,'name':u.name,'email':u.email} for u in owners], 'pg_count':c['pg_count'], 'total_beds':c['total_beds'], 'total_residents':c['total_residents'], 'billable_residents':c['billable_residents'], 'occupancy_percent':c['occupancy_percent'], 'unassigned_rooms':c['unassigned_rooms'],'unassigned_residents':c['unassigned_residents'], 'subscription':{'status':sub.status,'price_per_resident':_minor(sub.price_per_resident),'trial_until':sub.trial_until,'billing_notes':sub.billing_notes,'estimated_monthly':_minor(billed),'currency':'INR'}}
    if detail:
        out.update({'properties':c['properties'],'rooms':c['rooms'],'residents':c['residents']})
    return out


@router.post('/auth/login')
def platform_login(data:LoginIn, s:Session=Depends(db)):
    admin=s.scalar(select(AdminUser).where(AdminUser.email==data.email.strip().lower()))
    # Dummy verification against a non-secret hash would be preferable with throttling.
    # Never return whether an email exists.
    if not admin or not admin.is_active or not passwords.verify(data.password, admin.password_hash):
        raise HTTPException(401, 'Invalid administrator credentials')
    secret = _admin_secret()
    token=jwt.encode({'sub':str(admin.id),'scope':'platform_admin','aud':'comein-platform-admin','exp':utcnow()+timedelta(hours=2)},secret,algorithm='HS256')
    return {'access_token':token,'token_type':'bearer','expires_in':7200,'admin':{'name':admin.name,'email':admin.email}}


@router.get('/auth/me')
def platform_me(admin:AdminUser=Depends(_requires_admin)):
    return {'name':admin.name,'email':admin.email}


@router.get('/overview')
def platform_overview(admin:AdminUser=Depends(_requires_admin),s:Session=Depends(db)):
    tenants=s.scalars(select(Tenant).order_by(Tenant.id)).all()
    items=[_owner_out(s,t) for t in tenants]
    invoices=s.scalars(select(SubscriptionInvoice)).all()
    return {'owners':len(tenants),'pgs':sum(t['pg_count'] for t in items),'beds':sum(t['total_beds'] for t in items),'registered_residents':sum(t['total_residents'] for t in items),'billable_residents':sum(t['billable_residents'] for t in items),'estimated_monthly_revenue':_minor(sum((Decimal(t['subscription']['estimated_monthly']) for t in items),Decimal('0'))),'invoiced_total':_minor(sum((i.subtotal for i in invoices if i.status not in ('void',)),Decimal('0'))),'confirmed_collected':_minor(sum((i.subtotal for i in invoices if i.status=='paid'),Decimal('0'))),'outstanding':_minor(sum((i.subtotal for i in invoices if i.status=='issued'),Decimal('0'))),'owner_rows':items}


@router.get('/owners')
def list_owners(admin:AdminUser=Depends(_requires_admin),s:Session=Depends(db)):
    return [_owner_out(s,t) for t in s.scalars(select(Tenant).order_by(Tenant.id.desc())).all()]


@router.post('/owners', status_code=201)
def create_owner(data:OwnerCreate, admin:AdminUser=Depends(_requires_admin),s:Session=Depends(db)):
    email=data.owner_email.strip().lower()
    if '@' not in email:
        raise HTTPException(422, 'Invalid email')
    if s.scalar(select(User).where(User.email==email)):
        raise HTTPException(409, 'Email already registered')
    t=Tenant(name=data.business_name.strip(),primary_color='#A879DB')
    s.add(t);s.flush()
    new_owner=User(tenant_id=t.id,name=data.owner_name.strip(),email=email,password_hash=passwords.hash(data.temporary_password),role='owner',room='')
    s.add(new_owner);s.flush()
    if V3_AVAILABLE:
        # COME.in V14+ recognizes this flag in its first-login password-change flow.
        v3_put(s,t.id,'onboarding',new_owner.id,{'must_change':True})
    s.add(Subscription(tenant_id=t.id,price_per_resident=Decimal('39.00'),status='trial'))
    _audit(s,admin,'create_owner',f'tenant:{t.id}')
    s.commit()
    return {'id':t.id,'owner_email':email,'message':'Owner created. Share temporary password securely and require change on first login before production.'}


@router.get('/owners/{tenant_id}')
def owner_detail(tenant_id:int,admin:AdminUser=Depends(_requires_admin),s:Session=Depends(db)):
    return _owner_out(s,_tenant(s,tenant_id),detail=True)


@router.post('/owners/{tenant_id}/properties', status_code=201)
def add_property(tenant_id:int,data:PropertyIn,admin:AdminUser=Depends(_requires_admin),s:Session=Depends(db)):
    _tenant(s,tenant_id)
    if V3_AVAILABLE:
        import secrets
        prop_id=secrets.randbelow(2**30-1)+1
        while s.scalar(select(V3Document).where(V3Document.tenant_id==tenant_id,V3Document.kind=='property',V3Document.key==str(prop_id))):
            prop_id=secrets.randbelow(2**30-1)+1
        v3_put(s,tenant_id,'property',prop_id,{'name':data.name.strip(),'city':'','address':data.address.strip(),'upi':'','archived':False})
        result={'id':prop_id,'name':data.name.strip()}
    else:
        prop=PGProperty(tenant_id=tenant_id,name=data.name.strip(),address=data.address.strip())
        s.add(prop);s.flush();result={'id':prop.id,'name':prop.name}
    _audit(s,admin,'add_property',f'tenant:{tenant_id}/property:{result["id"]}');s.commit()
    return result


@router.put('/owners/{tenant_id}/properties/{property_id}/rooms/{room_id}')
def assign_room(tenant_id:int,property_id:int,room_id:int,admin:AdminUser=Depends(_requires_admin),s:Session=Depends(db)):
    _property(s,tenant_id,property_id)
    room=s.get(Room,room_id)
    if not room or room.tenant_id!=tenant_id:raise HTTPException(404,'Room not found for owner')
    if V3_AVAILABLE:
        old = v3_meta(s,tenant_id,'room_meta',room.id)
        # In V3 an occupied room must not be moved across properties directly.
        if int(old.get('property_id',0) or 0)!=property_id:
            occupied = [u for u in s.scalars(select(User).where(User.tenant_id==tenant_id,User.role=='resident',User.room==room.name)).all() if int(v3_meta(s,tenant_id,'resident_meta',u.id).get('property_id',0) or 0)==int(old.get('property_id',0) or 0)]
            if occupied:raise HTTPException(409,'Move residents from this room in the owner app before changing its property')
        v3_put(s,tenant_id,'room_meta',room.id,{**old,'property_id':property_id})
    else:
        row=s.get(RoomAssignment,room_id)
        if not row:row=RoomAssignment(room_id=room_id,property_id=property_id);s.add(row)
        else:row.property_id=property_id
    _audit(s,admin,'assign_room',f'room:{room_id}/property:{property_id}');s.commit();return {'ok':True}


@router.put('/owners/{tenant_id}/properties/{property_id}/residents/{resident_id}')
def assign_resident(tenant_id:int,property_id:int,resident_id:int,admin:AdminUser=Depends(_requires_admin),s:Session=Depends(db)):
    _property(s,tenant_id,property_id)
    resident=s.get(User,resident_id)
    if not resident or resident.tenant_id!=tenant_id or resident.role!='resident':raise HTTPException(404,'Resident not found for owner')
    if V3_AVAILABLE:
        existing = v3_meta(s,tenant_id,'resident_meta',resident.id)
        if resident.room and int(existing.get('property_id',0) or 0)!=property_id:
            raise HTTPException(409,'Move occupied residents with the owner app transfer workflow, not platform admin')
        v3_put(s,tenant_id,'resident_meta',resident.id,{**existing,'property_id':property_id})
    else:
        row=s.get(ResidentAssignment,resident_id)
        if not row:row=ResidentAssignment(resident_id=resident_id,property_id=property_id);s.add(row)
        else:row.property_id=property_id
    _audit(s,admin,'assign_resident',f'resident:{resident_id}/property:{property_id}');s.commit();return {'ok':True}


@router.put('/owners/{tenant_id}/residents/{resident_id}/billing')
def set_billable(tenant_id:int,resident_id:int,data:ExclusionIn,admin:AdminUser=Depends(_requires_admin),s:Session=Depends(db)):
    resident=s.get(User,resident_id)
    if not resident or resident.tenant_id!=tenant_id or resident.role!='resident':raise HTTPException(404,'Resident not found')
    existing=s.get(ResidentBillingOverride,resident_id)
    if data.excluded:
        if not data.reason.strip():raise HTTPException(422,'Reason required for exclusion')
        if existing:existing.reason=data.reason.strip()
        else:s.add(ResidentBillingOverride(resident_id=resident_id,reason=data.reason.strip()))
    elif existing:s.delete(existing)
    _audit(s,admin,'change_billing_eligibility',f'resident:{resident_id}/excluded:{data.excluded}');s.commit()
    return {'billable':not data.excluded}


@router.put('/owners/{tenant_id}/subscription')
def update_subscription(tenant_id:int,data:SubscriptionIn,admin:AdminUser=Depends(_requires_admin),s:Session=Depends(db)):
    _tenant(s,tenant_id)
    if data.trial_until and not re.fullmatch(r'\d{4}-\d{2}-\d{2}',data.trial_until):raise HTTPException(422,'Trial date must be YYYY-MM-DD')
    row=_subscription(s,tenant_id)
    row.price_per_resident=data.price_per_resident;row.status=data.status;row.trial_until=data.trial_until;row.billing_notes=data.billing_notes
    _audit(s,admin,'update_subscription',f'tenant:{tenant_id}')
    s.commit();return _owner_out(s,_tenant(s,tenant_id))['subscription']


@router.post('/owners/{tenant_id}/invoices', status_code=201)
def create_invoice(tenant_id:int,data:InvoicePeriodIn,admin:AdminUser=Depends(_requires_admin),s:Session=Depends(db)):
    tenant=_tenant(s,tenant_id)
    if s.scalar(select(SubscriptionInvoice).where(SubscriptionInvoice.tenant_id==tenant_id,SubscriptionInvoice.period==data.period)):
        raise HTTPException(409,'Invoice already exists for this owner and month')
    sub=_subscription(s,tenant_id)
    if sub.status in ('trial','paused','cancelled'):
        raise HTTPException(409,'Activate subscription to generate a billable invoice')
    cnt=_owner_counts(s,tenant)['billable_residents']
    subtotal=(sub.price_per_resident*Decimal(cnt)).quantize(Decimal('0.01'),rounding=ROUND_HALF_UP)
    i=SubscriptionInvoice(tenant_id=tenant_id,period=data.period,billable_residents=cnt,unit_rate=sub.price_per_resident,subtotal=subtotal,status='draft')
    s.add(i);s.flush();_audit(s,admin,'create_invoice',f'invoice:{i.id}');s.commit()
    return _invoice_out(i)


def _invoice_out(i):
    return {'id':i.id,'tenant_id':i.tenant_id,'period':i.period,'billable_residents':i.billable_residents,'unit_rate':_minor(i.unit_rate),'subtotal':_minor(i.subtotal),'status':i.status,'payment_reference':i.payment_reference,'created_at':i.created_at.isoformat() if i.created_at else None,'currency':'INR','gst_included':False}


@router.get('/invoices')
def list_invoices(admin:AdminUser=Depends(_requires_admin),s:Session=Depends(db)):
    return [_invoice_out(x) for x in s.scalars(select(SubscriptionInvoice).order_by(SubscriptionInvoice.id.desc()).limit(1000)).all()]


@router.post('/invoices/{invoice_id}/issue')
def issue_invoice(invoice_id:int,admin:AdminUser=Depends(_requires_admin),s:Session=Depends(db)):
    i=s.get(SubscriptionInvoice,invoice_id)
    if not i:raise HTTPException(404,'Invoice not found')
    if i.status!='draft':raise HTTPException(409,'Only draft invoices can be issued')
    i.status='issued';_audit(s,admin,'issue_invoice',f'invoice:{i.id}');s.commit();return _invoice_out(i)


@router.post('/invoices/{invoice_id}/confirm-manual-payment')
def confirm_payment(invoice_id:int,data:InvoicePaidIn,admin:AdminUser=Depends(_requires_admin),s:Session=Depends(db)):
    i=s.get(SubscriptionInvoice,invoice_id)
    if not i:raise HTTPException(404,'Invoice not found')
    if i.status!='issued':raise HTTPException(409,'Only issued invoices may be marked paid')
    if s.scalar(select(SubscriptionInvoice).where(SubscriptionInvoice.payment_reference==data.payment_reference.strip())):
        raise HTTPException(409,'Payment reference already used')
    i.status='paid';i.payment_reference=data.payment_reference.strip()
    _audit(s,admin,'confirm_manual_payment',f'invoice:{i.id}');s.commit();return _invoice_out(i)


@router.get('/audit')
def audit(admin:AdminUser=Depends(_requires_admin),s:Session=Depends(db)):
    return [{'id':a.id,'action':a.action,'target':a.target,'created_at':a.created_at.isoformat()} for a in s.scalars(select(AdminAudit).order_by(AdminAudit.id.desc()).limit(100)).all()]


def install_schema():
    # Creates only new tables. Existing tenant/room/resident schemas are untouched.
    Base.metadata.create_all(engine, tables=[AdminUser.__table__,PGProperty.__table__,RoomAssignment.__table__,ResidentAssignment.__table__,Subscription.__table__,SubscriptionInvoice.__table__,ResidentBillingOverride.__table__,AdminAudit.__table__])

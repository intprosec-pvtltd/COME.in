"""Verified mobile authentication, additive schema, no automatic trust of profile phones."""
import base64, hashlib, hmac, os, re, secrets, time
from urllib.parse import urlencode
from urllib.request import Request as HTTPRequest, urlopen
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field
from sqlalchemy import ForeignKey, String, Float, Integer, select, update, delete
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Mapped, mapped_column, Session
from main import Base, User, Tenant, db, passwords, _platform_user_enabled, login, Credentials
from v3_api import meta, put, commit, safe_email

router = APIRouter(prefix='/api/v3/phone', tags=['Verified mobile authentication'])

class VerifiedPhone(Base):
    __tablename__ = 'staysync_verified_phones'
    user_id: Mapped[int] = mapped_column(ForeignKey('users.id', ondelete='CASCADE'), primary_key=True)
    phone: Mapped[str] = mapped_column(String(16), unique=True, nullable=False)
    verified_at: Mapped[float] = mapped_column(Float)

class PhoneChallenge(Base):
    __tablename__ = 'staysync_phone_challenges'
    key: Mapped[str] = mapped_column(String(64), primary_key=True)
    digest: Mapped[str] = mapped_column(String(64))
    nonce: Mapped[str] = mapped_column(String(32))
    issued: Mapped[float] = mapped_column(Float)
    expires: Mapped[float] = mapped_column(Float)
    attempts: Mapped[int] = mapped_column(Integer)
    consumed: Mapped[int] = mapped_column(Integer)

class PhoneResetGrant(Base):
    __tablename__ = 'staysync_phone_reset_grants'
    key: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey('users.id', ondelete='CASCADE'), index=True)
    issued: Mapped[float] = mapped_column(Float)
    expires: Mapped[float] = mapped_column(Float)
    consumed: Mapped[int] = mapped_column(Integer)

class PhoneLimit(Base):
    __tablename__ = 'staysync_phone_rate_limits'
    key: Mapped[str] = mapped_column(String(64), primary_key=True)
    count: Mapped[int] = mapped_column(Integer)
    until: Mapped[float] = mapped_column(Float)

def normalize_phone(raw):
    value = re.sub(r'[\s()-]', '', str(raw).strip())
    if re.fullmatch(r'[6-9]\d{9}', value): value = '+91' + value
    elif re.fullmatch(r'91[6-9]\d{9}', value): value = '+' + value
    if not re.fullmatch(r'\+[1-9]\d{7,14}', value):
        raise HTTPException(422, 'Enter a valid mobile number with country code.')
    if value.startswith('+91') and not re.fullmatch(r'\+91[6-9]\d{9}', value):
        raise HTTPException(422, 'Enter a valid Indian mobile number.')
    return value

def secret():
    key = os.getenv('PHONE_OTP_SECRET', '')
    if len(key) < 32: raise HTTPException(503, 'Mobile verification is not configured. Contact support.')
    return key.encode()

def digest(value): return hmac.new(secret(), value.encode(), hashlib.sha256).hexdigest()

def sms_config():
    sid = os.getenv('TWILIO_ACCOUNT_SID', '')
    token = os.getenv('TWILIO_AUTH_TOKEN', '')
    sender = os.getenv('TWILIO_FROM_NUMBER', '')
    service = os.getenv('TWILIO_MESSAGING_SERVICE_SID', '')
    if not re.fullmatch(r'AC[0-9a-fA-F]{32}', sid) or not token or not (sender or service):
        raise HTTPException(503, 'SMS verification is not configured. Contact support.')
    return sid, token, sender, service

def send_sms(phone, code):
    sid, token, sender, service = sms_config()
    fields = {'To': phone, 'Body': f'Stay Sync verification code: {code}. Valid for 5 minutes. Do not share this code.'}
    fields['MessagingServiceSid' if service else 'From'] = service or sender
    req = HTTPRequest(f'https://api.twilio.com/2010-04-01/Accounts/{sid}/Messages.json',
                      data=urlencode(fields).encode(), headers={'Authorization': 'Basic '+base64.b64encode(f'{sid}:{token}'.encode()).decode(), 'Content-Type':'application/x-www-form-urlencoded'}, method='POST')
    try:
        with urlopen(req, timeout=15) as response:
            if not 200 <= response.status < 300: raise RuntimeError('SMS rejected')
    except Exception:
        raise HTTPException(503, 'SMS could not be sent. Try again later.') from None

def limit(s, key, maximum, window):
    key = digest('rate:'+key); now = time.time()
    # Conditional database updates are safe across workers; insert races fail closed.
    row = s.get(PhoneLimit, key)
    if row is None:
        s.add(PhoneLimit(key=key, count=1, until=now+window))
        try: s.commit()
        except IntegrityError:
            s.rollback(); raise HTTPException(429, 'Please try again shortly.')
        return
    changed = s.execute(update(PhoneLimit).where(PhoneLimit.key==key, PhoneLimit.until<=now).values(count=1, until=now+window)).rowcount
    if not changed:
        changed = s.execute(update(PhoneLimit).where(PhoneLimit.key==key, PhoneLimit.until>now, PhoneLimit.count<maximum).values(count=PhoneLimit.count+1)).rowcount
    s.commit()
    if not changed: raise HTTPException(429, 'Too many requests. Try again later.')

def throttle(s, request, phone, kind, maximum, window):
    # Do not trust client-supplied forwarding headers. Configure trusted proxy at deployment.
    ip = request.client.host if request.client else 'unknown'
    limit(s, f'{kind}:ip:{ip}', maximum*10, window)
    limit(s, f'{kind}:phone:{phone}', maximum, window)

def binding(s, phone): return s.scalar(select(VerifiedPhone).where(VerifiedPhone.phone==phone))
def active(s, user): return user is not None and _platform_user_enabled(s,user.id)
def challenge_key(phone,purpose,subject=''): return digest(f'challenge:{purpose}:{phone}:{subject}')

def issue(s, request, phone, purpose, subject='', deliver=True):
    secret(); sms_config()
    throttle(s,request,phone,'send',5,3600)
    limit(s,'send:global',int(os.getenv('PHONE_SMS_DAILY_LIMIT','500')),86400)
    key=challenge_key(phone,purpose,subject); now=time.time()
    row=s.get(PhoneChallenge,key)
    code=f'{secrets.randbelow(1000000):06d}'; nonce=secrets.token_hex(16)
    values=dict(digest=digest(f'{key}:{nonce}:{code}'),nonce=nonce,issued=now,expires=now+300,attempts=0,consumed=0)
    if row is None:
        s.add(PhoneChallenge(key=key,**values))
        try: s.commit()
        except IntegrityError:
            s.rollback(); raise HTTPException(429,'Wait 30 seconds before requesting another code.')
    else:
        changed=s.execute(update(PhoneChallenge).where(PhoneChallenge.key==key,PhoneChallenge.issued<=now-30).values(**values)).rowcount
        s.commit()
        if not changed: raise HTTPException(429,'Wait 30 seconds before requesting another code.')
    if deliver:
        try: send_sms(phone,code)
        except HTTPException:
            s.execute(update(PhoneChallenge).where(PhoneChallenge.key==key,PhoneChallenge.nonce==nonce).values(consumed=1));s.commit()
            import logging
            logging.getLogger(__name__).warning('SMS verification delivery failed')
    else:
        # Unknown account: same response and cooldown, never an actionable challenge.
        s.execute(update(PhoneChallenge).where(PhoneChallenge.key==key,PhoneChallenge.nonce==nonce).values(consumed=1));s.commit()
    return {'ok':True,'message':'If eligible, a verification code will be sent.','resend_after':30,'expires_in':300}

def consume(s, phone, purpose, code, subject=''):
    key=challenge_key(phone,purpose,subject); row=s.get(PhoneChallenge,key); now=time.time()
    bad=HTTPException(400,'The verification code is invalid or expired.')
    if not row or row.consumed or row.expires<=now or row.attempts>=5: raise bad
    valid=hmac.compare_digest(row.digest,digest(f'{key}:{row.nonce}:{code}'))
    where=(PhoneChallenge.key==key,PhoneChallenge.nonce==row.nonce,PhoneChallenge.consumed==0,PhoneChallenge.expires>now,PhoneChallenge.attempts<5)
    if not valid:
        s.execute(update(PhoneChallenge).where(*where).values(attempts=PhoneChallenge.attempts+1));s.commit();raise bad
    changed=s.execute(update(PhoneChallenge).where(*where).values(consumed=1)).rowcount
    if not changed: raise bad
    # Success consumption and account mutation commit together.

def bind(s,user,phone):
    s.add(VerifiedPhone(user_id=user.id,phone=phone,verified_at=time.time()))
    prefs=meta(s,user.tenant_id,'profile',user.id);prefs['phone']=phone
    put(s,user.tenant_id,'profile',user.id,prefs)

class PhoneIn(BaseModel):
    phone:str=Field(min_length=7,max_length=32)
class PhoneLogin(PhoneIn):
    password:str=Field(min_length=1,max_length=128)
class CodeIn(PhoneIn):
    code:str=Field(pattern=r'^\d{6}$')
class ResetIn(PhoneIn):
    reset_token:str=Field(min_length=40,max_length=128)
    new_password:str=Field(min_length=8,max_length=128)
class ExistingIn(PhoneLogin):
    email:str=Field(max_length=160)
class EnrollIn(ExistingIn):
    code:str=Field(pattern=r'^\d{6}$')
class RegisterIn(CodeIn):
    name:str=Field(min_length=2,max_length=120)
    email:str=Field(max_length=160)
    password:str=Field(min_length=8,max_length=128)
    property_name:str=Field(min_length=2,max_length=120)
    role:str=Field(default='owner',pattern='^owner$')

def existing(s,data):
    u=s.scalar(select(User).where(User.email==data.email.strip().lower()))
    if not active(s,u) or not passwords.verify(data.password,u.password_hash): raise HTTPException(401,'Invalid credentials')
    if s.get(VerifiedPhone,u.id): raise HTTPException(409,'This account already has a verified mobile number. Contact support to change it.')
    onboarding=meta(s,u.tenant_id,'onboarding',u.id)
    if onboarding.get('must_change') and onboarding.get('expires',0)<time.time():raise HTTPException(403,'Temporary password expired. Contact your PG owner.')
    return u

@router.post('/login')
def phone_login(data:PhoneLogin,request:Request,s:Session=Depends(db)):
    phone=normalize_phone(data.phone);throttle(s,request,phone,'login',10,300)
    b=binding(s,phone);u=s.get(User,b.user_id) if b else None
    if not active(s,u):raise HTTPException(401,'Invalid credentials. Existing users may activate mobile login first.')
    # Call the existing login function with the canonical email; preserves session policy.
    return login(Credentials(email=u.email,password=data.password),s)

@router.post('/enroll/request')
def enroll_request(data:ExistingIn,request:Request,s:Session=Depends(db)):
    phone=normalize_phone(data.phone);throttle(s,request,phone,'enroll',10,300)
    limit(s,'enroll:account:'+data.email.strip().lower(),10,300)
    u=existing(s,data)
    if binding(s,phone):raise HTTPException(409,'Mobile number is already in use.')
    return issue(s,request,phone,'enroll',str(u.id))

@router.post('/enroll/confirm')
def enroll_confirm(data:EnrollIn,request:Request,s:Session=Depends(db)):
    phone=normalize_phone(data.phone);throttle(s,request,phone,'verify',15,300)
    limit(s,'enroll:account:'+data.email.strip().lower(),10,300)
    u=existing(s,data)
    if binding(s,phone):raise HTTPException(409,'Mobile number is already in use.')
    consume(s,phone,'enroll',data.code,str(u.id));bind(s,u,phone);commit(s)
    return {'ok':True}

@router.post('/register/request')
def register_request(data:PhoneIn,request:Request,s:Session=Depends(db)):
    phone=normalize_phone(data.phone)
    return issue(s,request,phone,'register',deliver=binding(s,phone) is None)

@router.post('/register',status_code=201)
def register_phone(data:RegisterIn,request:Request,s:Session=Depends(db)):
    phone=normalize_phone(data.phone);throttle(s,request,phone,'verify',15,300)
    email=safe_email(data.email)
    if binding(s,phone) or s.scalar(select(User).where(User.email==email)):raise HTTPException(409,'Account already exists. Sign in or activate mobile login.')
    if len(data.name.strip())<2 or len(data.property_name.strip())<2:raise HTTPException(422,'Enter name and property name.')
    consume(s,phone,'register',data.code)
    t=Tenant(name=data.property_name.strip(),primary_color='#3B1E3F');s.add(t);s.flush()
    u=User(tenant_id=t.id,name=data.name.strip(),email=email,password_hash=passwords.hash(data.password),role='owner',room='');s.add(u)
    try:s.flush()
    except IntegrityError:s.rollback();raise HTTPException(409,'Account already exists.')
    bind(s,u,phone);commit(s);return {'id':u.id,'message':'Owner account created. Sign in to continue.'}

@router.post('/forgot-password')
def forgot_phone(data:PhoneIn,request:Request,s:Session=Depends(db)):
    phone=normalize_phone(data.phone);b=binding(s,phone);u=s.get(User,b.user_id) if b else None
    # Invited users must use their temporary access, not bypass onboarding.
    eligible=active(s,u) and not meta(s,u.tenant_id,'onboarding',u.id).get('must_change')
    return issue(s,request,phone,'reset',str(u.id) if eligible else '',deliver=bool(eligible))

@router.post('/reset/verify')
def verify_reset(data:CodeIn,request:Request,s:Session=Depends(db)):
    phone=normalize_phone(data.phone);throttle(s,request,phone,'verify',15,300)
    b=binding(s,phone);u=s.get(User,b.user_id) if b else None
    if not active(s,u) or meta(s,u.tenant_id,'onboarding',u.id).get('must_change'):raise HTTPException(400,'The verification code is invalid or expired.')
    consume(s,phone,'reset',data.code,str(u.id))
    now=time.time();token=secrets.token_urlsafe(32)
    s.execute(delete(PhoneResetGrant).where(PhoneResetGrant.user_id==u.id))
    s.add(PhoneResetGrant(key=digest('grant:'+token),user_id=u.id,issued=now,expires=now+300,consumed=0));commit(s)
    return {'reset_token':token,'expires_in':300}

@router.post('/reset-password')
def reset_phone(data:ResetIn,request:Request,s:Session=Depends(db)):
    phone=normalize_phone(data.phone);throttle(s,request,phone,'reset',10,300)
    b=binding(s,phone);u=s.get(User,b.user_id) if b else None
    bad=HTTPException(400,'Password reset authorization is invalid or expired.')
    if not active(s,u) or meta(s,u.tenant_id,'onboarding',u.id).get('must_change'):raise bad
    # Serialize password mutations on PostgreSQL, and claim the grant atomically.
    u=s.scalar(select(User).where(User.id==u.id).with_for_update())
    key=digest('grant:'+data.reset_token);grant=s.get(PhoneResetGrant,key);now=time.time()
    if not grant or grant.user_id!=u.id or grant.consumed or grant.expires<=now or meta(s,u.tenant_id,'security',u.id).get('changed_at',0)>grant.issued:raise bad
    changed=s.execute(update(PhoneResetGrant).where(PhoneResetGrant.key==key,PhoneResetGrant.consumed==0,PhoneResetGrant.expires>now).values(consumed=1)).rowcount
    if not changed:raise bad
    u.password_hash=passwords.hash(data.new_password);put(s,u.tenant_id,'security',u.id,{'changed_at':time.time()});commit(s)
    return {'ok':True}

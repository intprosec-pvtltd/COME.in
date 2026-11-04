"""One-time bootstrap; run on the backend host, never from a public endpoint."""
import os
from getpass import getpass
from sqlalchemy import select
from main import SessionLocal, passwords
from platform_api import AdminUser, install_schema

if __name__ == '__main__':
    secret=os.getenv('PLATFORM_ADMIN_JWT_SECRET','')
    if len(secret)<32:
        raise SystemExit('Set PLATFORM_ADMIN_JWT_SECRET to a cryptographically random 32+ character string first.')
    name=input('Administrator display name: ').strip()
    email=input('Administrator email: ').strip().lower()
    password=getpass('New administrator password (at least 14 characters): ')
    verify=getpass('Repeat password: ')
    if not name or '@' not in email or len(password)<14 or password!=verify:
        raise SystemExit('Invalid name/email or password length/mismatch.')
    install_schema()
    with SessionLocal() as s:
        if s.scalar(select(AdminUser).where(AdminUser.email==email)):
            raise SystemExit('This administrator already exists.')
        s.add(AdminUser(name=name,email=email,password_hash=passwords.hash(password),is_active=1))
        s.commit()
    print('Platform administrator created. Protect this account and enable additional controls before public deployment.')

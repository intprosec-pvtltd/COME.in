"""Count migration readiness without printing phone numbers or changing account records.
Run against a staging clone first. Importing main ensures additive tables exist.
"""
from collections import Counter
from sqlalchemy import select
from fastapi import HTTPException
from main import SessionLocal, User
from v3_api import meta
from phone_auth import VerifiedPhone, normalize_phone

def main():
    with SessionLocal() as session:
        users=session.scalars(select(User)).all()
        verified={r.user_id:r.phone for r in session.scalars(select(VerifiedPhone))}
        phones=Counter();missing=invalid=0
        for user in users:
            raw=meta(session,user.tenant_id,'profile',user.id).get('phone','')
            if not raw:missing+=1;continue
            try:phones[normalize_phone(raw)]+=1
            except HTTPException:invalid+=1
        print('Accounts:',len(users))
        print('Verified login numbers:',len(verified))
        print('Accounts requiring activation:',len(users)-len(verified))
        print('Missing contact phone:',missing)
        print('Invalid contact phone:',invalid)
        print('Duplicate contact number groups:',sum(n>1 for n in phones.values()))
        print('Accounts in duplicate groups:',sum(n for n in phones.values() if n>1))
        print('No account or password changes made. Contact phones are not automatically trusted.')
if __name__=='__main__':main()

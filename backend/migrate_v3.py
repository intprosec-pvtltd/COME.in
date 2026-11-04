"""Idempotent additive migration. Back up the database first; never drops old tables."""
from sqlalchemy import select
from main import Base, engine, SessionLocal, Tenant, User
from v2_api import Room
from v3_api import Document, PrivateFile, Alert, meta, put, doc

def migrate():
 Base.metadata.create_all(engine)
 with SessionLocal() as s:
  for tenant in s.scalars(select(Tenant)):
   people=s.scalars(select(User).where(User.tenant_id==tenant.id,User.role=='resident')).all()
   legacy_people=[p for p in people if not doc(s,tenant.id,'resident_meta',p.id)]
   for room_name in {p.room for p in legacy_people if p.room}:
    occupants=[p for p in people if p.room==room_name and meta(s,tenant.id,'resident_meta',p.id).get('property_id',0)==0]
    rooms=s.scalars(select(Room).where(Room.tenant_id==tenant.id,Room.name==room_name)).all()
    room=next((r for r in rooms if meta(s,tenant.id,'room_meta',r.id).get('property_id',0)==0),None)
    if room is None:
     room=Room(tenant_id=tenant.id,name=room_name,beds=max(1,len(occupants)));s.add(room);s.flush()
    if not meta(s,tenant.id,'room_meta',room.id):put(s,tenant.id,'room_meta',room.id,{'floor':'Ground','property_id':0})
    used={meta(s,tenant.id,'resident_meta',p.id).get('bed') for p in occupants}
    for person in occupants:
     md=meta(s,tenant.id,'resident_meta',person.id)
     if not md.get('bed'):
      bed=next((i for i in range(1,room.beds+1) if i not in used),0)
      md.update(property_id=md.get('property_id',0),bed=bed);put(s,tenant.id,'resident_meta',person.id,md);used.add(bed)
  s.commit()
 print('COME.in V3 additive tables and legacy room mappings are ready. Existing data preserved.')
if __name__=='__main__':migrate()

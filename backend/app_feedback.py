"""Private product feedback from signed-in owners and residents."""
from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field, StrictInt
from sqlalchemy import select
from sqlalchemy.orm import Session

from main import User, current, db, role
from platform_api import AdminUser, _requires_admin
from v3_api import Document, put, now

router = APIRouter(prefix='/api/v3', tags=['App feedback'])


class FeedbackInput(BaseModel):
    rating: StrictInt = Field(ge=1, le=5)
    comment: str = Field(default='', max_length=1000)


@router.put('/app-feedback')
def save_feedback(data: FeedbackInput, user: User = Depends(current), session: Session = Depends(db)):
    role(user, 'owner', 'resident')
    session.get(User, user.id, with_for_update=True)
    put(session, user.tenant_id, 'app_feedback', user.id, {
        'rating': data.rating, 'comment': data.comment.strip(),
        'role': user.role, 'updated_at': now().isoformat(),
    })
    session.commit()
    return {'saved': True}

@router.get('/platform/app-feedback')
def list_feedback(offset: int = Query(0, ge=0), admin: AdminUser = Depends(_requires_admin),
                  session: Session = Depends(db)):
    page_size = 50
    rows = session.scalars(select(Document).where(Document.kind == 'app_feedback')
                           .order_by(Document.id.desc()).offset(offset).limit(page_size + 1)).all()
    return {
        'items': [dict(row.payload, id=row.id) for row in rows[:page_size]],
        'previous_offset': max(0, offset - page_size) if offset else None,
        'next_offset': offset + page_size if len(rows) > page_size else None,
    }

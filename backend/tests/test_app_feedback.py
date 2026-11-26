from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from main import app  # Load the application before its routers.
from app_feedback import FeedbackInput, save_feedback


def test_feedback_rating_is_integer_and_in_range():
    for invalid in (0, 6, True, '5'):
        with pytest.raises(ValidationError):
            FeedbackInput(rating=invalid)


def test_feedback_is_scoped_to_the_authenticated_user(monkeypatch):
    import app_feedback

    saved = []
    monkeypatch.setattr(app_feedback, 'put', lambda *values: saved.append(values))
    session = SimpleNamespace(get=lambda *args, **kwargs: None, commit=lambda: None)
    owner = SimpleNamespace(id=7, tenant_id=5, role='owner')
    assert save_feedback(FeedbackInput(rating=4, comment=' Good '), owner, session) == {'saved': True}
    assert saved[0][1:4] == (5, 'app_feedback', 7)
    assert saved[0][4]['comment'] == 'Good'
    with pytest.raises(HTTPException) as denied:
        save_feedback(FeedbackInput(rating=5), SimpleNamespace(role='staff'), session)
    assert denied.value.status_code == 403
    assert len(saved) == 1

"""PG-boundary and guarded account deletion tests. No production data used."""
from types import SimpleNamespace
import pytest
from fastapi import HTTPException

from main import User  # initialize the application before importing its route module
from account_deletion import owner_preview, erase
from push_notifications import eligible

class OneRowSession:
    def __init__(self, user): self.user = user
    def get(self, model, ident): return self.user


def test_cross_pg_owner_cannot_preview_another_pg_resident():
    owner = User(id=1, tenant_id=10, role='owner', name='Owner', email='owner@example.test', room='', password_hash='x')
    other = User(id=2, tenant_id=20, role='resident', name='Resident', email='resident@example.test', room='', password_hash='x')
    with pytest.raises(HTTPException) as exc:
        owner_preview(2, u=owner, s=OneRowSession(other))
    assert exc.value.status_code == 404


def test_resident_cannot_preview_other_accounts():
    resident = User(id=1, tenant_id=10, role='resident', name='Resident', email='res@example.test', room='', password_hash='x')
    with pytest.raises(HTTPException) as exc:
        owner_preview(2, u=resident, s=OneRowSession(None))
    assert exc.value.status_code == 403


def test_deletion_requires_matching_email_before_any_writes():
    user = User(id=22, tenant_id=1, role='resident', email='tenant@example.test', name='Test', room='', password_hash='test')
    with pytest.raises(HTTPException) as exc:
        erase(OneRowSession(user),user,'wrong@example.test')
    assert exc.value.status_code == 422


def test_push_rejects_other_tenant_without_querying_metadata():
    alert = SimpleNamespace(id=3, tenant_id=1, user_id=None, audience='all')
    user = SimpleNamespace(id=22, tenant_id=2, role='resident')
    assert eligible(OneRowSession(None), alert, user) is False


def test_push_rejects_wrong_pg_and_self_created_alert(monkeypatch):
    import push_notifications
    def fake_meta(s, tenant, kind, key):
        return {'property_id': 8, 'created_by': 10} if kind == 'alert_meta' else {'property_id': 4}
    monkeypatch.setattr(push_notifications, 'meta', fake_meta)
    alert = SimpleNamespace(id=3, tenant_id=1, user_id=None, audience='all')
    other_pg = SimpleNamespace(id=22, tenant_id=1, role='resident')
    creator = SimpleNamespace(id=10, tenant_id=1, role='owner')
    assert eligible(OneRowSession(None), alert, other_pg) is False
    assert eligible(OneRowSession(None), alert, creator) is False


def test_push_rejects_inactive_account(monkeypatch):
    from platform_api import PlatformUserAccess
    class InactiveSession:
        def get(self, cls, ident):
            if cls is PlatformUserAccess:
                return SimpleNamespace(is_active=0)
            return None
    alert=SimpleNamespace(id=11,tenant_id=1,user_id=None,audience='all')
    user=SimpleNamespace(id=7,tenant_id=1,role='owner')
    assert eligible(InactiveSession(),alert,user) is False

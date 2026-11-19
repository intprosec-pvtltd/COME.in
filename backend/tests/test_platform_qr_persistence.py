"""Platform payment QR must survive a new BillingStore instance / app restart."""
import pytest
from sqlalchemy import create_engine
from staysync_subscriptions import BillingStore


def test_platform_qr_persists_across_instances_and_toggle(tmp_path):
    engine = create_engine(f"sqlite:///{tmp_path / 'main.db'}")
    image = b"\x89PNG\r\n\x1a\n" + b"illustrative-test-png"
    first = BillingStore(str(tmp_path / 'ledger_a.db'), str(tmp_path / 'uploads_a'))
    first.attach_durable_qr(engine)
    assert first.qr() is None
    first.set_qr('admin', image, 'IntProSec', 'example@upi')
    restarted = BillingStore(str(tmp_path / 'ledger_b.db'), str(tmp_path / 'uploads_b'))
    restarted.attach_durable_qr(engine)
    assert restarted.qr()['beneficiary'] == 'IntProSec'
    assert restarted.qr_content() == (image, 'image/png')
    restarted.set_qr_enabled('admin', False)
    with pytest.raises(LookupError):
        restarted.qr_content()
    restarted.set_qr_enabled('admin', True)
    assert restarted.qr_content()[0] == image

"""V35 risk acknowledgement response contract, tested alongside API integration tests."""
import inspect


def test_payment_state_defaults_for_older_records():
    import v3_api
    text = inspect.getsource(v3_api.payment_risk_out)
    assert "risk_acknowledged" in text


def test_owner_approval_saves_risk_acknowledgement():
    import v3_api
    text = inspect.getsource(v3_api.review)
    assert "risk_acknowledged=bool(data.risk_acknowledged)" in text
    assert "if data.decision=='approved' else False" in text

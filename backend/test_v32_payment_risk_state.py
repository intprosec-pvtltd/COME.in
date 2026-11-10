"""V32 payment-risk serialization contract (run alongside V31 API tests)."""
from pathlib import Path


def test_payment_risk_contract_is_present():
    source = (Path(__file__).parent / 'v3_api.py').read_text(encoding='utf-8')
    assert 'def payment_risk_out(' in source
    assert "'legacy_not_analyzed'" in source
    assert "**payment_risk_out(s,u.tenant_id,p)" in source
    assert "'risk_level':'review_required','risk_flags':['No proof attached']" in source
    assert "'risk_level':risk['risk_level']" in source

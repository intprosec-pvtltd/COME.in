"""Static deployment contract; API behaviour covered by test_v31_payment_api.py."""
from pathlib import Path

def test_v33_risk_approval_contract():
    source = (Path(__file__).parent / 'v3_api.py').read_text(encoding='utf-8')
    assert 'risk_acknowledged:bool=False' in source
    assert "payment_risk_out(s,u.tenant_id,p).get('risk_level')=='review_required'" in source
    assert "not data.risk_acknowledged" in source
    assert "if not data.bank_confirmed" in source
    assert 'pending_total=sum(' in source

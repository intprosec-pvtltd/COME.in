from risk_checks import inspect_file

def test_file_risk_duplicate_is_not_authentication():
    data = b"\x89PNG\r\n\x1a\n" + b"demo"
    first = inspect_file(data, 'image/png')
    assert first['risk_level'] == 'unverified'
    assert not first['authenticity_verified']
    repeat = inspect_file(data, 'image/png', [first['sha256']])
    assert repeat['risk_level'] == 'review_required'
    assert 'Exact file' in repeat['risk_flags'][0]

def test_pdf_metadata_indicators_are_not_proof_of_forgery():
    r = inspect_file(b'%PDF-1.7\n/Producer (Canva)\n', 'application/pdf')
    assert r['risk_level'] == 'review_required'
    assert not r['authenticity_verified']

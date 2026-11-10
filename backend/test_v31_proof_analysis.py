"""Standalone V31 fraud-risk tests; no private user files or server required."""
import io
from decimal import Decimal
from PIL import Image, ImageDraw
import risk_checks


def sample_png(*, text_color=(20, 20, 20), compression=6):
    img = Image.new('RGB', (400, 260), '#fafafa')
    ImageDraw.Draw(img).rectangle((30, 30, 280, 140), fill=text_color)
    buf = io.BytesIO()
    img.save(buf, format='PNG', compress_level=compression)
    return buf.getvalue()


def test_backward_compatible_exact_duplicate():
    data = sample_png()
    first = risk_checks.inspect_file(data, 'image/png')
    assert not first['authenticity_verified']
    assert not first['ai_generated_verified']
    again = risk_checks.inspect_file(data, 'image/png', [first['sha256']])
    assert again['risk_level'] == 'review_required'
    assert 'Exact file' in ' '.join(again['risk_flags'])


def test_near_duplicate_using_perceptual_hash():
    raw1 = sample_png(compression=1)
    raw2 = sample_png(compression=9)
    first = risk_checks.inspect_file(raw1, 'image/png')
    assert first['sha256'] != risk_checks.sha256(raw2)
    assert first['visual_hash']
    next_result = risk_checks.inspect_file(raw2, 'image/png',
                                           known_visual_hashes=[first['visual_hash']])
    assert 'Visually similar' in ' '.join(next_result['risk_flags'])


def test_ocr_invoice_amount_mismatch_is_flagged(monkeypatch):
    monkeypatch.setattr(risk_checks, '_ocr_text',
                        lambda *_args: ('Payment successful INR 2,500.00 Ref 123456789012', 'completed'))
    r = risk_checks.inspect_file(sample_png(), 'image/png',
                                 expected_amount=Decimal('3000.00'),
                                 expected_reference='123456789012', document_kind='payment')
    assert r['risk_level'] == 'review_required'
    assert 'does not match' in ' '.join(r['risk_flags'])
    assert not r['authenticity_verified']


def test_ocr_matching_amount_does_not_certify_payment(monkeypatch):
    monkeypatch.setattr(risk_checks, '_ocr_text',
                        lambda *_args: ('INR 3000.00 transaction 123456789012', 'completed'))
    r = risk_checks.inspect_file(sample_png(), 'image/png',
                                 expected_amount=3000, expected_reference='123456789012',
                                 document_kind='payment')
    assert r['risk_level'] == 'unverified'
    assert r['authenticity_verified'] is False
    assert r['ai_generated_verified'] is False


def test_pdf_producer_is_advisory():
    r = risk_checks.inspect_file(b'%PDF-1.7\n/Producer (Canva)\n', 'application/pdf')
    assert r['risk_level'] == 'review_required'
    assert r['authenticity_verified'] is False


def test_ocr_unavailable_keeps_manual_bank_gate(monkeypatch):
    monkeypatch.setattr(risk_checks, '_ocr_text',
                        lambda *_args: ('', 'dependency_unavailable'))
    r = risk_checks.inspect_file(sample_png(), 'image/png', document_kind='payment')
    assert r['analysis_status'] == 'dependency_unavailable'
    assert any('bank credit' in msg for msg in r['review_notes'])
    assert r['authenticity_verified'] is False


def test_no_full_ocr_text_exposed(monkeypatch):
    secret = '9999888877776666'
    monkeypatch.setattr(risk_checks, '_ocr_text',
                        lambda *_args: ('ID ' + secret, 'completed'))
    r = risk_checks.inspect_file(sample_png(), 'image/png', document_kind='identity')
    assert secret not in str(r)

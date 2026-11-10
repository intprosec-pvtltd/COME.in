"""V35: payment screenshot templates must not trigger fraudulent visual-duplicate flags."""
import io

from PIL import Image, ImageDraw
from risk_checks import inspect_file


def _receipt(amount: str, *, compression: int = 6) -> bytes:
    image = Image.new('RGB', (520, 240), 'white')
    draw = ImageDraw.Draw(image)
    draw.text((22, 30), 'Payment successful', fill='black')
    draw.text((22, 80), amount, fill='black')
    buffer = io.BytesIO()
    image.save(buffer, format='PNG', compress_level=compression)
    return buffer.getvalue()


def test_payment_template_similar_is_advisory_not_fraud():
    original = _receipt('INR 5000', compression=1)
    another = _receipt('INR 6000', compression=9)
    first = inspect_file(original, 'image/png', document_kind='payment', perform_ocr=False)
    second = inspect_file(another, 'image/png', document_kind='payment', perform_ocr=False,
                          known_visual_hashes=[first['visual_hash']])
    assert second['risk_level'] == 'unverified', second
    assert not any('Visually similar' in f for f in second['risk_flags'])
    assert any('layout resembles' in n for n in second['review_notes']), second
    assert second['authenticity_verified'] is False


def test_exact_payment_file_reuse_still_requires_review():
    raw = _receipt('INR 5000')
    first = inspect_file(raw, 'image/png', document_kind='payment', perform_ocr=False)
    repeated = inspect_file(raw, 'image/png', document_kind='payment', perform_ocr=False,
                            known_hashes=[first['sha256']])
    assert repeated['risk_level'] == 'review_required'
    assert any('Exact payment proof file' in flag for flag in repeated['risk_flags'])
    assert not repeated['authenticity_verified']


def test_identity_visual_duplicate_remains_flagged():
    raw = _receipt('ID FOR TEST ONLY', compression=1)
    first = inspect_file(raw, 'image/png', perform_ocr=False)
    second = inspect_file(_receipt('ID FOR TEST ONLY', compression=9), 'image/png',
                          known_visual_hashes=[first['visual_hash']], perform_ocr=False)
    assert second['risk_level'] == 'review_required'
    assert any('Visually similar' in flag for flag in second['risk_flags'])

"""V33 AI-origin metadata signal is advisory only."""
import io
from PIL import Image, PngImagePlugin
from risk_checks import inspect_file


def test_generating_tool_metadata_flag_does_not_claim_authenticity():
    img=Image.new('RGB',(80,40),'white')
    meta=PngImagePlugin.PngInfo()
    meta.add_text('Software','ComfyUI')
    buf=io.BytesIO();img.save(buf,format='PNG',pnginfo=meta)
    result=inspect_file(buf.getvalue(),'image/png',perform_ocr=False)
    assert result['risk_level']=='review_required'
    assert any('generative workflow' in f for f in result['risk_flags'])
    assert result['ai_generated_verified'] is False
    assert result['authenticity_verified'] is False


def test_missing_ai_metadata_does_not_assert_document_is_genuine():
    img=Image.new('RGB',(80,40),'white')
    buf=io.BytesIO();img.save(buf,format='PNG')
    result=inspect_file(buf.getvalue(),'image/png',perform_ocr=False)
    assert result['risk_level']=='unverified'
    assert result['authenticity_verified'] is False

"""COME.in V31 advisory proof analysis.

No detector can certify that a document is genuine or AI-generated. This module
never approves payments or identity, and does not transmit private documents.
CPU OCR is optional and bounded; failures produce explicit analysis statuses.
"""
from __future__ import annotations

import hashlib
import io
import os
import re
from decimal import Decimal, InvalidOperation
from typing import Iterable

MAX_ANALYSIS_BYTES = 5 * 1024 * 1024
MAX_IMAGE_PIXELS = 22_000_000
MAX_PDF_PAGES = 2


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _image_hash(data: bytes, mime: str) -> str | None:
    if mime not in ('image/png', 'image/jpeg', 'image/webp'):
        return None
    try:
        from PIL import Image, ImageOps
        Image.MAX_IMAGE_PIXELS = MAX_IMAGE_PIXELS
        with Image.open(io.BytesIO(data)) as img:
            if img.width * img.height > MAX_IMAGE_PIXELS:
                return None
            img = ImageOps.exif_transpose(img).convert('L').resize((9, 8))
            pixels = list(img.get_flattened_data() if hasattr(img, "get_flattened_data") else img.getdata())
            value = 0
            for y in range(8):
                for x in range(8):
                    value = (value << 1) | int(pixels[y * 9 + x] > pixels[y * 9 + x + 1])
            return f'{value:016x}'
    except Exception:
        return None


def hamming_distance(a: str, b: str) -> int:
    return (int(a, 16) ^ int(b, 16)).bit_count()


def _ocr_text(data: bytes, mime: str) -> tuple[str, str]:
    """Return (text, status). Image OCR needs Tesseract; PDF text uses PyMuPDF.

    OCR data is processed in memory, not sent to any external API.
    """
    if not os.getenv('COMEIN_V31_OCR_ENABLED', 'false').lower() == 'true':
        return '', 'disabled'
    try:
        if mime == 'application/pdf':
            from pypdf import PdfReader
            reader = PdfReader(io.BytesIO(data), strict=False)
            if reader.is_encrypted:
                return '', 'encrypted_pdf'
            if len(reader.pages) > 20:
                return '', 'too_many_pages'
            snippets = []
            for n in range(min(len(reader.pages), MAX_PDF_PAGES)):
                snippets.append((reader.pages[n].extract_text() or '')[:5000])
            text = '\n'.join(snippets)[:7000]
            if text.strip():
                return text, 'completed'
            # Scanned PDFs need separate licensed-safe PDFium renderer + Tesseract.
            try:
                import pypdfium2 as pdfium
                import pytesseract
                pdf = pdfium.PdfDocument(data)
                try:
                    for n in range(min(len(pdf), MAX_PDF_PAGES)):
                        page = pdf[n]
                        try:
                            bitmap = page.render(scale=1.3)
                            img = bitmap.to_pil()
                            snippets.append(pytesseract.image_to_string(
                                img, config='--psm 6', timeout=8)[:5000])
                        finally:
                            page.close()
                finally:
                    pdf.close()
            except Exception:
                pass
            text = '\n'.join(snippets)[:7000]
            return text, 'completed' if text.strip() else 'no_readable_text'
        if mime in ('image/png', 'image/jpeg', 'image/webp'):
            from PIL import Image, ImageOps
            import pytesseract
            Image.MAX_IMAGE_PIXELS = MAX_IMAGE_PIXELS
            with Image.open(io.BytesIO(data)) as img:
                if img.width * img.height > MAX_IMAGE_PIXELS:
                    return '', 'image_too_large'
                img = ImageOps.exif_transpose(img).convert('RGB')
                img.thumbnail((2200, 2200))
                return pytesseract.image_to_string(img, config='--psm 6', timeout=8)[:7000], 'completed'
    except ImportError:
        return '', 'dependency_unavailable'
    except Exception:
        return '', 'ocr_unavailable'
    return '', 'unsupported'


def _amounts(text: str) -> list[Decimal]:
    # Only currency-anchored candidates. Random 12-digit UTRs are never amounts.
    found = []
    for m in re.finditer(r'(?:₹|\bINR\b|\bRs\.?\b)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)', text, re.I):
        try:
            found.append(Decimal(m.group(1).replace(',', '')))
        except InvalidOperation:
            pass
    return found[:20]


def inspect_file(data: bytes, mime: str, known_hashes: Iterable[str] = (), *,
                 known_visual_hashes: Iterable[str] = (),
                 expected_amount=None, expected_reference: str | None = None,
                 document_kind: str = 'identity', perform_ocr: bool = True) -> dict:
    """Compatibility-safe replacement for V28 inspect_file.

    known_hashes and known_visual_hashes must come from the SAME tenant only.
    Never interpret risk_level='unverified' as authentic or approve automatically.
    """
    digest = sha256(data)
    flags: list[str] = []
    details: list[str] = []
    if not data or len(data) > MAX_ANALYSIS_BYTES:
        return dict(sha256=digest, visual_hash=None, risk_level='review_required',
                    risk_flags=['Document is missing or exceeds analysis size limit'],
                    analysis_status='invalid_input', authenticity_verified=False,
                    note='Upload is not an authenticity verification.')
    if digest in set(filter(None, known_hashes)):
        flags.append('Exact payment proof file was submitted previously; compare transaction reference, date and bank credit before deciding' if document_kind == 'payment' else 'Exact file already used in another submission')
    if mime == 'application/pdf':
        if any(x in data for x in (b'/JavaScript', b'/JS ', b'/OpenAction', b'/Launch')):
            flags.append('PDF contains active-content indicators; review using a safe viewer')
        if b'/Producer' in data and re.search(rb'/Producer\s*\([^)]*(?:Photoshop|Illustrator|Canva|GIMP)', data, re.I):
            flags.append('PDF metadata names an editing application; manual review suggested')
    if mime == 'image/png' and b'tEXt' in data and any(x in data.lower() for x in (b'generative', b'created by ai', b'comfyui')):
        flags.append('PNG metadata contains a generative-tool indicator (not proof of AI origin)')
    # Metadata-only origin signal, not a visual AI detector or authenticity decision.
    # Inspect bounded metadata from supported formats; avoid storing raw prompts/EXIF.
    if mime in ('image/png', 'image/jpeg', 'image/webp'):
        try:
            from PIL import Image
            with Image.open(io.BytesIO(data)) as img:
                metadata = ' '.join(str(v)[:512] for _, v in list(img.info.items())[:24])[:4096].lower()
                exif = img.getexif()
                software = str(exif.get(305, ''))[:256].lower() if exif else ''
                haystack = metadata + ' ' + software
                if any(marker in haystack for marker in (
                        'comfyui', 'automatic1111', 'stable diffusion',
                        'midjourney', 'dall-e', 'generative ai')):
                    flags.append('Image metadata references a generative workflow; manual review suggested')
        except (ValueError, TypeError, OSError):
            pass
    perceptual = _image_hash(data, mime)
    if perceptual:
        try:
            if any(hamming_distance(perceptual, other) <= 6 for other in known_visual_hashes
                   if other and re.fullmatch(r'[0-9a-fA-F]{16}', str(other))):
                if document_kind == 'payment':
                    details.append('Image layout resembles an earlier payment proof. Payment apps reuse templates; this alone does not indicate fraud. Compare UTR, amount and date.')
                else:
                    flags.append('Visually similar image was used in another submission; review for reuse')
        except (ValueError, TypeError):
            pass
    ocr_status = 'not_requested'
    observed_amounts: list[Decimal] = []
    if perform_ocr:
        text, ocr_status = _ocr_text(data, mime)
        # Extracted full text is deliberately NOT included in outputs (may hold ID numbers).
        if document_kind == 'payment' and text.strip():
            observed_amounts = _amounts(text)
            if expected_amount is not None and observed_amounts:
                expected = Decimal(str(expected_amount))
                if expected not in observed_amounts:
                    flags.append('OCR-readable currency amount does not match the submitted payment amount')
            if expected_reference and re.fullmatch(r'[A-Za-z0-9]{8,40}', expected_reference.strip()):
                normalized = re.sub(r'[^A-Za-z0-9]', '', text).upper()
                ref = expected_reference.strip().upper()
                if len(ref) >= 8 and ref not in normalized:
                    details.append('Submitted reference was not found in OCR text; manual comparison required')
    if document_kind == 'payment' and ocr_status not in ('completed', 'not_requested'):
        details.append('OCR could not establish payment details; verify bank credit independently')
    return {
        'sha256': digest,
        'visual_hash': perceptual,
        'risk_level': 'review_required' if flags else 'unverified',
        'risk_flags': flags,
        'review_notes': details,
        'analysis_status': ocr_status,
        'authenticity_verified': False,
        'ai_generated_verified': False,
        'note': 'Risk indicators are not proof of forgery. Confirm money in bank or verify identity independently.',
    }

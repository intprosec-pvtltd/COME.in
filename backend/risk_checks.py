"""Conservative, explainable uploaded-file risk indicators.

NOT an AI-generated-image detector, OCR engine, bank confirmation or ID verification.
A clean result cannot establish authenticity. Keep original files private.
"""
import hashlib
import re


def inspect_file(data: bytes, mime: str, known_hashes=()):
    digest = hashlib.sha256(data).hexdigest()
    flags = []
    known = set(known_hashes)
    if digest in known:
        flags.append('Exact file already used in another submission')
    # Indicators are intentionally weak signals, not forgery findings.
    if mime == 'application/pdf':
        if b'/JavaScript' in data or b'/JS ' in data or b'/OpenAction' in data:
            flags.append('PDF contains active-content indicators; inspect safely')
        if b'/Producer' in data and re.search(rb'/Producer\s*\([^)]*(?:Photoshop|Illustrator|Canva|GIMP)', data, re.I):
            flags.append('PDF metadata names an editing application; manual review suggested')
    if mime == 'image/png' and b'tEXt' in data and any(x in data.lower() for x in [b'generative', b'created by ai', b'comfyui']):
        flags.append('PNG metadata contains a generative-tool indicator')
    return {'sha256': digest, 'risk_level': 'review_required' if flags else 'unverified',
            'risk_flags': flags, 'authenticity_verified': False,
            'note': 'File analysis cannot prove authenticity. Verify bank credit or identity independently.'}

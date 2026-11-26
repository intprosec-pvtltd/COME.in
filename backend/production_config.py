"""Validate explicitly enabled production settings before opening the database."""
import os
import re
from urllib.parse import urlsplit

from sqlalchemy.engine import make_url
from sqlalchemy.exc import ArgumentError


def production_origins():
    return {origin.strip().rstrip('/') for origin in os.getenv('CORS_ORIGINS', '').split(',') if origin.strip()}


def validate_production():
    if os.getenv('STAYSYNC_ENV') != 'production':
        return

    issues = []
    try:
        database = make_url(os.environ['DATABASE_URL'])
        if database.get_backend_name() != 'postgresql' or not database.host:
            issues.append('DATABASE_URL must use PostgreSQL')
    except (KeyError, ValueError, ArgumentError):
        issues.append('DATABASE_URL must be configured')

    secret_names = ('SECRET_KEY', 'PLATFORM_ADMIN_JWT_SECRET', 'PHONE_OTP_SECRET')
    secrets = [os.getenv(name, '').strip() for name in secret_names]
    for name, value in zip(secret_names, secrets):
        if len(value) < 32 or value.lower().startswith(('development', 'replace', 'example')):
            issues.append(f'{name} needs a stable random secret of at least 32 characters')
    if len(set(secrets)) != len(secrets):
        issues.append('Signing and OTP secrets must be distinct')

    for name in ('DEMO_SEED', 'ALLOW_LEGACY_EMAIL_REGISTRATION'):
        if os.getenv(name, 'false').lower() == 'true':
            issues.append(f'{name} must be false')
    if os.getenv('COMEIN_V31_OCR_ENABLED', 'false').lower() == 'true':
        issues.append('COMEIN_V31_OCR_ENABLED must be false')
    if os.getenv('PHONE_OTP_DELIVERY', 'twilio') != 'twilio':
        issues.append('PHONE_OTP_DELIVERY must use live SMS')
    if not re.fullmatch(r'AC[0-9a-fA-F]{32}', os.getenv('TWILIO_ACCOUNT_SID', '')):
        issues.append('TWILIO_ACCOUNT_SID is invalid or missing')
    if not os.getenv('TWILIO_AUTH_TOKEN') or not (os.getenv('TWILIO_MESSAGING_SERVICE_SID') or os.getenv('TWILIO_FROM_NUMBER')):
        issues.append('Twilio authentication and an approved SMS sender are required')

    origins = production_origins()
    if not origins or any(not re.fullmatch(r'https://[^/\s?#@*]+', origin) for origin in origins):
        issues.append('CORS_ORIGINS must list exact HTTPS dashboard origins')
    for name in ('PRIVACY_POLICY_URL', 'TERMS_URL', 'ACCOUNT_DELETION_URL'):
        value = urlsplit(os.getenv(name, ''))
        if value.scheme != 'https' or not value.hostname or value.hostname.endswith('.example'):
            issues.append(f'{name} needs a published HTTPS URL')
    for name in ('COMEIN_PRIVATE_STORAGE', 'COMEIN_CHAT_STORAGE', 'STAYSYNC_SUBSCRIPTION_DB', 'STAYSYNC_SUBSCRIPTION_MEDIA_DIR'):
        if not os.getenv(name):
            issues.append(f'{name} needs an explicit durable storage path')

    if issues:
        raise RuntimeError('Invalid Stay Sync production configuration: ' + '; '.join(issues))

"""Twilio Messages transport; safe diagnostics without customer data or credentials."""
import base64
import json
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

_ACCEPTED = frozenset({'accepted', 'queued', 'sending', 'sent', 'delivered', 'scheduled'})
_MAX_RESPONSE = 65536


class SmsDeliveryError(Exception):
    def __init__(self, category, http_status=None, provider_code=None):
        super().__init__('SMS provider request failed')
        self.category = category
        self.http_status = http_status
        self.provider_code = provider_code


def _payload(response):
    try:
        raw = response.read(_MAX_RESPONSE + 1)
        if len(raw) > _MAX_RESPONSE:
            return None
        value = json.loads(raw)
        return value if isinstance(value, dict) else None
    except (ValueError, UnicodeError, OSError):
        return None


def _code(payload, key):
    value = (payload or {}).get(key)
    # Restrict diagnostics to numeric provider error identifiers, not raw messages.
    return value if type(value) is int and 10000 <= value <= 999999 else None


def submit_sms(sid, token, sender, service, phone, code):
    fields = {'To': phone, 'Body': f'Stay Sync verification code: {code}. Valid for 5 minutes. Do not share this code.'}
    fields['MessagingServiceSid' if service else 'From'] = service or sender
    req = Request(f'https://api.twilio.com/2010-04-01/Accounts/{sid}/Messages.json',
                  data=urlencode(fields).encode(),
                  headers={'Authorization': 'Basic ' + base64.b64encode(f'{sid}:{token}'.encode()).decode(),
                           'Content-Type': 'application/x-www-form-urlencoded'}, method='POST')
    try:
        with urlopen(req, timeout=15) as response:
            status = response.status
            payload = _payload(response)
            if not 200 <= status < 300:
                raise SmsDeliveryError('http_rejected', status, _code(payload, 'code'))
            if payload is None:
                raise SmsDeliveryError('invalid_response', status)
            message_status = payload.get('status')
            if not isinstance(message_status, str) or message_status not in _ACCEPTED or payload.get('error_code') is not None:
                raise SmsDeliveryError('message_rejected', status, _code(payload, 'error_code'))
            return message_status
    except HTTPError as exc:
        try:
            payload = _payload(exc)
            raise SmsDeliveryError('http_rejected', exc.code, _code(payload, 'code')) from None
        finally:
            exc.close()
    except (URLError, OSError, TimeoutError):
        raise SmsDeliveryError('transport_failure') from None
    except SmsDeliveryError:
        raise
    except Exception:
        # Preserve fail-closed behavior even on an unexpected transport/response error.
        raise SmsDeliveryError('unexpected_transport_failure') from None

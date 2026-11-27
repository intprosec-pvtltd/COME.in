"""Offline provider response tests: no network, credentials or real recipients."""
import io
import json
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs
import pytest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import sms_transport as sms

class Response(io.BytesIO):
    def __init__(self, payload, status=201):
        super().__init__(json.dumps(payload).encode())
        self.status = status

def send(service=''):
    return sms.submit_sms('AC' + '0' * 32, 'synthetic-token', '+15005550006', service, '+15005550001', '012345')

@pytest.mark.parametrize('status', ['accepted', 'queued', 'sending', 'sent', 'delivered', 'scheduled'])
def test_accepted_message(monkeypatch, status):
    def fake(req, timeout):
        assert timeout == 15
        data = parse_qs(req.data.decode())
        assert data['To'] == ['+15005550001']
        assert data['From'] == ['+15005550006']
        assert '012345' in data['Body'][0]
        return Response({'status': status, 'error_code': None})
    monkeypatch.setattr(sms, 'urlopen', fake)
    assert send() == status

def test_service_sender(monkeypatch):
    def fake(req, timeout):
        data = parse_qs(req.data.decode())
        assert data['MessagingServiceSid'] == ['MGsynthetic']
        assert 'From' not in data
        return Response({'status': 'queued'})
    monkeypatch.setattr(sms, 'urlopen', fake)
    assert send('MGsynthetic') == 'queued'

@pytest.mark.parametrize('code', [21608, 21408, 20003])
def test_provider_http_error_redacted(monkeypatch, code):
    def fake(req, timeout):
        raise HTTPError(req.full_url, 400, 'private provider text', {}, io.BytesIO(json.dumps({'code': code, 'message': 'private recipient and OTP'}).encode()))
    monkeypatch.setattr(sms, 'urlopen', fake)
    with pytest.raises(sms.SmsDeliveryError) as err:
        send()
    assert err.value.category == 'http_rejected'
    assert err.value.http_status == 400
    assert err.value.provider_code == code
    assert 'private' not in str(err.value)

@pytest.mark.parametrize('payload', [{'status': 'failed', 'error_code': 30007}, {'status': 'undelivered'}, {'status': 'queued', 'error_code': 30007}, {'status': ['queued']}, {}, {'status': 'private content'}])
def test_nonaccepted_message(monkeypatch, payload):
    monkeypatch.setattr(sms, 'urlopen', lambda *a, **k: Response(payload))
    with pytest.raises(sms.SmsDeliveryError) as err:
        send()
    assert err.value.category == 'message_rejected'
    assert 'private' not in str(err.value)

def test_invalid_response(monkeypatch):
    class Invalid(io.BytesIO):
        status = 201
    monkeypatch.setattr(sms, 'urlopen', lambda *a, **k: Invalid(b'not json'))
    with pytest.raises(sms.SmsDeliveryError) as err:
        send()
    assert err.value.category == 'invalid_response'

def test_network_error(monkeypatch):
    def fake(*a, **k):
        raise URLError('private address')
    monkeypatch.setattr(sms, 'urlopen', fake)
    with pytest.raises(sms.SmsDeliveryError) as err:
        send()
    assert err.value.category == 'transport_failure'
    assert 'private' not in str(err.value)


def test_unexpected_transport_error_fails_closed(monkeypatch):
    def fake(*args, **kwargs):
        raise RuntimeError('private provider response')
    monkeypatch.setattr(sms, 'urlopen', fake)
    with pytest.raises(sms.SmsDeliveryError) as err:
        send()
    assert err.value.category == 'unexpected_transport_failure'
    assert 'private' not in str(err.value)


def test_oversized_response_is_rejected(monkeypatch):
    monkeypatch.setattr(sms, 'urlopen', lambda *a, **k: Response({'status': 'queued', 'body': 'x' * 70000}))
    with pytest.raises(sms.SmsDeliveryError) as err:
        send()
    assert err.value.category == 'invalid_response'

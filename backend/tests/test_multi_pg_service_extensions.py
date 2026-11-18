"""Property isolation regression tests for Stay Sync Manage extensions.

These tests operate exclusively against the existing local SQLite test database.
"""
import uuid

from test_v3 import client, login, req, create


def test_pg_specific_meals_joining_codes_and_payment_accounts():
    email = f'multi-extra-{uuid.uuid4().hex}@test.pg'
    registration = client.post('/api/v3/register', json={
        'name': 'Multi Property Test Owner', 'email': email,
        'phone': '9876543210', 'password': 'MultiOwner123!',
        'role': 'owner', 'property_name': 'Primary PG',
    })
    assert registration.status_code == 201, registration.text
    owner = login(email, 'MultiOwner123!')
    pg1 = create('property', {'name': 'North PG'}, owner)
    pg2 = create('property', {'name': 'South PG'}, owner)

    # Each PG has a distinct joining code, without bypassing invitation.
    joining_1 = req('GET', f'/v3/joining-code?property_id={pg1}', owner)
    joining_2 = req('GET', f'/v3/joining-code?property_id={pg2}', owner)
    assert joining_1['property_id'] == pg1
    assert joining_2['property_id'] == pg2
    assert joining_1['code'] != joining_2['code']
    assert req('GET', f'/v3/joining-code?property_id={pg1}', owner)['code'] == joining_1['code']

    menu1 = {'day': 'Monday', 'breakfast': 'Idli', 'lunch': 'Rice', 'dinner': 'Dosa', 'property_id': pg1}
    menu2 = {'day': 'Monday', 'breakfast': 'Poha', 'lunch': 'Roti', 'dinner': 'Dal', 'property_id': pg2}
    create('meal', menu1, owner)
    create('meal', menu2, owner)
    menus = req('GET', '/v3/state', owner)['meals']
    assert any(x['property_id'] == pg1 and x['breakfast'] == 'Idli' for x in menus)
    assert any(x['property_id'] == pg2 and x['breakfast'] == 'Poha' for x in menus)

    req('PUT', '/v3/property-payment', owner, {
        'property_id': pg1, 'upi_id': 'north@upi',
        'bank_holder': 'North Owner', 'bank_name': 'North Bank',
        'bank_account': '123456789012', 'ifsc': 'ABCD0123456',
    })
    req('PUT', '/v3/property-payment', owner, {
        'property_id': pg2, 'upi_id': 'south@upi',
        'bank_holder': 'South Owner', 'bank_name': 'South Bank',
        'bank_account': '654321987012', 'ifsc': 'EFGH0123456',
    })
    north_payment = req('GET', f'/v3/property-payment?property_id={pg1}', owner)
    south_payment = req('GET', f'/v3/property-payment?property_id={pg2}', owner)
    assert north_payment['upi_id'] == 'north@upi'
    assert south_payment['upi_id'] == 'south@upi'
    assert north_payment['bank_account'] != south_payment['bank_account']

    def invited_resident(pg):
        resident_email = f'resident-ext-{uuid.uuid4().hex}@test.pg'
        invitation = req('POST', '/v3/residents/invite', owner, {
            'name': 'Resident Example', 'email': resident_email,
            'phone': '9876543210', 'property_id': pg,
        }, 201)
        temp = invitation['temporary_password']
        first_session = login(resident_email, temp)
        req('POST', '/v3/password', first_session, {
            'current_password': temp, 'new_password': 'NewSecure123!',
        })
        return login(resident_email, 'NewSecure123!')

    north = invited_resident(pg1)
    south = invited_resident(pg2)
    north_state = req('GET', '/v3/state', north)
    south_state = req('GET', '/v3/state', south)
    assert north_state['payment_methods']['upi_id'] == 'north@upi'
    assert south_state['payment_methods']['upi_id'] == 'south@upi'
    assert all(m['property_id'] == pg1 for m in north_state['meals'])
    assert all(m['property_id'] == pg2 for m in south_state['meals'])
    assert client.get(f'/api/v3/property-payment?property_id={pg2}', headers=north).status_code == 403
    assert client.get(f'/api/v3/messages?property_id={pg2}', headers=north).status_code == 403
    msg = req('POST', '/v3/messages', north, {'property_id': pg1, 'body': 'North only'}, 201)
    assert msg['id'] not in [m['id'] for m in req('GET', f'/v3/messages?property_id={pg2}', owner)]

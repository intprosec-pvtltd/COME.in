"""Regression tests for resident rent, account access and notification targeting."""
import uuid
from test_v3 import client, login, req, create
import os as _legacy_test_os
_legacy_test_os.environ['ALLOW_LEGACY_EMAIL_REGISTRATION']='true'

def test_resident_rent_and_safe_deactivation():
    uid=uuid.uuid4().hex
    email=f'rent-check-{uid}@test.pg'
    client.post('/api/v3/register',json={
        'name':'Rent Owner','email':f'owner-rent-{uid}@test.pg',
        'phone':'9876543210','password':'LongPassword123!',
        'role':'owner','property_name':'Rental Property'}).raise_for_status()
    owner=login(f'owner-rent-{uid}@test.pg','LongPassword123!')
    property_id=create('property',{'name':'East Wing'},owner)
    invitation=req('POST','/v3/residents/invite',owner,{
        'name':'Rental Resident','email':email,'property_id':property_id,
        'monthly_rent':'12500.50'},201)
    resident_id=invitation['id']
    resident=next(x for x in req('GET','/v3/state',owner)['residents'] if x['id']==resident_id)
    assert resident['monthly_rent']=='12500.50'
    assert resident['is_active'] is True
    req('PUT',f'/v3/entities/resident/{resident_id}',owner,{
        'name':'Rental Resident','email':email,'property_id':property_id,
        'monthly_rent':'13000.00'},200)
    resident=next(x for x in req('GET','/v3/state',owner)['residents'] if x['id']==resident_id)
    assert resident['monthly_rent']=='13000.00'
    assert client.patch(f'/api/v3/residents/{resident_id}/access',headers=login(email,invitation['temporary_password']),json={'active':False}).status_code==403
    result=req('PATCH',f'/v3/residents/{resident_id}/access',owner,{'active':False})
    assert result['active'] is False
    assert client.get('/api/v3/profile',headers=login(owner_email(uid), 'LongPassword123!')).status_code==200
    assert client.post('/api/login',json={'email':email,'password':invitation['temporary_password']}).status_code in (401,403)
    assert next(x for x in req('GET','/v3/state',owner)['residents'] if x['id']==resident_id)['is_active'] is False
    assert req('PATCH',f'/v3/residents/{resident_id}/access',owner,{'active':True})['active'] is True

def owner_email(uid):
    return f'owner-rent-{uid}@test.pg'

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import pytest
from email_validation import email_error

@pytest.mark.parametrize('value', ['user@gmail.com','User.Name@gmail.com','user123@gmail.com',' user+rent@gmail.com ','owner@demo.pg','name@company.co.in','a_b@example.org','name@googlemail.com'])
def test_valid_contact_email(value):
    assert email_error(value) is None

@pytest.mark.parametrize('value', ['', 'usergmail.com','@gmail.com','user@@gmail.com','user@gmial.com','user@gmail.co','user@gmail.con','a..b@gmail.com','a_b@gmail.com','a@-example.com','a@example..com','a b@example.com','a@example','a@a.c','x'*65+'@example.com'])
def test_invalid_contact_email(value):
    assert email_error(value) is not None

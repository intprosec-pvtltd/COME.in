"""Contact email syntax only; not a mailbox ownership check."""
import re

TYPOS = {'gmial.com','gamil.com','gmai.com','gmail.co','gmail.con','gmail.cm','gmail.om','gmail.comm','gmal.com','gmailcom'}

def email_error(raw):
    value = (raw or '').strip().lower()
    parts = value.split('@')
    if len(value) > 160 or len(parts) != 2:
        return 'Enter a valid email address'
    local, domain = parts
    if not local or len(local) > 64 or local.startswith('.') or local.endswith('.') or '..' in local or not re.fullmatch(r"[a-z0-9.!#$%&'*+/=?^_`{|}~-]+", local):
        return 'Enter a valid email address'
    if domain in TYPOS:
        return 'Did you mean gmail.com?'
    labels = domain.split('.')
    if len(labels) < 2 or not re.fullmatch(r'[a-z]{2,63}', labels[-1]) or any(not re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', label) for label in labels):
        return 'Enter a valid email address'
    if domain in ('gmail.com', 'googlemail.com') and not re.fullmatch(r'[a-z0-9]+(?:\.[a-z0-9]+)*(?:\+[a-z0-9._-]+)?', local):
        return 'Enter a valid Gmail address'
    return None

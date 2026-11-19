"""New billing snapshot and historical no-repricing regressions."""
import sqlite3
from staysync_subscriptions import BillingStore, calculate_invoice


def test_owner_plus_resident_gst_totals():
    actual=calculate_invoice(2,1)
    assert actual['billable_users']==3
    assert actual['subtotal_cents']==11700
    assert actual['gst_cents']==2106
    assert actual['amount_cents']==13806
    assert calculate_invoice(10,1)['amount_cents']==50622


def test_immutable_invoice_and_migration(tmp_path):
    path=tmp_path/'ledger.sqlite'
    store=BillingStore(str(path),str(tmp_path/'media'))
    first=store.issue_invoice('org1','2026-12',10,2,owners=1)
    assert (first['owners'],first['residents'],first['amount_cents'])==(1,2,13806)
    assert store.issue_invoice('org1','2026-12',10,500,owners=4)['id']==first['id']
    # An older invoice is not recalculated by the new code or migration.
    with sqlite3.connect(path) as db:
        db.execute('''INSERT INTO ss_invoices (id,owner_id,period,beds,residents,
            bed_rate_cents,resident_rate_cents,amount_cents,status,created_at)
            VALUES (?,?,?,?,?,?,?,?,?,?)''',('historic','org1','2026-11',10,1,0,3900,3900,'issued','2026-11-01'))
        db.commit()
    reopened=BillingStore(str(path),str(tmp_path/'media'))
    old=reopened.issue_invoice('org1','2026-11',10,500,owners=4)
    assert old['id']=='historic' and old['amount_cents']==3900 and old['owners']==0
    assert reopened.issue_invoice('org1','2026-12',1,0)['amount_cents']==13806

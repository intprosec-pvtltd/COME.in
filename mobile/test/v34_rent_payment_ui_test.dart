import 'package:flutter_test/flutter_test.dart';
import 'package:pg_resident/features/finance/finance.dart';

void main() {
  final invoice = <String, dynamic>{
    'id': 52,
    'amount': '1000',
    'paid': '1000',
    'outstanding': '0',
    'due_date': '2026-12-07',
  };
  test('prominent amount paid comes from verified ledger, not outstanding', () {
    expect(verifiedAmount(invoice), 1000);
    expect(invoiceReviewStatus(invoice, []), 'Paid');
  });
  test('latest proof is selected by payment ID, not list ordering', () {
    final invoice2 = <String, dynamic>{
      'id': 53,
      'paid': '0',
      'outstanding': '1000',
      'due_date': '2099-12-07',
    };
    final proofs = <Map<String, dynamic>>[
      {'id': 21, 'invoice_id': 53, 'status': 'pending', 'amount': '1000'},
      {'id': 20, 'invoice_id': 53, 'status': 'rejected', 'reason': 'Wrong proof'},
      {'id': 99, 'invoice_id': 77, 'status': 'approved'},
    ];
    expect(latestInvoiceProof(invoice2, proofs)?['status'], 'pending');
    expect(invoiceReviewStatus(invoice2, proofs), 'Verification pending');
    expect(verifiedAmount(invoice2), 0);
  });
  test('latest rejected proof retains owner rejection reason for resubmission', () {
    final unpaid = <String, dynamic>{
      'id': 53, 'paid': '0', 'outstanding': '1000', 'due_date': '2099-12-07'
    };
    final proofs = <Map<String, dynamic>>[
      {'id': 25, 'invoice_id': 53, 'status': 'rejected', 'reason': 'Wrong proof'},
      {'id': 24, 'invoice_id': 53, 'status': 'rejected', 'reason': 'Older rejection'},
    ];
    expect(invoiceReviewStatus(unpaid, proofs), 'Pending');
    expect(latestInvoiceProof(unpaid, proofs)?['reason'], 'Wrong proof');
  });
  test('latest proof does not cross invoices', () {
    expect(latestInvoiceProof(invoice, [
      {'id': 44, 'invoice_id': 99, 'status': 'rejected'}
    ]), isNull);
  });
}

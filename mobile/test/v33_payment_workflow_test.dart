import 'package:flutter_test/flutter_test.dart';
import 'package:pg_resident/features/finance/finance.dart';

void main() {
  final unpaid = <String, dynamic>{
    'id': 11, 'outstanding': '6000', 'paid': '0', 'due_date': '2099-12-01'
  };
  final pending = <Map<String, dynamic>>[
    {'invoice_id': 11, 'status': 'pending'}
  ];
  test('unpaid invoice without payment proof remains pending', () {
    expect(invoiceReviewStatus(unpaid, []), 'Pending');
  });
  test('submitted proof displays verification pending without changing paid amount', () {
    expect(invoiceReviewStatus(unpaid, pending), 'Verification pending');
    expect(unpaid['paid'], '0');
  });
  test('rejected proof returns invoice to pending', () {
    expect(invoiceReviewStatus(unpaid, [
      {'invoice_id':11, 'status':'rejected'}
    ]), 'Pending');
  });
  test('unrelated pending payment does not change invoice', () {
    expect(invoiceReviewStatus(unpaid, [
      {'invoice_id':13, 'status':'pending'}
    ]), 'Pending');
  });
  test('fully verified invoice displays paid', () {
    expect(invoiceReviewStatus({
      'id': 11,'outstanding':'0','paid':'6000','due_date':'2099-12-01'
    }, pending), 'Paid');
  });
}

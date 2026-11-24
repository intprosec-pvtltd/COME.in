import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pg_resident/core/email_validation.dart';
import 'package:pg_resident/features/auth/phone_verification.dart';
import 'package:pg_resident/core/display_photo.dart';

void main() {
  test('local and international Indian number forms normalize identically', () {
    for (final value in ['9876543210','+919876543210','919876543210','+91 98765 43210','98765 43210']) {
      expect(normalizeMobile(value), '+919876543210');
    }
    expect(normalizeMobile('+91+919876543210'), isNull);
    expect(normalizeMobile('1234567890'), isNull);
  });
  test('email syntax and common Gmail typos', () {
    for (final value in ['user@gmail.com',' User.Name@gmail.com ','user+rent@gmail.com','owner@demo.pg','name@company.co.in']) {
      expect(emailError(value), isNull, reason: value);
    }
    for (final value in ['','usergmail.com','@gmail.com','user@@gmail.com','user@gmial.com','user@gmail.co','a..b@gmail.com','a_b@gmail.com','a@-example.com']) {
      expect(emailError(value), isNotNull, reason: value);
    }
  });
  testWidgets('empty avatar opens photo sheet without a remove action', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: DisplayPhotoWidget(kind: 'user', id: 1, revision: 0, editable: true, size: 96))));
    await tester.tap(find.widgetWithText(TextButton, 'Edit photo'));
    await tester.pumpAndSettle();
    expect(find.text('Take a photo'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);
    expect(find.text('Remove photo'), findsNothing);
  });
}

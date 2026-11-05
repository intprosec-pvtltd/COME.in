import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pg_resident/features/auth/auth_screens.dart';

void main() {
  testWidgets('Sign-in keeps the same welcome branding with keyboard open',
      (tester) async {
    tester.view.physicalSize = const Size(420, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(420, 850),
          padding: EdgeInsets.only(top: 24, bottom: 24),
          viewInsets: EdgeInsets.only(bottom: 330),
        ),
        child: SignInScreen(),
      ),
    ));
    expect(find.text('Welcome back!'), findsOneWidget);
    expect(find.text('Same spaces. Brighter days.'), findsOneWidget);
    expect(find.text('Sign in to COME.in'), findsNothing);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(find.text('Email or Phone'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });
}

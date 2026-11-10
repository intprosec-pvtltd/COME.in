import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pg_resident/app/controller.dart';
import 'package:pg_resident/core/localization.dart';
import 'package:pg_resident/features/auth/auth_screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registration and sign-in labels are localized for all six languages', () {
    const required = <String>[
      'Create your account', 'Join your space. Start your stay.',
      'Full Name', 'Email', 'Phone Number', 'Password', 'Property Name',
      'Confirm Password', 'I agree to the Terms & Conditions and privacy policy',
      'Already have an account? Sign in', 'Keep me signed in',
      'Forgot password?', 'Email or Phone',
    ];
    for (final label in required) {
      final translations = localizedLabels[label];
      expect(translations, isNotNull, reason: label);
      for (final language in supportedLanguages.keys) {
        expect(translations![language], isNotEmpty,
            reason: '$label in $language');
      }
    }
  });

  testWidgets('Tamil sign-in keeps localized text without an auth language selector',
      (tester) async {
    tester.view.physicalSize = const Size(420, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final controller = AppController()..languageCode = 'ta';
    addTearDown(controller.dispose);
    await tester.pumpWidget(AppScope(
      controller: controller,
      child: const MaterialApp(
        locale: Locale('ta'),
        supportedLocales: [Locale('en'), Locale('ta')],
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: SignInScreen(),
      ),
    ));
    expect(find.byType(LanguagePicker), findsNothing);
    expect(find.text('மீண்டும் வரவேற்கிறோம்!'), findsOneWidget);
    expect(find.text('உள்நுழைந்தே வைத்திரு'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tamil registration keeps translated fields without an auth language selector',
      (tester) async {
    tester.view.physicalSize = const Size(420, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final controller = AppController()..languageCode = 'ta';
    addTearDown(controller.dispose);
    await tester.pumpWidget(AppScope(
      controller: controller,
      child: const MaterialApp(
        locale: Locale('ta'),
        supportedLocales: [Locale('en'), Locale('ta')],
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: RegistrationScreen(),
      ),
    ));
    expect(find.byType(LanguagePicker), findsNothing);
    expect(find.text('உங்கள் கணக்கை உருவாக்குங்கள்'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(6));
    expect(tester.takeException(), isNull);
  });
}

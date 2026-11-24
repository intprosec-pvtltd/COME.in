import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pg_resident/app/controller.dart';
import 'package:pg_resident/core/api_client.dart';
import 'package:pg_resident/features/auth/auth_screens.dart';

void main() {
  test('manual appearance is applied only after authentication and onboarding', () {
    final app=AppController();
    addTearDown(app.dispose);
    app.data={'profile':{'preferences':{'appearance':'Dark'}}};
    expect(app.themeMode,ThemeMode.dark);
    expect(app.effectiveThemeMode,ThemeMode.light);
    app.restoring=false;
    expect(app.effectiveThemeMode,ThemeMode.light);
    app.onboardingSeen=true;
    expect(app.effectiveThemeMode,ThemeMode.dark);
    app.data={'profile':{'preferences':{'appearance':'System'}}};
    expect(app.effectiveThemeMode,ThemeMode.system);
    app.data={'profile':{'preferences':{'appearance':'Light'}}};
    expect(app.effectiveThemeMode,ThemeMode.light);
    app.data={'profile':{'must_change_password':true,'preferences':{'appearance':'Dark'}}};
    expect(app.effectiveThemeMode,ThemeMode.light);
    app.data={};
    expect(app.effectiveThemeMode,ThemeMode.light);
  });
  testWidgets('known mobile hides activation; another number shows it', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final app=AppController(client:ApiClient(baseUrl:'http://qa.example'));
    addTearDown(app.dispose);
    await app.rememberVerifiedMobile('+919876543210');
    tester.view.physicalSize=const Size(420,850);
    tester.view.devicePixelRatio=1;
    addTearDown(() { tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio(); });
    await tester.pumpWidget(AppScope(controller:app,child:const MaterialApp(home:SignInScreen())));
    expect(find.text('Activate mobile login'),findsNothing);
    await tester.enterText(find.byType(TextFormField).first,'9876543211');
    await tester.pump();
    expect(find.text('Activate mobile login'),findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first,'9876543210');
    await tester.pump();
    expect(find.text('Activate mobile login'),findsNothing);
  });
  test('verified hints persist separately per backend', () async {
    SharedPreferences.setMockInitialValues({});
    final app=AppController(client:ApiClient(baseUrl:'http://qa.example'));
    addTearDown(app.dispose);
    await app.rememberVerifiedMobile('+919876543210');
    final prefs=await SharedPreferences.getInstance();
    expect(prefs.getStringList('verified_mobile_hints:http://qa.example'),['+919876543210']);
    expect(prefs.getStringList('verified_mobile_hints:https://come-in.onrender.com'),isNull);
  });
}

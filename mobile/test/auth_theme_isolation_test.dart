import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pg_resident/main.dart';
import 'package:pg_resident/app/controller.dart';
import 'package:pg_resident/core/app_theme.dart';
import 'package:pg_resident/features/auth/auth_screens.dart';

void main() {
  testWidgets('splash and login stay light when device is dark', (tester) async {
    tester.binding.platformDispatcher.platformBrightnessTestValue=Brightness.dark;
    addTearDown(tester.binding.platformDispatcher.clearPlatformBrightnessTestValue);
    tester.view.physicalSize=const Size(420,850);
    tester.view.devicePixelRatio=1;
    addTearDown(() {tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio();});
    final app=AppController();
    addTearDown(app.dispose);
    await tester.pumpWidget(PGApp(controller:app));
    expect(Theme.of(tester.element(find.byType(SplashScreen))).brightness,Brightness.light);
    final splash=tester.widget<Scaffold>(find.byType(Scaffold));
    expect(splash.backgroundColor ?? Theme.of(tester.element(find.byType(Scaffold))).scaffoldBackgroundColor,cream);
    app.restoring=false;
    app.onboardingSeen=true;
    // Rebuild with the same controller; no network or SMS calls.
    await tester.pumpWidget(PGApp(controller:app));
    // A fresh key forces a rebuild even if the parent widget is otherwise unchanged.
    await tester.pumpWidget(PGApp(key:const ValueKey('login'),controller:app));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.byType(SignInScreen))).brightness,Brightness.light);
    await tester.enterText(find.byType(TextFormField).first,'9876543210');
    await tester.pump();
    final field=tester.widget<EditableText>(find.byType(EditableText).first);
    expect(field.style.color, isNotNull);
    expect(field.style.color!.computeLuminance(),lessThan(.35));
  });
}

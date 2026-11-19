import 'core/push_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'app/controller.dart';
import 'app/router.dart';
import 'core/app_theme.dart';
import 'features/auth/auth_screens.dart';
import 'features/account/account.dart';
import 'features/account/identity_proof.dart';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StaySyncPush.initialize();
  runApp(const PGApp());
} class PGApp extends StatefulWidget {
  const PGApp({
    super.key,
    this.controller
  });
  final AppController? controller;
  @override State<PGApp> createState()=>_PGAppState();
} class _PGAppState extends State<PGApp>{
  late final AppController controller;
  @override void initState(){
    super.initState();
    controller=widget.controller??AppController();
    if(widget.controller==null)controller.initialize();
    controller.addListener(_onStateChanged);
    _onStateChanged();
  }
  void _onStateChanged(){
    if(controller.signedIn && controller.api.token!=null){
      final id='${controller.profile['id'] ?? ''}';
      StaySyncPush.register(controller.api,id);
    }
  }
  @override void dispose(){
    controller.removeListener(_onStateChanged);
    if(widget.controller==null)controller.dispose();
    super.dispose();
  } @override Widget build(BuildContext context)=>AppScope(controller:controller,
  child:AnimatedBuilder(animation:controller,
  builder:(context,
  _)=>MaterialApp(title:'Stay Sync Manage',
  debugShowCheckedModeBanner:false,
  theme:buildPgTheme(),
  darkTheme:ThemeData(useMaterial3:true,
  brightness:Brightness.dark,
  colorSchemeSeed:lavender,
  scaffoldBackgroundColor:const Color(0xFF271A2F),
  cardTheme:CardThemeData(color:const Color(0xFF37243F),
  shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(22)))),
  themeMode:controller.themeMode,
  locale:Locale(controller.languageCode),
  supportedLocales:const [Locale('en'),Locale('hi'),Locale('ta'),Locale('te'),Locale('kn'),Locale('ml')],
  localizationsDelegates:const [GlobalMaterialLocalizations.delegate,GlobalWidgetsLocalizations.delegate,GlobalCupertinoLocalizations.delegate],
  home:controller.restoring?const SplashScreen():!controller.onboardingSeen?const WelcomeScreen():!controller.signedIn?const SignInScreen():controller.profile['must_change_password']==true?const FirstLoginPasswordPage():controller.profile['role']=='resident' && (controller.data['identity_onboarding'] as Map?)?['needs_submission']==true?const IdentityProofPage():const AppShell())));
}

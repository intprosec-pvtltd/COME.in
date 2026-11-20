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
  home:controller.restoring?const SplashScreen():!controller.onboardingSeen?const WelcomeScreen():!controller.signedIn?const SignInScreen():controller.profile['must_change_password']==true?const FirstLoginPasswordPage():controller.profile['role']=='resident' && (controller.data['identity_onboarding'] as Map?)?['needs_submission']==true?const IdentityProofPage():SubscriptionAccessGate(controller:controller))));
}


/// Subscription gate applies to owner organizations after server enforcement
/// has been enabled. All actual permissions are enforced independently by API.
class SubscriptionAccessGate extends StatefulWidget {
  const SubscriptionAccessGate({super.key,required this.controller});
  final AppController controller;
  @override State<SubscriptionAccessGate> createState()=>_SubscriptionAccessGateState();
}
class _SubscriptionAccessGateState extends State<SubscriptionAccessGate> {
  bool busy=false;
  String? error;
  Future<void> startTrial() async {
    setState(() {busy=true;error=null;});
    try {
      await widget.controller.mutate('/trial/start');
    } catch(e) {
      if(mounted)setState(()=>error='Could not start trial. Please refresh or contact support.');
    } finally {
      if(mounted)setState(()=>busy=false);
    }
  }
  @override Widget build(BuildContext context) {
    final c=widget.controller;
    final trial=c.trial;
    final status='${trial?['status']??''}';
    final gated=c.profile['role']=='owner' && trial?['enforcement_enabled']==true
      && const {'pending','trial_expired','paid_expired','suspended'}.contains(status);
    if(!gated) return const AppShell();
    final pending=status=='pending';
    return Scaffold(
      appBar:AppBar(title:const Text('Stay Sync subscription')),
      body:SafeArea(child:Center(child:ConstrainedBox(
        constraints:const BoxConstraints(maxWidth:440),
        child:ListView(shrinkWrap:true,padding:const EdgeInsets.all(24),children:[
          Icon(pending?Icons.timelapse:Icons.lock_clock_outlined,size:58,color:const Color(0xff68427b)),
          const SizedBox(height:18),
          Text(pending?'Choose your plan':'Payment required to continue',
            textAlign:TextAlign.center,style:const TextStyle(fontSize:23,fontWeight:FontWeight.w800)),
          const SizedBox(height:12),
          Text(pending?'Try Stay Sync free for 15 days, or subscribe now.'
              :'Your plan has ended. Make a payment to continue using Stay Sync.',
              textAlign:TextAlign.center),
          const SizedBox(height:22),
          const Text('₹39 per person / month + GST',textAlign:TextAlign.center),
          const SizedBox(height:20),
          if(pending)FilledButton.icon(onPressed:busy?null:startTrial,
              icon:const Icon(Icons.hourglass_top),label:const Text('Start 15-day free trial')),
          const SizedBox(height:10),
          OutlinedButton.icon(onPressed:busy?null:()=>openPage(context,'ownerSubscription'),
              icon:const Icon(Icons.payments_outlined),label:const Text('View bill & pay')),
          TextButton(onPressed:busy?null:() async {
            setState(()=>busy=true);
            try{await c.refresh();}catch(_){ if(mounted)setState(()=>error='Could not refresh subscription status.'); }
            finally{if(mounted)setState(()=>busy=false);}
          },child:const Text('Refresh payment status')),
          TextButton(onPressed:busy?null:()=>c.logout(),child:const Text('Sign out')),
          if(error!=null)Padding(padding:const EdgeInsets.all(8),child:Text(error!,textAlign:TextAlign.center,
              style:const TextStyle(color:Colors.red))),
          if(busy)const Center(child:CircularProgressIndicator()),
          const SizedBox(height:12),
          const Text('Your information stays saved.',textAlign:TextAlign.center,
              style:TextStyle(fontSize:12)),
        ]),
      ))),
    );
  }
}

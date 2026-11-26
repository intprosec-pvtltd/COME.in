import '../../core/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../app/controller.dart';
import '../../core/design.dart';
import '../../core/app_theme.dart';
import 'phone_verification.dart';
import '../account/legal_content.dart';
import '../../core/email_validation.dart';
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final PageController pages = PageController();
  int index = 0;
  static const titles = [
    'Manage your PG, all in one place.',
    'Simplify rent and payment management.',
    'Manage better. Stay connected.',
  ];
  static const descriptions = [
    'Effortlessly manage rooms, beds, residents and daily operations through one simple, organized platform.',
    'Track rent, manage payments, monitor dues and keep financial records organized with ease.',
    'Handle maintenance requests, share announcements and keep owners, residents and staff connected.',
  ];
  @override
  void dispose() { pages.dispose(); super.dispose(); }
  void next() {
    if (index == 2) {
      AppScope.of(context).finishOnboarding();
    } else {
      pages.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeInOut);
    }
  }
  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(children: [
            SizedBox(height: 60, child: Row(children: [
              Transform.translate(offset: const Offset(-18, 0), child: const OfficialBrand(width: 124)),
              const Spacer(),
              TextButton(onPressed: () => AppScope.of(context).finishOnboarding(),
                child: const Text('Skip', style: TextStyle(fontWeight: FontWeight.w700))),
            ])),
            const SizedBox(height: 15),
            Expanded(child: PageView.builder(
              controller: pages,
              itemCount: 3,
              onPageChanged: (v) => setState(() => index = v),
              itemBuilder: (context, i) => LayoutBuilder(
                builder: (context, bounds) => SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ClipRRect(borderRadius: BorderRadius.circular(25),
                      child: Image.asset('assets/onboarding/illustration_${i+1}.png',
                        width: double.infinity,
                        height: bounds.maxHeight < 400 ? 160 : (bounds.maxHeight * .54).clamp(185.0, screen.height * .37 > 185 ? screen.height * .37 : 185.0).toDouble(),
                        fit: BoxFit.cover)),
                    const SizedBox(height: 21),
                    Text('YOUR NEXT CHAPTER  /  0${i+1}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11,
                        letterSpacing: 2, color: lavender)),
                    const SizedBox(height: 12),
                    Text(titles[i], style: const TextStyle(fontWeight: FontWeight.w900,
                      fontSize: 31, height: 1.13, color: Color(0xFF351339))),
                    const SizedBox(height: 15),
                    Text(descriptions[i], style: const TextStyle(fontSize: 15,
                      height: 1.55, color: muted)),
                  ]),
                ),
              ),
            )),
            Row(mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 230),
                margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
                height: 8, width: i == index ? 27 : 8,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(9),
                  color: i == index ? lavender : const Color(0xFFE9D6F5))))),
            const SizedBox(height: 7),
            Row(children: [
              if (index > 0) ...[
                TextButton(onPressed: () => pages.previousPage(
                  duration: const Duration(milliseconds: 300), curve: Curves.easeInOut),
                  child: const Text('Back')),
                const SizedBox(width: 9),
              ],
              Expanded(child: FilledButton(
                onPressed: next,
                child: Row(mainAxisSize:MainAxisSize.min,children:[
                  Text(index == 2 ? 'Get started' : 'Next'),
                  if(index != 2) ...[const SizedBox(width:8),const Icon(Icons.arrow_forward_rounded,size:19)],
                ]),
              )),
            ]),
            TextButton(onPressed: () => AppScope.of(context).finishOnboarding(),
              child: const Text('Already have an account? Sign in')),
            const Attribution(),
          ]),
        ),
      ),
    );
  }
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key
  });
  @override State<SignInScreen> createState()=>_SignInScreenState();
} class _SignInScreenState extends State<SignInScreen>{
  final form=GlobalKey<FormState>();
  final phone=TextEditingController(),
  password=TextEditingController();
  bool hidden=true,
  remember=true,
  busy=false;
  String? error;
  bool _initialPhoneLoaded=false;
  bool _showActivationAfterFailure=false;
  @override void didChangeDependencies(){
    super.didChangeDependencies();
    if (!_initialPhoneLoaded) {
      _initialPhoneLoaded=true;
      phone.text=AppScope.of(context).lastVerifiedMobile??'';
    }
  }
  @override void dispose(){
    phone.dispose();
    password.dispose();
    super.dispose();
  } Future<void> login()async{
    if(busy||!form.currentState!.validate())return;
    setState((){
      busy=true;
      error=null;
    });
    try{
      await AppScope.of(context).login(normalizeMobile(phone.text)!,
      password.text,
      remember);
    }catch(e){
      if(mounted)setState(() {
        error='$e';
        _showActivationAfterFailure='$e'.contains('activate mobile login first');
      });
    }finally{
      if(mounted)setState(()=>busy=false);
    }
  } @override Widget build(BuildContext context)=>_AuthScaffold(
    backgroundAsset:'assets/auth/login_background.png',
    topSpace:260,
    builder:(context,limits,keyboardOpen){
      return Column(mainAxisSize:MainAxisSize.min,children:[
        const _AuthBrand(),
        const SizedBox(height:8),
        Text(tr(context,'Welcome back!'),textAlign:TextAlign.center,
          softWrap:true,
          style:const TextStyle(fontSize:29,fontWeight:FontWeight.w900,height:1.12,color:plum)),
        const SizedBox(height:4),
        // Readable copy directly on the illustration, without a white background.
        Text('Same spaces. Brighter days.',
          textAlign:TextAlign.center,
          softWrap:true,
          style:const TextStyle(fontSize:14,fontWeight:FontWeight.w800,
            color:Color(0xFF351339),height:1.3,
            shadows:[Shadow(color:Color(0x66FFFFFF),blurRadius:5)])),
        const SizedBox(height:12),
        Form(key:form,child:Column(mainAxisSize:MainAxisSize.min,children:[
          _AuthField(child:TextFormField(controller:phone,keyboardType:TextInputType.phone,
            onChanged: (_) => setState(() => _showActivationAfterFailure=false),
            autofillHints:const [AutofillHints.telephoneNumber],textInputAction:TextInputAction.next,
            decoration:mobileDecoration(context, phone.text),
            validator:(v)=>mobileError(context,v))),
          const SizedBox(height:10),
          _AuthField(child:TextFormField(controller:password,obscureText:hidden,
            autofillHints:const [AutofillHints.password],textInputAction:TextInputAction.done,
            decoration:InputDecoration(hintText:tr(context,'Password'),prefixIcon:const Icon(Icons.lock_outline),
              suffixIcon:IconButton(tooltip:hidden?'Show password':'Hide password',
                onPressed:()=>setState(()=>hidden=!hidden),icon:Icon(hidden?Icons.visibility_outlined:Icons.visibility_off_outlined))),
            validator:(v)=>v==null||v.isEmpty?tr(context,'Enter your password'):null,onFieldSubmitted:(_)=>login())),
          const SizedBox(height:6),
          // Independent rows give every language enough horizontal room.
          // Long Tamil/Malayalam translations no longer collapse into letters.
          Row(children:[
            SizedBox(width:36,height:40,child:Checkbox(value:remember,activeColor:plum,
              onChanged:(v)=>setState(()=>remember=v??false))),
            const SizedBox(width:5),
            Expanded(child:Text(tr(context,'Keep me signed in'),
              maxLines:2,softWrap:true,
              style:const TextStyle(fontSize:13,color:Color(0xFF76657C)))),
          ]),
          Align(alignment:Alignment.centerRight,child:TextButton(
            onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>const RecoveryScreen())),
            child:Text(tr(context,'Forgot password?'),textAlign:TextAlign.end,
              style:const TextStyle(fontSize:13,fontWeight:FontWeight.w700,color:plum)))),
          if(error!=null)Padding(padding:const EdgeInsets.only(bottom:5),child:Text(error!,style:const TextStyle(color:Colors.red,fontSize:12))),
          const SizedBox(height:5),
          _AuthPrimary(label:tr(context,'Sign in'),busy:busy,onPressed:login),
        ])),
        const SizedBox(height:5),
        TextButton(onPressed:() async {
          final registered=await Navigator.push<String>(context,MaterialPageRoute(builder:(_)=>const RegistrationScreen()));
          if(mounted && registered!=null) {
            setState(() { phone.text=registered; error=null; _showActivationAfterFailure=false; });
          }
        },
          child:Text(tr(context,'Create account'),textAlign:TextAlign.center,
            style:const TextStyle(color:plum,fontWeight:FontWeight.w800,fontSize:15))),
        if (_showActivationAfterFailure || !AppScope.of(context).isKnownVerifiedMobile(normalizeMobile(phone.text)))
        TextButton(onPressed: () async {
          final activated = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ActivateMobilePage()));
          if (mounted && activated != null) {
            await AppScope.of(context).rememberVerifiedMobile(activated);
            if (!mounted) return;
            setState(() { phone.text = activated; error = null; _showActivationAfterFailure=false; });
            feedback(context, 'Mobile verified. Sign in with your existing password.');
          }
        }, child: Text(tr(context,'Activate mobile login'),textAlign:TextAlign.center,
          style:const TextStyle(color:plum,fontWeight:FontWeight.w700))),
        const _AuthSocialInfo(),
        const _AuthWhiteFooter(),
      ]);
    });
} class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({
    super.key
  });
  @override State<RegistrationScreen> createState()=>_RegistrationScreenState();
} class _RegistrationScreenState extends State<RegistrationScreen>{
  final form=GlobalKey<FormState>();
  final controls={
    for(final k in [
      'name',
      'email',
      'phone',
      'password',
      'property_name',
      'joining_code'
    ])k:TextEditingController()
  };
  String role='owner';
  final confirmPassword=TextEditingController();
  bool busy=false,
  terms=false;
  bool showSignupPassword=false;
  bool showConfirmPassword=false;
  String? error;
  @override void dispose(){
    for(final c in controls.values)c.dispose();
    confirmPassword.dispose();
    super.dispose();
  } Future<void> submit()async{
    if(busy)return;
    if(!form.currentState!.validate()||!terms){
      setState(()=>error=tr(context,'Complete the required fields and accept the terms.'));
      return;
    }setState(()=>busy=true);
    try{
      final api = AppScope.of(context).api;
      final phone = normalizeMobile(controls['phone']!.text)!;
      final data = <String,dynamic>{
        for(final key in ['name','email','property_name']) key:controls[key]!.text.trim(),
        'phone':phone, 'password':controls['password']!.text, 'role':role, 'legal_version':policyVersion,
      };
      Future<void> send() async {
        await api.request('/v3/phone/register/request',method:'POST',body:{'phone':phone});
      }
      await send();
      if (!mounted) return;
      final result = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => PhoneCodePage(
        phone:phone, resend:send, verify:(code) async {
          await api.request('/v3/phone/register',method:'POST',body:{...data,'code':code});
          return 'verified';
        })));
      if(mounted && result == 'verified'){
        await AppScope.of(context).rememberVerifiedMobile(phone);
        if (!mounted) return;
        feedback(context,tr(context,'Account created. You can now sign in.'));
        Navigator.pop(context,phone);
      }
    }catch(e){
      if(mounted)setState(()=>error='$e');
    }finally{
      if(mounted)setState(()=>busy=false);
    }
  } @override Widget build(BuildContext context)=>_AuthScaffold(
  backgroundAsset:'assets/auth/signup_background.png',
  topSpace:265,
  builder:(context,limits,keyboardOpen)=>Column(mainAxisSize:MainAxisSize.min,children:[
    const _AuthBrand(),
    const SizedBox(height:8),
    // No opaque card behind the registration headline: retain artwork.
    Text(tr(context,'Create your account'),textAlign:TextAlign.center,
      softWrap:true,style:const TextStyle(fontSize:28,fontWeight:FontWeight.w900,height:1.14,color:plum)),
    const SizedBox(height:5),
    Text(tr(context,'Join your space. Start your stay.'),textAlign:TextAlign.center,
      style:const TextStyle(fontSize:14,color:Color(0xFF84718B),fontStyle:FontStyle.italic)),
    const SizedBox(height:12),
    Form(key:form,child:Column(mainAxisSize:MainAxisSize.min,children:[
      for(final key in ['name','email','phone','password','property_name']) ...[
        _AuthField(child:TextFormField(controller:controls[key],obscureText:key=='password'&&!showSignupPassword,
          keyboardType:key=='phone'?TextInputType.phone:key=='email'?TextInputType.emailAddress:TextInputType.text,
          textInputAction:TextInputAction.next,
          onChanged: key=='phone' ? (_) => setState(() {}) : null,
          autovalidateMode: key=='email' ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
          decoration:key=='phone' ? mobileDecoration(context, controls[key]!.text) : InputDecoration(
            prefixIcon:Icon(key=='name'?Icons.person_outline:key=='password'?Icons.lock_outline:key=='phone'?Icons.phone_outlined:key=='property_name'?Icons.home_outlined:Icons.mail_outline),
            hintText:tr(context,{'name':'Full Name','email':'Email','phone':'Phone Number','password':'Password','property_name':'Property Name'}[key]!),
            suffixIcon:key=='password'?IconButton(
              tooltip:showSignupPassword?'Hide password':'Show password',
              onPressed:()=>setState(()=>showSignupPassword=!showSignupPassword),
              icon:Icon(showSignupPassword?Icons.visibility_off_outlined:Icons.visibility_outlined),
            ):null),
          validator:(v)=>v==null||v.trim().isEmpty?tr(context,'Required'):key=='phone'&&normalizeMobile(v)==null?tr(context,'Enter a valid mobile number'):key=='password'&&v.length<8?tr(context,'Use at least 8 characters'):key=='email'?emailError(v):null)),
        const SizedBox(height:10),
      ],
      _AuthField(child:TextFormField(controller:confirmPassword,obscureText:!showConfirmPassword,
        textInputAction:TextInputAction.done,
        decoration:InputDecoration(hintText:tr(context,'Confirm Password'),prefixIcon:const Icon(Icons.lock_outline),
          suffixIcon:IconButton(tooltip:showConfirmPassword?'Hide confirmation':'Show confirmation',
            onPressed:()=>setState(()=>showConfirmPassword=!showConfirmPassword),
            icon:Icon(showConfirmPassword?Icons.visibility_off_outlined:Icons.visibility_outlined))),
        validator:(v)=>v!=controls['password']!.text?tr(context,'Passwords do not match'):null)),
      const SizedBox(height:10),
      Padding(padding:const EdgeInsets.symmetric(vertical:8),
        child:Text(tr(context,'Registration is for PG owners. Residents receive their sign-in details from the owner.'),
          textAlign:TextAlign.center,style:const TextStyle(fontSize:12,color:Color(0xFF806C86)))),
      // The checkbox label expands across the screen; it never goes under the
      // Android navigation area because _AuthScaffold scrolls with safe insets.
      TextButton(
        onPressed:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>const LegalDocument())),
        child:const Text('Read privacy policy and terms'),
      ),
      CheckboxListTile(contentPadding:EdgeInsets.zero,controlAffinity:ListTileControlAffinity.leading,
        activeColor:plum,value:terms,onChanged:(v)=>setState(()=>terms=v??false),
        title:Text(tr(context,'I agree to the Terms & Conditions and privacy policy'),
          softWrap:true,style:const TextStyle(fontSize:12,color:plum))),
      if(error!=null)Padding(padding:const EdgeInsets.only(bottom:8),child:Text(error!,style:const TextStyle(color:Colors.red,fontSize:12))),
      const SizedBox(height:10),
      _AuthPrimary(label:tr(context,'Create account'),busy:busy,onPressed:submit),
    ])),
    const SizedBox(height:11),
    TextButton(onPressed:()=>Navigator.pop(context),
      child:Text(tr(context,'Already have an account? Sign in'),textAlign:TextAlign.center,
        style:const TextStyle(color:plum,fontWeight:FontWeight.w700))),
    const SizedBox(height:10),
    const _AuthWhiteFooter(),
  ]));
} class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key});
  @override State<RecoveryScreen> createState()=>_RecoveryScreenState();
}
class _RecoveryScreenState extends State<RecoveryScreen>{
  final phone=TextEditingController();
  final form=GlobalKey<FormState>();
  bool busy=false;
  String? message;
  @override void dispose(){phone.dispose();super.dispose();}
  Future<void> recover() async {
    if(busy||!form.currentState!.validate())return;
    final api=AppScope.of(context).api;
    final number=normalizeMobile(phone.text)!;
    setState((){busy=true;message=null;});
    try{
      Future<void> send() async {await api.request('/v3/phone/forgot-password',method:'POST',body:{'phone':number});}
      await send();
      if(!mounted)return;
      final token=await Navigator.of(context).push<String>(MaterialPageRoute(builder:(_)=>PhoneCodePage(
        phone:number,resend:send,verify:(code) async {
          final result=await api.request('/v3/phone/reset/verify',method:'POST',body:{'phone':number,'code':code});
          return result['reset_token'] as String;
        })));
      if(!mounted||token==null)return;
      await Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>ResetPasswordScreen(phone:number,resetToken:token)));
    }catch(e){if(mounted)setState(()=>message='$e');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>PageBody(title:'Reset password',
    subtitle:'Enter your verified mobile number to receive an SMS verification code.',children:[
    Surface(child:Form(key:form,child:Column(children:[
      TextFormField(controller:phone,keyboardType:TextInputType.phone,
        decoration:mobileDecoration(context, phone.text, label:true),
        onChanged: (_) => setState(() {}),
        validator:(v)=>mobileError(context,v)),
      const SizedBox(height:15),
      FilledButton(onPressed:busy?null:recover,child:Text(busy?'Requesting…':'Send SMS code')),
      if(message!=null)Padding(padding:const EdgeInsets.only(top:15),child:Text(message!)),
      const SizedBox(height:10),
      const Text('If you have not activated mobile login yet, activate it using your existing account credentials or contact your PG administrator.'),
    ])))
  ]);
} class DoorwayIllustration extends StatelessWidget {
  const DoorwayIllustration({
    super.key
  });
  @override Widget build(BuildContext context)=>SizedBox(width:145,
  height:150,
  child:Stack(children:[
    
    Positioned(left:0,
    bottom:0,
    child:SvgPicture.asset('assets/onboarding/traveler1.svg',
    width:47,
    height:70)),
    Positioned(right:0,
    bottom:0,
    child:SvgPicture.asset('assets/onboarding/traveler2.svg',
    width:47,
    height:70))
  ]));
} class SplashScreen extends StatelessWidget {
  const SplashScreen({
    super.key
  });
  @override Widget build(BuildContext context)=>const Scaffold(body:SafeArea(child:Center(child:Column(mainAxisSize:MainAxisSize.min,
  children:[
    
    OfficialBrand(width:190),
    SizedBox(height:16),
    SizedBox(width:24,
    height:24,
    child:CircularProgressIndicator(strokeWidth:2)),
    Attribution()
  ]))));
} class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key,required this.phone,required this.resetToken});
  final String phone,resetToken;
  @override State<ResetPasswordScreen> createState()=>_ResetPasswordScreenState();
}
class _ResetPasswordScreenState extends State<ResetPasswordScreen>{
  bool showPassword=false,showConfirm=false,busy=false;
  final form=GlobalKey<FormState>();
  final password=TextEditingController(),confirm=TextEditingController();
  @override void dispose(){password.dispose();confirm.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>PageBody(title:'Choose a new password',
    subtitle:'Mobile number verified. Complete password reset within five minutes.',children:[
    Surface(child:Form(key:form,child:Column(children:[
      TextFormField(controller:password,obscureText:!showPassword,
        decoration:InputDecoration(labelText:'New password',suffixIcon:IconButton(tooltip:showPassword?'Hide password':'Show password',icon:Icon(showPassword?Icons.visibility_off_outlined:Icons.visibility_outlined),onPressed:()=>setState(()=>showPassword=!showPassword))),
        validator:(v)=>(v??'').length<8||(v??'').length>128?'Use 8–128 characters':null),
      const SizedBox(height:15),
      TextFormField(controller:confirm,obscureText:!showConfirm,
        decoration:InputDecoration(labelText:'Confirm new password',suffixIcon:IconButton(onPressed:()=>setState(()=>showConfirm=!showConfirm),icon:Icon(showConfirm?Icons.visibility_off_outlined:Icons.visibility_outlined))),
        validator:(v)=>v==password.text?null:'Passwords do not match'),
      const SizedBox(height:20),
      FilledButton(onPressed:busy?null:()async{
        if(!form.currentState!.validate())return;
        setState(()=>busy=true);
        final api=AppScope.of(context).api;
        final ok=await perform(context,()async{
          await api.request('/v3/phone/reset-password',method:'POST',body:{'phone':widget.phone,'reset_token':widget.resetToken,'new_password':password.text});
        },success:'Password reset. Sign in with your new password.');
        if(mounted){setState(()=>busy=false);if(ok)Navigator.of(context).popUntil((r)=>r.isFirst);}
      },child:Text(busy?'Updating…':'Reset password')),
    ])))
  ]);
}

// The auth form always lives in one bounded scrolling viewport. The sign-in
// view fits normally on a phone but can scroll immediately when the keyboard
// opens or accessibility text scaling increases. No vertical Expanded is used.
// Responsive image-backed authentication screen. Forms and API handlers stay intact.
// Decorative images do not contain fields or logos: these are native Flutter widgets.
class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({
    this.child,
    this.builder,
    required this.backgroundAsset,
    required this.topSpace,
  }) : assert(child != null || builder != null);

  final Widget? child;
  final Widget Function(BuildContext, BoxConstraints, bool)? builder;
  final String backgroundAsset;
  final double topSpace;

  @override
  Widget build(BuildContext context) => Scaffold(
    // Keep the background and the form at the same visual scale when the
    // keyboard opens. Shrink the scroll viewport using bottom padding,
    // rather than resizing the entire illustration or fitting the form.
    resizeToAvoidBottomInset: false,
    backgroundColor: const Color(0xFFF8E5F9),
    body: LayoutBuilder(builder: (context, limits) {
      final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
      final keyboardOpen = keyboardInset > 0;
      final content = builder?.call(context, limits, keyboardOpen) ?? child!;
      final safeTop = MediaQuery.paddingOf(context).top;
      final safeBottom = MediaQuery.paddingOf(context).bottom;
      // The welcome artwork needs a generous top margin normally, but that
      // margin must disappear when the Android keyboard consumes the screen.
      // Otherwise the text fields are positioned behind the keyboard.
      // A fixed 260px gap previously pushed the footer behind Android's
      // navigation bar on compact phones. Reserve actual room for the form.
      // The full-height hero artwork itself remains unchanged.
      final available = limits.maxHeight - safeTop - safeBottom;
      final top = keyboardOpen
          ? 8.0
          : (available - 620.0).clamp(90.0, topSpace).toDouble();

      final contentBody = Padding(
        padding: const EdgeInsets.fromLTRB(23, 18, 23, 22),
        child: content,
      );
      // Login stays fixed in the ordinary device layout. If a compact
      // screen or large accessibility text would clip controls, allow
      // natural scrolling. Sign-up always remains scrollable.

      return Stack(children: [
        Positioned.fill(
          child: Image.asset(
            'assets/branding/mobile_login_background.png',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            semanticLabel: 'Co-living PG community artwork',
          ),
        ),
          Positioned.fill(
          // Constrain the scrolling viewport to the area above the keyboard.
          // Padding alone would leave the scrollable viewport behind the IME.
          bottom: keyboardInset,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const ClampingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              16,
              top + safeTop,
              16,
              safeBottom + 76,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: contentBody,
              ),
            ),
          ),
        ),
      ]);
    }),
  );
}

class _AuthBrand extends StatelessWidget {
  const _AuthBrand();
  @override
  Widget build(BuildContext context)=>Image.asset(
    'assets/branding/stay_sync_logo_transparent.png',
    width:190,height:124,fit:BoxFit.contain,
    semanticLabel:'COME.in Ã¢â‚¬â€ Spaces People Belong',
  );
}
class _AuthField extends StatelessWidget {
  const _AuthField({required this.child});
  final Widget child;
  @override Widget build(BuildContext context)=>Theme(
    data:buildPgTheme().copyWith(inputDecorationTheme:InputDecorationTheme(
      filled:true,fillColor:Colors.white,
      contentPadding:const EdgeInsets.symmetric(vertical:16,horizontal:14),
      prefixIconColor:plum,
      hintStyle:const TextStyle(color:Color(0xFF76657C),fontSize:15),
      helperStyle:const TextStyle(color:Color(0xFF59445F),fontSize:12),
      suffixIconColor:plum,
      border:OutlineInputBorder(borderRadius:BorderRadius.circular(30),borderSide:const BorderSide(color:Color(0xFFDDCEDC))),
      enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(30),borderSide:const BorderSide(color:Color(0xFFDDCEDC))),
      focusedBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(30),borderSide:const BorderSide(color:plum,width:1.6)))),
    child:child);
}
class _AuthPrimary extends StatelessWidget {
  const _AuthPrimary({required this.label,required this.busy,required this.onPressed});
  final String label;
  final bool busy;
  final VoidCallback onPressed;
  @override Widget build(BuildContext context)=>SizedBox(width:double.infinity,height:51,
    child:FilledButton(style:FilledButton.styleFrom(backgroundColor:plum,foregroundColor:Colors.white,
      shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(30))),
      onPressed:busy?null:onPressed,
      child:busy?const SizedBox(height:23,width:23,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)):
        Text(label,style:const TextStyle(fontSize:19,fontWeight:FontWeight.w800))));
}
// Match the company attribution used on Profile / Your account exactly.
class _AuthWhiteFooter extends StatelessWidget {
  const _AuthWhiteFooter();
  @override
  Widget build(BuildContext context) => Theme(data:buildPgTheme(),child:const Attribution());
}
class _AuthArtwork extends StatefulWidget {
  const _AuthArtwork({required this.asset});
  final String asset;
  @override State<_AuthArtwork> createState()=>_AuthArtworkState();
}
class _AuthArtworkState extends State<_AuthArtwork> with SingleTickerProviderStateMixin {
  late final AnimationController ripple=AnimationController(vsync:this,duration:const Duration(milliseconds:950));
  Offset touch=const Offset(.5,.5);
  @override void dispose(){ripple.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>Semantics(
    label:'Interactive illustration of residents arriving at a PG; tap for a ripple',
    button:true,
    child:GestureDetector(behavior:HitTestBehavior.opaque,
      onTapDown:(details){
        final box=context.findRenderObject();
        if(box is RenderBox && box.size.width>0 && box.size.height>0){
          touch=Offset((details.localPosition.dx/box.size.width).clamp(0.0,1.0),
            (details.localPosition.dy/box.size.height).clamp(0.0,1.0));
        }
        ripple.forward(from:0);
      },
      child:SizedBox(width:double.infinity,height:260,
        child:Stack(fit:StackFit.expand,children:[
          Image.asset(widget.asset,fit:BoxFit.cover,alignment:Alignment.center),
          AnimatedBuilder(animation:ripple,builder:(context,child)=>CustomPaint(
            painter:_PondRipple(progress:ripple.value,position:touch),child:child)),
        ]))));
}
class _PondRipple extends CustomPainter {
  const _PondRipple({required this.progress,required this.position});
  final double progress;
  final Offset position;
  @override void paint(Canvas canvas,Size size){
    if(progress<=0||progress>=1)return;
    final center=Offset(size.width*position.dx,size.height*position.dy);
    final maxRadius=size.longestSide*.65;
    for(var n=0;n<3;n++){
      final phase=(progress-n*.13).clamp(0.0,1.0);
      if(phase<=0)continue;
      final paint=Paint()..style=PaintingStyle.stroke
        ..strokeWidth=2.5*(1-phase)+.5
        ..color=Colors.white.withValues(alpha:(1-phase)*.75);
      canvas.drawCircle(center,maxRadius*phase,paint);
    }
  }
  @override bool shouldRepaint(covariant _PondRipple old)=>old.progress!=progress||old.position!=position;
}

// Authentication providers must not be presented as working until configured.
class _AuthSocialInfo extends StatelessWidget {
  const _AuthSocialInfo();
  @override Widget build(BuildContext context) => const Padding(
    padding:EdgeInsets.symmetric(vertical:5),
    child:Text('Secure sign-in with your Stay Sync account',
      textAlign:TextAlign.center,
      style:TextStyle(fontSize:12,fontWeight:FontWeight.w800,
        color:Color(0xFF351339),
        shadows:[Shadow(color:Color(0x66FFFFFF),blurRadius:4)])));
}

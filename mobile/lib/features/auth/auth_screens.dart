import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../app/controller.dart';
import '../../core/design.dart';
import '../../core/app_theme.dart';
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final PageController pages = PageController();
  int index = 0;
  static const titles = [
    'A fresh start, a place to belong.',
    'Make every day feel like home.',
    'Your PG life, all in one place.',
  ];
  static const descriptions = [
    'Move in with confidence. Settle into a welcoming space and start your next chapter.',
    'Connect with roommates, stay in the loop, and feel at home from day one.',
    'Track rent, raise requests, see announcements, and connect with your community in one app.',
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
              const OfficialBrand(width: 154),
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
  final email=TextEditingController(),
  password=TextEditingController();
  bool hidden=true,
  remember=true,
  busy=false;
  String? error;
  @override void dispose(){
    email.dispose();
    password.dispose();
    super.dispose();
  } Future<void> login()async{
    if(!form.currentState!.validate())return;
    setState((){
      busy=true;
      error=null;
    });
    try{
      await AppScope.of(context).login(email.text.trim(),
      password.text,
      remember);
    }catch(e){
      if(mounted)setState(()=>error='$e');
    }finally{
      if(mounted)setState(()=>busy=false);
    }
  } @override Widget build(BuildContext context)=>_AuthScaffold(
    backgroundAsset:'assets/auth/login_background.png',
    topSpace:260,
    fixedWhenKeyboardClosed: false,
    builder:(context,limits,keyboardOpen){
      // The keyboard reduces limits.maxHeight. Never use Expanded/Flexible in
      // the scrolling auth content: it caused the 317px overflow on Android.
      return Column(mainAxisSize:MainAxisSize.min,children:[
        // Keep the illustration and full welcome section on the normal screen.
        // When the keyboard is open, prioritize the credential fields so they
        // remain visible above the IME instead of overlapping the hero artwork.
        if (!keyboardOpen) ...[
          const SizedBox(height:5),
          const _AuthBrand(),
          const SizedBox(height:16),
          const Text('Welcome back!',style:TextStyle(fontSize:32,fontWeight:FontWeight.w900,color:plum)),
          const SizedBox(height:2),
          const Text('Same spaces. Brighter days.',style:TextStyle(fontSize:14,color:Color(0xFF84718B))),
          const SizedBox(height:12),
        ] else ...[
          const SizedBox(height:4),
          const Text('Sign in to COME.in',style:TextStyle(fontSize:22,fontWeight:FontWeight.w800,color:plum)),
          const SizedBox(height:12),
        ],
        Form(key:form,child:Column(mainAxisSize:MainAxisSize.min,children:[
          _AuthField(child:TextFormField(controller:email,keyboardType:TextInputType.emailAddress,
            autofillHints:const [AutofillHints.username],
            textInputAction:TextInputAction.next,
            decoration:const InputDecoration(hintText:'Email or Phone',prefixIcon:Icon(Icons.mail_outline)),
            validator:(v)=>v==null||(!v.contains('@')&&!RegExp(r'^\+?[0-9 ]{7,18}$').hasMatch(v))?'Enter your email or phone':null)),
          const SizedBox(height:10),
          _AuthField(child:TextFormField(controller:password,obscureText:hidden,
            autofillHints:const [AutofillHints.password],
            textInputAction:TextInputAction.done,
            decoration:InputDecoration(hintText:'Password',prefixIcon:const Icon(Icons.lock_outline),
              suffixIcon:IconButton(tooltip:hidden?'Show password':'Hide password',
                onPressed:()=>setState(()=>hidden=!hidden),icon:Icon(hidden?Icons.visibility_outlined:Icons.visibility_off_outlined))),
            validator:(v)=>v==null||v.isEmpty?'Enter your password':null,onFieldSubmitted:(_)=>login())),
          const SizedBox(height:5),
          Row(children:[
            SizedBox(width:32,height:36,child:Checkbox(value:remember,activeColor:plum,
              onChanged:(v)=>setState(()=>remember=v??false))),
            const Expanded(child:Text('Keep me signed in',style:TextStyle(fontSize:12,color:Color(0xFF76657C)))),
            TextButton(onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>const RecoveryScreen())),
              child:const Text('Forgot password?',style:TextStyle(fontSize:12,fontWeight:FontWeight.w700,color:plum)))
          ]),
          if(error!=null)Padding(padding:const EdgeInsets.only(bottom:5),child:Text(error!,style:const TextStyle(color:Colors.red,fontSize:12))),
          const SizedBox(height:6),
          _AuthPrimary(label:'Sign in',busy:busy,onPressed:login),
        ])),
        const SizedBox(height:3),
        TextButton(onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>const RegistrationScreen())),
          child:const Text('Create account',style:TextStyle(color:plum,fontWeight:FontWeight.w800,fontSize:15))),
        // Hide decorative content while typing; the form then scrolls naturally
        // inside the keyboard-reduced viewport without bottom overflow.
        if(!keyboardOpen) ...[
          const _AuthSocialInfo(),
          const _AuthWhiteFooter(),
        ],
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
  String? error;
  @override void dispose(){
    for(final c in controls.values)c.dispose();
    confirmPassword.dispose();
    super.dispose();
  } Future<void> submit()async{
    if(!form.currentState!.validate()||!terms){
      setState(()=>error='Complete the required fields and accept the terms.');
      return;
    }setState(()=>busy=true);
    try{
      await AppScope.of(context).api.request('/v3/register',
      method:'POST',
      body:{
        for(final e in controls.entries)e.key:e.value.text.trim(),
        'role':role
      });
      if(mounted){
        feedback(context,
        'Account created. You can now sign in.');
        Navigator.pop(context);
      }
    }catch(e){
      if(mounted)setState(()=>error='$e');
    }finally{
      if(mounted)setState(()=>busy=false);
    }
  } @override Widget build(BuildContext context)=>_AuthScaffold(
  backgroundAsset:'assets/auth/signup_background.png',
  topSpace:265,
  child:Column(children:[
    const SizedBox(height:8),
    const _AuthBrand(),
    const SizedBox(height:9),
    const SizedBox(height:11),
    const Text('Create your account',textAlign:TextAlign.center,style:TextStyle(fontSize:29,fontWeight:FontWeight.w900,color:plum)),
    const SizedBox(height:3),
    const Text('Join your space. Start your stay.',style:TextStyle(fontSize:15,color:Color(0xFF84718B),fontStyle:FontStyle.italic)),
    const SizedBox(height:14),
    Form(key:form,child:Column(children:[
      for(final key in ['name','email','phone','password','property_name']) ...[
        _AuthField(child:TextFormField(controller:controls[key],obscureText:key=='password',
          keyboardType:key=='phone'?TextInputType.phone:key=='email'?TextInputType.emailAddress:TextInputType.text,
          decoration:InputDecoration(
            prefixIcon:Icon(key=='name'?Icons.person_outline:key=='password'?Icons.lock_outline:key=='phone'?Icons.phone_outlined:key=='joining_code'?Icons.key_outlined:key=='property_name'?Icons.home_outlined:Icons.mail_outline),
            hintText:{'name':'Full Name','email':'Email','phone':'Phone Number','password':'Password','property_name':'Property Name','joining_code':'PG Joining Code'}[key],
            suffixIcon:key=='password'?const Icon(Icons.lock_reset_outlined,size:18):null),
          validator:(v)=>v==null||v.trim().isEmpty?'Required':key=='password'&&v.length<8?'Use at least 8 characters':key=='email'&&!v.contains('@')?'Enter a valid email':null)),
        const SizedBox(height:10),
      ],
      _AuthField(child:TextFormField(controller:confirmPassword,obscureText:true,
        decoration:const InputDecoration(hintText:'Confirm Password',prefixIcon:Icon(Icons.lock_outline)),
        validator:(v)=>v!=controls['password']!.text?'Passwords do not match':null)),
      const SizedBox(height:12),
      const Padding(padding:EdgeInsets.symmetric(vertical:9),child:Text('Registration is for PG owners. Residents receive their sign-in details from the owner.',textAlign:TextAlign.center,style:TextStyle(fontSize:12,color:Color(0xFF806C86)))),
      const SizedBox(height:12),
      CheckboxListTile(contentPadding:EdgeInsets.zero,controlAffinity:ListTileControlAffinity.leading,
        activeColor:plum,value:terms,onChanged:(v)=>setState(()=>terms=v??false),
        title:const Text('I agree to the Terms & Conditions and privacy policy',style:TextStyle(fontSize:12,color:plum))),
      if(error!=null)Padding(padding:const EdgeInsets.only(bottom:8),child:Text(error!,style:const TextStyle(color:Colors.red,fontSize:12))),
      const SizedBox(height:10),
      _AuthPrimary(label:'Create account',busy:busy,onPressed:submit),
    ])),
    const SizedBox(height:11),
    TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Already have an account? Sign in',
      style:TextStyle(color:plum,fontWeight:FontWeight.w700))),
    const SizedBox(height:10),
    const _AuthWhiteFooter(),
  ]));
} class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({
    super.key
  });
  @override State<RecoveryScreen> createState()=>_RecoveryScreenState();
} class _RecoveryScreenState extends State<RecoveryScreen>{
  final email=TextEditingController();
  bool busy=false;
  String? message;
  @override void dispose(){
    email.dispose();
    super.dispose();
  } @override Widget build(BuildContext context)=>PageBody(title:'Reset password',
  subtitle:'Recover access to your account',
  children:[
    Surface(child:Column(children:[
      TextField(controller:email,
      keyboardType:TextInputType.emailAddress,
      decoration:const InputDecoration(labelText:'Email or phone',prefixIcon:Icon(Icons.mail_outline))),
      const SizedBox(height:15),
      FilledButton(onPressed:busy?null:()async{
        setState(()=>busy=true);
        try{
          await AppScope.of(context).api.request('/v3/forgot-password',
          method:'POST',
          body:{
            'email':email.text.trim()
          });
          if(mounted){
            setState(()=>message='If the account exists, a reset code has been emailed.');
            await Navigator.push<void>(context,
            MaterialPageRoute(builder:(_)=>ResetPasswordScreen(email:email.text.trim())));
          }
        }catch(e){
          if(mounted)setState(()=>message='$e');
        }finally{
          if(mounted)setState(()=>busy=false);
        }
      },
      child:Text(busy?'Requestingâ€¦':'Request reset')),
      if(message!=null)Padding(padding:const EdgeInsets.only(top:15),
      child:Text(message!))
    ]))
  ]);
} class DoorwayIllustration extends StatelessWidget {
  const DoorwayIllustration({
    super.key
  });
  @override Widget build(BuildContext context)=>SizedBox(width:145,
  height:150,
  child:Stack(children:[
    const Positioned(left:13,
    top:0,
    child:OfficialBrand(width:120,
    iconOnly:true)),
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
    OfficialBrand(width:115,
    iconOnly:true),
    SizedBox(height:22),
    OfficialBrand(width:220),
    SizedBox(height:30),
    SizedBox(width:24,
    height:24,
    child:CircularProgressIndicator(strokeWidth:2)),
    Attribution()
  ]))));
} class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({
    super.key,
    required this.email
  });
  final String email;
  @override State<ResetPasswordScreen> createState()=>_ResetPasswordScreenState();
} class _ResetPasswordScreenState extends State<ResetPasswordScreen>{
  final form=GlobalKey<FormState>();
  final code=TextEditingController(),
  password=TextEditingController();
  bool busy=false;
  @override void dispose(){
    code.dispose();
    password.dispose();
    super.dispose();
  } @override Widget build(BuildContext context)=>PageBody(title:'Choose a new password',
  subtitle:'Enter the 6-digit code sent to ${widget.email}.',
  children:[
    Surface(child:Form(key:form,
    child:Column(children:[
      TextFormField(controller:code,
      keyboardType:TextInputType.number,
      maxLength:6,
      decoration:const InputDecoration(labelText:'Reset code'),
      validator:(v)=>RegExp(r'^\d{6}$').hasMatch(v??'')?null:'Enter the 6-digit code'),
      const SizedBox(height:15),
      TextFormField(controller:password,
      obscureText:true,
      decoration:const InputDecoration(labelText:'New password'),
      validator:(v)=>(v??'').length<8?'Use at least 8 characters':null),
      const SizedBox(height:20),
      FilledButton(onPressed:busy?null:()async{
        if(!form.currentState!.validate())return;
        setState(()=>busy=true);
        final ok=await perform(context,
        ()async{
          await AppScope.of(context).api.request('/v3/reset-password',
          method:'POST',
          body:{
            'email':widget.email,
            'code':code.text,
            'new_password':password.text
          });
        },
        success:'Password reset. Sign in with your new password.');
        if(mounted){
          setState(()=>busy=false);
          if(ok)Navigator.of(context).popUntil((r)=>r.isFirst);
        }
      },
      child:Text(busy?'Updatingâ€¦':'Reset password'))
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
    this.fixedWhenKeyboardClosed = false,
  }) : assert(child != null || builder != null);

  final Widget? child;
  final Widget Function(BuildContext, BoxConstraints, bool)? builder;
  final String backgroundAsset;
  final double topSpace;
  final bool fixedWhenKeyboardClosed;

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

      // Always permit scrolling. Otherwise the footer can be clipped while
      // the last controls are unreachable even before the keyboard opens.


      return Stack(children: [
        Positioned.fill(
          child: Image.asset(
            backgroundAsset,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            semanticLabel: 'Co-living PG community artwork',
          ),
        ),
        // A light scrim keeps the compact keyboard-open login readable over
        // the illustration without changing the ordinary COME.in design.
        if (keyboardOpen)
          const Positioned.fill(
            child: ColoredBox(color: Color(0xF5FFF3F2)),
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
              safeBottom + 36,
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
    'assets/brand/comein_auth_logo.png',
    width:235,height:92,fit:BoxFit.contain,
    semanticLabel:'COME.in â€” Spaces People Belong',
  );
}
class _AuthField extends StatelessWidget {
  const _AuthField({required this.child});
  final Widget child;
  @override Widget build(BuildContext context)=>Theme(
    data:Theme.of(context).copyWith(inputDecorationTheme:InputDecorationTheme(
      filled:true,fillColor:Colors.white,
      contentPadding:const EdgeInsets.symmetric(vertical:16,horizontal:14),
      prefixIconColor:plum,
      hintStyle:const TextStyle(color:Color(0xFF8D7990),fontSize:15),
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
  Widget build(BuildContext context) => const Attribution();
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
    child:Text('Secure sign-in with your COME.in account',
      textAlign:TextAlign.center,
      style:TextStyle(fontSize:11,color:Color(0xFF84718B))));
}

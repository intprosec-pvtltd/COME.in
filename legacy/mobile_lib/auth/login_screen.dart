import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../core/comein_widgets.dart';

class LoginPage extends StatefulWidget {
  final Future<void> Function(String, String) onLogin;
  const LoginPage({super.key, required this.onLogin});
  @override State<LoginPage> createState() => _LoginPageState();
}
class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final pass = TextEditingController();
  bool loading = false, obscure = true;
  String? error;
  @override void dispose() { email.dispose(); pass.dispose(); super.dispose(); }
  Future<void> signIn() async {
    if (email.text.trim().isEmpty || pass.text.isEmpty) {setState(() => error = 'Please enter your email and password.');return;}
    setState(() {loading = true;error = null;});
    try {await widget.onLogin(email.text.trim(),pass.text);}
    catch(e) {if(mounted)setState(()=>error='$e');}
    finally {if(mounted)setState(()=>loading=false);}
  }
  @override Widget build(BuildContext context) => Scaffold(body: SafeArea(child: SingleChildScrollView(child: Column(children: [
    Container(width: double.infinity, padding: const EdgeInsets.fromLTRB(28, 55, 28, 55), decoration: const BoxDecoration(gradient: LinearGradient(colors: [plum, Color(0xFF724D79)]), borderRadius: BorderRadius.only(bottomLeft: Radius.circular(38),bottomRight:Radius.circular(38))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const BrandMark(size: 50,wordmark:false),const SizedBox(height:20),
        const Text('COME.in',style:TextStyle(color:Colors.white,fontSize:35,fontWeight:FontWeight.w900)),
        const SizedBox(height:8),const Text('Spaces. People. Belong.',style:TextStyle(color:Color(0xFFF2DDE9),fontSize:15)),
        const SizedBox(height:18),const Text('Your place, your people, your everyday life.',style:TextStyle(color:Colors.white,fontWeight:FontWeight.w600)),
      ])),
    Padding(padding: const EdgeInsets.all(23), child: Card(child:Padding(padding:const EdgeInsets.all(22),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const Text('Welcome home',style:TextStyle(fontSize:25,fontWeight:FontWeight.w900,color:plum)),
      const SizedBox(height:6),const Text('One app for owners and residents.',style:TextStyle(color:muted)),
      const SizedBox(height:22),TextField(controller:email,keyboardType:TextInputType.emailAddress,autocorrect:false,decoration:const InputDecoration(labelText:'Email address',prefixIcon:Icon(Icons.alternate_email))),
      const SizedBox(height:13),TextField(controller:pass,obscureText:obscure,onSubmitted:(_)=>loading?null:signIn(),decoration:InputDecoration(labelText:'Password',prefixIcon:const Icon(Icons.lock_outline),suffixIcon:IconButton(onPressed:()=>setState(()=>obscure=!obscure),icon:Icon(obscure?Icons.visibility_outlined:Icons.visibility_off_outlined)))),
      if(error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(error!,style:const TextStyle(color:Colors.red))),
      const SizedBox(height:20),FilledButton(onPressed:loading?null:signIn,child:Text(loading?'Signing in…':'Sign in  →')),
      const SizedBox(height:14),const Text('Accounts are issued by your PG administrator. Contact your PG owner for access.',textAlign:TextAlign.center,style:TextStyle(fontSize:12,color:muted)),
    ]))))
  ]))));
}

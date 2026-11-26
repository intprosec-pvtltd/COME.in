import '../../core/localization.dart';
import '../../core/display_photo.dart';
import '../../core/email_validation.dart';
import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../app/router.dart';
import '../../core/design.dart';
import '../../core/app_theme.dart';
import 'app_feedback.dart';
import 'legal_content.dart';
class AccountPage extends StatelessWidget {
  const AccountPage({
    super.key
  });
  @override Widget build(BuildContext context){
    final app=AppScope.of(context),
    p=app.profile;
    return PageBody(title:'Your account',
    subtitle:'Manage your account and settings.',
    children:[
      Semantics(
        button: true,
        label: 'Open profile editor',
        child: Surface(
          onTap: ()=>openPage(context,'profileEditor'),
          child: Row(children:[
            DisplayPhotoWidget(kind:'user', id:(p['id'] as num).toInt(), revision:(p['photo_revision'] as num?)?.toInt()??0, size:62),
            const SizedBox(width:14),
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('${p['name']}',style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w800)),
              Text('${p['email']}',overflow:TextOverflow.ellipsis,style:TextStyle(color:secondaryText(context))),
              if('${p['verified_login_phone']??''}'.isNotEmpty)
                Text('${p['verified_login_phone']} · Verified mobile',style:TextStyle(color:secondaryText(context),fontSize:12)),
              const SizedBox(height:5),
              Text('View and edit profile',style:TextStyle(color:Theme.of(context).colorScheme.primary,fontWeight:FontWeight.w700)),
            ])),
            const Icon(Icons.chevron_right),
          ]),
        ),
      ),
      if(app.owner)...[
        const SectionTitle('Business settings'),
        FeatureTile(title:'Payment setup & QR',subtitle:'Manage UPI, bank account and QR image',
          icon:Icons.qr_code_2_outlined,onTap:()=>openPage(context,'paymentMethods')),
        FeatureTile(title:'Properties',subtitle:'View and update your PG locations',
          icon:Icons.home_outlined,onTap:()=>openPage(context,'properties')),
      ],
      if(!app.owner && !app.staff) FeatureTile(
        title:'Submit identity proof',
        subtitle:'Send a JPG, PNG or PDF identity document to your PG owner',
        icon:Icons.badge_outlined,
        onTap:()=>openPage(context,'identityProof')),
      const SectionTitle('Preferences & security'),
      const Surface(child: LanguagePicker()),
      for(final item in [
        if(!app.owner&&!app.staff)('accommodation','My accommodation',Icons.home_outlined),
        ('password','Change password',Icons.lock_outline),
        ('notificationSettings','Notification preferences',Icons.notifications_none),
        ('appearance','Appearance',Icons.palette_outlined),
        ('support','Help & support',Icons.help_outline),
        ('legal','Terms & privacy',Icons.description_outlined)
      ])FeatureTile(title:item.$2,
      icon:item.$3,
      onTap:()=>openPage(context,
      item.$1)),
      if (const {'owner','resident'}.contains(p['role']))
        FeatureTile(title:'Rate Stay Sync Manage',icon:Icons.star_outline,onTap:()=>showAppFeedback(context)),
      const SizedBox(height:15),
      OutlinedButton.icon(onPressed:()async{
        if(!await ask(context,
        'Log out of Stay Sync Manage?')||!context.mounted)return;
        await perform(context,
        app.logout);
        if(context.mounted)Navigator.of(context).popUntil((r)=>r.isFirst);
      },
      icon:const Icon(Icons.logout),
      label:Text(tr(context,'Log out'))),
      const Attribution()
    ]);
  }
} class ProfileEditorPage extends StatefulWidget {
  const ProfileEditorPage({
    super.key
  });
  @override State<ProfileEditorPage> createState()=>_ProfileEditorPageState();
} class _ProfileEditorPageState extends State<ProfileEditorPage>{
  final form=GlobalKey<FormState>();
  final name=TextEditingController(),
  email=TextEditingController(),
  phone=TextEditingController();
  bool init=false,
  busy=false;
  @override void didChangeDependencies(){
    super.didChangeDependencies();
    if(!init){
      final p=AppScope.of(context).profile;
      name.text='${p['name']}';
      email.text='${p['email']}';
      phone.text='${p['phone']??''}';
      init=true;
    }
  }@override void dispose(){
    name.dispose();
    email.dispose();
    phone.dispose();
    super.dispose();
  }@override Widget build(BuildContext context)=>PageBody(title:'Edit profile',
  children:[
    Surface(child:Form(key:form,
    child:Column(children:[
      DisplayPhotoWidget(kind:'user', id:(AppScope.of(context).profile['id'] as num).toInt(), revision:(AppScope.of(context).profile['photo_revision'] as num?)?.toInt()??0, editable:true, size:96),
      const SizedBox(height:14),
      TextFormField(controller:name,
      decoration:const InputDecoration(labelText:'Full name'),
      validator:(v)=>(v??'').trim().length<2?'Use at least 2 characters':null),
      const SizedBox(height:16),
      TextFormField(controller:email,
      keyboardType:TextInputType.emailAddress,
      decoration:const InputDecoration(labelText:'Email'),
      autovalidateMode:AutovalidateMode.onUserInteraction,
      validator:(v)=> (v??'').trim().toLowerCase() == '${AppScope.of(context).profile['email']}'.toLowerCase() ? null : emailError(v)),
      const SizedBox(height:16),
      TextFormField(controller:phone,
      keyboardType:TextInputType.phone,
      decoration:const InputDecoration(labelText:'Contact phone',helperText:'Does not change your verified login number.',helperMaxLines:3)),
      if('${AppScope.of(context).profile['verified_login_phone']??''}'.isNotEmpty)
        Padding(padding:const EdgeInsets.only(top:8),child:Text('Verified login: ${AppScope.of(context).profile['verified_login_phone']}. Contact support to change it.',style:TextStyle(color:secondaryText(context),fontSize:12))),
      const SizedBox(height:20),
      FilledButton(onPressed:busy?null:()async{
        if(!form.currentState!.validate())return;
        setState(()=>busy=true);
        final ok=await perform(context,
        ()=>AppScope.of(context).updateProfile({
          'name':name.text.trim(),
          'email':email.text.trim(),
          'phone':phone.text.trim()
        }),
        success:'Profile updated');
        if(mounted){
          setState(()=>busy=false);
          if(ok)Navigator.pop(context);
        }
      },
      child:Text(busy?'Saving…':'Save changes'))
    ])))
  ]);
} class PasswordPage extends StatefulWidget {
  const PasswordPage({
    super.key
  });
  @override State<PasswordPage> createState()=>_PasswordPageState();
} class _PasswordPageState extends State<PasswordPage>{
  final form=GlobalKey<FormState>();
  final current=TextEditingController(),
  password=TextEditingController(),
  confirm=TextEditingController();
  bool busy=false;
  bool showCurrent=false, showNew=false, showConfirm=false;
  @override void dispose(){
    current.dispose();
    password.dispose();
    confirm.dispose();
    super.dispose();
  }@override Widget build(BuildContext context)=>PageBody(title:'Change password',
  subtitle:'Other sessions will be invalidated. Sign in again after saving.',
  children:[
    Surface(child:Form(key:form,
    child:Column(children:[
      for(final row in [
        (current,
        'Current password'),
        (password,
        'New password'),
        (confirm,
        'Confirm new password')
      ])Padding(padding:const EdgeInsets.only(bottom:16),
      child:TextFormField(controller:row.$1,
      obscureText:row.$1==current?!showCurrent:row.$1==password?!showNew:!showConfirm,
      decoration:InputDecoration(labelText:row.$2,suffixIcon:IconButton(
        tooltip:(row.$1==current?showCurrent:row.$1==password?showNew:showConfirm)
            ?'Hide ${row.$2.toLowerCase()}':'Show ${row.$2.toLowerCase()}',
        icon:Icon((row.$1==current?showCurrent:row.$1==password?showNew:showConfirm)
            ?Icons.visibility_off_outlined:Icons.visibility_outlined),
        onPressed:()=>setState((){
          if(row.$1==current){showCurrent=!showCurrent;}
          else if(row.$1==password){showNew=!showNew;}
          else{showConfirm=!showConfirm;}
        }),
      )),
      validator:(v)=>row.$1==confirm?v==password.text?null:'Passwords must match':row.$1==password&&(v??'').length<8?'Use at least 8 characters':(v??'').isEmpty?'Required':null)),
      FilledButton(onPressed:busy?null:()async{
        if(!form.currentState!.validate())return;
        setState(()=>busy=true);
        final app=AppScope.of(context);
        final ok=await perform(context,
        ()async{
          await app.api.request('/v3/password',
          method:'POST',
          body:{
            'current_password':current.text,
            'new_password':password.text
          });
        });
        if(ok){
          try{
            await app.logout();
          }catch(_){
          }if(context.mounted)Navigator.of(context).popUntil((r)=>r.isFirst);
        }if(mounted)setState(()=>busy=false);
      },
      child:Text(busy?'Updating…':'Update password'))
    ])))
  ]);
} class AppearancePage extends StatelessWidget {
  const AppearancePage({
    super.key
  });
  @override Widget build(BuildContext context){
    final app=AppScope.of(context);
    final selected=(app.profile[
      'preferences'
    ]as Map?)?[
      'appearance'
    ]??'Light';
    return PageBody(title:'Appearance',
    children:[
      for(final mode in [
        'Light',
        'Dark',
        'System'
      ])Surface(onTap:()=>perform(context,
      ()=>app.updateProfile({
        'appearance':mode
      })),
      child:Row(children:[
        Expanded(child:Text(mode)),
        if(mode==selected)const Icon(Icons.check,
        color:lavender)
      ]))
    ]);
  }
 } class NotificationPreferencesPage extends StatefulWidget {
  const NotificationPreferencesPage({super.key});
  @override State<NotificationPreferencesPage> createState()=>_NotificationPreferencesPageState();
}
class _NotificationPreferencesPageState extends State<NotificationPreferencesPage> {
  Map<String,bool>? values;
  bool busy=false;
  static const items=<String, (String, IconData, String)>{
    'Rent reminders':('Rent reminders',Icons.calendar_month_outlined,'Upcoming and overdue rent alerts'),
    'Payment updates':('Payment alerts',Icons.credit_card_outlined,'Submissions, approvals and receipts'),
    'Announcements':('Announcements',Icons.campaign_outlined,'Important PG announcements'),
    'Maintenance':('Complaint updates',Icons.assignment_turned_in_outlined,'Progress and resolution of complaints'),
    'Facility notices':('Facility outages',Icons.build_outlined,'Water, power, Wi-Fi and maintenance'),
    'Community activity':('Community messages',Icons.people_outline,'Activity in your PG community'),
  };
  @override Widget build(BuildContext context) {
    final app=AppScope.of(context);
    final saved=Map<String,dynamic>.from((app.profile['preferences'] as Map?)?['notifications'] as Map? ?? {});
    values??={for(final k in items.keys) k:saved[k]!=false};
    return PageBody(title:'Notification preferences',subtitle:'Choose the updates you want to receive.',children:[
      Surface(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[Icon(Icons.notifications_active_outlined,color:Theme.of(context).colorScheme.primary),const SizedBox(width:9),
          Expanded(child:Text('Stay informed, your way',style:TextStyle(fontWeight:FontWeight.w800,color:Theme.of(context).colorScheme.primary)))]),
        const SizedBox(height:7),
        Text('These choices control in-app alerts. Android popup, sound and background notifications require push delivery to be configured.',
          style:TextStyle(fontSize:12,color:secondaryText(context),height:1.5)),
      ])),
      for(final e in items.entries) Surface(child:SwitchListTile.adaptive(
        contentPadding:EdgeInsets.zero,
        secondary:Icon(e.value.$2,color:Theme.of(context).colorScheme.primary),
        title:Text(e.value.$1,style:const TextStyle(fontSize:14,fontWeight:FontWeight.w700)),
        subtitle:Text(e.value.$3,style:TextStyle(fontSize:11,color:secondaryText(context))),
        value:values![e.key]??true,
        onChanged:(v)=>setState(()=>values![e.key]=v),
      )),
      FilledButton(onPressed:busy?null:()async{
        setState(()=>busy=true);
        try {
          await app.updateProfile({'notifications':{...saved,...values!}});
          if(context.mounted)feedback(context,'Preferences saved');
        }catch(e){if(context.mounted)feedback(context,e);}
        finally {if(mounted)setState(()=>busy=false);}
      },child:Text(busy?'Saving…':'Save preferences')),
    ]);
  }
 } class AccommodationPage extends StatelessWidget {
  const AccommodationPage({super.key});
  @override Widget build(BuildContext context){
    final app=AppScope.of(context);
    final room=Map<String,dynamic>.from(app.data['accommodation'] as Map? ?? {});
    final invoices=app.rows('invoices');
    final outstanding=invoices.fold<double>(0,(total,entry)=>total+amount(entry['outstanding']));
    final last=invoices.isEmpty?null:invoices.last;
    final pgName='${room['property']??app.profile['tenant']?['name']??'Not assigned'}';
    return PageBody(title:'My accommodation',subtitle:'Your current PG and rent information',children:[
      Surface(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[const Icon(Icons.apartment_outlined,color:lavender,size:32),
          const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('YOUR PG',style:TextStyle(fontSize:11,color:secondaryText(context))),
            Text(pgName,style:const TextStyle(fontSize:20,fontWeight:FontWeight.w800))]))]),
        const Divider(height:26),
        Row(children:[Expanded(child:_AccommodationInfo(label:'Room number',value:'${room['room']??'Not assigned'}')),
          Expanded(child:_AccommodationInfo(label:'Bed number',value:'${room['bed']??'Not assigned'}'))]),
      ])),
      const SectionTitle('Rent details'),
      HeroCard(label:'Outstanding balance',value:inr(outstanding),detail:outstanding<=0?'Your rent is up to date':'Due after approved payments only'),
      Surface(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        _AccommodationInfo(label:'Latest monthly bill',value:last==null?'No invoice yet':inr(last['amount'])),
        const SizedBox(height:12),
        _AccommodationInfo(label:'Billing period',value:last==null?'—':'${last['period']}'),
        const SizedBox(height:12),
        _AccommodationInfo(label:'Verified payments',value:inr(invoices.fold<double>(0,(s,i)=>s+amount(i['paid'])))),
        const SizedBox(height:12),
        _AccommodationInfo(label:'Next due date',value:last==null?'—':'${last['due_date']}'),
        const SizedBox(height:12),
        Text('Payments appear after confirmation.',style:TextStyle(color:secondaryText(context),fontSize:12)),
      ])),
      FeatureTile(title:'Rent & receipts',subtitle:'View bills, payments and receipts',icon:Icons.receipt_long_outlined,onTap:()=>openPage(context,'rent')),
      FeatureTile(title:'Facility updates',subtitle:'Water, power, maintenance and Wi-Fi',icon:Icons.water_drop_outlined,onTap:()=>openPage(context,'facilities'))
    ]);
  }
}
class _AccommodationInfo extends StatelessWidget {
  const _AccommodationInfo({required this.label,required this.value});
  final String label,value;
  @override Widget build(BuildContext context)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text(label,style:TextStyle(fontSize:12,color:secondaryText(context))),
    const SizedBox(height:4),
    Text(value,style:const TextStyle(fontSize:17,fontWeight:FontWeight.w700))
  ]);
} class JoiningCodePage extends StatefulWidget {
  const JoiningCodePage({
    super.key
  });
  @override State<JoiningCodePage> createState()=>_JoiningCodePageState();
} class _JoiningCodePageState extends State<JoiningCodePage>{
  String? code,
  error;
  int? selectedPropertyId;
  bool loading=false;
  @override void didChangeDependencies(){
    super.didChangeDependencies();
    if(code==null&&!loading&&error==null)load();
  }Future<void> load()async{
    loading=true;
    try{
      final app=AppScope.of(context);
      final pid=selectedPropertyId??app.propertyId??0;
      final data=await app.api.request('/v3/joining-code?property_id=$pid');
      if(mounted&&pid==(selectedPropertyId??app.propertyId??0))setState(()=>code='${data['code']}');
    }catch(e){
      if(mounted)setState(()=>error='$e');
    }finally{
      loading=false;
    }
  }@override Widget build(BuildContext context)=>PageBody(title:'Resident joining code',
  subtitle:'Share only with residents approved to join your PG.',
  children:[
    DropdownButtonFormField<int>(
      isExpanded:true,
      initialValue:selectedPropertyId??AppScope.of(context).propertyId??0,
      decoration:const InputDecoration(labelText:'PG for joining code'),
      items:AppScope.of(context).rows('properties').where((p)=>p['archived']!=true).map((p)=>DropdownMenuItem<int>(value:(p['id'] as num).toInt(),child:Text('${p['name']}'))).toList(),
      onChanged:(pid){if(pid==null)return;setState((){selectedPropertyId=pid;code=null;error=null;});load();}),
    const SizedBox(height:12),
    const Text('This code identifies the selected PG. Residents must still be invited and approved by the owner.'),
    if(error!=null)...[
      Text(error!),
      TextButton(onPressed:load,
      child:const Text('Retry'))
    ]else if(code==null)const Center(child:CircularProgressIndicator())else ...[
      HeroCard(label:'Selected PG joining code',
      value:code!),
      FilledButton.icon(onPressed:()=>copyValue(context,
      code!),
      icon:const Icon(Icons.copy),
      label:const Text('Copy joining code'))
    ]
  ]);
} class HelpPage extends StatelessWidget {
  const HelpPage({
    super.key
  });
  @override Widget build(BuildContext context)=>PageBody(title:'Help & support',
  children:[
    for(final row in [
      ('How do I pay rent?',
      'Pay your PG owner using the displayed UPI or bank details. Then upload payment proof in My rent. The owner checks the bank credit and approves it.'),
      ('How do I report an issue?',
      'Open Complaints, describe the issue and add an optional photo. You can follow updates in the request history.'),
      ('How do I recover my account?',
      'Use Forgot password on sign-in. Use your verified mobile number and SMS code. If mobile login is not activated, contact your PG owner or administrator.'),
      ('Who can see my messages?',
      'Community messages are restricted by the server to members of your PG. Delete for me hides a message from your account. Unsend is available to the sender within 15 minutes.')
    ])Surface(child:ExpansionTile(tilePadding:EdgeInsets.zero,
    title:Text(row.$1,
    style:const TextStyle(fontSize:13,
    fontWeight:FontWeight.w800)),
    children:[
      Padding(padding:const EdgeInsets.symmetric(vertical:12),
      child:Text(row.$2,
      style:TextStyle(color:secondaryText(context),
      fontSize:12,
      height:1.6)))
    ]))
  ]);
} class LegalPage extends StatelessWidget {
  const LegalPage({
    super.key
  });
  @override Widget build(BuildContext context)=>const LegalDocument();
}

class FirstLoginPasswordPage extends StatefulWidget {
  const FirstLoginPasswordPage({super.key});
  @override State<FirstLoginPasswordPage> createState()=>_FirstLoginPasswordPageState();
}
class _FirstLoginPasswordPageState extends State<FirstLoginPasswordPage> {
  bool showTemporary=false, showNew=false, showConfirm=false;
  final form=GlobalKey<FormState>();
  final initial=TextEditingController();
  final newer=TextEditingController();
  final confirm=TextEditingController();
  bool busy=false;
  String? error;
  @override void dispose(){initial.dispose();newer.dispose();confirm.dispose();super.dispose();}
  Future<void> save()async{
    if(!form.currentState!.validate())return;
    setState(()=>busy=true);
    final app=AppScope.of(context);
    try{
      await app.api.request('/v3/password',method:'POST',body:{'current_password':initial.text,'new_password':newer.text});
      await app.logout(); // server revokes previous session after password change
    }catch(e){if(mounted)setState(()=>error='$e');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Secure your new account')),
    body:SafeArea(child:ListView(padding:const EdgeInsets.all(24),children:[
      Icon(Icons.verified_user_outlined,size:55,color:Theme.of(context).colorScheme.primary),
      const SizedBox(height:16),
      const Text('Create your personal password',style:TextStyle(fontSize:24,fontWeight:FontWeight.w800)),
      const SizedBox(height:8),
      const Text('Your PG owner gave you temporary access. Change that password before using COME.in. You will sign in again afterward.'),
      const SizedBox(height:25),
      Form(key:form,child:Column(children:[
        TextFormField(controller:initial,obscureText:!showTemporary,decoration:InputDecoration(labelText:'Temporary password',suffixIcon:IconButton(tooltip:showTemporary?'Hide temporary password':'Show temporary password',icon:Icon(showTemporary?Icons.visibility_off_outlined:Icons.visibility_outlined),onPressed:()=>setState(()=>showTemporary=!showTemporary))),validator:(v)=>(v??'').isEmpty?'Required':null),
        const SizedBox(height:15),
        TextFormField(controller:newer,obscureText:!showNew,decoration:InputDecoration(labelText:'New password',suffixIcon:IconButton(tooltip:showNew?'Hide new password':'Show new password',icon:Icon(showNew?Icons.visibility_off_outlined:Icons.visibility_outlined),onPressed:()=>setState(()=>showNew=!showNew))),validator:(v)=>(v??'').length<8?'Use at least 8 characters':null),
        const SizedBox(height:15),
        TextFormField(controller:confirm,obscureText:!showConfirm,decoration:InputDecoration(labelText:'Confirm new password',suffixIcon:IconButton(tooltip:showConfirm?'Hide confirmation':'Show confirmation',icon:Icon(showConfirm?Icons.visibility_off_outlined:Icons.visibility_outlined),onPressed:()=>setState(()=>showConfirm=!showConfirm))),validator:(v)=>v!=newer.text?'Passwords do not match':null),
      ])),
      if(error!=null)Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text(error!,style:const TextStyle(color:Colors.red))),
      const SizedBox(height:22),
      FilledButton(onPressed:busy?null:save,child:Text(busy?'Saving…':'Set password & sign in again')),
      TextButton(onPressed:() async => AppScope.of(context).logout(),child:const Text('Sign out')),
    ])));
}

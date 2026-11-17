import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

/// Integrate only in the authenticated PG-owner navigation.
/// Obtain bearerToken from the existing secure authentication controller.
/// Never expose the platform-admin token to the Flutter app.
class OwnerSubscriptionPage extends StatefulWidget {
  const OwnerSubscriptionPage({super.key, required this.apiBase, required this.bearerToken});
  final String apiBase;
  final String bearerToken;
  @override
  State<OwnerSubscriptionPage> createState() => _OwnerSubscriptionPageState();
}

class _OwnerSubscriptionPageState extends State<OwnerSubscriptionPage> {
  Map<String,dynamic>? payload;
  bool busy=false;
  String? error;
  String utr='';
  XFile? proof;
  final _picker=ImagePicker();
  String get root=>'${widget.apiBase.replaceFirst(RegExp(r'/$'), '')}/api/owner-subscriptions';
  Map<String,String> get headers=>{'Authorization':'Bearer ${widget.bearerToken}'};
  @override void initState(){super.initState();load();}

  Future<http.Response> call(String path,{String method='GET',Object? body}) async {
    final u=Uri.parse('$root$path');
    final h={...headers,'Content-Type':'application/json'};
    final r=method=='POST'?await http.post(u,headers:h,body:jsonEncode(body)):
      await http.get(u,headers:headers);
    if(r.statusCode>=400){
      String msg='Server error (${r.statusCode})';
      try{msg=(jsonDecode(r.body) as Map)['detail']?.toString()??msg;}catch(_){}
      throw Exception(msg);
    }
    return r;
  }

  Future<void> load() async {
    setState(() {busy=true;error=null;});
    try{
      final r=await call('/me');
      if(mounted)setState(()=>payload=jsonDecode(r.body) as Map<String,dynamic>);
    }catch(e){if(mounted)setState(()=>error=e.toString());}
    finally{if(mounted)setState(()=>busy=false);}
  }

  Future<void> issueCurrentInvoice() async {
    setState(() {busy=true;error=null;});
    try{
      final d=DateTime.now();
      final period='${d.year}-${d.month.toString().padLeft(2,'0')}';
      await call('/me/invoice/$period',method:'POST');
      await load();
    }catch(e){if(mounted)setState(()=>error=e.toString());}
    finally{if(mounted)setState(()=>busy=false);}
  }

  Future<void> submit(String invoiceId) async {
    if(proof==null||utr.trim().length<6){setState(()=>error='Enter a valid UTR and select a payment screenshot');return;}
    setState(()=>busy=true);
    try{
      final req=http.MultipartRequest('POST',Uri.parse('$root/me/payments'));
      req.headers.addAll(headers);
      req.fields['invoice_id']=invoiceId;
      req.fields['utr']=utr.trim();
      req.files.add(await http.MultipartFile.fromPath('proof',proof!.path,filename:proof!.name));
      final r=await http.Response.fromStream(await req.send());
      if(r.statusCode>=400){
        String msg='Submission failed (${r.statusCode})';
        try{msg=(jsonDecode(r.body) as Map)['detail']?.toString()??msg;}catch(_){}
        throw Exception(msg);
      }
      if(mounted)setState(() {utr='';proof=null;});
      await load();
    }catch(e){if(mounted)setState(()=>error=e.toString());}
    finally{if(mounted)setState(()=>busy=false);}
  }

  String money(dynamic cents){final v=(num.tryParse('$cents')??0)/100;return '₹${v.toStringAsFixed(2)}';}
  Widget panel(Widget child)=>Card(elevation:0,color:Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16),side:const BorderSide(color:Color(0xffece2f0))),child:Padding(padding:const EdgeInsets.all(18),child:child));
  @override
  Widget build(BuildContext context){
    final inv=(payload?['invoices'] as List<dynamic>?)??[];
    final payments=(payload?['payments'] as List<dynamic>?)??[];
    final qr=payload?['qr'] as Map<String,dynamic>?;
    final pricing=payload?['pricing'] as Map<String,dynamic>?;
    return Scaffold(backgroundColor:const Color(0xfffaf6fc),appBar:AppBar(title:const Text('My Subscription')),
      body:RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(16),children:[
        if(error!=null)panel(Text(error!,style:const TextStyle(color:Colors.red))),
        panel(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          const Text('Monthly subscription',style:TextStyle(fontSize:19,fontWeight:FontWeight.bold)),
          const SizedBox(height:8),
          Text(pricing==null?'Pricing awaiting administrator configuration':'Bed rate ₹${pricing['bed_rate']} · Resident rate ₹${pricing['resident_rate']}'),
          const SizedBox(height:12),
          FilledButton(onPressed:busy||pricing==null?null:issueCurrentInvoice,child:const Text('View current month bill')),
        ])),
        ...inv.map((e){final i=Map<String,dynamic>.from(e as Map);return panel(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('Billing period ${i['period']}',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
          const SizedBox(height:7),Text('Beds: ${i['beds']} · Active residents: ${i['residents']}'),
          Text('Bed charge: ${money((i['beds'] as num)*(i['bed_rate_cents'] as num))}'),
          Text('Resident charge: ${money((i['residents'] as num)*(i['resident_rate_cents'] as num))}'),
          Text('Amount due: ${money(i['amount_cents'])}',style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
          Text('Status: ${i['status']}'),
          if(i['status']!='paid') ...[
            const Divider(),
            if(qr?['enabled']==1||qr?['enabled']==true) ...[
              const Text('Pay only to the verified account below.'),
              Text('Beneficiary: ${qr?['beneficiary']??''}'),Text('UPI ID: ${qr?['upi_id']??''}'),
              const SizedBox(height:10),
              // Authenticated image requests must use the same owner bearer token.
              Image.network('$root/payment-qr',width:200,height:200,fit:BoxFit.contain,
                headers:headers,errorBuilder:(c,e,s)=>const Text('Payment QR unavailable')),
              const SizedBox(height:12),
              TextField(onChanged:(v)=>utr=v,decoration:const InputDecoration(labelText:'UTR / transaction reference',border:OutlineInputBorder())),
              TextButton.icon(onPressed:busy?null:() async {final result=await _picker.pickImage(source:ImageSource.gallery,imageQuality:85);if(mounted)setState(()=>proof=result);},icon:const Icon(Icons.upload_file),label:Text(proof?.name??'Choose payment screenshot')),
              FilledButton(onPressed:busy?null:()=>submit(i['id'] as String),child:const Text('Submit for verification')),
            ] else const Text('Administrator has not enabled a payment QR.'),
          ],
        ]));}),
        panel(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('Payment history',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
          if(payments.isEmpty)const Padding(padding:EdgeInsets.only(top:10),child:Text('No payments submitted yet.')),
          ...payments.map((e){final p=Map<String,dynamic>.from(e as Map);return ListTile(contentPadding:EdgeInsets.zero,title:Text('UTR ${p['utr']}'),subtitle:Text(p['remarks']?.toString()??'${p['submitted_at']??''}'),trailing:Text('${p['status']}'));})
        ])),
        if(busy)const Center(child:CircularProgressIndicator()),
      ])),
    );
  }
}

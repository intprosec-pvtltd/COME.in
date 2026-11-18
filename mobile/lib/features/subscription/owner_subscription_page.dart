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
  final utrController=TextEditingController();
  XFile? proof;
  final _picker=ImagePicker();
  String get root=>'${widget.apiBase.replaceFirst(RegExp(r'/$'), '')}/api/owner-subscriptions';
  Map<String,String> get headers=>{'Authorization':'Bearer ${widget.bearerToken}'};
  @override void initState(){super.initState();load();}
  @override void dispose(){utrController.dispose();super.dispose();}

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
    if(!mounted)return;
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
    }catch(e){if(mounted)setState(()=>error=e.toString().contains('Existing legacy invoice')
        ? 'An invoice already exists for this month. A second bill is blocked. Ask your platform administrator to reconcile the existing invoice.'
        : e.toString());}
    finally{if(mounted)setState(()=>busy=false);}
  }

  Future<void> submit(String invoiceId) async {
    final utr=utrController.text.trim();
    if(proof==null||utr.length<6){setState(()=>error='Enter a valid UTR and select a payment screenshot');return;}
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
      if(mounted){utrController.clear();setState(()=>proof=null);}
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
    final legacy=payload?['legacy_invoice'] as Map<String,dynamic>?;
    final residents=(payload?['billable_residents'] as num?)?.toInt()??0;
    final current=DateTime.now();
    final period='${current.year}-${current.month.toString().padLeft(2,'0')}';
    final thisMonth=inv.where((i)=>i['period']==period).toList();
    final legacyThisMonth=legacy!=null&&legacy['period']==period;
    final monthly=residents*39;
    return Scaffold(
      backgroundColor:const Color(0xfffaf6fc),
      appBar:AppBar(title:const Text('Stay Sync Manage · Subscription')),
      body:RefreshIndicator(
        onRefresh:load,
        child:ListView(padding:const EdgeInsets.all(16),children:[
          if(error!=null)panel(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(error!,style:const TextStyle(color:Colors.red)),
            TextButton(onPressed:busy?null:load,child:const Text('Retry')),
          ])),
          Container(
            padding:const EdgeInsets.all(22),
            decoration:BoxDecoration(
              gradient:const LinearGradient(colors:[Color(0xff3c224e),Color(0xff75518d)]),
              borderRadius:BorderRadius.circular(22),
            ),
            child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              const Text('ONE SIMPLE PLAN',style:TextStyle(color:Color(0xffe7d9ed),fontSize:12,fontWeight:FontWeight.bold)),
              const SizedBox(height:12),
              const Text('₹39',style:TextStyle(color:Colors.white,fontSize:44,fontWeight:FontWeight.w900)),
              const Text('per billable resident / month',style:TextStyle(color:Colors.white,fontSize:15)),
              const SizedBox(height:20),
              Text('$residents billable residents  ×  ₹39',style:const TextStyle(color:Colors.white)),
              const SizedBox(height:6),
              Text('Estimated monthly total: ₹$monthly',style:const TextStyle(color:Colors.white,fontSize:20,fontWeight:FontWeight.w800)),
              const SizedBox(height:6),
              const Text('Beds are not billed. Previously issued invoices retain their original amounts.',style:TextStyle(color:Color(0xffe7d9ed),fontSize:11)),
            ]),
          ),
          const SizedBox(height:14),
          panel(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Text('Current monthly bill',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
            const SizedBox(height:8),
            Text('Billing month: $period'),
            const SizedBox(height:10),
            if(thisMonth.isNotEmpty)Text('Invoice ${thisMonth.first['status']} · ${money(thisMonth.first['amount_cents'])}',style:const TextStyle(fontWeight:FontWeight.bold)),
            if(legacyThisMonth)...[
              Text('Existing invoice #${legacy['id']} · ${legacy['status']}',
                  style:const TextStyle(fontWeight:FontWeight.bold)),
              Text('Original amount: ${money(legacy['amount_cents'])}'),
              const SizedBox(height:6),
              const Text('This month was already billed through the administrator. A second invoice is blocked to prevent duplicate charges. For payment or reconciliation, contact the platform administrator.',
                  style:TextStyle(fontSize:12)),
            ],
            const SizedBox(height:10),
            if(!legacyThisMonth)FilledButton.icon(
              onPressed:busy||payload==null?null:issueCurrentInvoice,
              icon:const Icon(Icons.receipt_long_outlined),
              label:Text(thisMonth.isEmpty?'Generate / view current bill':'Refresh current bill'),
            ),
          ])),
          const SizedBox(height:14),
          for(final item in inv)Builder(builder:(context){
            final i=Map<String,dynamic>.from(item as Map);
            final pending=payments.any((p)=>p['invoice_id']==i['id']&&p['status']=='pending');
            return panel(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Row(children:[
                Expanded(child:Text('Invoice · ${i['period']}',style:const TextStyle(fontSize:17,fontWeight:FontWeight.bold))),
                Chip(label:Text('${i['status']}'.toUpperCase())),
              ]),
              const SizedBox(height:5),
              Text('Residents billed: ${i['residents']}'),
              Text('Amount: ${money(i['amount_cents'])}',style:const TextStyle(fontSize:24,fontWeight:FontWeight.w900)),
              if(i['status']!='paid') ...[
                const Divider(height:25),
                if(pending)const Text('Your payment is awaiting administrator bank verification. You cannot submit a duplicate proof for this invoice.'),
                if(!pending&&(qr?['enabled']==1||qr?['enabled']==true)) ...[
                  const Text('Pay only to the verified account:',style:TextStyle(fontWeight:FontWeight.w600)),
                  Text('Beneficiary: ${qr?['beneficiary']??''}'),
                  SelectableText('UPI: ${qr?['upi_id']??''}'),
                  const SizedBox(height:12),
                  Center(child:Image.network('$root/payment-qr',width:210,height:210,fit:BoxFit.contain,headers:headers,
                    errorBuilder:(c,e,s)=>const Text('QR unavailable. Refresh or contact the administrator.'))),
                  const SizedBox(height:14),
                  TextField(controller:utrController,maxLength:64,decoration:const InputDecoration(labelText:'UTR / bank transaction reference',border:OutlineInputBorder())),
                  TextButton.icon(onPressed:busy?null:() async {
                    final result=await _picker.pickImage(source:ImageSource.gallery,imageQuality:85);
                    if(mounted)setState(()=>proof=result);
                  },icon:const Icon(Icons.upload_file),label:Text(proof?.name??'Select payment screenshot')),
                  const SizedBox(height:8),
                  FilledButton(onPressed:busy?null:()=>submit(i['id'] as String),child:const Text('Submit payment for verification')),
                  const SizedBox(height:6),
                  const Text('Payment is marked paid only after the administrator verifies the bank credit.',style:TextStyle(fontSize:11)),
                ]else if(!pending)const Text('Administrator payment QR is not enabled. Please contact support.'),
              ],
            ]));
          }),
          const SizedBox(height:14),
          panel(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Text('Payment history',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
            if(payments.isEmpty)const Padding(padding:EdgeInsets.only(top:10),child:Text('No payments submitted yet.')),
            for(final item in payments)Builder(builder:(context){
              final p=Map<String,dynamic>.from(item as Map);
              return ListTile(
                contentPadding:EdgeInsets.zero,
                title:Text('UTR ${p['utr']}'),
                subtitle:Text('Submitted: ${p['submitted_at']??''}\n${p['remarks']??''}\nActivation: ${p['activation_status']??'not applicable'}'),
                isThreeLine:true,
                trailing:Chip(label:Text('${p['status']}')),
              );
            }),
          ])),
          if(busy)const Center(child:Padding(padding:EdgeInsets.all(16),child:CircularProgressIndicator())),
        ]),
      ),
    );
  }
}

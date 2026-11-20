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
        ? 'This month’s invoice is already available. Refresh to view it.'
        : e.toString());}
    finally{if(mounted)setState(()=>busy=false);}
  }

  Future<void> submit(String invoiceId) async {
    final utr=utrController.text.trim();
    if(proof==null||utr.length<6){setState(()=>error='Enter your transaction reference and attach a screenshot');return;}
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
  String statusText(dynamic value) {
    switch ('$value'.toLowerCase()) {
      case 'paid': return 'Paid';
      case 'unpaid': return 'Payment due';
      case 'pending': return 'Pending';
      case 'rejected': return 'Rejected';
      case 'approved': return 'Approved';
      default: return '$value'.replaceAll('_', ' ');
    }
  }

  Widget invoiceCard(Map<String,dynamic> i, List<dynamic> payments,
      Map<String,dynamic>? qr) {
    final pending=payments.any((p)=>p['invoice_id']==i['id']&&p['status']=='pending');
    final paid='${i['status']}'.toLowerCase()=='paid';
    final owners=(i['owners'] as num?)?.toInt()??0;
    return panel(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[
        Expanded(child:Text('${i['period']}',style:const TextStyle(fontSize:17,fontWeight:FontWeight.bold))),
        Chip(label:Text(statusText(i['status']))),
      ]),
      const SizedBox(height:8),
      Text(money(i['amount_cents']),style:const TextStyle(fontSize:27,fontWeight:FontWeight.w800)),
      if(owners>0)ExpansionTile(
        tilePadding:EdgeInsets.zero,childrenPadding:EdgeInsets.zero,
        title:const Text('Bill details',style:TextStyle(fontSize:13)),
        children:[
          Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
            const Text('Subscription'),Text(money(i['subtotal_cents']??0))]),
          const SizedBox(height:4),
          Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
            const Text('GST'),Text(money(i['gst_cents']??0))]),
          const SizedBox(height:8),
        ],
      ),
      if(!paid)...[
        const Divider(height:24),
        if(pending)const Text('Payment submitted. Awaiting confirmation.'),
        if(!pending&&(qr?['enabled']==1||qr?['enabled']==true))...[
          const Text('Pay using the details below',style:TextStyle(fontWeight:FontWeight.w600)),
          const SizedBox(height:8),
          if('${qr?['beneficiary']??''}'.trim().isNotEmpty)
            Text('Name: ${qr?['beneficiary']}'),
          if('${qr?['upi_id']??''}'.trim().isNotEmpty)
            SelectableText('UPI: ${qr?['upi_id']}'),
          const SizedBox(height:12),
          Center(child:Image.network('$root/payment-qr',width:190,height:190,
            fit:BoxFit.contain,headers:headers,
            errorBuilder:(c,e,s)=>const Text('Payment QR unavailable. Please refresh.'))),
          const SizedBox(height:12),
          TextField(controller:utrController,maxLength:64,
            decoration:const InputDecoration(labelText:'Transaction reference (UTR)',border:OutlineInputBorder())),
          TextButton.icon(onPressed:busy?null:() async {
            final result=await _picker.pickImage(source:ImageSource.gallery,imageQuality:85);
            if(mounted)setState(()=>proof=result);
          },icon:const Icon(Icons.upload_file),label:Text(proof?.name??'Attach payment screenshot')),
          const SizedBox(height:6),
          SizedBox(width:double.infinity,child:FilledButton(
            onPressed:busy?null:()=>submit(i['id'] as String),
            child:const Text('Submit payment'))),
        ]else if(!pending)const Text('Payment details unavailable. Contact support.'),
      ],
    ]));
  }

  @override
  Widget build(BuildContext context){
    final inv=(payload?['invoices'] as List<dynamic>?)??[];
    final payments=(payload?['payments'] as List<dynamic>?)??[];
    final qr=payload?['qr'] as Map<String,dynamic>?;
    final legacy=payload?['legacy_invoice'] as Map<String,dynamic>?;
    final current=DateTime.now();
    final period='${current.year}-${current.month.toString().padLeft(2,'0')}';
    final hasCurrentInvoice=inv.any((i)=>i['period']==period);
    final legacyThisMonth=legacy!=null&&legacy['period']==period;
    final estimate=payload?['estimate'] as Map<String,dynamic>?;
    final total=money(estimate?['amount_cents']??0);

    return Scaffold(
      backgroundColor:const Color(0xfffaf6fc),
      appBar:AppBar(title:const Text('My subscription')),
      body:RefreshIndicator(onRefresh:load,
        child:ListView(padding:const EdgeInsets.all(16),children:[
          if(error!=null)panel(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(error!,style:const TextStyle(color:Colors.red)),
            TextButton(onPressed:busy?null:load,child:const Text('Retry')),
          ])),
          Container(
            padding:const EdgeInsets.all(22),
            decoration:BoxDecoration(
              gradient:const LinearGradient(colors:[Color(0xff3c224e),Color(0xff75518d)]),
              borderRadius:BorderRadius.circular(22)),
            child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              const Text('MONTHLY PLAN',style:TextStyle(color:Color(0xffe7d9ed),fontSize:12,fontWeight:FontWeight.bold)),
              const SizedBox(height:8),
              const Text('₹39 / person',style:TextStyle(color:Colors.white,fontSize:28,fontWeight:FontWeight.w800)),
              const Text('per month + GST',style:TextStyle(color:Color(0xffe7d9ed),fontSize:13)),
              const SizedBox(height:20),
              const Text('Estimated monthly total',style:TextStyle(color:Colors.white70,fontSize:13)),
              Text(total,style:const TextStyle(color:Colors.white,fontSize:32,fontWeight:FontWeight.w900)),
              const Text('Including GST',style:TextStyle(color:Color(0xffe7d9ed),fontSize:12)),
              if(estimate!=null)Theme(
                data:Theme.of(context).copyWith(dividerColor:Colors.transparent),
                child:ExpansionTile(
                  tilePadding:EdgeInsets.zero,childrenPadding:EdgeInsets.zero,
                  title:const Text('Price details',style:TextStyle(color:Colors.white,fontSize:13)),
                  iconColor:Colors.white,collapsedIconColor:Colors.white70,
                  children:[
                    Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
                      const Text('Subscription',style:TextStyle(color:Colors.white70)),
                      Text(money(estimate['subtotal_cents']??0),style:const TextStyle(color:Colors.white))]),
                    const SizedBox(height:5),
                    Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
                      const Text('GST',style:TextStyle(color:Colors.white70)),
                      Text(money(estimate['gst_cents']??0),style:const TextStyle(color:Colors.white))]),
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height:20),
          Row(children:[
            const Expanded(child:Text('Invoices',style:TextStyle(fontSize:19,fontWeight:FontWeight.bold))),
            IconButton(tooltip:'Refresh',onPressed:busy?null:load,icon:const Icon(Icons.refresh)),
          ]),
          const SizedBox(height:8),
          if(!hasCurrentInvoice&&!legacyThisMonth)
            panel(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              const Text('No invoice for this month yet.'),
              const SizedBox(height:10),
              FilledButton(onPressed:busy||payload==null?null:issueCurrentInvoice,
                child:const Text('View current bill')),
            ])),
          if(legacyThisMonth)panel(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(period,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:17)),
            const SizedBox(height:6),
            Text(money(legacy['amount_cents']),style:const TextStyle(fontSize:27,fontWeight:FontWeight.bold)),
            const SizedBox(height:4),
            Text(statusText(legacy['status'])),
            const SizedBox(height:8),
            const Text('For payment assistance, contact support.'),
          ])),
          for(final item in inv)
            invoiceCard(Map<String,dynamic>.from(item as Map),payments,qr),
          const SizedBox(height:14),
          panel(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Text('Payment history',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
            if(payments.isEmpty)const Padding(padding:EdgeInsets.only(top:10),child:Text('No payments yet.')),
            for(final item in payments)Builder(builder:(context){
              final p=Map<String,dynamic>.from(item as Map);
              final submitted='${p['submitted_at']??''}';
              final remarks='${p['remarks']??''}'.trim();
              return ListTile(
                contentPadding:EdgeInsets.zero,
                title:Text('Payment · ${statusText(p['status'])}'),
                subtitle:Text(remarks.isEmpty?submitted:'$submitted\n$remarks'),
                isThreeLine:false,
              );
            }),
          ])),
          if(busy)const Center(child:Padding(padding:EdgeInsets.all(16),child:CircularProgressIndicator())),
        ]),
      ),
    );
  }
}

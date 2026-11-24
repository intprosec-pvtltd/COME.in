import '../../core/localization.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../app/controller.dart';
import '../../app/router.dart';
import '../../core/design.dart';
import '../../core/app_theme.dart';
import '../management/management.dart';
// Presentation-only status: an unverified proof never changes the rent ledger.
String invoiceReviewStatus(Map<String, dynamic> invoice, List<Map<String, dynamic>> payments) {
  final financialStatus = invoiceStatus(invoice);
  if (financialStatus == 'Paid') return financialStatus;
  final id = invoice['id'];
  if (payments.any((payment) => payment['invoice_id'] == id && payment['status'] == 'pending')) {
    return 'Verification pending';
  }
  return financialStatus;
}
/// Returns the latest proof for a single invoice, independent of API row order.
/// Prior rejected proofs must not hide an active pending resubmission.
Map<String, dynamic>? latestInvoiceProof(
  Map<String, dynamic> invoice,
  List<Map<String, dynamic>> payments,
) {
  final matching = payments.where((p) =>
      '${p['invoice_id']}' == '${invoice['id']}').toList();
  if (matching.isEmpty) return null;
  matching.sort((a, b) {
    final aId = int.tryParse('${a['id']}') ?? 0;
    final bId = int.tryParse('${b['id']}') ?? 0;
    return aId.compareTo(bId);
  });
  return matching.last;
}

// Resolve PG labels from the resident's assigned property, not room number.
String pgNameForResident(AppController app, Map<String, dynamic>? resident) {
  if (resident == null) return 'PG not assigned';
  final propertyId = int.tryParse('${resident['property_id'] ?? ''}');
  if (propertyId == null) return 'PG not assigned';
  final pg = app.find('properties', propertyId);
  if (pg == null) return 'PG not assigned';
  return '${pg['name'] ?? 'PG'}';
}

/// Only owner-approved payments count as paid; uploaded proofs do not.
double verifiedAmount(Map<String, dynamic> invoice) => amount(invoice['paid']);

String invoiceStatus(Map<String,
dynamic> i)=>amount(i[
  'outstanding'
])<=0?'Paid':amount(i[
  'paid'
])>0?'Partial':DateTime.tryParse('${i['due_date']}')?.isBefore(DateTime.now().subtract(const Duration(days:1)))==true?'Overdue':'Pending';
List<Map<String,
dynamic>> scopedInvoices(AppController app){
  final ids=app.scoped('residents').map((r)=>r[
    'id'
  ]).toSet();
  return app.rows('invoices').where((i)=>(!app.owner||i[
    'period'
  ]==app.period)&&(app.propertyId==null||!app.owner||ids.contains(i[
    'resident_id'
  ]))).toList();
} Widget periodSelector(BuildContext context){
  final app=AppScope.of(context);
  final periods={
    app.period,
    ...app.rows('invoices').map((r)=>'${r['period']}'),
    ...app.rows('expenses').map((r)=>'${r['period']}')
  }.toList()..sort((a,
  b)=>b.compareTo(a));
  return Padding(padding:const EdgeInsets.only(bottom:15),
  child:DropdownButtonFormField<String>(isExpanded:true,
  initialValue:app.period,
  decoration:const InputDecoration(labelText:'Reporting period'),
  items:periods.map((p)=>DropdownMenuItem(value:p,
  child:Text(p))).toList(),
  onChanged:(v){
    if(v!=null)app.selectPeriod(v);
  }));
} class RentPage extends StatefulWidget {
  const RentPage({
    super.key
  });
  @override State<RentPage> createState()=>_RentPageState();
} class _RentPageState extends State<RentPage>{
  String filter='All';
  @override Widget build(BuildContext context){
    final app=AppScope.of(context);
    final all=scopedInvoices(app),
    payments=app.rows('payments'),
    inv=all.where((i)=>filter=='All'||invoiceReviewStatus(i,payments)==filter).toList();
    return PageBody(title:app.owner?'Rent & dues':'My rent',
    refresh:app.refresh,
    children:[
      if(app.owner)...[
        propertySelector(context),
        periodSelector(context)
      ],
      HeroCard(label:app.owner?'Outstanding this month':'Your rent balance',
      value:inr(all.fold<double>(0,
      (s,
      i)=>s+amount(i[
        'outstanding'
      ]))),
      detail:app.owner?'${all.length} invoices · ${app.period}':'Pay directly to your PG owner.'),
      if(!app.owner)Surface(child:ListTile(
        title:const Text('Agreed monthly rent'),
        subtitle:const Text('Your monthly rent'),
        trailing:Text(inr((app.data['accommodation'] as Map?)?['monthly_rent']??'0'),
          style:const TextStyle(fontWeight:FontWeight.w700)))),
      Wrap(spacing:7,
      children:[
        for(final s in [
          'All',
          'Paid',
          'Pending',
          'Verification pending',
          'Partial',
          'Overdue'
        ])ChoiceChip(label:Text(tr(context,s)),
        selected:filter==s,
        onSelected:(_)=>setState(()=>filter=s))
      ]),
      const SizedBox(height:15),
      for(final i in inv) Builder(builder:(context){
        final proof = latestInvoiceProof(i, payments);
        final awaitingReview = invoiceReviewStatus(i,payments) == 'Verification pending';
        final rejectedProof = !awaitingReview &&
          proof != null && proof['status'] == 'rejected' &&
          amount(i['outstanding']) > 0;
        return Surface(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
      children:[
        Row(children:[
          Expanded(child:Text(app.owner?'${app.find('residents',i['resident_id']as int)?['name']??'Resident'}':'${i['period']}',
          style:const TextStyle(fontWeight:FontWeight.w800))),
          StatusPill(invoiceReviewStatus(i,payments))
        ]),
        if(app.owner)...[
          const SizedBox(height:7),
          Row(children:[
            Icon(Icons.apartment_rounded, size:19, color:Theme.of(context).colorScheme.primary),
            const SizedBox(width:6),
            Expanded(child:Text(
              pgNameForResident(app, app.find('residents', (i['resident_id'] as num?)?.toInt())),
              style:TextStyle(fontSize:14, color:Theme.of(context).colorScheme.primary, fontWeight:FontWeight.w700),
            )),
          ]),
        ],
        const SizedBox(height:12),
        Text(tr(context,'Amount paid'),
          style:TextStyle(fontSize:12,color:secondaryText(context),fontWeight:FontWeight.w600)),
        const SizedBox(height:3),
        Text(inr(verifiedAmount(i)),
          style:const TextStyle(fontSize:26,fontWeight:FontWeight.w900)),
        const SizedBox(height:6),
        Text('${tr(context,'Remaining balance')}: ${inr(i['outstanding'])}',
          style:const TextStyle(fontSize:12,fontWeight:FontWeight.w700)),
        const SizedBox(height:3),
        Text('${tr(context,'Billed')}: ${inr(i['amount'])}  ·  ${tr(context,'Verified')}: ${inr(i['paid'])}',
          style:TextStyle(color:secondaryText(context),fontSize:11)),
        if(awaitingReview && proof != null)...[
          const SizedBox(height:8),
          Text('${tr(context,'Submitted for verification')}: ${inr(proof['amount'])}',
            style:const TextStyle(color:Color(0xFF9A5200),fontSize:12,fontWeight:FontWeight.w700)),
          Text(tr(context,'Payment submitted. Awaiting confirmation.'),
            style:const TextStyle(color:Color(0xFF9A5200),fontSize:11)),
        ],
        if(rejectedProof)...[
          const SizedBox(height:10),
          Container(width:double.infinity,
            padding:const EdgeInsets.all(12),
            decoration:BoxDecoration(color:const Color(0xFFFFF0F1),
              borderRadius:BorderRadius.circular(12)),
            child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Row(children:[
                const Icon(Icons.error_outline,color:Color(0xFFA92842),size:19),
                const SizedBox(width:7),
                Expanded(child:Text(tr(context,'Proof rejected — submit the correct proof'),
                  style:const TextStyle(fontWeight:FontWeight.w800,color:Color(0xFFA92842),fontSize:12))),
              ]),
              if('${proof['reason']??''}'.trim().isNotEmpty)...[
                const SizedBox(height:5),
                Text('${tr(context,'Reason')}: ${proof['reason']}',
                  style:const TextStyle(fontSize:11)),
              ],
            ])),
        ],
        const SizedBox(height:5),
        Text('${tr(context,'Due')} ${i['due_date']}',
        style:TextStyle(color:secondaryText(context),
        fontSize:11)),
        if(!app.owner&&amount(i[
          'outstanding'
        ])>0)Padding(padding:const EdgeInsets.only(top:15),
        child:FilledButton(onPressed:invoiceReviewStatus(i,payments)=='Verification pending'?null:()=>openPage(context,
        'submitPayment',
        id:i[
          'id'
        ]as int),
        child:Text(tr(context,awaitingReview?'Awaiting owner verification':rejectedProof?'Resubmit correct proof':'Submit payment proof'))))
      ]));
      }),
      if(inv.isEmpty)const EmptyState('No invoices in this view.'),
      if(app.owner)...[
        FilledButton.icon(onPressed:()=>Navigator.push<void>(context,
        MaterialPageRoute(builder:(_)=>const InvoiceFormPage())),
        icon:const Icon(Icons.add),
        label:const Text('Create invoice')),
        const SizedBox(height:12),
        FeatureTile(title:'Payment verification',
        icon:Icons.verified_outlined,
        onTap:()=>openPage(context,
        'payments'))
      ]else ...[
        FeatureTile(title:'Owner payment details',
        icon:Icons.account_balance_outlined,
        onTap:()=>openPage(context,
        'paymentMethods')),
        FeatureTile(title:'Payment history & receipts',
        icon:Icons.receipt_long_outlined,
        onTap:()=>Navigator.push<void>(context,
        MaterialPageRoute(builder:(_)=>const PaymentsPage())))
      ]
    ]);
  }
} class InvoiceFormPage extends StatefulWidget {
  const InvoiceFormPage({
    super.key
  });
  @override State<InvoiceFormPage> createState()=>_InvoiceFormPageState();
} class _InvoiceFormPageState extends State<InvoiceFormPage>{
  final form=GlobalKey<FormState>();
  final period=TextEditingController(),
  amountInput=TextEditingController(),
  date=TextEditingController();
  int? resident;
  bool busy=false;
  @override void didChangeDependencies(){
    super.didChangeDependencies();
    if(period.text.isEmpty)period.text=AppScope.of(context).period;
  }@override void dispose(){
    period.dispose();
    amountInput.dispose();
    date.dispose();
    super.dispose();
  }@override Widget build(BuildContext context){
    final app=AppScope.of(context);
    return PageBody(title:'New invoice',
    children:[
      Surface(child:Form(key:form,
      child:Column(children:[
        DropdownButtonFormField<int>(isExpanded:true,
        decoration:const InputDecoration(labelText:'Resident'),
        items:app.rows('residents').map((r)=>DropdownMenuItem(value:r[
          'id'
        ]as int,
        child:Text('${r['name']}'))).toList(),
        onChanged:(v){
          resident=v;
          final row=app.rows('residents').where((r)=>r['id']==v).toList();
          if(row.isNotEmpty){final rent=amount(row.first['monthly_rent']);
            amountInput.text=rent>0?rent.toStringAsFixed(2):'';}
        },
        validator:(v)=>v==null?'Choose a resident':null),
        const SizedBox(height:15),
        TextFormField(controller:period,
        decoration:const InputDecoration(labelText:'Period YYYY-MM'),
        validator:(v)=>RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(v??'')?null:'Use YYYY-MM'),
        const SizedBox(height:15),
        TextFormField(controller:amountInput,
        keyboardType:TextInputType.number,
        decoration:const InputDecoration(labelText:'Monthly rent (₹)'),
        validator:(v)=>amount(v)>0?null:'Use a positive amount'),
        const SizedBox(height:15),
        TextFormField(controller:date,
        readOnly:true,
        decoration:const InputDecoration(labelText:'Due date',
        suffixIcon:Icon(Icons.calendar_today_outlined)),
        onTap:()async{
          final d=await showDatePicker(context:context,
          firstDate:DateTime(2020),
          lastDate:DateTime(2100),
          initialDate:DateTime.now());
          if(d!=null)date.text=d.toIso8601String().substring(0,
          10);
        },
        validator:(v)=>(v??'').isEmpty?'Choose a due date':null),
        const SizedBox(height:20),
        FilledButton(onPressed:busy?null:()async{
          if(!form.currentState!.validate())return;
          setState(()=>busy=true);
          final ok=await perform(context,
          ()=>app.mutate('/invoices',
          body:{
            'resident_id':resident,
            'period':period.text,
            'amount':amount(amountInput.text),
            'due_date':date.text
          }));
          if(mounted){
            setState(()=>busy=false);
            if(ok)Navigator.pop(context);
          }
        },
        child:Text(busy?'Creating…':'Create invoice'))
      ])))
    ]);
  }
} class SubmitPaymentPage extends StatefulWidget {
  const SubmitPaymentPage({
    super.key,
    required this.invoiceId
  });
  final int invoiceId;
  @override State<SubmitPaymentPage> createState()=>_SubmitPaymentPageState();
} class _SubmitPaymentPageState extends State<SubmitPaymentPage>{
  final form=GlobalKey<FormState>();
  final value=TextEditingController();
  Map<String,dynamic>? file;
  bool busy=false;
  bool fullyPaid=true;
  @override void dispose(){value.dispose();super.dispose();}
  Future<void> attach()async{
    setState(()=>busy=true);
    try{
      final picked=await FilePicker.platform.pickFiles(type:FileType.custom,
        allowedExtensions:['jpg','jpeg','png','webp','pdf'],withData:true);
      if(picked==null||!mounted)return;
      final f=picked.files.single;
      if(f.bytes==null)throw Exception('Unable to read attachment');
      if(f.size>5*1024*1024)throw Exception('Maximum file size is 5 MB');
      final uploaded=await AppScope.of(context).api.upload('/v3/files/payment',
        f.name,f.bytes!,mimeType(f.name));
      if(mounted)setState(()=>file=Map<String,dynamic>.from(uploaded as Map));
    }catch(e){if(mounted)feedback(context,e);}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context){
    final app=AppScope.of(context);
    final inv=app.find('invoices',widget.invoiceId);
    final balance=amount(inv?['outstanding']);
    final paid=fullyPaid?balance:amount(value.text);
    final remaining=(balance-paid).clamp(0, double.infinity);
    return PageBody(title:'Submit payment',
      subtitle:'Attach a screenshot of your payment.',
      children:[
        HeroCard(label:'Invoice balance',value:inr(balance)),
        Surface(child:Form(key:form,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(tr(context,'Payment type'),style:TextStyle(fontSize:17,fontWeight:FontWeight.w800,color:Theme.of(context).colorScheme.primary)),
          const SizedBox(height:12),
          Row(children:[
            Expanded(child:ChoiceChip(label:Text(tr(context,'Fully paid')),selected:fullyPaid,
              onSelected:(_)=>setState(()=>fullyPaid=true))),
            const SizedBox(width:10),
            Expanded(child:ChoiceChip(label:Text(tr(context,'Partially paid')),selected:!fullyPaid,
              onSelected:(_)=>setState(()=>fullyPaid=false))),
          ]),
          const SizedBox(height:16),
          if(!fullyPaid)...[
            TextFormField(controller:value,keyboardType:const TextInputType.numberWithOptions(decimal:true),
              onChanged:(_)=>setState((){}),
              decoration:const InputDecoration(labelText:'Amount paid (₹)',prefixIcon:Icon(Icons.currency_rupee)),
              validator:(v){final a=amount(v);return a>0&&a<balance?null:'Enter an amount below the outstanding balance';}),
            const SizedBox(height:12),
          ],
          Container(width:double.infinity,padding:const EdgeInsets.all(12),
            decoration:BoxDecoration(color:Theme.of(context).brightness==Brightness.dark?Theme.of(context).colorScheme.secondaryContainer:const Color(0xFFF7EEFC),borderRadius:BorderRadius.circular(14)),
            child:Text('Remaining after approval: ${inr(remaining)}',
              style:TextStyle(color:Theme.of(context).colorScheme.primary,fontWeight:FontWeight.w700))),
          const SizedBox(height:15),
          _ResidentOwnerPaymentPreview(),
          const SizedBox(height:15),
          OutlinedButton.icon(onPressed:busy?null:attach,
            icon:const Icon(Icons.attach_file),
            label:Text(file==null?'Upload payment proof (required)':'Proof attached — change file')),
          const SizedBox(height:5),
          Text('Screenshot or PDF (PNG, JPG, WebP or PDF; maximum 5 MB).',style:TextStyle(color:secondaryText(context),fontSize:11)),
          const SizedBox(height:18),
          SizedBox(width:double.infinity,child:FilledButton(onPressed:busy?null:()async{
            if(!form.currentState!.validate())return;
            if(balance<=0){feedback(context,'This invoice is already paid.');return;}
            if(file==null){feedback(context,'Attach your payment screenshot or PDF.');return;}
            setState(()=>busy=true);
            final ok=await perform(context,()=>app.mutate('/v3/payments',body:{
              'invoice_id':widget.invoiceId,
              'amount':paid,
              'file_id':file?['id']
            }),success:'Payment proof submitted for owner verification');
            if(mounted){setState(()=>busy=false);if(ok)Navigator.pop(context);}
          },child:Text(tr(context,busy?'Please wait…':'Submit for verification')))),
          const SizedBox(height:8),
          Text('Your balance updates once payment is confirmed.',style:TextStyle(fontSize:11,color:secondaryText(context))),
        ]))),
      ]);
  }
}
class _ResidentOwnerPaymentPreview extends StatelessWidget {
  const _ResidentOwnerPaymentPreview();
  @override Widget build(BuildContext context){
    final app=AppScope.of(context);
    final d=app.data['payment_methods'] as Map? ?? {};
    final upi='${d['upi_id']??''}'.trim();
    final bank='${d['bank_name']??''}'.trim();
    final holder='${d['bank_holder']??''}'.trim();
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('Owner payment details',style:TextStyle(fontWeight:FontWeight.w800,fontSize:16,color:Theme.of(context).colorScheme.primary)),
      const SizedBox(height:10),
      if(holder.isNotEmpty)Text(holder,style:const TextStyle(fontWeight:FontWeight.w700)),
      if(upi.isNotEmpty)Text('UPI: $upi',style:TextStyle(fontSize:12,color:secondaryText(context))),
      if(bank.isNotEmpty)Text('Bank: $bank',style:TextStyle(fontSize:12,color:secondaryText(context))),
      if('${d['bank_account']??''}'.trim().isNotEmpty)Text('Account: ${d['bank_account']}',style:TextStyle(fontSize:12,color:secondaryText(context))),
      if(d['qr_file_id'] is int) Padding(padding:const EdgeInsets.symmetric(vertical:10),
        child:FutureBuilder<Uint8List>(
          future:app.api.download('/v3/files/${d['qr_file_id']}'),
          builder:(context,snapshot){
            if(snapshot.connectionState!=ConnectionState.done) return const SizedBox(height:40,child:Center(child:CircularProgressIndicator()));
            if(snapshot.hasError||snapshot.data==null) return const Text('QR not available. View owner payment details.',style:TextStyle(fontSize:12));
            return Center(child:Image.memory(snapshot.data!,width:170,height:170,fit:BoxFit.contain));
          })),
      if(d['qr_file_id']==null)Text('No QR uploaded yet. Request payment details from your owner.',style:TextStyle(fontSize:12,color:secondaryText(context))),
      Text('Check the recipient in your UPI app before paying.',style:TextStyle(fontSize:11,color:secondaryText(context))),
    ]);
  }
} String mimeType(String name)=>switch(name.toLowerCase().split('.').last){
  'jpg'||'jpeg'=>'image/jpeg',
  'png'=>'image/png',
  'webp'=>'image/webp',
  'pdf'=>'application/pdf',
  'txt'=>'text/plain',
  _=>'application/octet-stream'
};
class PaymentsPage extends StatelessWidget {
  const PaymentsPage({
    super.key
  });
  @override Widget build(BuildContext context){
    final app=AppScope.of(context);
    return PageBody(title:app.owner?'Payment verification':'Payment history',
    subtitle:'Review payment status and approved receipts.',
    refresh:app.refresh,
    children:[
      for(final p in app.rows('payments').reversed)Surface(onTap:()=>openPage(context,
      'paymentDetail',
      id:p[
        'id'
      ]as int),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,
      children:[
        Row(children:[
          Expanded(child:Text(inr(p[
            'amount'
          ]),
          style:const TextStyle(fontWeight:FontWeight.w900,
          fontSize:22))),
          StatusPill(p['status']=='pending'?'Verification pending':'${p['status']}')
        ]),
        const SizedBox(height:10),
        Text(app.owner?'${app.find('residents',p['resident_id']as int)?['name']??'Resident'}':'Reference: ${p['reference']}',
        style:const TextStyle(fontWeight:FontWeight.w700,
        fontSize:12)),
        Text('${p['reference']} · ${p['created_at']}',
        style:TextStyle(color:secondaryText(context),
        fontSize:10)),
        if(app.owner&&p['status']=='rejected')
          Padding(padding:const EdgeInsets.only(top:8),
            child:Text(tr(context,'Awaiting corrected proof from resident'),
              style:const TextStyle(color:Color(0xFFA92842),fontWeight:FontWeight.w700,fontSize:12))),
        if(!app.owner&&p['status']=='rejected')
          Padding(padding:const EdgeInsets.only(top:8),
            child:Text(tr(context,'Proof rejected — submit the correct proof'),
              style:const TextStyle(color:Color(0xFFA92842),fontWeight:FontWeight.w700,fontSize:12))),
        if(!app.owner&&p['status']=='pending')
          Padding(padding:const EdgeInsets.only(top:8),
            child:Text(tr(context,'Awaiting owner verification'),
              style:const TextStyle(color:Color(0xFF9A5200),fontWeight:FontWeight.w700,fontSize:12))),
        if(app.owner)...[
          const SizedBox(height:8),
          if(p['risk_level']=='review_required' && p['status']=='approved' && p['risk_acknowledged']==true)
            Text(tr(context,'Approved after risk review'),style:const TextStyle(color:Color(0xFF9A5200),fontWeight:FontWeight.w700,fontSize:12))
          else if(p['risk_level']=='review_required')
            Row(children:[
              const Icon(Icons.warning_amber_rounded,size:17,color:Color(0xFF9A5200)),
              const SizedBox(width:6),
              Expanded(child:Text(tr(context,'Risk review required'),
                style:const TextStyle(color:Color(0xFF9A5200),fontWeight:FontWeight.w800,fontSize:12)))
            ])
          else if(p['risk_level']=='not_analyzed'||p['analysis_status']==null)
            Text(tr(context,'Proof analysis not available for this record'),
              style:TextStyle(color:secondaryText(context),fontSize:11))
          else
            Text(tr(context,'Document authenticity not verified'),
              style:TextStyle(color:secondaryText(context),fontSize:11)),
        ],
        if('${p['reason']??''}'.isNotEmpty)Text('${p['reason']}',
        style:TextStyle(color:secondaryText(context),
        fontSize:11))
      ])),
      if(app.rows('payments').isEmpty)const EmptyState('No payment submissions yet.')
    ]);
  }
} class PaymentDetailPage extends StatefulWidget {
  const PaymentDetailPage({
    super.key,
    required this.id
  });
  final int id;
  @override State<PaymentDetailPage> createState()=>_PaymentDetailPageState();
} class _PaymentDetailPageState extends State<PaymentDetailPage>{
  @override void initState(){
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if(!mounted)return;
      try { await AppScope.of(context).refresh(); }
      catch (_) { if(mounted)feedback(context,'Unable to refresh payment details.'); }
    });
  }
  bool busy=false,
  confirmed=false,
  riskAcknowledged=false;
  final reason=TextEditingController();
  @override void dispose(){
    reason.dispose();
    super.dispose();
  } Future<void> review(String decision)async{
    if(decision=='approved'&&!confirmed){
      feedback(context,
      'Confirm the bank credit first.');
      return;
    }if(decision=='approved' && AppScope.of(context).find('payments',widget.id)?['risk_level']=='review_required' && !riskAcknowledged){
      feedback(context,'Review the flagged proof and acknowledge its risks before approval.');
      return;
    }if(decision=='rejected'&&reason.text.trim().length<3){
      feedback(context,
      'Please give a rejection reason.');
      return;
    }if(!await ask(context,
    'Confirm $decision for this payment?')||!mounted)return;
    setState(()=>busy=true);
    await perform(context,
    ()=>AppScope.of(context).mutate('/v3/payments/${widget.id}/review',
    body:{
      'decision':decision,
      'bank_confirmed':confirmed,
      'risk_acknowledged':riskAcknowledged,
      'reason':reason.text.trim()
    }),
    success:'Payment reviewed');
    if(mounted)setState(()=>busy=false);
  } @override Widget build(BuildContext context){
    final app=AppScope.of(context),
    p=app.find('payments',
    widget.id);
    if(p==null)return const PageBody(title:'Payment',
    children:[
      EmptyState('Payment not found.')
    ]);
    return PageBody(title:'Payment details',
    children:[
      HeroCard(label:'Submitted amount',
      value:inr(p[
        'amount'
      ]),
      detail:'Reference · ${p['reference']}'),
      Surface(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
      children:[
        StatusPill(p['status']=='pending'?'Verification pending':'${p['status']}'),
        const SizedBox(height:10),
        if(app.owner) Container(
          width:double.infinity,
          padding:const EdgeInsets.all(12),
          decoration:BoxDecoration(color:const Color(0xFFFFF4E5),
            borderRadius:BorderRadius.circular(12)),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(tr(context,'Authenticity not verified'),
              style:const TextStyle(fontWeight:FontWeight.bold)),
            const SizedBox(height:5),
            Text(p['risk_level']=='not_analyzed'||p['analysis_status']==null
              ? tr(context,'Proof analysis not available for this record')
              : (p['risk_flags'] as List? ?? []).isEmpty
                ? tr(context,'No flags found')
                : (p['risk_flags'] as List).map((item)=>tr(context,'$item')).join(' • ')),
            const SizedBox(height:5),
            Text('${tr(context,'Analysis status')}: ${p['analysis_status']??'not_analyzed'}',
              style:TextStyle(fontSize:11,color:secondaryText(context))),
            const SizedBox(height:5),
            Text(tr(context,'Check bank credit before approval'),
              style:const TextStyle(fontSize:12)),
            const SizedBox(height:5),
            Text(tr(context,'AI origin cannot be confirmed from this file.'),
              style:const TextStyle(fontSize:11)),
            if((p['review_notes'] as List? ?? []).isNotEmpty) ...[
              const SizedBox(height:5),
              Text((p['review_notes'] as List).map((item)=>tr(context,'$item')).join(' • '),
                style:const TextStyle(fontSize:11)),
            ],
          ])),

        if(p[
          'file_id'
        ]!=null)OutlinedButton.icon(onPressed:()=>openPrivateFile(context,
        p[
          'file_id'
        ]as int),
        icon:const Icon(Icons.attachment),
        label:Text(tr(context,'View payment proof'))),
        if(p['status']=='rejected')
          Padding(padding:const EdgeInsets.only(top:8),
            child:Text(tr(context,'Proof rejected — submit the correct proof'),
              style:const TextStyle(fontWeight:FontWeight.w700,color:Color(0xFFA92842)))),
        if('${p['reason']??''}'.isNotEmpty)Text('${tr(context,'Review note')}: ${p['reason']}'),
        if(p[
          'status'
        ]=='approved')FilledButton(onPressed:()=>openPage(context,
        'receipt',
        id:widget.id),
        child:Text(tr(context,'View receipt')))
      ])),
      if(app.profile[
        'role'
      ]=='owner'&&p[
        'status'
      ]=='pending')Surface(child:Column(children:[
        CheckboxListTile(value:confirmed,
        onChanged:(v)=>setState(()=>confirmed=v??false),
        title:Text(tr(context,'I have confirmed the credit in the bank / UPI statement.'),
        style:const TextStyle(fontSize:12))),
        if(p['risk_level']=='review_required')
          CheckboxListTile(value:riskAcknowledged,
            onChanged:(v)=>setState(()=>riskAcknowledged=v??false),
            title:Text(tr(context,'I reviewed the risk flags and verified the payment independently.'),
              style:const TextStyle(fontSize:12))),
        FilledButton(onPressed:busy?null:()=>review('approved'),
        child:Text(tr(context,'Approve payment'))),
        const SizedBox(height:20),
        TextField(controller:reason,
        decoration:InputDecoration(labelText:tr(context,'Reason for rejection'))),
        const SizedBox(height:12),
        OutlinedButton(onPressed:busy?null:()=>review('rejected'),
        child:Text(tr(context,'Reject proof')))
      ]))
    ]);
  }
} Future<void> openPrivateFile(BuildContext context,
int id)async{
  final app=AppScope.of(context),
  file=app.find('files',
  id);
  await showFile(context,
  '/v3/files/$id',
  '${file?['filename']??'attachment.bin'}',
  image:'${file?['mime']}'.startsWith('image/'));
} class ReceiptPage extends StatefulWidget {
  const ReceiptPage({
    super.key,
    required this.id
  });
  final int id;
  @override State<ReceiptPage> createState()=>_ReceiptPageState();
} class _ReceiptPageState extends State<ReceiptPage>{
  Map<String,
  dynamic>? receipt;
  String? error;
  @override void didChangeDependencies(){
    super.didChangeDependencies();
    if(receipt==null&&error==null)load();
  }Future<void> load()async{
    try{
      final d=await AppScope.of(context).api.request('/receipts/${widget.id}');
      if(mounted)setState(()=>receipt=Map<String,
      dynamic>.from(d as Map));
    }catch(e){
      if(mounted)setState(()=>error='$e');
    }
  }@override Widget build(BuildContext context){
    final r=receipt;
    return PageBody(title:'Payment receipt',
    children:[
      if(error!=null)...[
        Text(error!),
        TextButton(onPressed:load,
        child:const Text('Retry'))
      ]else if(r==null)const Center(child:CircularProgressIndicator())else ...[
        Surface(child:Column(children:[
          const OfficialBrand(),
          const SizedBox(height:20),
          Text('${r['receipt_number']}',
          style:const TextStyle(fontWeight:FontWeight.w800)),
          const SizedBox(height:10),
          Text(inr(r[
            'amount'
          ]),
          style:const TextStyle(fontSize:34,
          fontWeight:FontWeight.w900)),
          const StatusPill('Approved'),
          const SizedBox(height:20),
          Text('${r['pg_name']}\n${r['resident']}\nRent month: ${r['period']}\nInternal receipt reference: ${r['reference']}\nRecorded: ${friendlyDate(r['recorded_at'])}',
          textAlign:TextAlign.center,
          style:const TextStyle(height:1.7))
        ])),
        FilledButton.icon(onPressed:()=>saveBytes(context,
        Uint8List.fromList(utf8.encode('COME.in PAYMENT RECEIPT\n${r.entries.map((e)=>'${e.key}: ${e.value}').join('\n')}')),
        'COME_in_receipt_${widget.id}.txt'),
        icon:const Icon(Icons.download_outlined),
        label:const Text('Save receipt'))
      ]
    ]);
  }
} class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key});
  @override State<ExpensesPage> createState()=>_ExpensesPageState();
} class _ExpensesPageState extends State<ExpensesPage> {
  final form=GlobalKey<FormState>();
  final description=TextEditingController();
  final amountController=TextEditingController();
  String category='Utilities';
  bool saving=false;
  String? error;
  int? entryProperty;

  @override void dispose(){
    description.dispose();
    amountController.dispose();
    super.dispose();
  }

  Future<void> saveExpense(AppController app)async{
    if(!(form.currentState?.validate()??false))return;
    final properties=app.rows('properties');
    final pid=entryProperty??app.propertyId;
    if(pid==null||!properties.any((p)=>p['id']==pid)){
      setState(()=>error='Select the PG for this expense.');return;
    }
    setState((){saving=true;error=null;});
    try{
      await app.save('expense',{
        'property_id':pid,
        'description':description.text.trim(),
        'category':category,
        'amount':num.parse(amountController.text.trim()),
        'period':app.period,
      });
      if(!mounted)return;
      description.clear();amountController.clear();
      setState(()=>entryProperty=pid);
      feedback(context,'Expense saved to selected PG');
    }catch(e){
      if(mounted)setState(()=>error='$e');
    }finally{
      if(mounted)setState(()=>saving=false);
    }
  }

  @override Widget build(BuildContext context){
    final app=AppScope.of(context);
    final properties=app.rows('properties').where((p)=>p['archived']!=true).toList();
    final pid=entryProperty??app.propertyId;
    final validPid=properties.any((p)=>p['id']==pid)?pid:null;
    final rows=app.scoped('expenses').where((r)=>r['period']==app.period).toList();
    return PageBody(title:'Expenses & cashflow',refresh:app.refresh,children:[
      Surface(child:Form(key:form,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('Record an expense',style:TextStyle(fontSize:18,fontWeight:FontWeight.w800)),
        const SizedBox(height:5),
        Text('Choose the PG receiving this expense. Each expense is recorded against that PG.',style:TextStyle(fontSize:12,color:secondaryText(context))),
        const SizedBox(height:16),
        DropdownButtonFormField<int>(isExpanded:true,initialValue:validPid,
          decoration:const InputDecoration(labelText:'Expense for PG *'),
          hint:const Text('Select PG property'),
          items:properties.map((p)=>DropdownMenuItem<int>(value:p['id'] as int,
            child:Text('${p['name']}',overflow:TextOverflow.ellipsis))).toList(),
          validator:(v)=>v==null?'Select the PG':null,
          onChanged:saving?null:(v)=>setState(()=>entryProperty=v)),
        const SizedBox(height:12),
        TextFormField(controller:description,decoration:const InputDecoration(labelText:'Expense description *'),
          validator:(v)=>(v?.trim().isEmpty??true)?'Enter a description':null),
        const SizedBox(height:12),
        DropdownButtonFormField<String>(initialValue:category,isExpanded:true,
          decoration:const InputDecoration(labelText:'Category *'),
          items:['Utilities','Operations','Food','Maintenance','General']
            .map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),
          onChanged:saving?null:(v)=>setState(()=>category=v??'Utilities')),
        const SizedBox(height:12),
        TextFormField(controller:amountController,keyboardType:const TextInputType.numberWithOptions(decimal:true),
          decoration:const InputDecoration(labelText:'Amount (₹) *'),
          validator:(v){final a=num.tryParse(v?.trim()??'');
            return a==null||!a.isFinite||a<=0?'Enter a valid positive amount':null;}),
        const SizedBox(height:10),
        Text('Reporting month: ${app.period}',style:TextStyle(color:secondaryText(context),fontSize:12)),
        if(error!=null)Padding(padding:const EdgeInsets.only(top:10),child:Text(error!,style:const TextStyle(color:Colors.red))),
        const SizedBox(height:14),
        SizedBox(width:double.infinity,child:FilledButton.icon(
          onPressed:saving?null:()=>saveExpense(app),
          icon:const Icon(Icons.add),
          label:Text(saving?'Saving…':'Save expense to PG'))),
      ]))),
      const SizedBox(height:12),
      const Text('Recorded expenses',style:TextStyle(fontSize:17,fontWeight:FontWeight.w800)),
      propertySelector(context),
      periodSelector(context),
      HeroCard(label:'Recorded operating expenses',
        value:inr(rows.fold<double>(0,(s,r)=>s+amount(r['amount'])))),
      for(final r in rows)Surface(onTap:()=>editEntity(context,'expense',id:r['id'] as int,initial:r),
        child:Row(children:[
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('${r['description']}',style:const TextStyle(fontWeight:FontWeight.w800)),
            Row(children:[Icon(Icons.apartment_rounded,size:17,color:Theme.of(context).colorScheme.primary),const SizedBox(width:5),Expanded(child:Text('PG: ${app.find('properties',(r['property_id'] as num?)?.toInt()??0)?['name']??'Primary PG'} · ${r['category']}',
              style:TextStyle(color:Theme.of(context).colorScheme.primary,fontSize:14,fontWeight:FontWeight.w700)))])])),
          Text(inr(r['amount']),style:const TextStyle(fontWeight:FontWeight.w800)),
          const Icon(Icons.edit_outlined,size:17)
        ])),
      if(rows.isEmpty)const EmptyState('No expenses for this period.'),
    ]);
  }
} class ReportsPage extends StatefulWidget {
  const ReportsPage({
    super.key
  });
  @override State<ReportsPage> createState()=>_ReportsPageState();
} class _ReportsPageState extends State<ReportsPage>{
  String tab='Overview';
  @override Widget build(BuildContext context){
    final app=AppScope.of(context);
    final invoices=scopedInvoices(app),
    expenses=app.scoped('expenses').where((r)=>r[
      'period'
    ]==app.period).toList();
    final billed=invoices.fold<double>(0,
    (s,
    r)=>s+amount(r[
      'amount'
    ])),
    paid=invoices.fold<double>(0,
    (s,
    r)=>s+amount(r[
      'paid'
    ])),
    spent=expenses.fold<double>(0,
    (s,
    r)=>s+amount(r[
      'amount'
    ]));
    final beds=app.scoped('rooms').fold<int>(0,
    (s,
    r)=>s+(r[
      'beds'
    ]as int));
    return PageBody(title:'Reports & analytics',
    subtitle:'Income and expenses at a glance.',
    refresh:app.refresh,
    children:[
      propertySelector(context),
      periodSelector(context),
      Wrap(spacing:6,
      children:[
        for(final name in [
          'Overview',
          'Payments',
          'Occupancy',
          'Residents'
        ])ChoiceChip(label:Text(name),
        selected:tab==name,
        onSelected:(_)=>setState(()=>tab=name))
      ]),
      const SizedBox(height:15),
      if(tab=='Overview')... [
        HeroCard(label:'Net cashflow',
        value:inr(paid-spent),
        detail:'Collected less recorded expenses'),
        Surface(child:Column(children:[
          _bar('Billed',
          billed,
          billed+spent,
          lavender),
          _bar('Collected',
          paid,
          billed+spent,
          successGreen),
          _bar('Expenses',
          spent,
          billed+spent,
          const Color(0xFFBF8152)),
          const SizedBox(height:10),
          Text('Deposits, refunds and tax are excluded.',style:TextStyle(color:secondaryText(context),
          fontSize:10))
        ]))
      ]else if(tab=='Occupancy')HeroCard(label:'Occupancy',
      value:'${beds==0?0:(app.scoped('residents').where((r)=>'${r['room']}'.isNotEmpty).length/beds*100).round()}%',
      detail:'${app.scoped('residents').length} residents · $beds beds')else if(tab=='Residents')... app.scoped('residents').map((r)=>FeatureTile(title:'${r['name']}',
      subtitle:'${pgNameForResident(app, r)} · Room ${r['room']}',
      icon:Icons.apartment_rounded,
      onTap:()=>openPage(context,
      'residentDetail',
      id:r[
        'id'
      ]as int)))else ...invoices.map((r)=>Surface(child:Row(children:[
        Expanded(child:Text('${app.find('residents',r['resident_id']as int)?['name']??r['resident_id']}')),
        StatusPill(invoiceStatus(r)),
        const SizedBox(width:10),
        Text(inr(r[
          'outstanding'
        ]))
      ]))),
      const SizedBox(height:16),
      FilledButton.icon(onPressed:()=>export(context,
      invoices,
      expenses,
      app.period),
      icon:const Icon(Icons.download_outlined),
      label:const Text('Export CSV report'))
    ]);
  } Widget _bar(String title,
  double value,
  double total,
  Color color)=>Padding(padding:const EdgeInsets.only(bottom:15),
  child:Column(children:[
    Row(children:[
      Expanded(child:Text(title,
      style:const TextStyle(fontSize:12))),
      Text(inr(value),
      style:const TextStyle(fontWeight:FontWeight.w800,
      fontSize:12))
    ]),
    const SizedBox(height:8),
    LinearProgressIndicator(value:total==0?0:(value/total).clamp(0,
    1).toDouble(),
    backgroundColor:lavender.withValues(alpha:.1),
    color:color,
    minHeight:8,
    borderRadius:BorderRadius.circular(10))
  ]));
  void export(BuildContext context,
  List<Map<String,
  dynamic>> inv,
  List<Map<String,
  dynamic>> exp,
  String period){
    String cell(dynamic value){
      var s='$value';
      if(RegExp(r'^[=+@-]').hasMatch(s))s="'$s";
      return '"${s.replaceAll('"','""')}"';
    }final rows=<List<dynamic>>[
      [
        'Type',
        'ID',
        'Period',
        'Amount',
        'Paid',
        'Balance'
      ],
      for(final i in inv)[
        'Invoice',
        i[
          'id'
        ],
        i[
          'period'
        ],
        i[
          'amount'
        ],
        i[
          'paid'
        ],
        i[
          'outstanding'
        ]
      ],
      for(final e in exp)[
        'Expense',
        e[
          'id'
        ],
        e[
          'period'
        ],
        e[
          'amount'
        ],
        '',
        ''
      ]
    ];
    saveBytes(context,
    Uint8List.fromList(utf8.encode(rows.map((r)=>r.map(cell).join(',')).join('\r\n'))),
    'COME_in_report_$period.csv');
  }
} class PaymentMethodsPage extends StatefulWidget {
  const PaymentMethodsPage({
    super.key
  });
  @override State<PaymentMethodsPage> createState()=>_PaymentMethodsPageState();
} class _PaymentMethodsPageState extends State<PaymentMethodsPage>{
  final form=GlobalKey<FormState>();
  final controls={
    for(final key in [
      'upi_id',
      'bank_holder',
      'bank_name',
      'bank_account',
      'ifsc'
    ])key:TextEditingController()
  };
  bool editing=false,
  busy=false;
  int? selectedPaymentProperty;
  @override void dispose(){
    for(final c in controls.values)c.dispose();
    super.dispose();
  }@override Widget build(BuildContext context){
    final app=AppScope.of(context),
    pid=selectedPaymentProperty??app.propertyId??0;
    final methods=(app.data['property_payment_methods'] as List? ?? const []);
    final d=app.owner
      ? (methods.where((x)=>x is Map && x['property_id']==pid).isNotEmpty
          ? Map<String,dynamic>.from(methods.firstWhere((x)=>x is Map && x['property_id']==pid) as Map)
          : <String,dynamic>{})
      : Map<String,dynamic>.from(app.data['payment_methods'] as Map? ?? {});
    return PageBody(title:'Owner payment details',
    subtitle:'Verify the recipient in your UPI / bank app before paying.',
    children:[
      if(app.owner)DropdownButtonFormField<int>(
        isExpanded:true,
        initialValue:pid,
        decoration:const InputDecoration(labelText:'Payment account for PG *'),
        items:app.rows('properties').where((p)=>p['archived']!=true).map((p)=>DropdownMenuItem<int>(value:(p['id'] as num).toInt(),child:Text('🏢 ${p['name']}'))).toList(),
        onChanged:(v){if(v==null)return;setState((){selectedPaymentProperty=v;editing=false;});}),
      const SizedBox(height:12),
      Surface(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
      children:[
        Text(app.owner?'Payment destination for this PG':'Pay directly to your PG owner',
          style:const TextStyle(fontWeight:FontWeight.w800, fontSize:16)),
        const SizedBox(height:10),
        if('${d['upi_id']??''}'.trim().isNotEmpty)...[
          Text('UPI ID: ${d['upi_id']}',style:const TextStyle(fontWeight:FontWeight.w700)),
          TextButton.icon(onPressed:()=>copyValue(context,'${d['upi_id']}'),
          icon:const Icon(Icons.copy,size:16),label:const Text('Copy UPI ID')),
        ],
        if('${d['bank_holder']??''}'.trim().isNotEmpty)Text('Account holder: ${d['bank_holder']}'),
        if('${d['bank_name']??''}'.trim().isNotEmpty)Text('Bank: ${d['bank_name']}'),
        if('${d['bank_account']??''}'.trim().isNotEmpty)Text('Account: ${d['bank_account']}')else if('${d['bank_account_masked']??''}'.trim().isNotEmpty)Text('Account: ${d['bank_account_masked']}'),
        if('${d['ifsc']??''}'.trim().isNotEmpty)Text('IFSC: ${d['ifsc']}'),
        if(d['qr_file_id'] is int)Padding(padding:const EdgeInsets.only(top:14),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          const Text('Scan owner UPI QR',style:TextStyle(fontWeight:FontWeight.w800)),
          const SizedBox(height:8),
          FutureBuilder<Uint8List>(
            future:app.api.download('/v3/files/${d['qr_file_id']}'),
            builder:(context,snapshot){
              if(snapshot.connectionState!=ConnectionState.done) return const Center(child:CircularProgressIndicator());
              if(snapshot.hasError||snapshot.data==null) return const Text('QR image unavailable. Use the UPI ID or contact your PG owner.');
              return Center(child:ClipRRect(borderRadius:BorderRadius.circular(12),
                child:Image.memory(snapshot.data!,width:220,height:220,fit:BoxFit.contain)));
            }),
          ])),
        if(d['qr_file_id']==null)Padding(padding:const EdgeInsets.only(top:12),
          child:Text(app.owner?'No UPI QR uploaded for this PG yet. Use the Upload QR button below.':
          'No QR image uploaded yet. Contact your PG owner for payment details.',
          style:TextStyle(color:secondaryText(context)))),
        const SizedBox(height:8),
        Text('Always verify the beneficiary name in your UPI or bank app before sending money.',style:TextStyle(color:secondaryText(context),fontSize:12)),
      ])),
      if(app.profile[
        'role'
      ]=='owner')... [
        OutlinedButton(onPressed:(){
          for(final key in controls.keys){
            controls[
              key
            ]!.text=key=='bank_account'?'':'${d[key]??''}';
          }setState(()=>editing=!editing);
        },
        child:Text(editing?'Close bank / UPI editor':
          (d['upi_id']==null && d['bank_name']==null ? 'Add bank account / UPI details':'Edit bank account / UPI details'))),
        FilledButton.icon(
          onPressed:busy?null:()async{
            setState(()=>busy=true);
            try{
              final picked=await FilePicker.platform.pickFiles(
                type:FileType.custom,allowedExtensions:['jpg','jpeg','png','webp'],withData:true);
              if(picked==null||!mounted)return;
              final f=picked.files.single;
              if(f.bytes==null||f.bytes!.isEmpty)throw Exception('Unable to read QR image');
              if(f.bytes!.length>5*1024*1024)throw Exception('QR image must be smaller than 5 MB');
              final app=AppScope.of(context);
              final uploaded=await app.api.upload('/v3/files/owner_qr',f.name,f.bytes!,mimeType(f.name));
              await app.mutate('/v3/payment-qr',method:'PUT',body:{'file_id':(uploaded as Map)['id'],'property_id':pid});
              if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(
                d['qr_file_id'] is int?'UPI QR replaced for this PG':'UPI QR uploaded for this PG')));
            }catch(e){if(mounted)feedback(context,e);}
            finally{if(mounted)setState(()=>busy=false);}
          },
          icon:busy?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)):
            const Icon(Icons.qr_code_2),
          label:Text(busy?'Uploading QR…':(d['qr_file_id'] is int?'Change UPI QR image':'Upload UPI QR image'))),
        const SizedBox(height:10),
        if(editing)Surface(child:Form(key:form,
        child:Column(children:[
          for(final e in controls.entries)Padding(padding:const EdgeInsets.only(bottom:15),
          child:TextFormField(controller:e.value,
          decoration:InputDecoration(labelText:switch(e.key){'upi_id'=>'UPI ID','bank_holder'=>'Account holder','bank_name'=>'Bank name','bank_account'=>'Account number','ifsc'=>'IFSC',_=>e.key}),
          validator:(v)=>null)),
          FilledButton(onPressed:busy?null:()async{
            if(!form.currentState!.validate())return;
            if(!await ask(context,
            'Save these payment destination details?')||!context.mounted)return;
            setState(()=>busy=true);
            final ok=await perform(context,
            ()=>app.mutate('/v3/property-payment',
            method:'PUT',
            body:{
              'property_id':pid,
              for(final e in controls.entries)e.key:e.value.text.trim()
            }),
            success:'Payment settings saved');
            if(mounted)setState((){
              busy=false;
              if(ok)editing=false;
            });
          },
          child:Text(busy?'Saving…':'Save payment details for this PG'))
        ])))
      ]
    ]);
  }
}

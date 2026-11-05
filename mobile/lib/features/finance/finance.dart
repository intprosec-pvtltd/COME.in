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
    inv=all.where((i)=>filter=='All'||invoiceStatus(i)==filter).toList();
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
      Wrap(spacing:7,
      children:[
        for(final s in [
          'All',
          'Paid',
          'Pending',
          'Partial',
          'Overdue'
        ])ChoiceChip(label:Text(s),
        selected:filter==s,
        onSelected:(_)=>setState(()=>filter=s))
      ]),
      const SizedBox(height:15),
      for(final i in inv)Surface(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
      children:[
        Row(children:[
          Expanded(child:Text(app.owner?'${app.find('residents',i['resident_id']as int)?['name']??'Resident'}':'${i['period']}',
          style:const TextStyle(fontWeight:FontWeight.w800))),
          StatusPill(invoiceStatus(i))
        ]),
        const SizedBox(height:12),
        Text(inr(i[
          'outstanding'
        ]),
        style:const TextStyle(fontSize:24,
        fontWeight:FontWeight.w900)),
        Text('Billed ${inr(i['amount'])} · Verified ${inr(i['paid'])}',
        style:const TextStyle(color:muted,
        fontSize:11)),
        const SizedBox(height:5),
        Text('Due ${i['due_date']}',
        style:const TextStyle(color:muted,
        fontSize:11)),
        if(!app.owner&&amount(i[
          'outstanding'
        ])>0)Padding(padding:const EdgeInsets.only(top:15),
        child:FilledButton(onPressed:()=>openPage(context,
        'submitPayment',
        id:i[
          'id'
        ]as int),
        child:const Text('Submit payment proof')))
      ])),
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
        onChanged:(v)=>resident=v,
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
      subtitle:'Upload proof of payment. Your PG owner will confirm the bank credit.',
      children:[
        HeroCard(label:'Invoice balance',value:inr(balance)),
        Surface(child:Form(key:form,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          const Text('Payment type',style:TextStyle(fontSize:17,fontWeight:FontWeight.w800,color:plum)),
          const SizedBox(height:12),
          Row(children:[
            Expanded(child:ChoiceChip(label:const Text('Fully paid'),selected:fullyPaid,
              onSelected:(_)=>setState(()=>fullyPaid=true))),
            const SizedBox(width:10),
            Expanded(child:ChoiceChip(label:const Text('Partially paid'),selected:!fullyPaid,
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
            decoration:BoxDecoration(color:const Color(0xFFF7EEFC),borderRadius:BorderRadius.circular(14)),
            child:Text('Remaining after approval: ${inr(remaining)}',
              style:const TextStyle(color:plum,fontWeight:FontWeight.w700))),
          const SizedBox(height:15),
          _ResidentOwnerPaymentPreview(),
          const SizedBox(height:15),
          OutlinedButton.icon(onPressed:busy?null:attach,
            icon:const Icon(Icons.attach_file),
            label:Text(file==null?'Upload payment proof (required)':'Proof attached — change file')),
          const SizedBox(height:5),
          const Text('Screenshot or PDF (PNG, JPG, WebP or PDF; maximum 5 MB).',
            style:TextStyle(color:muted,fontSize:11)),
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
          },child:Text(busy?'Please wait…':'Submit for verification'))),
          const SizedBox(height:8),
          const Text('Your rent balance will update after the owner verifies actual bank credit.',
            style:TextStyle(fontSize:11,color:muted)),
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
      const Text('Owner payment details',style:TextStyle(fontWeight:FontWeight.w800,fontSize:16,color:plum)),
      const SizedBox(height:10),
      if(holder.isNotEmpty)Text(holder,style:const TextStyle(fontWeight:FontWeight.w700)),
      if(upi.isNotEmpty)Text('UPI: $upi',style:const TextStyle(fontSize:12,color:muted)),
      if(bank.isNotEmpty)Text('Bank: $bank',style:const TextStyle(fontSize:12,color:muted)),
      if(d['qr_file_id'] is int) Padding(padding:const EdgeInsets.symmetric(vertical:10),
        child:FutureBuilder<Uint8List>(
          future:app.api.download('/v3/files/${d['qr_file_id']}'),
          builder:(context,snapshot){
            if(snapshot.connectionState!=ConnectionState.done) return const SizedBox(height:40,child:Center(child:CircularProgressIndicator()));
            if(snapshot.hasError||snapshot.data==null) return const Text('QR not available. View owner payment details.',style:TextStyle(fontSize:12));
            return Center(child:Image.memory(snapshot.data!,width:170,height:170,fit:BoxFit.contain));
          })),
      if(d['qr_file_id']==null)const Text('No QR uploaded yet. Request payment details from your owner.',style:TextStyle(fontSize:12,color:muted)),
      const Text('Check the recipient in your UPI app before paying.',style:TextStyle(fontSize:11,color:muted)),
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
          StatusPill('${p['status']}')
        ]),
        const SizedBox(height:10),
        Text(app.owner?'${app.find('residents',p['resident_id']as int)?['name']??'Resident'}':'Reference: ${p['reference']}',
        style:const TextStyle(fontWeight:FontWeight.w700,
        fontSize:12)),
        Text('${p['reference']} · ${p['created_at']}',
        style:const TextStyle(color:muted,
        fontSize:10)),
        if('${p['reason']??''}'.isNotEmpty)Text('${p['reason']}',
        style:const TextStyle(color:muted,
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
  bool busy=false,
  confirmed=false;
  final reason=TextEditingController();
  @override void dispose(){
    reason.dispose();
    super.dispose();
  } Future<void> review(String decision)async{
    if(decision=='approved'&&!confirmed){
      feedback(context,
      'Confirm the bank credit first.');
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
        StatusPill('${p['status']}'),
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
            Text((p['risk_flags'] as List? ?? []).isEmpty
              ? tr(context,'No flags found')
              : (p['risk_flags'] as List).join(' • ')),
            const SizedBox(height:5),
            Text(tr(context,'Check bank credit before approval'),
              style:const TextStyle(fontSize:12)),
          ])),

        if(p[
          'file_id'
        ]!=null)OutlinedButton.icon(onPressed:()=>openPrivateFile(context,
        p[
          'file_id'
        ]as int),
        icon:const Icon(Icons.attachment),
        label:const Text('View payment proof')),
        if('${p['reason']??''}'.isNotEmpty)Text('Review note: ${p['reason']}'),
        if(p[
          'status'
        ]=='approved')FilledButton(onPressed:()=>openPage(context,
        'receipt',
        id:widget.id),
        child:const Text('View receipt'))
      ])),
      if(app.profile[
        'role'
      ]=='owner'&&p[
        'status'
      ]=='pending')Surface(child:Column(children:[
        CheckboxListTile(value:confirmed,
        onChanged:(v)=>setState(()=>confirmed=v??false),
        title:const Text('I have confirmed the credit in the bank / UPI statement.',
        style:TextStyle(fontSize:12))),
        FilledButton(onPressed:busy?null:()=>review('approved'),
        child:const Text('Approve payment')),
        const SizedBox(height:20),
        TextField(controller:reason,
        decoration:const InputDecoration(labelText:'Reason for rejection')),
        const SizedBox(height:12),
        OutlinedButton(onPressed:busy?null:()=>review('rejected'),
        child:const Text('Reject proof'))
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
} class ExpensesPage extends StatelessWidget {
  const ExpensesPage({
    super.key
  });
  @override Widget build(BuildContext context){
    final app=AppScope.of(context);
    final rows=app.scoped('expenses').where((r)=>r[
      'period'
    ]==app.period).toList();
    return PageBody(title:'Expenses & cashflow',
    refresh:app.refresh,
    children:[
      propertySelector(context),
      periodSelector(context),
      HeroCard(label:'Recorded operating expenses',
      value:inr(rows.fold<double>(0,
      (s,
      r)=>s+amount(r[
        'amount'
      ])))),
      for(final r in rows)Surface(onTap:()=>editEntity(context,
      'expense',
      id:r[
        'id'
      ]as int,
      initial:r),
      child:Row(children:[
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
        children:[
          Text('${r['description']}',
          style:const TextStyle(fontWeight:FontWeight.w800)),
          Text('${r['category']}',
          style:const TextStyle(color:muted,
          fontSize:11))
        ])),
        Text(inr(r[
          'amount'
        ]),
        style:const TextStyle(fontWeight:FontWeight.w800)),
        const Icon(Icons.edit_outlined,
        size:17)
      ])),
      if(rows.isEmpty)const EmptyState('No expenses in this period.'),
      addButton(context,
      'Add expense',
      'expense')
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
    subtitle:'Calculated from your recorded invoices and expenses.',
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
          const Text('Deposits, refunds and tax are excluded.',
          style:TextStyle(color:muted,
          fontSize:10))
        ]))
      ]else if(tab=='Occupancy')HeroCard(label:'Occupancy',
      value:'${beds==0?0:(app.scoped('residents').where((r)=>'${r['room']}'.isNotEmpty).length/beds*100).round()}%',
      detail:'${app.scoped('residents').length} residents · $beds beds')else if(tab=='Residents')... app.scoped('residents').map((r)=>FeatureTile(title:'${r['name']}',
      subtitle:'Room ${r['room']}',
      icon:Icons.person_outline,
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
  @override void dispose(){
    for(final c in controls.values)c.dispose();
    super.dispose();
  }@override Widget build(BuildContext context){
    final app=AppScope.of(context),
    d=app.data[
      'payment_methods'
    ]as Map? ?? {
    };
    return PageBody(title:'Owner payment details',
    subtitle:'Verify the recipient in your UPI / bank app before paying.',
    children:[
      Surface(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
      children:[
        const Text('Pay directly to your PG owner', style:TextStyle(fontWeight:FontWeight.w800, fontSize:16)),
        const SizedBox(height:10),
        if('${d['upi_id']??''}'.trim().isNotEmpty)...[
          Text('UPI ID: ${d['upi_id']}',style:const TextStyle(fontWeight:FontWeight.w700)),
          TextButton.icon(onPressed:()=>copyValue(context,'${d['upi_id']}'),
          icon:const Icon(Icons.copy,size:16),label:const Text('Copy UPI ID')),
        ],
        if('${d['bank_holder']??''}'.trim().isNotEmpty)Text('Account holder: ${d['bank_holder']}'),
        if('${d['bank_name']??''}'.trim().isNotEmpty)Text('Bank: ${d['bank_name']}'),
        if('${d['bank_account_masked']??''}'.trim().isNotEmpty)Text('Account: ${d['bank_account_masked']}'),
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
        if(d['qr_file_id']==null)const Padding(padding:EdgeInsets.only(top:12),
          child:Text('No QR image uploaded yet. Check payment details with your PG owner.',style:TextStyle(color:muted))),
        const SizedBox(height:8),
        const Text('Always verify the beneficiary name in your UPI or bank app before sending money.',
          style:TextStyle(color:muted,fontSize:12)),
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
        child:const Text('Update payment settings')),
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
              await app.mutate('/v3/payment-qr',method:'PUT',body:{'file_id':(uploaded as Map)['id']});
              if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Owner QR image updated')));
            }catch(e){if(mounted)feedback(context,e);}
            finally{if(mounted)setState(()=>busy=false);}
          },
          icon:const Icon(Icons.qr_code_2),
          label:const Text('Upload / replace my UPI QR image')),
        const SizedBox(height:10),
        if(editing)Surface(child:Form(key:form,
        child:Column(children:[
          for(final e in controls.entries)Padding(padding:const EdgeInsets.only(bottom:15),
          child:TextFormField(controller:e.value,
          decoration:InputDecoration(labelText:switch(e.key){'upi_id'=>'UPI ID','bank_holder'=>'Account holder','bank_name'=>'Bank name','bank_account'=>'Account number','ifsc'=>'IFSC',_=>e.key}),
          validator:(v)=>e.key=='bank_account'&&(v??'').isEmpty?'Enter the full account number to save':null)),
          FilledButton(onPressed:busy?null:()async{
            if(!form.currentState!.validate())return;
            if(!await ask(context,
            'Save these payment destination details?')||!context.mounted)return;
            setState(()=>busy=true);
            final ok=await perform(context,
            ()=>app.mutate('/payment-methods',
            method:'PUT',
            body:{
              for(final e in controls.entries)e.key:e.value.text.trim()
            }),
            success:'Payment settings saved');
            if(mounted)setState((){
              busy=false;
              if(ok)editing=false;
            });
          },
          child:Text(busy?'Saving…':'Save payment details'))
        ])))
      ]
    ]);
  }
}

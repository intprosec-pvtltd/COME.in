import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/app_theme.dart';
import '../core/comein_widgets.dart';
import '../core/v2_ui.dart';

class ReportsScreen extends StatefulWidget {
  final ApiRequest api;
  const ReportsScreen({super.key, required this.api});
  @override State<ReportsScreen> createState() => _ReportsScreenState();
}
class _ReportsScreenState extends State<ReportsScreen> {
  late DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  String get period => '${month.year}-${month.month.toString().padLeft(2, '0')}';
  Map<String,dynamic>? data;
  String? error;
  bool loading=false;
  @override void initState(){super.initState();load();}
  Future<void> load() async {
    if(loading)return;
    setState(() {loading=true;error=null;});
    try { final response=await widget.api('/reports/analytics?period=$period');
      if(mounted)setState(()=>data=Map<String,dynamic>.from(response));
    } catch(e){if(mounted)setState(()=>error='$e');}
    finally {if(mounted)setState(()=>loading=false);}
  }
  Future<void> addExpense()async{
    final form=await inputForm(context,'Record expense',['Category','Description','Amount'],initial:{'Category':'utilities'});
    if(form==null||!mounted)return;
    final amount=double.tryParse(form['Amount']??'');
    if(amount==null||amount<=0){toast(context,'Enter a valid expense amount.');return;}
    await apiAction(context,()=>widget.api('/reports/expenses',method:'POST',body:{
      'period':period,'category':form['Category'],'description':form['Description'],'amount':amount,
    }),load);
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Reports & insights'),actions:[IconButton(onPressed:load,icon:const Icon(Icons.refresh))]),
    body:RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(17),children:[
      const Text('Your PG at a glance',style:TextStyle(fontSize:23,fontWeight:FontWeight.w900,color:plum)),
      const Text('Real figures from your PG records',style:TextStyle(color:muted)),
      const SizedBox(height:16),
      Card(child:Padding(padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),child:Row(children:[
        IconButton(onPressed:(){month=DateTime(month.year,month.month-1);load();},icon:const Icon(Icons.chevron_left)),
        Expanded(child:Text('${month.year} • ${_monthName(month.month)}',textAlign:TextAlign.center,style:const TextStyle(fontWeight:FontWeight.w800,color:plum))),
        IconButton(onPressed:(){month=DateTime(month.year,month.month+1);load();},icon:const Icon(Icons.chevron_right)),
      ]))),
      if(loading)const LinearProgressIndicator(),
      if(error!=null)Card(child:Padding(padding:const EdgeInsets.all(18),child:Text('Unable to load reports: $error'))),
      if(data!=null)...[
        const SizedBox(height:10),
        PlumHero(eyebrow:'Verified rent collected',amount:money(data!['collected']),detail:'${data!['collection_percent']}% of ${money(data!['billed'])} billed',footer:ClipRRect(borderRadius:BorderRadius.circular(20),child:LinearProgressIndicator(value:(number(data!['collection_percent'])/100).clamp(0,1),minHeight:8,backgroundColor:Colors.white24,color:blush))),
        GridView.count(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),crossAxisCount:2,childAspectRatio:1.12,children:[
          SoftMetric(label:'Outstanding dues',value:money(data!['outstanding']),icon:Icons.schedule_outlined,accent:const Color(0xFFD0846A)),
          SoftMetric(label:'Recorded expenses',value:money(data!['expenses']),icon:Icons.receipt_long_outlined,accent:const Color(0xFFB07ABA)),
          SoftMetric(label:'Net cash flow',value:money(data!['net_cash_flow']),icon:Icons.trending_up_rounded,accent:successGreen),
          SoftMetric(label:'Bed occupancy',value:'${data!['occupancy_percent']}%',icon:Icons.bed_outlined,accent:plum),
        ]),
        const SectionHeading('Payment breakdown'),
        Card(child:Column(children:[
          ListTile(leading:const Icon(Icons.check_circle_outline,color:successGreen),title:const Text('Paid invoices'),trailing:Text('${data!['paid_invoices']}')),
          ListTile(leading:const Icon(Icons.pending_outlined,color:Color(0xFFD0846A)),title:const Text('Unpaid invoices'),trailing:Text('${data!['pending_invoices']}')),
          ListTile(leading:const Icon(Icons.pie_chart_outline,color:plum),title:const Text('Part-paid invoices'),trailing:Text('${data!['partial_invoices']}')),
          ListTile(leading:const Icon(Icons.bed_outlined,color:plum),title:const Text('Occupied / total beds'),trailing:Text('${data!['occupied_beds']} / ${data!['total_beds']}')),
        ])),
        SectionHeading('Expenses',action:addExpense),
        for(final row in (data!['expense_rows'] as List<dynamic>)) Card(child:ListTile(title:Text('${row['description']}'),subtitle:Text('${row['category']}'),trailing:Text(money(row['amount']),style:const TextStyle(fontWeight:FontWeight.w800,color:plum)))),
        if((data!['expense_rows'] as List).isEmpty)const Card(child:Padding(padding:EdgeInsets.all(20),child:Text('No expenses recorded for this month.'))),
        const SizedBox(height:12),FilledButton.icon(onPressed:addExpense,icon:const Icon(Icons.add),label:const Text('Record an expense')),
        const SizedBox(height:10),const Text('Net cash flow = verified rent collected − recorded expenses. It is not accounting profit; deposits, refunds, taxes and unpaid liabilities may be excluded.',style:TextStyle(color:muted,fontSize:11)),
      ]
    ])));
  String _monthName(int m)=>const ['','Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][m];
}

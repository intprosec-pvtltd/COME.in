import 'localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../app/controller.dart';
import 'app_theme.dart';
String inr(dynamic value)=>NumberFormat.currency(locale:'en_IN',
symbol:'₹',
decimalDigits:0).format(amount(value));
String friendlyDate(dynamic value) {
  final d = DateTime.tryParse('$value');
  if (d == null) return '';
  final local = d.toLocal();
  return DateFormat('d MMM yyyy, h:mm a').format(local);
}
String indiaTime(dynamic value){
  final d=DateTime.tryParse('$value');
  return d==null?'':DateFormat('h:mm a').format(d.toUtc().add(const Duration(hours:5,
  minutes:30)));
} class OfficialBrand extends StatelessWidget {
  const OfficialBrand({
    super.key,
    this.width=170,
    this.iconOnly=false
  });
  final double width;
  final bool iconOnly;
  @override Widget build(BuildContext context)=>iconOnly?Image.asset('assets/brand/icon.png',
  width:width,
  height:width,
  semanticLabel:'COME.in'):SizedBox(width:width,
  height:width*.32,
  child:ClipRect(child:OverflowBox(maxHeight:width*.75,
  minHeight:width*.75,
  child:Image.asset('assets/brand/logo.png',
  width:width,
  height:width*.75,
  fit:BoxFit.contain,
  semanticLabel:'COME.in — Spaces People Belong'))));
 } class Attribution extends StatelessWidget {
  const Attribution({super.key});
  @override Widget build(BuildContext context)=>Padding(
    padding:const EdgeInsets.symmetric(vertical:14),
    child:Center(child:Semantics(
      label:'by IntProSec, Intelligence Protection Security',
      child:Row(mainAxisAlignment:MainAxisAlignment.center,
        mainAxisSize:MainAxisSize.min,children:[
          const Text('by',style:TextStyle(fontSize:15,color:Color(0xFF82748B),fontWeight:FontWeight.w500)),
          const SizedBox(width:8),
          Image.asset('assets/brand/intprosec_dark.webp',width:142,height:49,fit:BoxFit.contain,
            semanticLabel:'IntProSec company logo'),
        ]))));
} class PageBody extends StatelessWidget {
  const PageBody({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.actions=const [
    ],
    this.refresh
  });
  final String title;
  final String? subtitle;
  final List<Widget> children,
  actions;
  final Future<void> Function()? refresh;
  @override Widget build(BuildContext context){
    final list=ListView(padding:const EdgeInsets.fromLTRB(20,
    8,
    20,
    30),
    physics:const AlwaysScrollableScrollPhysics(),
    children:[
      if(subtitle!=null)Padding(padding:const EdgeInsets.only(bottom:18),
      child:Text(tr(context,subtitle!),
      style:const TextStyle(color:muted,
      fontSize:12))),
      ...children
    ]);
    return Scaffold(appBar:AppBar(title:Text(tr(context,title),
    style:const TextStyle(fontWeight:FontWeight.w800,
    fontSize:21)),
    actions:actions),
    body:SafeArea(top:false,
    child:refresh==null?list:RefreshIndicator(onRefresh:refresh!,
    child:list)));
  }
} class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.padding=const EdgeInsets.all(17),
    this.onTap
  });
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  @override Widget build(BuildContext context)=>Card(margin:const EdgeInsets.only(bottom:12),
  child:InkWell(onTap:onTap,
  borderRadius:BorderRadius.circular(22),
  child:Padding(padding:padding,
  child:child)));
} class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text,
  {
    super.key,
    this.action,
    this.label='View all'
  });
  final String text,
  label;
  final VoidCallback? action;
  @override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.only(top:16,
  bottom:10),
  child:Row(children:[
    Expanded(child:Text(tr(context,text),
    style:const TextStyle(fontSize:16,
    fontWeight:FontWeight.w800))),
    if(action!=null)TextButton(onPressed:action,
    child:Text(tr(context,label)))
  ]));
} class StatusPill extends StatelessWidget {
  const StatusPill(this.status,
  {
    super.key
  });
  final String status;
  @override Widget build(BuildContext context){
    final good=[
      'paid',
      'approved',
      'resolved',
      'restored',
      'normal'
    ].contains(status.toLowerCase());
    final red=[
      'rejected',
      'overdue',
      'submitted'
    ].contains(status.toLowerCase());
    final color=good?successGreen:red?const Color(0xFFB94D64):const Color(0xFFAE7148);
    return Container(padding:const EdgeInsets.symmetric(horizontal:9,
    vertical:5),
    decoration:BoxDecoration(color:color.withValues(alpha:.12),
    borderRadius:BorderRadius.circular(8)),
    child:Text(tr(context,status.replaceAll('_',
    ' ')),
    style:TextStyle(fontSize:10,
    fontWeight:FontWeight.w800,
    color:color)));
  }
} class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    required this.label,
    required this.value,
    this.detail='',
    this.child,
    this.trailing
  });
  final String label,
  value,
  detail;
  final Widget? child, trailing;
  @override Widget build(BuildContext context)=>Container(margin:const EdgeInsets.symmetric(vertical:12),
  width:double.infinity,
  padding:const EdgeInsets.all(23),
  decoration:BoxDecoration(borderRadius:BorderRadius.circular(25),
  gradient:const LinearGradient(colors:[
    plum,
    Color(0xFF8C5A9B)
  ],
  begin:Alignment.topLeft,
  end:Alignment.bottomRight)),
  child:Column(crossAxisAlignment:CrossAxisAlignment.start,
  children:[
    Row(children:[Expanded(child:Text(label,
    style:const TextStyle(color:Color(0xFFF2DDF4),
    fontSize:12))),if(trailing!=null)trailing!]),
    const SizedBox(height:10),
    Text(value,
    style:const TextStyle(fontSize:32,
    color:Colors.white,
    fontWeight:FontWeight.w900)),
    if(detail.isNotEmpty)Padding(padding:const EdgeInsets.only(top:8),
    child:Text(detail,
    style:const TextStyle(color:Colors.white70,
    fontSize:12))),
    if(child!=null)...[
      const SizedBox(height:17),
      child!
    ]
  ]));
} class FeatureTile extends StatelessWidget {
  const FeatureTile({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle=''
  });
  final String title,
  subtitle;
  final IconData icon;
  final VoidCallback onTap;
  @override Widget build(BuildContext context)=>Surface(onTap:onTap,
  child:Row(children:[
    Container(padding:const EdgeInsets.all(10),
    decoration:BoxDecoration(color:lavender.withValues(alpha:.17),
    borderRadius:BorderRadius.circular(13)),
    child:Icon(icon,
    color:lavender,
    size:22)),
    const SizedBox(width:13),
    Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
    children:[
      Text(tr(context,title),
      style:const TextStyle(fontWeight:FontWeight.w800,
      fontSize:13)),
      if(subtitle.isNotEmpty)Text(tr(context,subtitle),
      style:const TextStyle(fontSize:11,
      color:muted))
    ])),
    const Icon(Icons.chevron_right,
    size:19)
  ]));
} class EmptyState extends StatelessWidget {
  const EmptyState(this.message,
  {
    super.key,
    this.action
  });
  final String message;
  final Widget? action;
  @override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.symmetric(vertical:35),
  child:Column(children:[
    const Icon(Icons.inbox_outlined,
    color:lavender,
    size:38),
    const SizedBox(height:12),
    Text(message,
    textAlign:TextAlign.center,
    style:const TextStyle(color:muted)),
    if(action!=null)...[
      const SizedBox(height:15),
      action!
    ]
  ]));
} 
Future<bool> ask(BuildContext context, String text) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Please confirm'),
      content: Text(text),
      actionsPadding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
      actions: [
        Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'))),
          const SizedBox(width: 12),
          Expanded(child: FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm'))),
        ]),
      ],
    ),
  );
  return result ?? false;
}
void feedback(BuildContext context,
Object value){
  if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$value'),
  behavior:SnackBarBehavior.floating));
} Future<bool> perform(BuildContext context,
Future<void> Function() fn,
{
  String? success
}) async {
  try{
    await fn();
    if(context.mounted&&success!=null)feedback(context,
    success);
    return true;
  }catch(e){
    if(context.mounted)feedback(context,
    e);
    return false;
  }
} Future<void> saveBytes(BuildContext context,
Uint8List bytes,
String name) async {
  try{
    final path=await FilePicker.platform.saveFile(dialogTitle:'Save $name',
    fileName:name,
    bytes:bytes);
    if(context.mounted)feedback(context,
    path==null?'Save cancelled':'File saved');
  }catch(e){
    if(context.mounted)feedback(context,
    e);
  }
} Future<void> showFile(BuildContext context,
String path,
String filename,
{
  bool image=false
}) async {
  final app=AppScope.of(context);
  try{
    final bytes=await app.api.download(path);
    if(!context.mounted)return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(dialogContext).height * .76),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                const Icon(Icons.attachment_outlined, color: lavender),
                const SizedBox(width: 9),
                const Expanded(child: Text('Attachment',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
                IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(dialogContext),
                  icon: const Icon(Icons.close)),
              ]),
              const SizedBox(height: 12),
              if (image) Flexible(child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: InteractiveViewer(child: Image.memory(bytes, fit: BoxFit.contain)),
              )) else const Flexible(child: Center(child: Icon(Icons.description_outlined, size: 65))),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: FilledButton.icon(
                onPressed: () => saveBytes(context, bytes, filename),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Save file'),
              )),
            ]),
          ),
        ),
      ),
    );
  }catch(e){
    if(context.mounted)feedback(context,
    e);
  }
} Future<void> copyValue(BuildContext context,
String value) async {
  await Clipboard.setData(ClipboardData(text:value));
  if(context.mounted)feedback(context,
  'Copied');
}

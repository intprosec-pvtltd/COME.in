import 'package:another_flushbar/flushbar.dart';
import 'package:flutter/material.dart';
import 'api_client.dart';
import 'app_theme.dart';

String money(dynamic v) => '₹${v ?? '0'}';
double number(dynamic v) => double.tryParse('$v') ?? 0;

class DataPanel extends StatefulWidget {
  final String title;
  final ApiRequest api;
  final String path;
  final Widget Function(BuildContext, dynamic, Future<void> Function()) builder;
  const DataPanel({super.key,required this.title,required this.api,required this.path,required this.builder});
  @override State<DataPanel> createState()=>_DataPanelState();
}
class _DataPanelState extends State<DataPanel>{
  dynamic data;String? error;bool loading=true;
  @override void initState(){super.initState();refresh();}
  Future<void> refresh()async{
    if(mounted)setState((){loading=true;error=null;});
    try {final d=await widget.api(widget.path);if(mounted)setState(()=>data=d);}
    catch(e){if(mounted)setState(()=>error='$e');}
    finally{if(mounted)setState(()=>loading=false);}
  }
  @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:Text(widget.title),actions:[IconButton(onPressed:refresh,icon:const Icon(Icons.refresh))]),body:Column(children:[if(loading)const LinearProgressIndicator(),if(error!=null)Padding(padding:const EdgeInsets.all(12),child:Text(error!,style:const TextStyle(color:Colors.red))),Expanded(child:RefreshIndicator(onRefresh:refresh,child:data==null?ListView(children:const [SizedBox(height:100),Center(child:Text('Loading...'))]):widget.builder(c,data,refresh)))]));
}

Future<Map<String,String>?> inputForm(BuildContext context,String title,List<String> labels,{Map<String,String> initial=const {},String submit='Save'})async{
  final ctrls={for(final label in labels)label:TextEditingController(text:initial[label]??'')};
  final key=GlobalKey<FormState>();
  try {
    return await showDialog<Map<String,String>>(context:context,builder:(ctx)=>AlertDialog(title:Text(title),content:SingleChildScrollView(child:Form(key:key,child:Column(mainAxisSize:MainAxisSize.min,children:[for(final label in labels)Padding(padding:const EdgeInsets.symmetric(vertical:6),child:TextFormField(controller:ctrls[label],obscureText:label.toLowerCase().contains('password'),decoration:InputDecoration(labelText:label,border:const OutlineInputBorder()),validator:(v)=>v==null||v.trim().isEmpty?'Required':null))]))),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),FilledButton(onPressed:(){if(key.currentState!.validate())Navigator.pop(ctx,{for(final entry in ctrls.entries)entry.key:entry.value.text.trim()});},child:Text(submit))]));
  } finally {for(final c in ctrls.values)c.dispose();}
}
Future<bool> confirm(BuildContext context,String question)async=>await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Please confirm'),content:Text(question),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Confirm'))]))??false;
void toast(BuildContext context,Object message){
  if (!context.mounted) return;
  Flushbar<void>(
    message: '$message',
    backgroundColor: plum,
    borderRadius: BorderRadius.circular(18),
    margin: const EdgeInsets.all(14),
    icon: const Icon(Icons.check_circle_outline,color:Colors.white),
    duration: const Duration(seconds: 3),
    flushbarPosition: FlushbarPosition.TOP,
  ).show(context);
}
Future<void> apiAction(BuildContext context,Future<dynamic> Function() action,Future<void> Function() refresh)async{
  try{await action();await refresh();if(context.mounted)toast(context,'Saved successfully');}
  catch(e){if(context.mounted)toast(context,e);}
}
Widget section(String title)=>Padding(padding:const EdgeInsets.fromLTRB(12,18,12,8),child:Text(title,style:const TextStyle(fontSize:19,fontWeight:FontWeight.w800,color:plum)));
Widget item(String title,String subtitle,{VoidCallback? onTap,IconData icon=Icons.chevron_right})=>Card(child:ListTile(contentPadding:const EdgeInsets.symmetric(horizontal:16,vertical:7),title:Text(title,style:const TextStyle(fontWeight:FontWeight.w700,color:plum)),subtitle:Text(subtitle),trailing:Icon(icon,color:muted),onTap:onTap));

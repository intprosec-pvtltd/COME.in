import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/india_time.dart';
import '../core/app_theme.dart';

class NotificationScreen extends StatefulWidget {
  final ApiRequest api;
  const NotificationScreen({super.key,required this.api});
  @override State<NotificationScreen> createState()=>_NotificationScreenState();
}
class _NotificationScreenState extends State<NotificationScreen> {
  bool loading=true;
  String? error;
  List<dynamic> feed=[];
  final Set<String> read=<String>{};
  @override void initState(){super.initState();reload();}
  Future<void> reload() async {
    try {
      final result=await widget.api('/notifications/feed');
      if(mounted)setState(() {feed=result is List?result:[];loading=false;error=null;});
    } catch(e) {if(mounted)setState(() {loading=false;error='$e';});}
  }
  IconData iconFor(String kind) => switch(kind) {
    'announcement'=>Icons.campaign_outlined,
    'outage'=>Icons.plumbing_outlined,
    'community'=>Icons.forum_outlined,
    _=>Icons.notifications_outlined,
  };
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Notifications'),actions:[TextButton(
      onPressed:()=>setState(()=>read.addAll(feed.map((e)=>'${e['id']}'))),
      child:const Text('Mark all read'))]),
    body:Column(children:[
      if(loading)const LinearProgressIndicator(),
      if(error!=null)ListTile(title:Text(error!),trailing:TextButton(onPressed:reload,child:const Text('Retry'))),
      Expanded(child:RefreshIndicator(onRefresh:reload,child:feed.isEmpty
        ?ListView(children:const[Padding(padding:EdgeInsets.all(55),child:Center(child:Text('You are all caught up 💜')))])
        :ListView.builder(itemCount:feed.length,itemBuilder:(context,index){
          final n=feed[index] as Map<String,dynamic>;
          final id='${n['id']}';
          final isNew=!read.contains(id);
          return Card(margin:const EdgeInsets.fromLTRB(12,6,12,6),
            child:ListTile(onTap:()=>setState(()=>read.add(id)),
              leading:CircleAvatar(backgroundColor:blush,child:Icon(iconFor('${n['type']}'),color:plum)),
              title:Text('${n['title']}',style:TextStyle(fontWeight:isNew?FontWeight.bold:FontWeight.normal)),
              subtitle:Text('${n['body']}\n${formatIndiaTime(n['created_at'])}',maxLines:4),
              trailing:isNew?const Icon(Icons.circle,color:lavender,size:9):null));
        }))),
    ]),
  );
}

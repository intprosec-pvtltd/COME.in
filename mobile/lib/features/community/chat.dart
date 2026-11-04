import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../app/controller.dart';
import '../../app/router.dart';
import '../../core/design.dart';
import '../../core/app_theme.dart';
import '../finance/finance.dart';
class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key
  });
  @override State<ChatPage> createState()=>_ChatPageState();
} class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final input=TextEditingController(),
  scroll=ScrollController();
  Timer? timer;
  AppController? app;
  List<Map<String,
  dynamic>> messages=[
  ];
  bool loading=true,
  polling=false,
  sending=false;
  String? error,
  reply;
  int? editing;
  @override void initState(){
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  } @override void didChangeDependencies(){
    super.didChangeDependencies();
    if(app==null){
      app=AppScope.of(context);
      messages=app!.rows('messages');
      Future.microtask(()=>load(forceScroll:true));
      startTimer();
    }
  } void startTimer(){
    timer?.cancel();
    timer=Timer.periodic(const Duration(seconds:5),
    (_)=>load());
  } @override void didChangeAppLifecycleState(AppLifecycleState state){
    if(state==AppLifecycleState.resumed){
      startTimer();
      load();
    }else{
      timer?.cancel();
    }
  } @override void dispose(){
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    input.dispose();
    scroll.dispose();
    super.dispose();
  } Future<void> load({
    bool forceScroll=false
  })async{
    if(polling)return;
    polling=true;
    final nearEnd=!scroll.hasClients||scroll.position.maxScrollExtent-scroll.offset<100;
    try{
      final rows=await app!.api.request('/v3/messages')as List;
      final next=rows.map((m)=>Map<String,
      dynamic>.from(m as Map)).toList();
      if(!mounted)return;
      if(jsonEncode(next)!=jsonEncode(messages)||loading||error!=null){
        setState((){
          messages=next;
          loading=false;
          error=null;
        });
        if(forceScroll||nearEnd)scrollEnd();
      }
    }catch(e){
      if(mounted)setState((){
        error='$e';
        loading=false;
      });
    }finally{
      polling=false;
    }
  } void scrollEnd(){
    WidgetsBinding.instance.addPostFrameCallback((_){
      if(mounted&&scroll.hasClients)scroll.animateTo(scroll.position.maxScrollExtent,
      duration:const Duration(milliseconds:250),
      curve:Curves.easeOut);
    });
  } Future<void> send()async{
    final text=input.text.trim();
    if(text.isEmpty||sending)return;
    setState(()=>sending=true);
    try{
      await app!.api.request('/v3/messages${editing==null?'':'/$editing'}',
      method:editing==null?'POST':'PATCH',
      body:{
        'body':text,
        'reply':reply??''
      });
      if(!mounted)return;
      input.clear();
      setState((){
        editing=null;
        reply=null;
      });
      await load(forceScroll:true);
    }catch(e){
      if(mounted)feedback(context,
      'Message not sent: $e');
    }finally{
      if(mounted)setState(()=>sending=false);
    }
  } Future<void> upload(String name,
  Uint8List bytes)async{
    if(sending)return;
    if(bytes.length>10*1024*1024){
      feedback(context,
      'Use a file up to 10 MB.');
      return;
    }setState(()=>sending=true);
    try{
      await app!.api.upload('/community/attachments',
      name,
      bytes,
      mimeType(name));
      await load(forceScroll:true);
    }catch(e){
      if(mounted)feedback(context,
      'Attachment not sent: $e');
    }finally{
      if(mounted)setState(()=>sending=false);
    }
  } Future<void> photo(ImageSource source)async{
    try{
      final f=await ImagePicker().pickImage(source:source,
      imageQuality:85,
      maxWidth:1800);
      if(f!=null&&mounted)await upload(f.name,
      await f.readAsBytes());
    }catch(e){
      if(mounted)feedback(context,
      'Camera / gallery unavailable: $e');
    }
  } Future<void> file()async{
    try{
      final r=await FilePicker.platform.pickFiles(type:FileType.custom,
      allowedExtensions:[
        'png',
        'jpg',
        'jpeg',
        'webp',
        'pdf',
        'txt'
      ],
      withData:true);
      if(r==null||!mounted)return;
      final f=r.files.single;
      if(f.bytes==null){
        feedback(context,
        'Unable to read file.');
        return;
      }await upload(f.name,
      f.bytes!);
    }catch(e){
      if(mounted)feedback(context,
      e);
    }
  } Future<void> attach()async{
    final choice=await showModalBottomSheet<String>(context:context,
    showDragHandle:true,
    builder:(c)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,
    children:[
      const Padding(padding:EdgeInsets.all(15),
      child:Text('Share with your community',
      style:TextStyle(fontWeight:FontWeight.w800,
      fontSize:18))),
      for(final choice in [
        ('Camera',
        Icons.camera_alt_outlined),
        ('Gallery',
        Icons.photo_outlined),
        ('Document',
        Icons.attach_file)
      ])ListTile(leading:Icon(choice.$2,
      color:lavender),
      title:Text(choice.$1),
      onTap:()=>Navigator.pop(c,
      choice.$1)),
      const Padding(padding:EdgeInsets.all(15),
      child:Text('Images, PDF and TXT · Up to 10 MB',
      style:TextStyle(color:muted,
      fontSize:11)))
    ])));
    if(!mounted)return;
    switch(choice){
      case 'Camera':await photo(ImageSource.camera);
      case 'Gallery':await photo(ImageSource.gallery);
      case 'Document':await file();
    }
  } bool editable(Map<String,
  dynamic> m){
    final time=DateTime.tryParse('${m['created_at']}');
    return m[
      'author_id'
    ]==app!.profile[
      'id'
    ]&&m[
      'deleted'
    ]!=true&&time!=null&&DateTime.now().toUtc().difference(time.toUtc())<=const Duration(minutes:15);
  } Future<void> actions(Map<String,
  dynamic> m)async{
    final action=await showModalBottomSheet<String>(context:context,
    showDragHandle:true,
    builder:(c)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,
    children:[
      if(m[
        'deleted'
      ]!=true)...[
        ListTile(leading:const Icon(Icons.reply),
        title:const Text('Reply'),
        onTap:()=>Navigator.pop(c,
        'reply')),
        ListTile(leading:const Icon(Icons.copy),
        title:const Text('Copy'),
        onTap:()=>Navigator.pop(c,
        'copy'))
      ],
      if(editable(m))... [
        ListTile(leading:const Icon(Icons.edit_outlined),
        title:const Text('Edit'),
        onTap:()=>Navigator.pop(c,
        'edit')),
        ListTile(leading:const Icon(Icons.undo),
        title:const Text('Unsend for everyone'),
        onTap:()=>Navigator.pop(c,
        'unsend'))
      ],
      ListTile(leading:const Icon(Icons.delete_outline),
      title:const Text('Delete for me'),
      onTap:()=>Navigator.pop(c,
      'delete')),
      const Padding(padding:EdgeInsets.all(16),
      child:Text('Edit and unsend are available for 15 minutes.',
      style:TextStyle(color:muted,
      fontSize:11)))
    ])));
    if(!mounted)return;
    if(action=='copy')await copyValue(context,
    '${m['body']}');
    else if(action=='reply')setState((){
      reply='${m['body']}';
      if(reply!.length>300)reply=reply!.substring(0,
      300);
      editing=null;
    });
    else if(action=='edit')setState((){
      editing=m[
        'id'
      ]as int;
      input.text='${m['body']}';
      reply=null;
    });
    else if(action=='unsend'||action=='delete'){
      if(!await ask(context,
      action=='unsend'?'Unsend this message for everyone?':'Hide this message only for your account?')||!mounted)return;
      await perform(context,
      ()async{
        await app!.api.request('/v3/messages/${m['id']}?for_everyone=${action=='unsend'}',
        method:'DELETE');
        await load();
      });
    }
  } @override Widget build(BuildContext context){
    final a=AppScope.of(context);
    return Scaffold(appBar:AppBar(leading:Navigator.canPop(context)?const BackButton():null,
    title:Row(children:[
      const OfficialBrand(width:35,
      iconOnly:true),
      const SizedBox(width:10),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
      children:[
        Text('${a.profile['tenant']?['name']??'PG community'}',
        style:const TextStyle(fontSize:15,
        fontWeight:FontWeight.w800)),
        const Text('Private community',
        style:TextStyle(fontSize:10,
        color:muted))
      ]))
    ]),
    actions:[
      IconButton(tooltip:'Group information',
      onPressed:()=>openPage(context,
      'groupInfo'),
      icon:const Icon(Icons.more_horiz))
    ]),
    body:Column(children:[
      Material(color:lavender.withValues(alpha:.13),
      child:InkWell(onTap:()=>openPage(context,
      'facilities'),
      child:const Padding(padding:EdgeInsets.symmetric(horizontal:15,
      vertical:11),
      child:Row(children:[
        Icon(Icons.campaign_outlined,
        size:16,
        color:lavender),
        SizedBox(width:8),
        Expanded(child:Text('View your PG’s latest facility updates',
        style:TextStyle(fontSize:11))),
        Icon(Icons.chevron_right,
        size:16)
      ])))),
      if(loading||sending)const LinearProgressIndicator(minHeight:2),
      if(error!=null)MaterialBanner(content:Text(error!,
      style:const TextStyle(fontSize:12)),
      actions:[
        TextButton(onPressed:()=>load(),
        child:const Text('Retry'))
      ]),
      Expanded(child:RefreshIndicator(onRefresh:()=>load(),
      child:messages.isEmpty&&!loading?ListView(children:const [
        EmptyState('No messages yet. Say hello to your community.')
      ]):ListView.builder(controller:scroll,
      padding:const EdgeInsets.all(15),
      itemCount:messages.length,
      itemBuilder:(c,
      i){
        final m=messages[
          i
        ],
        mine=m[
          'author_id'
        ]==a.profile[
          'id'
        ];
        final attachments=m[
          'attachments'
        ]as List? ?? [
        ];
        final date='${m['created_at']}'.split('T').first;
        final previousDate=i==0?'':'${messages[i-1]['created_at']}'.split('T').first;
        return Column(children:[
          if(date!=previousDate)Padding(padding:const EdgeInsets.only(top:8,
          bottom:15),
          child:StatusPill(date)),
          Align(alignment:mine?Alignment.centerRight:Alignment.centerLeft,
          child:GestureDetector(onLongPress:()=>actions(m),
          child:ConstrainedBox(constraints:BoxConstraints(maxWidth:MediaQuery.sizeOf(c).width*.84),
          child:Container(margin:const EdgeInsets.only(bottom:12),
          padding:const EdgeInsets.fromLTRB(13,
          10,
          10,
          6),
          decoration:BoxDecoration(color:mine?lavender.withValues(alpha:.26):Theme.of(c).cardColor,
          borderRadius:BorderRadius.only(topLeft:const Radius.circular(17),
          topRight:const Radius.circular(17),
          bottomLeft:Radius.circular(mine?17:4),
          bottomRight:Radius.circular(mine?4:17)),
          border:Border.all(color:lavender.withValues(alpha:.12))),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,
          children:[
            Text('${m['author']}${'${m['author_room']??''}'.trim().isNotEmpty ? ' · Room ${m['author_room']}' : ''}',
            style:const TextStyle(fontSize:10,
            color:lavender,
            fontWeight:FontWeight.w800)),
            if('${m['reply']??''}'.isNotEmpty)Container(margin:const EdgeInsets.symmetric(vertical:7),
            padding:const EdgeInsets.all(8),
            decoration:BoxDecoration(color:lavender.withValues(alpha:.12),
            border:const Border(left:BorderSide(width:3,
            color:lavender))),
            child:Text('${m['reply']}',
            style:const TextStyle(fontSize:10))),
            const SizedBox(height:4),
            Text(m[
              'deleted'
            ]==true?'This message was unsent':attachments.isNotEmpty && '${m['body']}'.startsWith('Attachment:') ? '' : '${m['body']}',
            style:TextStyle(fontSize:13,
            height:1.5,
            fontStyle:m[
              'deleted'
            ]==true?FontStyle.italic:FontStyle.normal)),
            for(final f in attachments)PrivateChatAttachment(key:ValueKey(f[
              'id'
            ]),
            file:Map<String,
            dynamic>.from(f as Map)),
            Row(mainAxisSize:MainAxisSize.min,
            children:[
              Text('${indiaTime(m['created_at'])}${m['edited']==true?' · edited':''}',
              style:const TextStyle(fontSize:9,
              color:muted)),
              IconButton(tooltip:'Message actions',
              visualDensity:VisualDensity.compact,
              constraints:const BoxConstraints(minWidth:30,
              minHeight:28),
              padding:EdgeInsets.zero,
              onPressed:()=>actions(m),
              icon:const Icon(Icons.more_horiz,
              size:17,
              color:muted))
            ])
          ])))))
        ]);
      }))),
      if(reply!=null||editing!=null)Container(width:double.infinity,
      padding:const EdgeInsets.symmetric(horizontal:15),
      color:lavender.withValues(alpha:.15),
      child:Row(children:[
        Expanded(child:Text(editing!=null?'Editing your message':'Replying to $reply',
        maxLines:2,
        overflow:TextOverflow.ellipsis,
        style:const TextStyle(fontSize:11))),
        IconButton(onPressed:()=>setState((){
          editing=null;
          reply=null;
          input.clear();
        }),
        icon:const Icon(Icons.close,
        size:17))
      ])),
      SafeArea(top:false,
      child:Padding(padding:const EdgeInsets.fromLTRB(7,
      8,
      7,
      10),
      child:Row(crossAxisAlignment:CrossAxisAlignment.end,
      children:[
        IconButton(tooltip:'Attachments',
        onPressed:sending?null:attach,
        icon:const Icon(Icons.add_circle_outline,
        color:lavender)),
        Expanded(child:TextField(controller:input,
        minLines:1,
        maxLines:4,
        maxLength:2000,
        decoration:const InputDecoration(hintText:'Message your community…',
        counterText:'',
        contentPadding:EdgeInsets.all(12)),
        onSubmitted:(_)=>send())),
        IconButton(tooltip:'Send message',
        onPressed:sending?null:send,
        icon:const Icon(Icons.send_rounded,
        color:lavender))
      ])))
    ]));
  }
} class PrivateChatAttachment extends StatefulWidget {
  const PrivateChatAttachment({
    super.key,
    required this.file
  });
  final Map<String,
  dynamic> file;
  @override State<PrivateChatAttachment> createState()=>_PrivateChatAttachmentState();
} class _PrivateChatAttachmentState extends State<PrivateChatAttachment>{
  Future<Uint8List>? bytes;
  @override void didChangeDependencies(){
    super.didChangeDependencies();
    if('${widget.file['content_type']}'.startsWith('image/'))bytes??=AppScope.of(context).api.download('${widget.file['url']}');
  }@override Widget build(BuildContext context)=>InkWell(onTap:()=>showFile(context,
  '${widget.file['url']}',
  '${widget.file['filename']}',
  image:'${widget.file['content_type']}'.startsWith('image/')),
  child:Padding(padding:const EdgeInsets.symmetric(vertical:8),
  child:Column(crossAxisAlignment:CrossAxisAlignment.start,
  children:[
    if(bytes!=null)FutureBuilder<Uint8List>(future:bytes,
    builder:(c,
    s)=>s.hasData?ClipRRect(borderRadius:BorderRadius.circular(12),
    child:Image.memory(s.data!,
    height:150,
    fit:BoxFit.cover)):s.hasError?const Icon(Icons.broken_image_outlined):const Padding(padding:EdgeInsets.all(18),
    child:CircularProgressIndicator()))else const Icon(Icons.description_outlined,
    color:lavender),
    const SizedBox(height:5),
    const Row(mainAxisSize:MainAxisSize.min, children:[Icon(Icons.download_outlined,size:15,color:lavender), SizedBox(width:5), Text('View / save attachment',style:TextStyle(fontSize:11,color:lavender))])
  ])));
} class GroupInfoPage extends StatelessWidget {
  const GroupInfoPage({
    super.key
  });
  @override Widget build(BuildContext context){
    final app=AppScope.of(context);
    return PageBody(title:'Community information',
    subtitle:'Private to ${app.profile['tenant']?['name']}',
    children:[
      const Center(child:OfficialBrand(width:90,
      iconOnly:true)),
      const SizedBox(height:20),
      const Text('Share useful updates and keep conversations respectful. Report maintenance through Complaints so it can be tracked.',
      style:TextStyle(color:muted,
      fontSize:12,
      height:1.6)),
      const SectionTitle('Members'),
      for(final m in app.rows('members'))Surface(child:ListTile(contentPadding:EdgeInsets.zero,
      leading:CircleAvatar(backgroundColor:lavender.withValues(alpha:.2),
      child:Text('${m['name']}'.substring(0,
      1))),
      title:Text('${m['name']}'),
      subtitle:Text('${m['role']}')))
    ]);
  }
}

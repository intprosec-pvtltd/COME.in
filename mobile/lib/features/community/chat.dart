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
/// Stable across app runs and independent of name, message order or theme.
/// A finite accessible palette can repeat for large groups; the user ID, name
/// and verified role remain the authoritative identifiers.
Color communitySenderColor(Object? id, Brightness brightness) {
  const dark = <Color>[
    Color(0xFFFFB4AB), Color(0xFF91D6FF), Color(0xFF86E1B8), Color(0xFFE7BBFF),
    Color(0xFFFFD18C), Color(0xFFA7D8F5), Color(0xFFF9B2DA), Color(0xFFCAEB91),
    Color(0xFFB8C3FF), Color(0xFFFFC0A1), Color(0xFF91E5E3), Color(0xFFE4CBFF),
    Color(0xFFF6D975), Color(0xFFD1EEB2), Color(0xFFF4B9BB), Color(0xFFAAC9FF),
  ];
  const light = <Color>[
    Color(0xFF8D2424), Color(0xFF174F84), Color(0xFF00623E), Color(0xFF663184),
    Color(0xFF805000), Color(0xFF005A73), Color(0xFF85235D), Color(0xFF3F5D13),
    Color(0xFF354B9B), Color(0xFF963B16), Color(0xFF005E59), Color(0xFF583A8F),
    Color(0xFF725500), Color(0xFF426020), Color(0xFF852D47), Color(0xFF2F5196),
  ];
  final key = '$id';
  // Numeric server IDs give neighboring users distinct slots. Stable string
  // fallback covers migrated data without depending on Dart's runtime hashCode.
  var hash = int.tryParse(key) ?? 0;
  if (int.tryParse(key) == null) {
    for (final ch in key.codeUnits) { hash = (hash * 31 + ch) & 0x7fffffff; }
  }
  final palette = brightness == Brightness.dark ? dark : light;
  return palette[hash.abs() % palette.length];
}

String? communityRoleLabel(Object? role) => switch (role) {
  'owner' => 'Owner', 'manager' => 'Manager', 'staff' => 'Staff', _ => null,
};

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key
  });
  @override State<ChatPage> createState()=>_ChatPageState();
} class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final input=TextEditingController(),
  scroll=ScrollController();
  Timer? timer;
  bool tabVisible=true;
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
  int? selectedPropertyId;
  int get communityPropertyId => selectedPropertyId ?? (app?.owner==true
      ? (app?.propertyId ?? ((app?.rows('properties')??const <Map<String,dynamic>>[]).where((p)=>p['archived']!=true).isNotEmpty
          ? (app!.rows('properties').firstWhere((p)=>p['archived']!=true)['id'] as num).toInt() : 0))
      : ((app?.data['accommodation'] as Map?)?['property_id'] as num?)?.toInt()??0);
  @override void initState(){
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  } @override void didChangeDependencies(){
    super.didChangeDependencies();
    final wasVisible=tabVisible;
    tabVisible=TickerMode.valuesOf(context).enabled;
    if(!tabVisible){timer?.cancel();}
    else if(!wasVisible&&app!=null){startTimer();Future.microtask(()=>load());}
    if(app==null){
      app=AppScope.of(context);
      messages=app!.rows('messages').where((m)=>(m['property_id']??0)==communityPropertyId).toList();
      Future.microtask(()=>load(forceScroll:true));
      startTimer();
    }
  } void startTimer(){
    timer?.cancel();
    if(!tabVisible)return;
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
    if(!mounted||!tabVisible||polling)return;
    polling=true;
    final requestedProperty=communityPropertyId;
    final nearEnd=!scroll.hasClients||scroll.position.maxScrollExtent-scroll.offset<100;
    try{
      final rows=await app!.api.request('/v3/messages?property_id=$requestedProperty')as List;
      // Fail closed: do not display legacy/unscoped messages or messages from another PG.
      // The server also MUST enforce property-scoped authorization; this check
      // prevents stale/incorrect response data from appearing under another PG.
      final next=rows.map((m)=>Map<String,
      dynamic>.from(m as Map)).where((m) =>
          int.tryParse('${m['property_id'] ?? ''}') == requestedProperty).toList();
      if(!mounted||requestedProperty!=communityPropertyId)return;
      if(jsonEncode(next)!=jsonEncode(messages)||loading||error!=null){
        setState((){
          messages=next;
          loading=false;
          error=null;
        });
        if(forceScroll||nearEnd)scrollEnd();
      }
    }catch(e){
      if(mounted&&requestedProperty==communityPropertyId)setState((){
        error='$e';
        loading=false;
      });
    }finally{
      polling=false;
      // An older PG response must never replace the newly selected PG feed.
      if(mounted&&requestedProperty!=communityPropertyId){
        Future.microtask(()=>load(forceScroll:true));
      }
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
    final targetProperty = communityPropertyId;
    setState(()=>sending=true);
    try{
      // Never post into an older owner-wide community endpoint.
      final capability=await app!.api.request('/v3/community-capabilities');
      if(capability is! Map || capability['property_scoped']!=true){
        throw Exception('Community messaging is temporarily unavailable.');
      }
      await app!.api.request('/v3/messages${editing==null?'':'/$editing'}',
      method:editing==null?'POST':'PATCH',
      body:{
        'body':text,
        'reply':reply??'',
        'property_id':targetProperty
      });
      if(!mounted)return;
      // Don't clear a draft entered for another PG while this request was pending.
      if(targetProperty == communityPropertyId){
        input.clear();
        setState((){
          editing=null;
          reply=null;
        });
        await load(forceScroll:true);
      }
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
    }
    final targetProperty = communityPropertyId;
    setState(()=>sending=true);
    try{
      final capability=await app!.api.request('/v3/community-capabilities');
      if(capability is! Map || capability['property_scoped']!=true){
        throw Exception('Community attachments are temporarily unavailable.');
      }
      await app!.api.upload('/community/attachments?property_id=$targetProperty',
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
      Padding(padding:const EdgeInsets.all(15),
      child:Text('Images, PDF and TXT · Up to 10 MB',
      style:TextStyle(color:secondaryText(c),
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
      Padding(padding:const EdgeInsets.all(16),
      child:Text('Edit and unsend are available for 15 minutes.',
      style:TextStyle(color:secondaryText(c),
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
        if(a.owner)DropdownButton<int>(
          isDense:true,
          value:a.rows('properties').any((p)=>p['id']==communityPropertyId)?communityPropertyId:0,
          underline:const SizedBox.shrink(),
          items:a.rows('properties').where((p)=>p['archived']!=true).map((p)=>DropdownMenuItem<int>(value:p['id'] as int,child:Text('${p['name']}',overflow:TextOverflow.ellipsis))).toList(),
          onChanged:(pid){if(pid==null)return;setState((){selectedPropertyId=pid;messages=[];loading=true;reply=null;editing=null;});load(forceScroll:true);},
        )else Text('${a.data['accommodation']?['property']??a.profile['tenant']?['name']??'PG community'}',
        style:const TextStyle(fontSize:15,
        fontWeight:FontWeight.w800)),
        Text('Private community',
        style:TextStyle(fontSize:10,
        color:secondaryText(context)))
      ]))
    ]),
    actions:[
      IconButton(
        tooltip:'Notifications',
        onPressed:()=>openPage(context,'notifications'),
        icon:Badge(
          isLabelVisible:a.rows('notifications').any((n)=>n['read']!=true),
          child:const Icon(Icons.notifications_none_outlined),
        ),
      ),
      IconButton(tooltip:'Group information',
      onPressed:()=>openPage(context,
      'groupInfo',args:{'property_id':communityPropertyId}),
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
        final theme=Theme.of(c);
        final senderColor=communitySenderColor(m['author_id'],theme.brightness);
        final senderRole=communityRoleLabel(m['author_role']);
        final date='${m['created_at']}'.split('T').first;
        final previousDate=i==0?'':'${messages[i-1]['created_at']}'.split('T').first;
        return Column(children:[
          if(date!=previousDate)Padding(padding:const EdgeInsets.only(top:8,
          bottom:15),
          child:Theme.of(c).brightness == Brightness.dark ? Chip(label: Text(date,
            style: TextStyle(fontSize: 10, color: secondaryText(c))), visualDensity: VisualDensity.compact) : StatusPill(date)),
          Align(alignment:mine?Alignment.centerRight:Alignment.centerLeft,
          child:GestureDetector(onLongPress:()=>actions(m),
          child:ConstrainedBox(constraints:BoxConstraints(maxWidth:MediaQuery.sizeOf(c).width*.84),
          child:Container(margin:const EdgeInsets.only(bottom:12),
          padding:const EdgeInsets.fromLTRB(12,8,10,4),
          decoration:BoxDecoration(color:mine?(theme.brightness==Brightness.dark?const Color(0xFF403355):const Color(0xFFF0E5FF)):theme.cardColor,
          borderRadius:BorderRadius.only(topLeft:const Radius.circular(17),
          topRight:const Radius.circular(17),
          bottomLeft:Radius.circular(mine?17:4),
          bottomRight:Radius.circular(mine?4:17)),
          border:Border.all(color:lavender.withValues(alpha:.12))),
          child:Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment:CrossAxisAlignment.start,
          children:[
            Wrap(crossAxisAlignment:WrapCrossAlignment.center,spacing:6,runSpacing:3,children:[
              Text('${m['author']}${'${m['author_room']??''}'.trim().isNotEmpty ? ' · Room ${m['author_room']}' : ''}',
                style:TextStyle(fontSize:12,color:senderColor,fontWeight:FontWeight.w800)),
              if(senderRole!=null)Container(
                padding:const EdgeInsets.symmetric(horizontal:7,vertical:3),
                decoration:BoxDecoration(color:senderColor.withValues(alpha:.10),
                  border:Border.all(color:senderColor.withValues(alpha:.55)),borderRadius:BorderRadius.circular(6)),
                child:Text(senderRole,style:TextStyle(fontSize:10,color:senderColor,fontWeight:FontWeight.w700))),
            ]),
            if('${m['reply']??''}'.isNotEmpty)Container(margin:const EdgeInsets.symmetric(vertical:7),
            padding:const EdgeInsets.all(8),
            decoration:BoxDecoration(color:lavender.withValues(alpha:.12),
            border:const Border(left:BorderSide(width:3,
            color:lavender))),
            child:Text('${m['reply']}',
            style:const TextStyle(fontSize:10))),
            const SizedBox(height:4),
            if (attachments.isEmpty || !'${m['body']}'.startsWith('Attachment:')) Text(m[
              'deleted'
            ]==true?'This message was unsent':attachments.isNotEmpty && '${m['body']}'.startsWith('Attachment:') ? '' : '${m['body']}',
            style:TextStyle(fontSize:13,
            height:1.35,
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
              style:TextStyle(fontSize:10,
              color:secondaryText(c))),
              IconButton(tooltip:'Message actions',
              visualDensity:VisualDensity.compact,
              constraints:const BoxConstraints(minWidth:30,
              minHeight:28),
              padding:EdgeInsets.zero,
              onPressed:()=>actions(m),
              icon:Icon(Icons.more_horiz,
              size:17,
              color:secondaryText(c)))
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
  bool get isImage => '${widget.file['content_type']}'.toLowerCase().startsWith('image/');
  Future<Uint8List> fetch()=>AppScope.of(context).api.download('${widget.file['url']}');
  @override void didChangeDependencies(){
    super.didChangeDependencies();
    if(isImage)bytes??=fetch();
  }
  @override void didUpdateWidget(covariant PrivateChatAttachment oldWidget){
    super.didUpdateWidget(oldWidget);
    if(oldWidget.file['url']!=widget.file['url']||oldWidget.file['content_type']!=widget.file['content_type']){
      bytes=isImage?fetch():null;
    }
  }
  Widget unavailable()=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text('Image preview unavailable',style:TextStyle(fontSize:12,color:secondaryText(context))),
    TextButton.icon(onPressed:()=>setState(()=>bytes=fetch()),icon:const Icon(Icons.refresh,size:16),label:const Text('Retry preview')),
  ]);
  @override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.symmetric(vertical:6),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      if(isImage)FutureBuilder<Uint8List>(future:bytes,builder:(c,s){
        if(s.hasError)return unavailable();
        if(!s.hasData)return const SizedBox(height:44,width:44,child:Padding(padding:EdgeInsets.all(10),child:CircularProgressIndicator(strokeWidth:2)));
        return ClipRRect(borderRadius:BorderRadius.circular(12),child:Image.memory(s.data!,height:150,
          fit:BoxFit.contain,cacheWidth:640,errorBuilder:(_,error,stack)=>unavailable()));
      })else const Icon(Icons.description_outlined),
      Text('${widget.file['filename']??'Attachment'}',maxLines:2,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:12,color:secondaryText(context))),
      TextButton.icon(onPressed:()=>showFile(context,'${widget.file['url']}','${widget.file['filename']}',image:isImage),
        icon:const Icon(Icons.download_outlined,size:16),label:const Text('View / save attachment')),
    ]));
 } class GroupInfoPage extends StatefulWidget {
  const GroupInfoPage({super.key, required this.propertyId});
  final int propertyId;
  @override State<GroupInfoPage> createState()=>_GroupInfoPageState();
}
class _GroupInfoPageState extends State<GroupInfoPage> {
  late Future<List<Map<String,dynamic>>> members;
  @override void didChangeDependencies(){
    super.didChangeDependencies();
    // Fetch fresh, authorized PG members from the backend, never the owner-wide cache.
    members=AppScope.of(context).api.request('/v3/community-members?property_id=${widget.propertyId}')
      .then((v)=>(v as List).map((item)=>Map<String,dynamic>.from(item as Map)).toList());
  }
  @override Widget build(BuildContext context){
    return PageBody(title:'Community information',children:[
      const Center(child:OfficialBrand(width:90,iconOnly:true)),
      const SizedBox(height:20),
      Text('Share useful updates and keep conversations respectful. Report maintenance through Complaints so it can be tracked.',
        style:TextStyle(color:secondaryText(context),fontSize:12,height:1.6)),
      const SectionTitle('Members'),
      FutureBuilder<List<Map<String,dynamic>>>(future:members,builder:(ctx,snapshot){
        if(snapshot.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
        if(snapshot.hasError)return const Text('Could not load members for this PG. Please try again.');
        final rows=snapshot.data??[];
        if(rows.isEmpty)return const Text('No members assigned to this PG yet.');
        return Column(children:[for(final m in rows) Surface(child:ListTile(
          contentPadding:EdgeInsets.zero,
          leading:CircleAvatar(backgroundColor:lavender.withValues(alpha:.2),
            child:Text('${m['name']}'.isEmpty?'?':'${m['name']}'[0])),
          title:Text('${m['name']}'),subtitle:Text('${m['role']}'),
        ))]);
      }),
    ]);
  }
}

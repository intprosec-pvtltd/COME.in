import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../app/controller.dart';
import '../../app/router.dart';
import '../../core/design.dart';
import '../../core/app_theme.dart';
import '../finance/finance.dart';
import '../management/management.dart';
class ComplaintsPage extends StatefulWidget {
  const ComplaintsPage({
    super.key
  });
  @override State<ComplaintsPage> createState()=>_ComplaintsPageState();
} class _ComplaintsPageState extends State<ComplaintsPage>{
  String filter='All';
  @override Widget build(BuildContext context){
    final app=AppScope.of(context);
    final rows=app.rows('complaints').where((r)=>filter=='All'||r[
      'status'
    ]==filter).toList();
    return PageBody(title:app.owner?'Maintenance & complaints':app.staff?'My assigned tasks':'My complaints',
    refresh:app.refresh,
    children:[
      Wrap(spacing:7,
      children:[
        for(final s in [
          'All',
          'submitted',
          'in_progress',
          'resolved'
        ])ChoiceChip(label:Text(s.replaceAll('_',
        ' ')),
        selected:filter==s,
        onSelected:(_)=>setState(()=>filter=s))
      ]),
      const SizedBox(height:15),
      for(final r in rows)Surface(onTap:()=>openPage(context,
      'complaintDetail',
      id:r[
        'id'
      ]as int),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,
      children:[
        Row(children:[
          Expanded(child:Text('${r['category']}',
          style:const TextStyle(fontWeight:FontWeight.w800))),
          StatusPill('${r['status']}')
        ]),
        const SizedBox(height:10),
        Text('${r['description']}',
        maxLines:2,
        overflow:TextOverflow.ellipsis,
        style:const TextStyle(color:muted,
        fontSize:12)),
        const SizedBox(height:10),
        Text('${r['priority']??'Medium'} priority',
        style:const TextStyle(fontSize:10,
        fontWeight:FontWeight.w700))
      ])),
      if(rows.isEmpty)const EmptyState('No complaints in this view.'),
      if(!app.owner&&!app.staff)FilledButton.icon(onPressed:()=>openPage(context,
      'newComplaint'),
      icon:const Icon(Icons.add),
      label:const Text('Report an issue'))
    ]);
  }
} class NewComplaintPage extends StatefulWidget {
  const NewComplaintPage({
    super.key
  });
  @override State<NewComplaintPage> createState()=>_NewComplaintPageState();
} class _NewComplaintPageState extends State<NewComplaintPage>{
  final form=GlobalKey<FormState>();
  final title=TextEditingController(),
  description=TextEditingController();
  String priority='Medium';
  Map<String,
  dynamic>? file;
  bool busy=false;
  @override void dispose(){
    title.dispose();
    description.dispose();
    super.dispose();
  }Future<void> attach(ImageSource source)async{
    setState(()=>busy=true);
    try{
      final picked=await ImagePicker().pickImage(source:source,
      imageQuality:85,
      maxWidth:1800);
      if(picked==null||!mounted)return;
      final result=await AppScope.of(context).api.upload('/v3/files/complaint',
      picked.name,
      await picked.readAsBytes(),
      mimeType(picked.name));
      if(mounted)setState(()=>file=Map<String,
      dynamic>.from(result as Map));
    }catch(e){
      if(mounted)feedback(context,
      e);
    }finally{
      if(mounted)setState(()=>busy=false);
    }
  } @override Widget build(BuildContext context)=>PageBody(title:'Report an issue',
  subtitle:'Tell us what needs attention.',
  children:[
    Surface(child:Form(key:form,
    child:Column(children:[
      TextFormField(controller:title,
      decoration:const InputDecoration(labelText:'Category / title'),
      validator:(v)=>(v??'').trim().length<2?'Use at least 2 characters':null),
      const SizedBox(height:16),
      TextFormField(controller:description,
      minLines:4,
      maxLines:7,
      decoration:const InputDecoration(labelText:'Description'),
      validator:(v)=>(v??'').trim().length<5?'Describe the issue in at least 5 characters':null),
      const SizedBox(height:16),
      DropdownButtonFormField<String>(isExpanded:true,
      initialValue:priority,
      decoration:const InputDecoration(labelText:'Priority'),
      items:[
        'Low',
        'Medium',
        'High',
        'Urgent'
      ].map((v)=>DropdownMenuItem(value:v,
      child:Text(v))).toList(),
      onChanged:(v)=>priority=v??'Medium'),
      const SizedBox(height:15),
      Wrap(spacing:8,
      children:[
        OutlinedButton.icon(onPressed:busy?null:()=>attach(ImageSource.camera),
        icon:const Icon(Icons.camera_alt_outlined),
        label:const Text('Camera')),
        OutlinedButton.icon(onPressed:busy?null:()=>attach(ImageSource.gallery),
        icon:const Icon(Icons.photo_outlined),
        label:const Text('Photos'))
      ]),
      if(file!=null)Text('${file!['name']}'),
      const SizedBox(height:18),
      FilledButton(onPressed:busy?null:()async{
        if(!form.currentState!.validate())return;
        setState(()=>busy=true);
        final ok=await perform(context,
        ()=>AppScope.of(context).save('complaint',
        {
          'category':title.text.trim(),
          'description':description.text.trim(),
          'priority':priority,
          'file_id':file?[
            'id'
          ]
        }),
        success:'Complaint submitted');
        if(mounted){
          setState(()=>busy=false);
          if(ok)Navigator.pop(context);
        }
      },
      child:Text(busy?'Please wait…':'Submit complaint'))
    ])))
  ]);
} class ComplaintDetailPage extends StatefulWidget {
  const ComplaintDetailPage({
    super.key,
    required this.id
  });
  final int id;
  @override State<ComplaintDetailPage> createState()=>_ComplaintDetailPageState();
} class _ComplaintDetailPageState extends State<ComplaintDetailPage>{
  final note=TextEditingController();
  String? status;
  int? assigned;
  bool initialized=false,
  busy=false;
  @override void dispose(){
    note.dispose();
    super.dispose();
  }@override Widget build(BuildContext context){
    final app=AppScope.of(context),
    t=app.find('complaints',
    widget.id);
    if(t==null)return const PageBody(title:'Complaint',
    children:[
      EmptyState('Complaint not found or no longer assigned.')
    ]);
    if(!initialized){
      status='${t['status']}';
      assigned=t[
        'assigned_to'
      ]as int?;
      initialized=true;
    }return PageBody(title:'${t['category']}',
    subtitle:'Maintenance request',
    refresh:app.refresh,
    children:[
      Surface(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
      children:[
        StatusPill('${t['status']}'),
        const SizedBox(height:14),
        Text('${t['description']}'),
        const SizedBox(height:12),
        Text('${t['priority']??'Medium'} priority',
        style:const TextStyle(color:muted,
        fontSize:12)),
        if(t[
          'file_id'
        ]!=null)TextButton.icon(onPressed:()=>openPrivateFile(context,
        t[
          'file_id'
        ]as int),
        icon:const Icon(Icons.image_outlined),
        label:const Text('View attachment'))
      ])),
      if(app.owner||app.staff)Surface(child:Column(children:[
        if(app.owner)DropdownButtonFormField<int>(isExpanded:true,
        initialValue:assigned??0,
        decoration:const InputDecoration(labelText:'Assigned staff'),
        items:[
          const DropdownMenuItem(value:0,
          child:Text('Unassigned')),
          for(final s in app.rows('staff'))DropdownMenuItem(value:s[
            'id'
          ]as int,
          child:Text('${s['name']}'))
        ],
        onChanged:(v)=>assigned=v==0?null:v),
        const SizedBox(height:16),
        DropdownButtonFormField<String>(isExpanded:true,
        initialValue:status,
        decoration:const InputDecoration(labelText:'Status'),
        items:[
          'submitted',
          'assigned',
          'in_progress',
          'resolved',
          'reopened'
        ].map((s)=>DropdownMenuItem(value:s,
        child:Text(s.replaceAll('_',
        ' ')))).toList(),
        onChanged:(v)=>status=v),
        const SizedBox(height:16),
        TextField(controller:note,
        minLines:2,
        maxLines:4,
        decoration:const InputDecoration(labelText:'Progress / resolution note')),
        const SizedBox(height:16),
        FilledButton(onPressed:busy?null:()async{
          if(note.text.trim().length<2){
            feedback(context,
            'Add an update note.');
            return;
          }setState(()=>busy=true);
          final ok=await perform(context,
          ()=>app.mutate('/v3/complaints/${widget.id}',
          method:'PATCH',
          body:{
            'status':status,
            'assigned_to':assigned,
            'note':note.text.trim()
          }),
          success:'Complaint updated');
          if(mounted){
            setState(()=>busy=false);
            if(ok)note.clear();
          }
        },
        child:Text(busy?'Saving…':'Save update'))
      ])),
      const SectionTitle('Request history'),
      for(final h in t[
        'history'
      ]as List? ?? [
      ])Surface(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
      children:[
        Text('${h['status']}'.replaceAll('_',
        ' '),
        style:const TextStyle(fontWeight:FontWeight.w800)),
        const SizedBox(height:6),
        Text('${h['note']}'),
        Text(friendlyDate(h['at']),
        style:const TextStyle(color:muted,
        fontSize:10))
      ]))
    ]);
  }
} class FacilitiesPage extends StatefulWidget {
  const FacilitiesPage({
    super.key
  });
  @override State<FacilitiesPage> createState()=>_FacilitiesPageState();
} class _FacilitiesPageState extends State<FacilitiesPage>{
  String filter='All';
  @override Widget build(BuildContext context){
    final app=AppScope.of(context);
    final rows=app.rows('facilities').where((r)=>filter=='All'||r[
      'status'
    ]==filter).toList();
    return PageBody(title:'Facility updates',
    subtitle:'Power, water, Wi-Fi and maintenance.',
    refresh:app.refresh,
    children:[
      Wrap(spacing:7,
      children:[
        for(final s in [
          'All',
          'scheduled',
          'outage',
          'restored'
        ])ChoiceChip(label:Text(s),
        selected:filter==s,
        onSelected:(_)=>setState(()=>filter=s))
      ]),
      const SizedBox(height:15),
      for(final f in rows)Surface(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
      children:[
        Row(children:[
          Expanded(child:Text('${f['title']}',
          style:const TextStyle(fontWeight:FontWeight.w800))),
          StatusPill('${f['status']}')
        ]),
        const SizedBox(height:12),
        Text('${f['details']}',
        style:const TextStyle(fontSize:12)),
        Text('${f['category']}',
        style:const TextStyle(color:muted,
        fontSize:10)),
        if((f[
          'history'
        ]as List? ?? [
        ]).isNotEmpty)ExpansionTile(tilePadding:EdgeInsets.zero,
        title:const Text('Status history',
        style:TextStyle(fontSize:11)),
        children:[
          for(final h in f[
            'history'
          ]as List)ListTile(dense:true,
          title:Text('${h['status']}'),
          subtitle:Text(friendlyDate(h['at'])))
        ]),
        if(app.owner)TextButton(onPressed:()=>editEntity(context,
        'facility',
        id:f[
          'id'
        ]as int,
        initial:f),
        child:const Text('Edit update'))
      ])),
      if(rows.isEmpty)const EmptyState('No facility updates in this view.'),
      if(app.owner)addButton(context,
      'Publish update',
      'facility')
    ]);
  }
} class AnnouncementsPage extends StatefulWidget {
  const AnnouncementsPage({
    super.key
  });
  @override State<AnnouncementsPage> createState()=>_AnnouncementsPageState();
} class _AnnouncementsPageState extends State<AnnouncementsPage>{
  bool archived=false;
  @override Widget build(BuildContext context){
    final app=AppScope.of(context);
    final notices=app.rows('notices').where((n)=>archived?n[
      'status'
    ]=='archived':n[
      'status'
    ]!='archived').toList();
    return PageBody(title:'Announcements',
    refresh:app.refresh,
    children:[
      if(app.owner)SwitchListTile(contentPadding:EdgeInsets.zero,
      title:const Text('Show archive',
      style:TextStyle(fontSize:12)),
      value:archived,
      onChanged:(v)=>setState(()=>archived=v)),
      for(final n in notices)Surface(onTap:()=>openPage(context,
      'postDetail',
      id:n[
        'id'
      ]as int),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,
      children:[
        Row(children:[
          Expanded(child:Text('${n['title']}',
          style:const TextStyle(fontWeight:FontWeight.w800))),
          if(n[
            'important'
          ]==true)const StatusPill('Important')
        ]),
        const SizedBox(height:12),
        Text('${n['body']}',
        maxLines:3,
        overflow:TextOverflow.ellipsis,
        style:const TextStyle(color:muted,
        fontSize:12)),
        const SizedBox(height:10),
        Text(n[
          'read'
        ]==true?'Read':'Unread',
        style:const TextStyle(color:lavender,
        fontSize:10))
      ])),
      if(notices.isEmpty)const EmptyState('No announcements here yet.'),
      if(app.owner)addButton(context,
      'New announcement',
      'notice')
    ]);
  }
} class NoticeDetailPage extends StatefulWidget {
  const NoticeDetailPage({
    super.key,
    required this.id
  });
  final int id;
  @override State<NoticeDetailPage> createState()=>_NoticeDetailPageState();
} class _NoticeDetailPageState extends State<NoticeDetailPage>{
  bool marked=false;
  @override void didChangeDependencies(){
    super.didChangeDependencies();
    if(!marked){
      marked=true;
      final app=AppScope.of(context);
      Future.microtask(()async{
        try{
          await app.mutate('/v3/read/notice/${widget.id}');
        }catch(_){
        }
      });
    }
  }@override Widget build(BuildContext context){
    final app=AppScope.of(context),
    n=app.find('notices',
    widget.id);
    if(n==null)return const PageBody(title:'Announcement',
    children:[
      EmptyState('Notice unavailable.')
    ]);
    return PageBody(title:'${n['title']}',
    subtitle:'Posted by your PG owner',
    children:[
      Surface(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
      children:[
        if(n[
          'important'
        ]==true)const StatusPill('Important'),
        const SizedBox(height:15),
        Text('${n['body']}',
        style:const TextStyle(height:1.7)),
        const SizedBox(height:20),
        Text(friendlyDate(n['created_at']),
        style:const TextStyle(color:muted,
        fontSize:10))
      ])),
      if(app.owner)... [
        FilledButton(onPressed:()=>editEntity(context,
        'notice',
        id:widget.id,
        initial:n),
        child:const Text('Edit announcement')),
        const SizedBox(height:12),
        OutlinedButton(onPressed:()async{
          if(await ask(context,
          'Change the archive status of this notice?')&&context.mounted)await perform(context,
          ()=>app.save('notice',
          {
            ...n,
            'status':n[
              'status'
            ]=='archived'?'active':'archived'
          },
          id:widget.id));
        },
        child:Text(n[
          'status'
        ]=='archived'?'Restore announcement':'Archive announcement'))
      ]
    ]);
  }
} class MealsPage extends StatelessWidget {
  const MealsPage({
    super.key
  });
  @override Widget build(BuildContext context){
    final app=AppScope.of(context);
    return PageBody(title:'Food menu',
    subtitle:'Your PG’s weekly meals.',
    refresh:app.refresh,
    children:[
      for(final m in app.rows('meals'))Surface(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
      children:[
        Text('${m['day']}',
        style:const TextStyle(fontSize:17,
        fontWeight:FontWeight.w800)),
        const SizedBox(height:12),
        for(final key in [
          'breakfast',
          'lunch',
          'dinner'
        ])Padding(padding:const EdgeInsets.only(bottom:12),
        child:Row(crossAxisAlignment:CrossAxisAlignment.start,
        children:[
          const Icon(Icons.restaurant_outlined,
          color:lavender,
          size:18),
          const SizedBox(width:10),
          Expanded(child:Text('${key[0].toUpperCase()}${key.substring(1)}\n${m[key]}',
          style:const TextStyle(height:1.5,
          fontSize:12)))
        ])),
        if(app.owner)TextButton(onPressed:()=>editEntity(context,
        'meal',
        id:m[
          'id'
        ]as int,
        initial:m),
        child:const Text('Edit menu'))
      ])),
      if(app.rows('meals').isEmpty)const EmptyState('No meal menu published.'),
      if(app.owner)addButton(context,
      'Set daily menu',
      'meal')
    ]);
  }
} class NotificationsPage extends StatefulWidget {
  const NotificationsPage({
    super.key
  });
  @override State<NotificationsPage> createState() => _NotificationsPageState();
}
class _NotificationsPageState extends State<NotificationsPage> {
  Timer? _poller;
  bool _loading = false;
  Future<void> _reload() async {
    if (!mounted || _loading) return;
    _loading = true;
    try { await AppScope.of(context).refresh(); } catch (_) { /* Pull to refresh can be retried. */ }
    finally { _loading = false; }
  }
  @override void didChangeDependencies() {
    super.didChangeDependencies();
    if (_poller == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _reload(); });
      _poller = Timer.periodic(const Duration(seconds: 15), (_) => _reload());
    }
  }
  @override void dispose() { _poller?.cancel(); super.dispose(); }
  @override Widget build(BuildContext context){
    final app=AppScope.of(context),
    rows=app.rows('notifications');
    return PageBody(title:'Notifications',
    subtitle:'Important activity in one place.',
    refresh:app.refresh,
    actions:[
      IconButton(tooltip:'Mark all read',
      onPressed:()=>perform(context,
      ()async{
        for(final n in rows.where((n)=>n[
          'read'
        ]!=true)){
          await app.api.request('/v3/read/alert/${n['id']}',
          method:'POST');
        }await app.refresh();
      }),
      icon:const Icon(Icons.done_all))
    ],
    children:[
      for(final n in rows)Surface(onTap:()async{
        final ok=await perform(context,
        ()=>app.mutate('/v3/read/alert/${n['id']}'));
        if(ok&&context.mounted)await openPage(context,
        '${n['destination']}');
      },
      child:Row(children:[
        const Icon(Icons.notifications_outlined,
        color:lavender),
        const SizedBox(width:12),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
        children:[
          Text('${n['title']}',
          style:TextStyle(fontWeight:n[
            'read'
          ]==true?FontWeight.w500:FontWeight.w800)),
          Text('${n['body']}',
          style:const TextStyle(color:muted,
          fontSize:11)),
          Text(friendlyDate(n['created_at']),
          style:const TextStyle(color:muted,
          fontSize:9))
        ])),
        if(n[
          'read'
        ]!=true)const CircleAvatar(radius:4,
        backgroundColor:lavender)
      ])),
      if(rows.isEmpty)const EmptyState('You’re all caught up.')
    ]);
  }
}

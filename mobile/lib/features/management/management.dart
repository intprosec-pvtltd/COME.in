import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../app/controller.dart';
import '../../app/router.dart';
import '../../core/design.dart';
import '../../core/app_theme.dart';
Widget addButton(BuildContext context,
String label,
String kind)=>Padding(padding:const EdgeInsets.symmetric(vertical:10),
child:FilledButton.icon(onPressed:()=>editEntity(context,
kind),
icon:const Icon(Icons.add),
label:Text(label)));
Widget propertySelector(BuildContext context){
  final app=AppScope.of(context);
  return Padding(padding:const EdgeInsets.only(bottom:15),
  child:DropdownButtonFormField<int>(isExpanded:true,
  initialValue:app.propertyId??-1,
  decoration:const InputDecoration(labelText:'Property'),
  items:[
    const DropdownMenuItem(value:-1,
    child:Text('All properties')),
    for(final p in app.rows('properties'))DropdownMenuItem(value:p[
      'id'
    ] as int,
    child:Text('${p['name']}',
    overflow:TextOverflow.ellipsis))
  ],
  onChanged:(v)=>app.selectProperty(v==-1?null:v)));
} class PropertiesPage extends StatelessWidget {
  const PropertiesPage({
    super.key
  });
  @override Widget build(BuildContext context){
    final app=AppScope.of(context);
    return PageBody(title:'Your properties',
    subtitle:'A home for every new chapter.',
    refresh:app.refresh,
    children:[
      for(final p in app.rows('properties'))Surface(onTap:()=>openPage(context,
      'propertyDetail',
      id:p[
        'id'
      ]as int),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,
      children:[
        Row(children:[
          const Icon(Icons.apartment_rounded,
          color:lavender,
          size:38),
          const SizedBox(width:12),
          Expanded(child:Text('${p['name']}',
          style:const TextStyle(fontWeight:FontWeight.w800,
          fontSize:17))),
          if(p[
            'archived'
          ]==true)const StatusPill('Archived')
        ]),
        const SizedBox(height:12),
        Text('${p['city']}\n${p['address']}',
        style:const TextStyle(color:muted,
        fontSize:12)),
        const SizedBox(height:10),
        const Text('Open property →',
        style:TextStyle(fontWeight:FontWeight.w700,
        fontSize:12))
      ])),
      addButton(context,
      'Add property',
      'property')
    ]);
  }
} class PropertyDetailPage extends StatelessWidget {
  const PropertyDetailPage({
    super.key,
    required this.id
  });
  final int id;
  @override Widget build(BuildContext context){
    final app=AppScope.of(context),
    p=app.find('properties',
    id);
    if(p==null)return const PageBody(title:'Property',
    children:[
      EmptyState('Property not found.')
    ]);
    final rooms=app.rows('rooms').where((r)=>(r[
      'property_id'
    ]??0)==id).toList();
    final residents=app.rows('residents').where((r)=>(r[
      'property_id'
    ]??0)==id).toList();
    return PageBody(title:'${p['name']}',
    subtitle:'${p['address']}',
    children:[
      HeroCard(label:'Property occupancy',
      value:'${residents.length} residents',
      detail:'${rooms.length} rooms · ${rooms.fold<int>(0,(s,r)=>s+(r['beds']as int))} beds'),
      Surface(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
      children:[
        Text('City · ${p['city']}'),
        const SizedBox(height:8),
        Text('UPI · ${p['upi']}'),
        const SizedBox(height:10),
        TextButton(onPressed:()=>editEntity(context,
        'property',
        id:id,
        initial:p),
        child:const Text('Edit property'))
      ])),
      FeatureTile(title:'Rooms & beds',
      icon:Icons.bed_outlined,
      onTap:(){
        app.selectProperty(id);
        openPage(context,
        'rooms');
      }),
      FeatureTile(title:'Residents',
      icon:Icons.people_outline,
      onTap:(){
        app.selectProperty(id);
        openPage(context,
        'residents');
      }),
      if(id!=0)OutlinedButton(onPressed:()async{
        if(await ask(context,
        '${p['archived']==true?'Restore':'Archive'} this property? Occupied properties cannot be archived.')&&context.mounted)await perform(context,
        ()=>app.save('property',
        {
          ...p,
          'archived':p[
            'archived'
          ]!=true
        },
        id:id));
      },
      child:Text(p[
        'archived'
      ]==true?'Restore property':'Archive property'))
    ]);
  }
} class RoomsPage extends StatefulWidget {
  const RoomsPage({
    super.key
  });
  @override State<RoomsPage> createState()=>_RoomsPageState();
} class _RoomsPageState extends State<RoomsPage>{
  String floor='All';
  @override Widget build(BuildContext context){
    final app=AppScope.of(context);
    final allRooms=app.scoped('rooms');
    // Build floor choices from rooms belonging to the currently selected PG.
    // No fixed number of floors is assumed.
    final availableFloors=allRooms
        .map((r)=>(r['floor']??'Ground').toString().trim())
        .map((f)=>f.isEmpty?'Ground':f)
        .toSet().toList();
    availableFloors.sort((a,b){
      if(a=='Ground')return -1;
      if(b=='Ground')return 1;
      final ai=int.tryParse(RegExp(r'^(?:Floor\s+)?(\d+)$',caseSensitive:false).firstMatch(a)?.group(1)??'');
      final bi=int.tryParse(RegExp(r'^(?:Floor\s+)?(\d+)$',caseSensitive:false).firstMatch(b)?.group(1)??'');
      if(ai!=null&&bi!=null)return ai.compareTo(bi);
      if(ai!=null)return -1;
      if(bi!=null)return 1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
    final selectedFloor=floor=='All'||availableFloors.contains(floor)?floor:'All';
    final rooms=allRooms.where((r)=>selectedFloor=='All'||
      ((r['floor']??'Ground').toString().trim().isEmpty?'Ground':(r['floor']??'Ground').toString().trim())==selectedFloor).toList();
    return PageBody(title:'Rooms & beds',
    refresh:app.refresh,
    children:[
      propertySelector(context),
      Wrap(spacing:7,
      children:[
        for(final f in ['All',...availableFloors])ChoiceChip(label:Text(f),
        selected:selectedFloor==f,
        onSelected:(_)=>setState(()=>floor=f))
      ]),
      const SizedBox(height:15),
      for(final r in rooms)Surface(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
      children:[
        Row(children:[
          Expanded(child:Text('Room ${r['name']}',
          style:const TextStyle(fontWeight:FontWeight.w800,
          fontSize:16))),
          Text('${r['floor']??'Ground'}',
          style:const TextStyle(color:muted,
          fontSize:11))
        ]),
        const SizedBox(height:6),
        Row(children:[
          const Icon(Icons.apartment_rounded,size:19,color:plum),
          const SizedBox(width:5),
          Expanded(child:Text('PG: ${app.find('properties',(r['property_id'] as num?)?.toInt()??0)?['name']??'Primary PG'}',
            style:const TextStyle(color:plum,fontSize:14,fontWeight:FontWeight.w700))),
        ]),
        const SizedBox(height:13),
        Wrap(spacing:8,
        runSpacing:8,
        children:[
          for(var i=1;
          i<=(r[
            'beds'
          ]as int);
          i++)_bed(context,
          app,
          r,
          i)
        ]),
        TextButton(onPressed:()=>openPage(context,
        'roomDetail',
        id:r[
          'id'
        ]as int),
        child:const Text('View room →'))
      ])),
      if(rooms.isEmpty)const EmptyState('No rooms in this view.'),
      addButton(context,
      'Add room',
      'room')
    ]);
  } Widget _bed(BuildContext context,
  AppController app,
  Map<String,
  dynamic> room,
  int bed){
    final people=app.rows('residents').where((p)=>p[
      'room'
    ]==room[
      'name'
    ]&&(p[
      'property_id'
    ]??0)==(room[
      'property_id'
    ]??0)&&p[
      'bed'
    ]==bed);
    final person=people.isEmpty?null:people.first;
    return InkWell(onTap:()=>openPage(context,
    'allocation',
    id:room[
      'id'
    ]as int),
    child:Container(width:(MediaQuery.sizeOf(context).width-100)/2,
    padding:const EdgeInsets.all(12),
    decoration:BoxDecoration(color:person==null?lavender.withValues(alpha:.12):successGreen.withValues(alpha:.10),
    borderRadius:BorderRadius.circular(13),
    border:Border.all(color:person==null?lavender.withValues(alpha:.35):successGreen.withValues(alpha:.2))),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,
    children:[
      Text('Bed $bed',
      style:const TextStyle(fontSize:11)),
      const SizedBox(height:6),
      Text(person==null?'Available':'${person['name']}',
      style:const TextStyle(fontWeight:FontWeight.w700,
      fontSize:12),
      maxLines:2)
    ])));
  }
} class RoomDetailPage extends StatelessWidget {
  const RoomDetailPage({
    super.key,
    required this.id
  });
  final int id;
  @override Widget build(BuildContext context){
    final app=AppScope.of(context),
    r=app.find('rooms',
    id);
    if(r==null)return const PageBody(title:'Room',
    children:[
      EmptyState('Room not found.')
    ]);
    final people=app.rows('residents').where((p)=>p[
      'room'
    ]==r[
      'name'
    ]&&(p[
      'property_id'
    ]??0)==(r[
      'property_id'
    ]??0)).toList();
    return PageBody(title:'Room ${r['name']}',
    subtitle:'${r['floor']??'Ground'}',
    children:[
      HeroCard(label:'Bed occupancy',
      value:'${people.length} / ${r['beds']}',
      detail:'${(r['beds']as int)-people.length} available beds'),
      for(final p in people)FeatureTile(title:'${p['name']}',
      subtitle:'Bed ${p['bed']??'not assigned'}',
      icon:Icons.person_outline,
      onTap:()=>openPage(context,
      'residentDetail',
      id:p[
        'id'
      ]as int)),
      FilledButton(onPressed:()=>openPage(context,
      'allocation',
      id:id),
      child:const Text('Assign / move resident')),
      const SizedBox(height:10),
      OutlinedButton(onPressed:()=>editEntity(context,
      'room',
      id:id,
      initial:r),
      child:const Text('Edit room'))
    ]);
  }
} class AllocationPage extends StatefulWidget {
  const AllocationPage({
    super.key,
    required this.roomId
  });
  final int roomId;
  @override State<AllocationPage> createState()=>_AllocationPageState();
} class _AllocationPageState extends State<AllocationPage>{
  int? resident,
  bed;
  final reason = TextEditingController();
  bool busy=false;
  @override void dispose(){reason.dispose();super.dispose();}
  @override Widget build(BuildContext context){
    final app=AppScope.of(context),
    room=app.find('rooms',
    widget.roomId);
    if(room==null)return const PageBody(title:'Assign bed',
    children:[
      EmptyState('Room not found.')
    ]);
    final occupied=app.rows('residents').where((r)=>r[
      'room'
    ]==room[
      'name'
    ]&&(r[
      'property_id'
    ]??0)==(room[
      'property_id'
    ]??0)&&r[
      'id'
    ]!=resident).map((r)=>r[
      'bed'
    ]).toSet();
    final available=List.generate(room[
      'beds'
    ]as int,
    (i)=>i+1).where((i)=>!occupied.contains(i)).toList();
    return PageBody(title:'Assign a bed',
    subtitle:'Room ${room['name']}',
    children:[
      Surface(child:Column(children:[
        DropdownButtonFormField<int>(isExpanded:true,
        decoration:const InputDecoration(labelText:'Resident'),
        items:app.rows('residents').map((r)=>DropdownMenuItem(value:r[
          'id'
        ]as int,
        child:Text('${r['name']}'))).toList(),
        onChanged:(v)=>setState((){
          resident=v;
          bed=null;
        })),
        const SizedBox(height:16),
        DropdownButtonFormField<int>(isExpanded:true,
        key:ValueKey(resident),
        decoration:const InputDecoration(labelText:'Available bed'),
        items:available.map((i)=>DropdownMenuItem(value:i,
        child:Text('Bed $i'))).toList(),
        onChanged:(v)=>setState(()=>bed=v)),
        const SizedBox(height:12),
        TextField(controller:reason, maxLength:300,
          decoration:const InputDecoration(labelText:'Reason for room assignment / transfer',
          hintText:'e.g. Requested a different room')),
        const SizedBox(height:10),
        FilledButton(onPressed:busy||resident==null||bed==null?null:()async{
          if(reason.text.trim().length < 3){
            feedback(context,'Enter a reason (at least 3 characters).');return;
          }
          setState(()=>busy=true);
          final ok=await perform(context, ()async{
            await app.api.request('/v3/residents/$resident/transfer-room',
              method:'POST', body:{'room_id':widget.roomId,'bed':bed,
              'reason':reason.text.trim()});
            await app.refresh();
          });
          if(mounted){
            setState(()=>busy=false);
            if(ok)Navigator.pop(context);
          }
        },
        child:Text(busy?'Updating…':'Confirm room / bed transfer')),
        const SizedBox(height:10),
        const Text('The previous bed is released. Transfers are recorded with a reason and timestamp.',
        style:TextStyle(color:muted,
        fontSize:11))
      ]))
    ]);
  }
} class ResidentsPage extends StatefulWidget {
  const ResidentsPage({
    super.key
  });
  @override State<ResidentsPage> createState()=>_ResidentsPageState();
} class _ResidentsPageState extends State<ResidentsPage>{
  String query='';
  @override Widget build(BuildContext context){
    final app=AppScope.of(context);
    final residents=app.scoped('residents').where((r)=>'${r['name']} ${r['room']}'.toLowerCase().contains(query.toLowerCase())).toList();
    return PageBody(title:'Residents',
    refresh:app.refresh,
    children:[
      propertySelector(context),
      TextField(decoration:const InputDecoration(hintText:'Search name or room',
      prefixIcon:Icon(Icons.search)),
      onChanged:(v)=>setState(()=>query=v)),
      const SizedBox(height:15),
      for(final r in residents)Surface(onTap:()=>openPage(context,
      'residentDetail',id:r['id'] as int),
      child:Row(children:[
        const Icon(Icons.person_outline_rounded,color:plum,size:32),
        const SizedBox(width:14),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('${r['name']}',style:const TextStyle(fontSize:16,fontWeight:FontWeight.w800)),
          const SizedBox(height:7),
          Row(children:[
            const Icon(Icons.apartment_rounded,color:plum,size:19),
            const SizedBox(width:6),
            Expanded(child:Text('PG: ${app.find('properties', int.tryParse('${r['property_id']}')??-1)?['name'] ?? 'Not assigned'}',
              maxLines:2,overflow:TextOverflow.ellipsis,
              style:const TextStyle(color:plum,fontSize:15,fontWeight:FontWeight.w700))),
          ]),
          const SizedBox(height:5),
          Text('Room ${r['room']??'—'} · Bed ${r['bed']??'—'}',
            style:const TextStyle(color:muted,fontSize:13)),
        ])),
        const Icon(Icons.chevron_right_rounded,color:plum),
      ])),
      if(residents.isEmpty)const EmptyState('No matching residents.'),
      Padding(padding:const EdgeInsets.symmetric(vertical:10),child:FilledButton.icon(
        onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>const OwnerInviteResidentPage())),
        icon:const Icon(Icons.person_add_alt_1),label:const Text('Create resident account')))
    ]);
  }
} class ResidentDetailPage extends StatelessWidget {
  const ResidentDetailPage({
    super.key,
    required this.id
  });
  final int id;
  @override Widget build(BuildContext context){
    final app=AppScope.of(context),
    r=app.find('residents',
    id);
    if(r==null)return const PageBody(title:'Resident',
    children:[
      EmptyState('Resident not found.')
    ]);
    final inv=app.rows('invoices').where((i)=>i[
      'resident_id'
    ]==id).toList();
    return PageBody(title:'${r['name']}',
    subtitle:'Room ${r['room']} · Bed ${r['bed']??'—'} · Monthly rent ${inr(r['monthly_rent']??'0')}',
    children:[
      HeroCard(label:'Outstanding rent',
      value:inr(inv.fold<double>(0,
      (s,
      i)=>s+amount(i[
        'outstanding'
      ])))),
      Surface(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
      children:[
        Text('${r['email']}'),
        const SizedBox(height:8),
        Text('Phone · ${r['phone']??'—'}'),
        const SizedBox(height:8),
        Text('Monthly rent · ${inr(r['monthly_rent']??'0')}',style:const TextStyle(fontWeight:FontWeight.w700)),
        const SizedBox(height:15),
        FilledButton(onPressed:()=>editEntity(context,
        'resident',
        id:id,
        initial:r),
        child:const Text('Edit resident'))
      ])),
      if(app.owner) FeatureTile(
        title:'Review identity proof',
        subtitle:'View documents uploaded by this resident and approve or reject',
        icon:Icons.assignment_ind_outlined,
        onTap:()=>openPage(context,'residentProofReview',id:id)),
      if(app.profile['role']=='owner')FeatureTile(title:'Reissue temporary login',
        subtitle:'Generate new one-time resident access details',icon:Icons.lock_reset,
        onTap:()async{
          if(!await ask(context,'Generate a new temporary password for this resident?')||!context.mounted)return;
          try{
            final data=await app.mutate('/v3/residents/$id/reset-access');
            if(context.mounted)await showResidentCredentials(context,Map<String,dynamic>.from(data as Map));
          }catch(e){if(context.mounted)feedback(context,'$e');}
        }),
      if(app.profile['role']=='owner')OutlinedButton.icon(
        onPressed:()async{
          final active=r['is_active']!=false;
          if(!await ask(context,active
            ?'Deactivate this resident account? Sign-in access will be removed; rent and document history remains.'
            :'Reactivate this resident account?')||!context.mounted)return;
          try{await app.mutate('/v3/residents/$id/access',method:'PATCH',body:{'active':!active});
            if(context.mounted){feedback(context,active?'Resident deactivated':'Resident reactivated');Navigator.pop(context);}}
          catch(e){if(context.mounted)feedback(context,'$e');}
        },icon:Icon(r['is_active']==false?Icons.person_add_alt_1_outlined:Icons.person_off_outlined),
          label:Text(r['is_active']==false?'Reactivate resident':'Deactivate resident')),
      if(app.profile['role']=='owner' && r['is_active']==false)
        OutlinedButton.icon(
          icon:const Icon(Icons.delete_forever_outlined),
          label:const Text('Delete permanently (eligible accounts only)'),
          onPressed:()async{
            final email='${r['email'] ?? ''}';
            try {
              final review=Map<String,dynamic>.from(await app.api.request('/v3/residents/$id/deletion-review') as Map);
              if(review['eligible']!=true){
                if(context.mounted)feedback(context,'This resident has linked financial, document or activity records. Keep the account deactivated.');
                return;
              }
              if(!context.mounted)return;
              final field=TextEditingController();
              final entered=await showDialog<String>(context:context,builder:(dialogContext)=>AlertDialog(
                title:const Text('Permanently delete resident?'),
                content:Column(mainAxisSize:MainAxisSize.min,children:[
                  const Text('This cannot be undone. Type the exact resident email to confirm:'),
                  const SizedBox(height:10),Text(email,style:const TextStyle(fontWeight:FontWeight.w700)),
                  TextField(controller:field,autocorrect:false,keyboardType:TextInputType.emailAddress),
                ]),
                actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext),child:const Text('Cancel')),
                  TextButton(onPressed:()=>Navigator.pop(dialogContext,field.text.trim()),child:const Text('Delete permanently'))],
              ));
              field.dispose();
              if(entered!=email || !context.mounted)return;
              await app.mutate('/v3/residents/$id',method:'DELETE',body:{'confirm_email':entered});
              if(context.mounted){feedback(context,'Resident deleted');Navigator.pop(context);}
            } catch(e){if(context.mounted)feedback(context,'Deletion not permitted: $e');}
          },
        ),
      const SectionTitle('Invoices'),
      for(final i in inv)Surface(child:ListTile(contentPadding:EdgeInsets.zero,
      title:Text('${i['period']} · ${inr(i['amount'])}'),
      subtitle:Text('Due ${i['due_date']} · Balance ${inr(i['outstanding'])}'))),
      FeatureTile(title:'Send rent reminder',
      subtitle:'In-app notification to this resident',
      icon:Icons.notifications_outlined,
      onTap:()=>perform(context,
      ()=>app.mutate('/v3/reminders/$id'),
      success:'In-app reminder sent')),
      FeatureTile(title:'Review payments',
      icon:Icons.payments_outlined,
      onTap:()=>openPage(context,
      'payments'))
    ]);
  }
} class StaffPage extends StatelessWidget {
  const StaffPage({
    super.key
  });
  @override Widget build(BuildContext context){
    final app=AppScope.of(context);
    return PageBody(title:'Team & staff',
    subtitle:'People who keep things running.',
    children:[
      propertySelector(context),
      for(final s in app.rows('staff').where((r)=>app.propertyId==null ||
        int.tryParse('${r['property_id']}')==app.propertyId))
        Surface(onTap:()=>openPage(context,'staffDetail',id:s['id'] as int),
        child:Row(children:[
          const Icon(Icons.badge_outlined,color:plum,size:32),
          const SizedBox(width:14),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('${s['name']}',style:const TextStyle(fontSize:16,fontWeight:FontWeight.w800)),
            const SizedBox(height:6),
            Row(children:[
              const Icon(Icons.apartment_rounded,color:plum,size:19),
              const SizedBox(width:6),
              Expanded(child:Text('PG: ${app.find('properties',int.tryParse('${s['property_id']}')??-1)?['name'] ?? 'Not assigned'}',
                maxLines:2,overflow:TextOverflow.ellipsis,
                style:const TextStyle(fontSize:15,color:plum,fontWeight:FontWeight.w700))),
            ]),
            const SizedBox(height:5),
            Text('${s['job']??'Maintenance'}',style:const TextStyle(color:muted,fontSize:13)),
          ])),
          const Icon(Icons.chevron_right_rounded,color:plum),
        ])),
      if(app.rows('staff').isEmpty)const EmptyState('No staff members yet.'),
      addButton(context,
      'Add staff member',
      'staff')
    ]);
  }
} class StaffDetailPage extends StatelessWidget {
  const StaffDetailPage({
    super.key,
    required this.id
  });
  final int id;
  @override Widget build(BuildContext context){
    final app=AppScope.of(context),
    s=app.find('staff',
    id);
    if(s==null)return const PageBody(title:'Staff',
    children:[
      EmptyState('Staff member not found.')
    ]);
    return PageBody(title:'${s['name']}',
    subtitle:'${s['job']??'Maintenance'}',
    children:[
      Surface(child:Row(children:[
        const Icon(Icons.apartment_rounded,color:plum,size:23),
        const SizedBox(width:10),
        Expanded(child:Text('PG: ${app.find('properties',int.tryParse('${s['property_id']}')??-1)?['name'] ?? 'Not assigned'}',
          style:const TextStyle(color:plum,fontSize:16,fontWeight:FontWeight.w700))),
      ])),
      Surface(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
      children:[
        Text('${s['email']}'),
        Text('${s['phone']??''}'),
        TextButton(onPressed:()=>editEntity(context,
        'staff',
        id:id,
        initial:s),
        child:const Text('Edit staff details'))
      ])),
      const SectionTitle('Assigned tasks'),
      for(final t in app.rows('complaints').where((t)=>t[
        'assigned_to'
      ]==id))FeatureTile(title:'${t['category']}',
      subtitle:'${t['status']}',
      icon:Icons.handyman_outlined,
      onTap:()=>openPage(context,
      'complaintDetail',
      id:t[
        'id'
      ]as int)),
      FeatureTile(title:'Assign a task',
      icon:Icons.add_task,
      onTap:()=>openPage(context,
      'complaints'))
    ]);
  }
} class BookingsPage extends StatelessWidget {
  const BookingsPage({
    super.key
  });
  @override Widget build(BuildContext context){
    final app=AppScope.of(context);
    return PageBody(title:'Bookings & allocation',
    subtitle:'An enquiry does not reserve a bed or collect payment.',
    children:[
      propertySelector(context),
      for(final b in app.scoped('bookings'))Surface(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
      children:[
        Row(children:[
          Expanded(child:Text('${b['name']}',
          style:const TextStyle(fontWeight:FontWeight.w800))),
          StatusPill('${b['status']}')
        ]),
        const SizedBox(height:10),
        Text('🏢 ${app.rows('properties').firstWhere((p)=>p['id']==(b['property_id']??0),orElse:()=>{'name':'Primary PG'})['name']}'),
        const SizedBox(height:5),
        Text('${b['phone']} · Preferred room ${b['room']}'),
        TextButton(onPressed:()=>editEntity(context,
        'booking',
        id:b[
          'id'
        ]as int,
        initial:b),
        child:const Text('Update enquiry'))
      ])),
      if(app.scoped('bookings').isEmpty)const EmptyState('No booking enquiries yet.'),
      addButton(context,
      'Add enquiry',
      'booking'),
      FeatureTile(title:'Approve resident & allocate a bed',
      icon:Icons.person_add_alt_1_outlined,
      onTap:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>const OwnerInviteResidentPage()))),
      FeatureTile(title:'Room & bed map',
      icon:Icons.bed_outlined,
      onTap:()=>openPage(context,
      'rooms'))
    ]);
  }
}

Future<void> showResidentCredentials(BuildContext context,Map<String,dynamic> credential) async {
  final text='COME.in resident access\nLogin: ${credential['email']}\nTemporary password: ${credential['temporary_password']}\nValid for 72 hours. Please sign in and change your password immediately. Do not forward this message.';
  await showDialog<void>(context:context,barrierDismissible:false,builder:(dialogContext)=>AlertDialog(
    title:const Text('Resident access created'),
    content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('Credentials are displayed once. Copy or share them securely, then close this dialog.'),
      const SizedBox(height:12),SelectableText(text),
    ])),
    actions:[
      TextButton(onPressed:()async{await Clipboard.setData(ClipboardData(text:text));if(dialogContext.mounted)feedback(dialogContext,'Copied securely');},child:const Text('Copy')),
      TextButton(onPressed:()async{await Share.share(text,subject:'COME.in resident login');},child:const Text('Share')),
      FilledButton(onPressed:()=>Navigator.pop(dialogContext),child:const Text('Done')),
    ]));
}
class OwnerInviteResidentPage extends StatefulWidget {
  const OwnerInviteResidentPage({super.key});
  @override State<OwnerInviteResidentPage> createState()=>_OwnerInviteResidentPageState();
}
class _OwnerInviteResidentPageState extends State<OwnerInviteResidentPage> {
  final form=GlobalKey<FormState>();
  final name=TextEditingController(),email=TextEditingController(),phone=TextEditingController(),rent=TextEditingController(text:'0');
  int propertyId=0,bed=0;String room='';bool busy=false;String? error;
  bool _propertyInitialized=false;
  @override void didChangeDependencies(){
    super.didChangeDependencies();
    if(!_propertyInitialized){propertyId=AppScope.of(context).propertyId??0;_propertyInitialized=true;}
  }
  @override void dispose(){name.dispose();email.dispose();phone.dispose();rent.dispose();super.dispose();}
  Future<void> submit() async {
    if(!form.currentState!.validate())return;
    setState(()=>busy=true);
    final app=AppScope.of(context);
    try{
      final data=await app.mutate('/v3/residents/invite',body:{'name':name.text.trim(),'email':email.text.trim(),
        'phone':phone.text.trim(),'monthly_rent':rent.text.trim(),'property_id':propertyId,'room':room,'bed':bed});
      if(mounted){await showResidentCredentials(context,Map<String,dynamic>.from(data as Map));if(mounted)Navigator.pop(context);}
    }catch(e){if(mounted)setState(()=>error='$e');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context){
    final app=AppScope.of(context);
    final properties=app.rows('properties');
    final rooms=app.rows('rooms').where((r)=>(r['property_id']??0)==propertyId).toList();
    final matching=rooms.where((r)=>r['name']==room).toList();
    final capacity=matching.isEmpty?0:(matching.first['beds'] as num).toInt();
    return PageBody(title:'Create resident account',subtitle:'Only PG owners can issue resident access. Temporary credentials expire in 72 hours.',children:[
      Surface(child:Form(key:form,child:Column(children:[
        TextFormField(controller:name,decoration:const InputDecoration(labelText:'Resident full name'),validator:(v)=>(v??'').trim().length<2?'Enter a name':null),
        const SizedBox(height:12),
        TextFormField(controller:email,keyboardType:TextInputType.emailAddress,decoration:const InputDecoration(labelText:'Resident email'),validator:(v)=>(v??'').contains('@')?null:'Enter a valid email'),
        const SizedBox(height:12),
        TextFormField(controller:phone,keyboardType:TextInputType.phone,decoration:const InputDecoration(labelText:'Phone (optional)')),
        const SizedBox(height:12),
        TextFormField(controller:rent,keyboardType:const TextInputType.numberWithOptions(decimal:true),
          decoration:const InputDecoration(labelText:'Monthly resident rent (₹)'),
          validator:(v){final n=num.tryParse(v?.trim()??'');return n==null||n<0?'Enter a valid non-negative rent':null;}),
        const SizedBox(height:12),
        DropdownButtonFormField<int>(isExpanded:true,initialValue:propertyId,
          decoration:const InputDecoration(labelText:'PG property'),
          items:properties.map((p)=>DropdownMenuItem<int>(value:(p['id'] as num).toInt(),child:Text('${p['name']}',overflow:TextOverflow.ellipsis))).toList(),
          onChanged:(v)=>setState((){propertyId=v??0;room='';bed=0;})),
        const SizedBox(height:12),
        DropdownButtonFormField<String>(isExpanded:true,initialValue:room,
          decoration:const InputDecoration(labelText:'Room (optional)'),
          items:[const DropdownMenuItem(value:'',child:Text('Assign later')),
            for(final r in rooms)DropdownMenuItem(value:'${r['name']}',child:Text('${r['name']}'))],
          onChanged:(v)=>setState((){room=v??'';bed=0;})),
        if(room.isNotEmpty)...[
          const SizedBox(height:12),
          DropdownButtonFormField<int>(initialValue:bed,decoration:const InputDecoration(labelText:'Bed number'),
            items:[const DropdownMenuItem(value:0,child:Text('Assign later')),
              for(var i=1;i<=capacity;i++)DropdownMenuItem(value:i,child:Text('Bed $i'))],onChanged:(v)=>setState(()=>bed=v??0)),
        ],
        if(error!=null)Padding(padding:const EdgeInsets.all(12),child:Text(error!,style:const TextStyle(color:Colors.red))),
        const SizedBox(height:18),
        FilledButton.icon(onPressed:busy?null:submit,icon:const Icon(Icons.person_add_alt_1),
          label:Text(busy?'Creating…':'Create & share access')),
      ]))),
    ]);
  }
}

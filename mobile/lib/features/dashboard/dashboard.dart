import '../../core/localization.dart';
import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../app/router.dart';
import '../../core/design.dart';
import '../../core/app_theme.dart';
String comeinGreeting(DateTime now) {
  final hour = now.hour;
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}
class Dashboard extends StatefulWidget {
  const Dashboard({
    super.key
  });
  @override State<Dashboard> createState() => _DashboardState();
}
class _DashboardState extends State<Dashboard> {
  bool showRent = true;
  @override Widget build(BuildContext context){
    final app=AppScope.of(context);
    final inv=app.rows('invoices').where((i)=>!app.owner||i[
      'period'
    ]==app.period).toList();
    final billed=inv.fold<double>(0,
    (s,
    r)=>s+amount(r[
      'amount'
    ])),
    collected=inv.fold<double>(0,
    (s,
    r)=>s+amount(r[
      'paid'
    ]));
    final expenses=app.rows('expenses').where((e)=>e[
      'period'
    ]==app.period).fold<double>(0,
    (s,
    r)=>s+amount(r[
      'amount'
    ]));
    final residents=app.rows('residents'),
    rooms=app.rows('rooms');
    final beds=rooms.fold<int>(0,
    (s,
    r)=>s+((r[
      'beds'
    ]as num?)?.toInt()??0));
    final issues=app.rows('complaints').where((r)=>r[
      'status'
    ]!='resolved').length;
    return PageBody(title:'',
    refresh:app.refresh,
    actions:[

    ],
    children:[
      const OfficialBrand(width:155),
      const SizedBox(height:22),
      if(app.profile['role']=='owner') Padding(
        padding:const EdgeInsets.only(bottom:14),
        child:FeatureTile(
          title:'My Subscription',
          subtitle:'View bills and payments',
          icon:Icons.qr_code_2,
          onTap:()=>openPage(context,'ownerSubscription'),
        ),
      ),
      Text(app.owner?'${tr(context,'YOUR PORTFOLIO')} · ${app.period}':app.staff?tr(context,'YOUR ASSIGNED WORK'):tr(context,'WELCOME HOME'),
      style:TextStyle(color:secondaryText(context),
      fontSize:10,
      letterSpacing:1.4,
      fontWeight:FontWeight.w800)),
      const SizedBox(height:7),
      Text('${tr(context,comeinGreeting(DateTime.now()))}, ${'${app.profile['name']}'.split(' ').first}.',
      style:const TextStyle(fontSize:27,
      fontWeight:FontWeight.w900)),
      const SizedBox(height:7),
      Text(app.owner?'A good day starts with everything in place.':'${app.profile['tenant']?['name']} · ${app.profile['room']??'Room not assigned'}',
      style:TextStyle(fontSize:12,
      color:secondaryText(context))),
      if(!app.owner && !app.staff) Padding(
        padding: const EdgeInsets.only(top: 12),
        child: FeatureTile(
          title: 'Complete resident verification',
          subtitle: 'Submit a passport photo and masked identity document',
          icon: Icons.badge_outlined,
          onTap: () => openPage(context, 'identityProof'),
        ),
      ),
      if(app.owner)Padding(
        padding:const EdgeInsets.only(top:13,bottom:14),
        child:Material(
          color:Theme.of(context).brightness==Brightness.dark?Theme.of(context).cardColor:const Color(0xFFF4EBF6),
          borderRadius:BorderRadius.circular(18),
          child:InkWell(
            borderRadius:BorderRadius.circular(18),
            onTap:()=>openPage(context,'properties'),
            child:Padding(
              padding:const EdgeInsets.symmetric(horizontal:15,vertical:13),
              child:Row(children:[
                CircleAvatar(
                  radius:20,backgroundColor:Theme.of(context).brightness==Brightness.dark?Theme.of(context).colorScheme.secondaryContainer:Colors.white,
                  child:Icon(Icons.home_work_outlined,color:Theme.of(context).colorScheme.primary,size:22)),
                const SizedBox(width:12),
                Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text('Manage properties',
                    style:TextStyle(fontWeight:FontWeight.w800,color:Theme.of(context).colorScheme.primary,fontSize:14)),
                  const SizedBox(height:2),
                  Text('${app.rows('properties').length} ${app.rows('properties').length==1?'property':'properties'} in your portfolio',
                    style:TextStyle(color:secondaryText(context),fontSize:12)),
                ])),
                Icon(Icons.arrow_forward_ios_rounded,size:16,color:Theme.of(context).colorScheme.primary),
              ]),
            ),
          ),
        ),
      ),
      if(app.staff)HeroCard(label:'Assigned maintenance requests',
      value:'$issues',
      detail:'Keep residents informed with progress updates.',
      child:FilledButton.tonal(onPressed:()=>openPage(context,
      'complaints'),
      child:const Text('View assigned tasks')))else HeroCard(label:app.owner?'Rent collected':'Your rent balance',
      value:app.owner && !showRent ? '₹ •••••' : inr(app.owner?collected:billed-collected),
      detail:app.owner?'${billed==0?0:(collected/billed*100).round()}% collected · ${inr(billed-collected)} outstanding':tr(context,inv.isEmpty?'No invoices yet':'Pay directly to your PG owner'),
      trailing:app.owner?IconButton(tooltip:showRent?'Hide financial amounts':'Show financial amounts',
        onPressed:()=>setState(()=>showRent=!showRent),
        icon:Icon(showRent?Icons.visibility_off_outlined:Icons.visibility_outlined,color:Colors.white)):null,
      child:app.owner?Column(children:[
        LinearProgressIndicator(value:billed==0?0:(collected/billed).clamp(0,
        1).toDouble(),
        minHeight:7,
        color:blush,
        backgroundColor:Colors.white24,
        borderRadius:BorderRadius.circular(8)),
        const SizedBox(height:15),
        Row(children:[
          Expanded(child:Text('Expenses\n${showRent?inr(expenses):'₹ •••••'}',
          style:const TextStyle(color:Colors.white,
          fontSize:12))),
          Expanded(child:Text('Net cashflow\n${showRent?inr(collected-expenses):'₹ •••••'}',
          style:const TextStyle(color:Colors.white,
          fontSize:12))),
          TextButton(onPressed:()=>openPage(context,
          'reports'),
          child:Text(tr(context,'View →'),
          style:TextStyle(color:Colors.white)))
        ])
      ]):FilledButton.tonal(onPressed:()=>openPage(context,
      'rent'),
      child:Text(tr(context,'View rent & payment →')))),
      if(app.owner)Wrap(spacing:12,
      runSpacing:12,
      children:[
        _metric(context,
        'Rent pending',
        inr(billed-collected),
        Icons.schedule,
        'dues'),
        _metric(context,
        'Vacant beds',
        '${(beds-residents.where((r)=>'${r['room']}'.isNotEmpty).length).clamp(0,beds)}',
        Icons.bed_outlined,
        'rooms'),
        _metric(context,
        'Residents',
        '${residents.length}',
        Icons.people_outline,
        'residents'),
        _metric(context,
        'Open issues',
        '$issues',
        Icons.handyman_outlined,
        'complaints')
      ]),
      const SectionTitle('Latest announcements'),
      for(final n in app.rows('notices').where((n)=>n[
        'status'
      ]!='archived').take(2))Surface(onTap:()=>openPage(context,
      'postDetail',
      id:n[
        'id'
      ] as int),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,
      children:[
        Text('${n['title']}',
        style:const TextStyle(fontWeight:FontWeight.w800)),
        const SizedBox(height:8),
        Text('${n['body']}',
        maxLines:2,
        overflow:TextOverflow.ellipsis,
        style:TextStyle(fontSize:12,
        color:secondaryText(context)))
      ])),
      if(app.rows('notices').isEmpty)const EmptyState('No announcements yet.')
    ]);
  } Widget _metric(BuildContext context,
  String label,
  String value,
  IconData icon,
  String route)=>SizedBox(width:(MediaQuery.sizeOf(context).width-52)/2,
  child:Surface(onTap:()=>openPage(context,
  route),
  child:Column(crossAxisAlignment:CrossAxisAlignment.start,
  children:[
    Icon(icon,
    color:lavender),
    const SizedBox(height:14),
    Text(value,
    style:const TextStyle(fontWeight:FontWeight.w900,
    fontSize:21)),
    const SizedBox(height:4),
    Text(tr(context,label),
    style:TextStyle(color:secondaryText(context),
    fontSize:11))
  ])));
} class FeatureMenu extends StatelessWidget {
  const FeatureMenu({
    super.key
  });
  @override Widget build(BuildContext context){
    final app=AppScope.of(context);
    final entries=app.owner? <(String,
    String,
    IconData)>[
      ('properties',
      'Properties',
      Icons.apartment_outlined),
      ('rooms',
      'Rooms & beds',
      Icons.bed_outlined),
      ('residents',
      'Residents',
      Icons.people_outline),
      ('dues',
      'Dues & collections',
      Icons.payments_outlined),
      ('payments',
      'Payment verification',
      Icons.verified_outlined),
      ('expenses',
      'Expenses',
      Icons.trending_up),
      ('reports',
      'Reports & analytics',
      Icons.bar_chart),
      ('staff',
      'Team & staff',
      Icons.badge_outlined),
      ('booking',
      'Bookings & allocation',
      Icons.book_online_outlined),
      ('joiningCode',
      'Resident joining code',
      Icons.key_outlined),
      ('paymentMethods',
      'UPI & bank details',
      Icons.account_balance_outlined),
      if(app.profile['role']=='owner')(
      'ownerSubscription',
      'My subscription · ₹39',
      Icons.receipt_long_outlined)
    ]:<(String,
    String,
    IconData)>[
      ('rent',
      'My rent & receipts',
      Icons.receipt_long_outlined),
      ('accommodation',
      'My accommodation',
      Icons.home_outlined)
    ];
    entries.addAll([
      ('complaints',
      app.owner?'Complaints':'My complaints',
      Icons.handyman_outlined),
      ('facilities',
      'Facility outages',
      Icons.water_drop_outlined),
      ('announcements',
      'Announcements',
      Icons.campaign_outlined),
      ('meals',
      'Food menu',
      Icons.restaurant_outlined),
      ('community',
      'Community chat',
      Icons.forum_outlined),
      ('account',
      'Profile & settings',
      Icons.settings_outlined)
    ]);
    return PageBody(title:app.owner?'Manage your PG':'My PG Life',
    subtitle:'Everything you need, in one place.',
    children:[
      Wrap(spacing:12,
      runSpacing:0,
      children:[
        for(final e in entries)SizedBox(width:(MediaQuery.sizeOf(context).width-52)/2,
        child:Surface(onTap:()=>openPage(context,
        e.$1),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,
        children:[
          Icon(e.$3,
          color:lavender,
          size:27),
          const SizedBox(height:14),
          Text(tr(context,e.$2),
          style:const TextStyle(fontWeight:FontWeight.w800,
          fontSize:13)),
          const SizedBox(height:8),
          Text(tr(context,'Open →'),
          style:TextStyle(color:secondaryText(context),
          fontSize:11))
        ])))
      ])
    ]);
  }
}

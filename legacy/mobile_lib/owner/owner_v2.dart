import '../shared/notification_screen.dart';
import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/v2_ui.dart';
import '../community/community_screen.dart';
import '../core/app_theme.dart';
import '../core/comein_widgets.dart';
import 'reports_screen.dart';

class OwnerV2 extends StatefulWidget{
 final ApiRequest api;final AttachmentUpload upload;final Map<String,dynamic> profile;final VoidCallback logout;
 const OwnerV2({super.key,required this.api,required this.upload,required this.profile,required this.logout});
 @override State<OwnerV2> createState()=>_OwnerV2State();
}
class _OwnerV2State extends State<OwnerV2>{
 int tab=0;String period='${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2,'0')}';
 void go(String title,Widget child)=>Navigator.push(context,MaterialPageRoute(builder:(_)=>child));
 void panel(String title,String path,Widget Function(BuildContext,dynamic,Future<void> Function()) build)=>go(title,DataPanel(title:title,api:widget.api,path:path,builder:build));
 Future<void> addResident()async{final d=await inputForm(context,'Add Resident',['Name','Email','Password','Room']);if(d==null||!mounted)return;await apiAction(context,()=>widget.api('/residents',method:'POST',body:{'name':d['Name'],'email':d['Email'],'password':d['Password'],'room':d['Room']}),()async{setState((){});});}
 void residents()=>panel('Residents','/residents',(c,data,refresh)=>ListView(children:[section('Current residents'),for(final r in data)item('${r['name']} • Room ${r['room']}','${r['email']}',onTap:()async{final d=await inputForm(c,'Edit Resident',['Name','Room'],initial:{'Name':'${r['name']}','Room':'${r['room']}'});if(d!=null&&c.mounted)await apiAction(c,()=>widget.api('/residents/${r['id']}',method:'PUT',body:{'name':d['Name'],'room':d['Room']}),refresh);}),Padding(padding:const EdgeInsets.all(12),child:ElevatedButton.icon(onPressed:()async{await addResident();await refresh();},icon:const Icon(Icons.person_add),label:const Text('Add resident')))]));
 void rent()=>panel('Resident rent status','/owner/rent-status?period=$period',(c,data,refresh){final totals=data['totals'];return ListView(children:[section('Rent for $period'),Card(child:ListTile(title:Text('Collected: ${money(totals['collected'])}'),subtitle:Text('Outstanding: ${money(totals['outstanding'])}\nPaid: ${totals['paid_count']} • Pending: ${totals['pending_count']} • Partial: ${totals['partial_count']} • Unbilled: ${totals['unbilled_count']}'))),for(final r in data['residents'])item('${r['name']} • ${r['status']}','Room ${r['room']} • Due ${money(r['outstanding'])} • Paid ${money(r['paid'])}'),Padding(padding:const EdgeInsets.all(12),child:ElevatedButton(onPressed:()=>newInvoice(c,refresh),child:const Text('Create resident invoice')))]);});
 Future<void> newInvoice(BuildContext c,Future<void> Function() refresh)async{
 final rows=await widget.api('/residents') as List; if(rows.isEmpty){if(c.mounted)toast(c,'Add residents first');return;}
 if(!c.mounted)return;
 final d=await inputForm(c,'New Invoice',['Resident ID','Period YYYY-MM','Amount','Due date YYYY-MM-DD'],initial:{'Resident ID':'${rows.first['id']}','Period YYYY-MM':period,'Amount':'8500','Due date YYYY-MM-DD':'${DateTime.now().toIso8601String().substring(0,10)}'});
 if(d==null||!c.mounted)return;
 await apiAction(c,()=>widget.api('/invoices',method:'POST',body:{'resident_id':int.tryParse(d['Resident ID']??'')??0,'period':d['Period YYYY-MM'],'amount':double.tryParse(d['Amount']??'')??0,'due_date':d['Due date YYYY-MM-DD']}),refresh);
 }
 void payments()=>panel('Payments awaiting verification','/payments',(c,data,refresh)=>ListView(children:[section('Submitted payments'),for(final p in data)Card(child:ListTile(title:Text('${money(p['amount'])} • ${p['status']}'),subtitle:Text('Resident #${p['resident_id']}\nReference: ${p['reference']}'),trailing:p['status']=='pending'&&widget.profile['role']=='owner'?PopupMenuButton<String>(onSelected:(decision)async{if(await confirm(c,'Check your bank/UPI transaction before $decision this payment.')&&c.mounted){await apiAction(c,()=>widget.api('/payments/${p['id']}/verify',method:'POST',body:{'decision':decision}),refresh);}},itemBuilder:(_)=>const[PopupMenuItem(value:'approved',child:Text('Approve bank-verified payment')),PopupMenuItem(value:'rejected',child:Text('Reject payment'))]):p['status']=='approved'?TextButton(onPressed:()=>panel('Receipt #${p['id']}','/receipts/${p['id']}',(ctx,d,_r)=>ListView(children:[section('${d['receipt_number']}'),item('${d['pg_name']} • ${d['resident']}','Amount: ${money(d['amount'])}\nPeriod: ${d['period']}\nReference: ${d['reference']}')])) ,child:const Text('Receipt')):null))]));
 void complaints()=>panel('Manage complaints','/tickets',(c,data,refresh)=>ListView(children:[section('Repair & service tickets'),for(final t in data)Card(child:ListTile(title:Text('${t['category']} • ${t['status']}'),subtitle:Text('${t['description']}\nResident #${t['resident_id']}'),trailing:PopupMenuButton<String>(onSelected:(status)=>apiAction(c,()=>widget.api('/tickets/${t['id']}',method:'PATCH',body:{'status':status}),refresh),itemBuilder:(_)=>['submitted','assigned','in_progress','resolved','reopened'].map((s)=>PopupMenuItem(value:s,child:Text(s))).toList())))]));
 void rooms()=>panel('Rooms and beds','/rooms',(c,data,refresh)=>ListView(children:[section('Room occupancy'),for(final r in data)item('Room ${r['name']}','${r['occupied']} / ${r['beds']} beds occupied',onTap:()async{final d=await inputForm(c,'Edit Room',['Name','Beds'],initial:{'Name':'${r['name']}','Beds':'${r['beds']}'});if(d!=null&&c.mounted)await apiAction(c,()=>widget.api('/rooms/${r['id']}',method:'PUT',body:{'name':d['Name'],'beds':int.tryParse(d['Beds']??'')??0}),refresh);}),Padding(padding:const EdgeInsets.all(12),child:ElevatedButton(onPressed:()async{final d=await inputForm(c,'New Room',['Name','Beds']);if(d!=null&&c.mounted)await apiAction(c,()=>widget.api('/rooms',method:'POST',body:{'name':d['Name'],'beds':int.tryParse(d['Beds']??'')??0}),refresh);},child:const Text('Create room')))]));
 void facilities()=>panel('Facility updates','/facilities',(c,data,refresh)=>ListView(children:[section('Water • Power • Wi-Fi'),for(final f in data)Card(child:ListTile(title:Text('${f['category']} • ${f['status']}'),subtitle:Text('${f['title']}\n${f['details']}'),trailing:PopupMenuButton<String>(onSelected:(status)=>apiAction(c,()=>widget.api('/facilities/${f['id']}',method:'PATCH',body:{'status':status}),refresh),itemBuilder:(_)=>['outage','maintenance','restored','normal'].map((s)=>PopupMenuItem(value:s,child:Text(s))).toList()))),Padding(padding:const EdgeInsets.all(12),child:ElevatedButton(onPressed:()async{final d=await inputForm(c,'New facility update',['Category (water/power/wifi/maintenance/other)','Title','Details','Status (outage/maintenance/restored/normal)'],initial:{'Category (water/power/wifi/maintenance/other)':'water','Status (outage/maintenance/restored/normal)':'outage'});if(d!=null&&c.mounted)await apiAction(c,()=>widget.api('/facilities',method:'POST',body:{'category':d['Category (water/power/wifi/maintenance/other)'],'title':d['Title'],'details':d['Details'],'status':d['Status (outage/maintenance/restored/normal)']}),refresh);},child:const Text('Publish outage/status')))]));
 void notices()=>panel('Announcements','/notices',(c,data,refresh)=>ListView(children:[section('PG announcements'),for(final n in data)item('${n['title']}','${n['category']} • ${n['body']}'),Padding(padding:const EdgeInsets.all(12),child:ElevatedButton(onPressed:()async{final d=await inputForm(c,'New notice',['Title','Body','Category'],initial:{'Category':'general'});if(d!=null&&c.mounted)await apiAction(c,()=>widget.api('/notices',method:'POST',body:{'title':d['Title'],'body':d['Body'],'category':d['Category']}),refresh);},child:const Text('Publish notice')))]));
 void meals()=>panel('Weekly food menu','/meals',(c,data,refresh)=>ListView(children:[section('Weekly meal schedule'),for(final m in data)item('${m['day']}','Breakfast: ${m['breakfast']}\nLunch: ${m['lunch']}\nDinner: ${m['dinner']}'),Padding(padding:const EdgeInsets.all(12),child:ElevatedButton(onPressed:()async{final d=await inputForm(c,'Set meal menu',['Day','Breakfast','Lunch','Dinner'],initial:{'Day':'Monday'});if(d!=null&&c.mounted)await apiAction(c,()=>widget.api('/meals',method:'PUT',body:{'day':d['Day'],'breakfast':d['Breakfast'],'lunch':d['Lunch'],'dinner':d['Dinner']}),refresh);},child:const Text('Set day menu')))]));
 void methods()=>panel('Bank and UPI details','/payment-methods',(c,data,refresh)=>ListView(children:[section('Owner payment settings'),item('UPI ID','${data['upi_id']}'),item('Bank','${data['bank_name']} • ${data['bank_account_masked']}'),if(widget.profile['role']=='owner')Padding(padding:const EdgeInsets.all(12),child:ElevatedButton(onPressed:()async{final d=await inputForm(c,'Owner payment details',['UPI ID','QR URL','Account holder','Bank name','Account number','IFSC']);if(d!=null&&c.mounted)await apiAction(c,()=>widget.api('/payment-methods',method:'PUT',body:{'upi_id':d['UPI ID'],'qr_image_url':d['QR URL'],'bank_holder':d['Account holder'],'bank_name':d['Bank name'],'bank_account':d['Account number'],'ifsc':d['IFSC']}),refresh);},child:const Text('Update payment details')))]));
 Widget dashboard()=>DataPanel(key:ValueKey('summary-$period'),title:'COME.in • Owner',api:widget.api,path:'/owner/rent-status?period=$period',builder:(c,d,refresh){
 final t=d['totals'];
 final outstanding=number(t['outstanding']);
 final billed=number(t['billed']);
 final collected=number(t['collected']);
 return ListView(padding:const EdgeInsets.all(17),children:[
   const BrandMark(size:37),const SizedBox(height:21),
   Text('Hello, ${widget.profile['name']}',style:const TextStyle(fontSize:25,fontWeight:FontWeight.w900,color:plum)),
   Text('${widget.profile['tenant']?['name']??'Your PG'} • $period',style:const TextStyle(color:muted)),
   const SizedBox(height:17),
   PlumHero(eyebrow:'Collected this month',amount:money(t['collected']),detail:'${billed==0?'0':(collected/billed*100).toStringAsFixed(0)}% collected • ${money(t['outstanding'])} remaining',footer:ClipRRect(borderRadius:BorderRadius.circular(10),child:LinearProgressIndicator(value:billed==0?0:(collected/billed).clamp(0,1),minHeight:8,color:blush,backgroundColor:Colors.white24))),
   const SizedBox(height:9),
   GridView.count(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),crossAxisCount:2,childAspectRatio:1.19,children:[
     SoftMetric(label:'Rent dues',value:money(outstanding),icon:Icons.hourglass_bottom_rounded,accent:const Color(0xFFD2806E),onTap:rent),
     SoftMetric(label:'Residents',value:'${d['residents'].length}',icon:Icons.people_alt_outlined,accent:plum,onTap:residents),
     SoftMetric(label:'Pending payments',value:'${t['pending_count']}',icon:Icons.pending_actions_outlined,accent:const Color(0xFFBC7C9B),onTap:payments),
     SoftMetric(label:'Partly paid',value:'${t['partial_count']}',icon:Icons.payments_outlined,accent:successGreen,onTap:rent),
   ]),
   SectionHeading('Quick manage',action:()=>setState(()=>tab=1)),
   ActionTile(title:'Residents & rooms',subtitle:'People, occupancy and beds',icon:Icons.meeting_room_outlined,onTap:rooms),
   ActionTile(title:'Rent verification',subtitle:'Review bank-confirmed submissions',icon:Icons.verified_user_outlined,onTap:payments),
   ActionTile(title:'Expenses & reports',subtitle:'View cash flow and occupancy analytics',icon:Icons.insights_rounded,onTap:()=>go('Reports',ReportsScreen(api:widget.api))),
   ActionTile(title:'Facility outages',subtitle:'Water, power and Wi-Fi updates',icon:Icons.water_drop_outlined,onTap:facilities),
   ActionTile(title:'Notifications',subtitle:'Notices, outages and messages',icon:Icons.notifications_active_outlined,onTap:()=>go('Notifications',NotificationScreen(api:widget.api))),
   ActionTile(title:'Community',subtitle:'Talk with your PG residents',icon:Icons.forum_outlined,onTap:()=>go('Community',CommunityScreen(api:widget.api,upload:widget.upload,profile:widget.profile))),
 ]);
 });
 Widget actions()=>ListView(padding:const EdgeInsets.all(12),children:[section('PG operations'),item('Residents','Add and edit residents',onTap:residents),item('Rent and invoices','Monthly paid, partial and pending lists',onTap:rent),item('Payment verification','Approve or reject submissions',onTap:payments),item('Rooms and beds','Room inventory and occupancy',onTap:rooms),item('Complaints','Track and resolve issues',onTap:complaints),item('Facility outages','Water, power and Wi-Fi status',onTap:facilities),item('Announcements','Publish PG notices',onTap:notices),item('Food and meals','Weekly food schedule',onTap:meals),item('UPI and bank settings','Manage payment destination',onTap:methods)]);
 Widget account()=>ListView(padding:const EdgeInsets.all(12),children:[const BrandMark(),section('Owner profile'),item('${widget.profile['name']}','Role: ${widget.profile['role']}'),item('${widget.profile['tenant']?['name']}','White-label PG'),Padding(padding:const EdgeInsets.all(12),child:ElevatedButton(onPressed:widget.logout,child:const Text('Log out')))]);
 @override Widget build(BuildContext c) => Scaffold(
 body:[dashboard(),actions(),ReportsScreen(api:widget.api),CommunityScreen(api:widget.api,upload:widget.upload,profile:widget.profile),account()][tab],
 bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(i)=>setState(()=>tab=i),destinations:const[
 NavigationDestination(icon:Icon(Icons.home_outlined),selectedIcon:Icon(Icons.home_rounded),label:'Home'),
 NavigationDestination(icon:Icon(Icons.grid_view_outlined),label:'Manage'),
 NavigationDestination(icon:Icon(Icons.insights_outlined),label:'Reports'),
 NavigationDestination(icon:Icon(Icons.forum_outlined),label:'Community'),
 NavigationDestination(icon:Icon(Icons.person_outline),label:'Account'),
 ]));
}

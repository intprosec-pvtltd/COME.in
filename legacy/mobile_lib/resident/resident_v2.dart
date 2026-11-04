import '../shared/notification_screen.dart';
import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/v2_ui.dart';
import '../community/community_screen.dart';
import '../core/app_theme.dart';
import '../core/comein_widgets.dart';

class ResidentV2 extends StatefulWidget{
 final ApiRequest api;final AttachmentUpload upload;final Map<String,dynamic> profile;final VoidCallback logout;
 const ResidentV2({super.key,required this.api,required this.upload,required this.profile,required this.logout});
 @override State<ResidentV2> createState()=>_ResidentV2State();
}
class _ResidentV2State extends State<ResidentV2>{
 int tab=0;
 void go(Widget child)=>Navigator.push(context,MaterialPageRoute(builder:(_)=>child));
 void panel(String title,String path,Widget Function(BuildContext,dynamic,Future<void> Function()) builder)=>go(DataPanel(title:title,api:widget.api,path:path,builder:builder));
 void rent()=>panel('My rent & dues','/invoices',(c,invoices,refresh)=>ListView(children:[section('Rent & payment history'),for(final i in invoices)Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${i['period']}',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),Text('Billed ${money(i['amount'])} • Paid ${money(i['paid'])}'),Text('Balance ${money(i['outstanding'])} • Due ${i['due_date']}'),if(number(i['outstanding'])>0)ElevatedButton(onPressed:()=>submitPayment(c,i,refresh),child:const Text('Submit payment reference'))]))),item('Owner UPI and bank details','Check the recipient before paying',onTap:paymentMethods),item('Submitted payments / receipts','View verification status',onTap:paymentHistory)]));
 void paymentMethods()=>panel('Owner payment account','/payment-methods',(c,d,_r)=>ListView(children:[section('Pay your PG owner directly'),item('UPI ID','${d['upi_id']}'),item('Bank name','${d['bank_name']}'),item('Account','${d['bank_account_masked']}'),item('IFSC','${d['ifsc']}'),item('QR image URL','${d['qr_image_url']}'),const Padding(padding:EdgeInsets.all(12),child:Text('Pay through your banking/UPI app. The owner must verify bank credit before the receipt becomes available.'))]));
 Future<void> submitPayment(BuildContext c,d,Future<void> Function() refresh)async{
 final form=await inputForm(c,'Submit bank/UPI reference',['Amount','Transaction reference'],initial:{'Amount':'${d['outstanding']}'});
 if(form==null||!c.mounted)return;
 final amount=double.tryParse(form['Amount']??'')??0;
 if(amount<=0||amount>number(d['outstanding'])){toast(c,'Enter an amount within the outstanding balance');return;}
 await apiAction(c,()=>widget.api('/payments',method:'POST',body:{'invoice_id':d['id'],'amount':amount,'reference':form['Transaction reference']}),refresh);
 }
 void paymentHistory()=>panel('Payment submissions','/payments',(c,data,refresh)=>ListView(children:[section('Owner verification'),for(final p in data)item('${money(p['amount'])} • ${p['status']}','Reference ${p['reference']}',onTap:p['status']=='approved'?()=>panel('Payment receipt','/receipts/${p['id']}',(ctx,d,_r)=>ListView(children:[section('Receipt ${d['receipt_number']}'),item('Amount ${money(d['amount'])}','${d['pg_name']} • ${d['resident']}\n${d['period']} • Ref ${d['reference']}')])):null)]));
 void tickets()=>panel('My complaints','/tickets',(c,data,refresh)=>ListView(children:[section('Maintenance tickets'),for(final t in data)item('${t['category']} • ${t['status']}','${t['description']}'),Padding(padding:const EdgeInsets.all(12),child:ElevatedButton(onPressed:()async{final d=await inputForm(c,'Raise complaint',['Category','Description'],initial:{'Category':'Plumbing'});if(d!=null&&c.mounted)await apiAction(c,()=>widget.api('/tickets',method:'POST',body:{'category':d['Category'],'description':d['Description']}),refresh);},child:const Text('Raise new complaint')))]));
 void notices()=>panel('PG notices','/notices',(c,data,_r)=>ListView(children:[section('Announcements'),for(final n in data)item('${n['title']}','${n['body']} • ${n['category']}')]));
 void facilities()=>panel('Facility status','/facilities',(c,data,_r)=>ListView(children:[section('Water • Power • Wi-Fi'),if(data.isEmpty)item('No facility notices','No incidents have been reported'),for(final f in data)item('${f['category']} • ${f['status']}','${f['title']}\n${f['details']}')]));
 void meals()=>panel('Today & weekly meals','/meals',(c,data,_r)=>ListView(children:[section('Food schedule'),if(data.isEmpty)item('No menu published','Ask your owner for meal details'),for(final m in data)item('${m['day']}','Breakfast: ${m['breakfast']}\nLunch: ${m['lunch']}\nDinner: ${m['dinner']}')]));
 Widget home()=>DataPanel(title:'COME.in • Resident',api:widget.api,path:'/invoices',builder:(c,records,refresh){
 final invoices=records as List;
 final total=invoices.fold<double>(0,(x,r)=>x+number(r['outstanding']));
 final nextDue=invoices.where((r)=>number(r['outstanding'])>0).map((r)=>'${r['due_date']}').toList();
 return ListView(padding:const EdgeInsets.all(17),children:[
 const BrandMark(size:37),const SizedBox(height:22),
 Text('Welcome, ${widget.profile['name']}',style:const TextStyle(color:plum,fontWeight:FontWeight.w900,fontSize:24)),
 Text('${widget.profile['tenant']?['name']??'Your PG'}  •  Room ${widget.profile['room']??'—'}',style:const TextStyle(color:muted)),
 const SizedBox(height:18),
 PlumHero(eyebrow:'Your rent balance',amount:money(total),detail:nextDue.isEmpty?'All caught up!':'Next due • ${nextDue.first}',footer:FilledButton.tonalIcon(onPressed:rent,icon:const Icon(Icons.payments_outlined),label:const Text('View & submit payment'))),
 const SizedBox(height:8),
 GridView.count(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),crossAxisCount:2,childAspectRatio:1.18,children:[
 SoftMetric(label:'Bills & receipts',value:'${invoices.length}',icon:Icons.receipt_long_outlined,accent:plum,onTap:rent),
 SoftMetric(label:'Room',value:'${widget.profile['room']??'—'}',icon:Icons.bed_outlined,accent:successGreen),
 ]),
 const SectionHeading('Your everyday living'),
 ActionTile(title:'Facility status',subtitle:'Water, electricity and Wi-Fi',icon:Icons.water_drop_outlined,onTap:facilities),
 ActionTile(title:'Announcements',subtitle:'Notices from your PG',icon:Icons.campaign_outlined,onTap:notices),
 ActionTile(title:'My complaints',subtitle:'Request maintenance and track updates',icon:Icons.handyman_outlined,onTap:tickets),
 ActionTile(title:'Notifications',subtitle:'Stay informed about PG updates',icon:Icons.notifications_active_outlined,onTap:()=>go(NotificationScreen(api:widget.api))),
 ActionTile(title:'Community',subtitle:'Connect with your PG neighbours',icon:Icons.forum_outlined,onTap:()=>go(CommunityScreen(api:widget.api,upload:widget.upload,profile:widget.profile))),
 ActionTile(title:'Food menu',subtitle:'Breakfast, lunch and dinner',icon:Icons.restaurant_outlined,onTap:meals),
 ]);
 });
 Widget services()=>ListView(children:[section('Resident services'),item('My rent and dues','Balance, payments and receipts',onTap:rent),item('Facility outages','Water, power and Wi-Fi',onTap:facilities),item('Notices','Announcements',onTap:notices),item('Complaints','Report problems',onTap:tickets),item('Food menu','View daily meals',onTap:meals)]);
 Widget profile()=>ListView(padding:const EdgeInsets.all(12),children:[const BrandMark(),section('My profile'),item('${widget.profile['name']}','Room ${widget.profile['room']}'),item('PG','${widget.profile['tenant']?['name']}'),Padding(padding:const EdgeInsets.all(12),child:ElevatedButton(onPressed:widget.logout,child:const Text('Log out')))]);
 @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('COME.in • Resident')),body:[home(),services(),CommunityScreen(api:widget.api,upload:widget.upload,profile:widget.profile),profile()][tab],bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(i)=>setState(()=>tab=i),destinations:const[NavigationDestination(icon:Icon(Icons.home_outlined),label:'Home'),NavigationDestination(icon:Icon(Icons.grid_view_outlined),label:'Services'),NavigationDestination(icon:Icon(Icons.forum_outlined),label:'Community'),NavigationDestination(icon:Icon(Icons.person_outline),label:'Profile')]));
}

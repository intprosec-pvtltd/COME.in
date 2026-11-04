import 'package:flutter/material.dart';
import 'controller.dart';
import '../core/design.dart';
import '../features/dashboard/dashboard.dart';
import '../features/management/management.dart';
import '../features/management/entity_form.dart';
import '../features/finance/finance.dart';
import '../features/operations/operations.dart';
import '../features/community/chat.dart';
import '../features/account/account.dart';
const ownerRoutes={
  'properties',
  'propertyDetail',
  'rooms',
  'roomDetail',
  'allocation',
  'residents',
  'residentDetail',
  'dues',
  'payments',
  'reports',
  'analytics',
  'expenses',
  'staff',
  'staffDetail',
  'booking',
  'joiningCode',
  'paymentMethodsEditor'
};
Widget pageFor(String route,
{
  int? id,
  Map<String,
  dynamic> args=const {
  }
})=>switch(route){
  'home'=>const Dashboard(),
  'tools'=>const FeatureMenu(),
  'properties'=>const PropertiesPage(),
  'propertyDetail'=>PropertyDetailPage(id:id??0),
  'rooms'=>const RoomsPage(),
  'roomDetail'=>RoomDetailPage(id:id!),
  'allocation'=>AllocationPage(roomId:id!),
  'residents'=>const ResidentsPage(),
  'residentDetail'=>ResidentDetailPage(id:id!),
  'staff'=>const StaffPage(),
  'staffDetail'=>StaffDetailPage(id:id!),
  'booking'=>const BookingsPage(),
  'entity'=>EntityForm(kind:args[
    'kind'
  ] as String,
  id:id,
  initial:args[
    'initial'
  ] as Map<String,
  dynamic>? ?? {
  }),
  'rent'||'dues'=>const RentPage(),
  'payments'=>const PaymentsPage(),
  'paymentDetail'=>PaymentDetailPage(id:id!),
  'submitPayment'=>SubmitPaymentPage(invoiceId:id!),
  'receipt'=>ReceiptPage(id:id!),
  'reports'||'analytics'=>const ReportsPage(),
  'expenses'=>const ExpensesPage(),
  'paymentMethods'=>const PaymentMethodsPage(),
  'complaints'=>const ComplaintsPage(),
  'complaintDetail'=>ComplaintDetailPage(id:id!),
  'newComplaint'=>const NewComplaintPage(),
  'facilities'=>const FacilitiesPage(),
  'announcements'=>const AnnouncementsPage(),
  'postDetail'=>NoticeDetailPage(id:id!),
  'meals'=>const MealsPage(),
  'notifications'=>const NotificationsPage(),
  'community'=>const ChatPage(),
  'groupInfo'=>const GroupInfoPage(),
  'account'=>const AccountPage(),
  'profileEditor'=>const ProfileEditorPage(),
  'password'=>const PasswordPage(),
  'appearance'=>const AppearancePage(),
  'notificationSettings'=>const NotificationPreferencesPage(),
  'accommodation'=>const AccommodationPage(),
  'joiningCode'=>const JoiningCodePage(),
  'support'=>const HelpPage(),
  'legal'=>const LegalPage(),
  _=>const HelpPage(),
};
Future<void> openPage(BuildContext context,
String route,
{
  int? id,
  Map<String,
  dynamic> args=const {
  }
}) async {
  final app=AppScope.of(context);
  if(ownerRoutes.contains(route)&&!app.owner){
    feedback(context,
    'Your account does not have access to that page.');
    return;
  } if(route=='entity'&&!app.owner){
    feedback(context,
    'Owner access is required.');
    return;
  } await Navigator.push<void>(context,
  MaterialPageRoute(builder:(_)=>pageFor(route,
  id:id,
  args:args)));
} Future<void> editEntity(BuildContext context,
String kind,
{
  int? id,
  Map<String,
  dynamic> initial=const {
  }
})=>openPage(context,
'entity',
id:id,
args:{
  'kind':kind,
  'initial':initial
});
class AppShell extends StatefulWidget {
  const AppShell({
    super.key
  });
  @override State<AppShell> createState()=>_AppShellState();
} class _AppShellState extends State<AppShell>{
  int tab=0;
  bool refreshing=false;
  @override Widget build(BuildContext context){
    final app=AppScope.of(context);
    final owner=app.owner;
    final staff=app.staff;
    final destinations=staff?[
      'home',
      'complaints',
      'account'
    ]:owner?[
      'home',
      'tools',
      'community',
      'reports',
      'account'
    ]:[
      'home',
      'tools',
      'community',
      'account'
    ];
    if(tab>=destinations.length)tab=0;
    final page=destinations[
      tab
    ];
    return Scaffold(body:Column(children:[
      if(refreshing)const LinearProgressIndicator(),
      Expanded(child:app.error!=null?Center(child:Column(mainAxisSize:MainAxisSize.min,
      children:[
        Text(app.error!),
        TextButton(onPressed:()=>perform(context,
        app.refresh),
        child:const Text('Retry'))
      ])):pageFor(page))
    ]),
    bottomNavigationBar:NavigationBar(selectedIndex:tab,
    onDestinationSelected:(i)async{
      setState(()=>tab=i);
      if(i==0&&!refreshing){
        setState(()=>refreshing=true);
        await perform(context,
        app.refresh);
        if(mounted)setState(()=>refreshing=false);
      }
    },
    destinations:[
      for(final route in destinations)NavigationDestination(icon:Icon(switch(route){
        'home'=>Icons.home_outlined,
        'tools'=>Icons.grid_view_outlined,
        'reports'=>Icons.bar_chart_outlined,
        'community'=>Icons.forum_outlined,
        'complaints'=>Icons.handyman_outlined,
        _=>Icons.person_outline
      }),
      label:switch(route){
        'home'=>'Home',
        'tools'=>owner?'Manage':'Explore',
        'reports'=>'Reports',
        'community'=>'Community',
        'complaints'=>'Tasks',
        _=>owner?'Account':'Profile'
      })
    ]));
  }
}

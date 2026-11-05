import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:pg_resident/main.dart';
import 'package:pg_resident/app/controller.dart';
import 'package:pg_resident/core/api_client.dart';
import 'package:pg_resident/features/management/entity_form.dart';
import 'package:pg_resident/features/finance/finance.dart';
class FakeApi extends ApiClient {
  Map<String,
  dynamic> fixture={
  };
  @override Future<dynamic> request(String path,
  {
    String method='GET',
    Map<String,
    dynamic>? body
  })async {
    if(path=='/login')return {
      'token':'test'
    };
    if(path=='/v3/state')return fixture;
    return {
      'ok':true
    };
  }
} Map<String,
dynamic> fixture(String role)=>{
  'profile':{
    'id':1,
    'name':'Test Person',
    'email':'test@pg.local',
    'role':role,
    'room':'101',
    'tenant':{
      'name':'Test PG'
    },
    'preferences':{
    }
  },
  'properties':[
    {
      'id':0,
      'name':'Test PG',
      'city':'Bengaluru',
      'address':'HSR Layout',
      'upi':'test@upi'
    }
  ],
  'residents':role=='owner'?[
    {
      'id':2,
      'name':'Resident One',
      'room':'101',
      'email':'resident@pg.local',
      'bed':1
    }
  ]:[
  ],
  'rooms':role=='owner'?[
    {
      'id':1,
      'name':'101',
      'beds':2,
      'floor':'Ground'
    }
  ]:[
  ],
  'invoices':[
    {
      'id':1,
      'resident_id':2,
      'period':'2026-11',
      'amount':'6500',
      'paid':'0',
      'outstanding':'6500',
      'due_date':'2026-11-05'
    }
  ],
  'expenses':[
  ],
  'complaints':[
  ],
  'notices':[
  ],
  'facilities':[
  ],
  'staff':[
  ],
  'bookings':[
  ],
  'notifications':[
  ],
  'messages':[
  ],
  'members':[
  ],
  'payments':[
  ],
  'meals':[
  ],
};
AppController controller(String? role){
  final api=FakeApi();
  final app=AppController(client:api)..restoring=false..onboardingSeen=true;
  if(role!=null){
    api.fixture=fixture(role);
    app.data=api.fixture;
  }app.period='2026-11';
  return app;
} void main(){
  testWidgets('Sign-in exposes validation and recovery navigation',
  (tester)async{
    final app=controller(null);
    await tester.pumpWidget(PGApp(controller:app));
    expect(find.text('Welcome back!'),
    findsOneWidget);
    await tester.ensureVisible(find.text('Sign in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your email or phone'),
    findsOneWidget);
    expect(find.text('Enter your password'),
    findsOneWidget);
    await tester.ensureVisible(find.text('Forgot password?'));
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(find.text('Reset password'),
    findsOneWidget);
  });
  testWidgets('Sign-in stays visible when Android keyboard opens',
  (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetViewInsets();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(PGApp(controller:controller(null)));
    // Simulate the phone keyboard taking up the lower screen.
    tester.view.viewInsets = const FakeViewPadding(bottom: 340);
    await tester.pumpAndSettle();
    expect(find.text('Welcome back!'), findsOneWidget);
    expect(find.text('Sign in to COME.in'), findsNothing);
    expect(find.byType(TextFormField), findsNWidgets(2));
    // The password field must be reachable by scrolling the form viewport.
    final password = find.byType(TextFormField).last;
    await tester.ensureVisible(password);
    await tester.pumpAndSettle();
    final bottom = tester.getBottomLeft(password).dy + tester.getSize(password).height;
    expect(bottom, lessThanOrEqualTo(844 - 340));
  });
  testWidgets('Owner navigation exposes complete management directory',
  (tester)async{
    await tester.pumpWidget(PGApp(controller:controller('owner')));
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();
    expect(find.text('Manage your PG'),
    findsOneWidget);
    expect(find.text('Properties'),
    findsOneWidget);
    await tester.tap(find.text('Properties'));
    await tester.pumpAndSettle();
    expect(find.text('Your properties'),
    findsOneWidget);
  });
  testWidgets('Resident navigation includes accommodation and rent',
  (tester)async{
    await tester.pumpWidget(PGApp(controller:controller('resident')));
    await tester.tap(find.text('Explore'));
    await tester.pumpAndSettle();
    expect(find.text('My accommodation'),
    findsOneWidget);
    expect(find.text('My rent & receipts'),
    findsOneWidget);
  });
  test('All editable design entities have field schemas',
  (){
    for(final kind in [
      'property',
      'room',
      'resident',
      'staff',
      'expense',
      'booking',
      'facility',
      'notice',
      'meal'
    ]){
      expect(fieldsFor(kind),
      isNotEmpty,
      reason:kind);
    }
  });
  test('Invoice status distinguishes paid, partial and overdue',
  (){
    expect(invoiceStatus({
      'outstanding':'0',
      'paid':'6500'
    }),
    'Paid');
    expect(invoiceStatus({
      'outstanding':'100',
      'paid':'6000'
    }),
    'Partial');
    expect(invoiceStatus({
      'outstanding':'100',
      'paid':'0',
      'due_date':'2020-01-01'
    }),
    'Overdue');
  });
}



import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pg_resident/app/controller.dart';
import 'package:pg_resident/core/api_client.dart';
import 'package:pg_resident/features/account/app_feedback.dart';

class FeedbackApi extends ApiClient {
  Map<String, dynamic>? submitted;

  @override
  Future<dynamic> request(String path, {
    String method = 'GET', Map<String, dynamic>? body,
  }) async {
    expect(path, '/v3/app-feedback');
    expect(method, 'PUT');
    submitted = body;
    return {'saved': true};
  }
}

void main() {
  testWidgets('Feedback dialog can close and sends a private rating only on submit', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = FeedbackApi();
    final app = AppController(client: api)..data = {'profile': {'id': 1, 'role': 'resident'}};
    await tester.pumpWidget(AppScope(
      controller: app,
      child: MaterialApp(home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () => showAppFeedback(context), child: const Text('Rate'),
      )))),
    ));
    await tester.tap(find.text('Rate'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close review'));
    await tester.pumpAndSettle();
    expect(api.submitted, isNull);
    await tester.tap(find.text('Rate'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('4 of 5 stars'));
    await tester.pump();
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(api.submitted, {'rating': 4, 'comment': ''});
    expect((await SharedPreferences.getInstance()).getBool('app_feedback.v1..1.done'), isTrue);
  });

  testWidgets('A dismissed timed prompt records a one-day retry', (tester) async {
    SharedPreferences.setMockInitialValues({'app_feedback.v1.5.1.seconds': 600});
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final app = AppController(client: FeedbackApi())..data = {'profile': {'id': 1, 'role': 'owner'}};
    await tester.pumpWidget(AppScope(
      controller: app,
      child: const MaterialApp(home: FeedbackReminder(
        account: '5.1', child: Scaffold(body: Text('Home')),
      )),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    final next = (await SharedPreferences.getInstance()).getInt('app_feedback.v1.5.1.next');
    expect(next, isNotNull);
    expect(DateTime.fromMillisecondsSinceEpoch(next!).difference(DateTime.now()).inHours, greaterThanOrEqualTo(23));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

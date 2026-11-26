import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pg_resident/app/controller.dart';
import 'package:pg_resident/core/api_client.dart';
import 'package:pg_resident/features/management/management.dart';

class ResidentApi extends ApiClient {
  ResidentApi({this.eligible = true});

  final bool eligible;
  final data = <String, dynamic>{
    'profile': {'role': 'owner'},
    'residents': [
      {'id': 7, 'name': 'QA Resident', 'email': 'qa@example.test', 'room': '101'},
    ],
  };
  int deletes = 0;

  @override
  Future<dynamic> request(String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    if (path == '/v3/residents/7/deletion-review') return {'eligible': eligible};
    if (path == '/v3/residents/7' && method == 'DELETE') {
      expect(body, {'confirm_email': 'qa@example.test'});
      deletes++;
      data['residents'] = [];
      return {'deleted': true};
    }
    if (path == '/v3/state') return data;
    return <String, dynamic>{};
  }
}

Future<void> showResidents(WidgetTester tester, ResidentApi api) async {
  final controller = AppController(client: api)..data = Map.of(api.data);
  await tester.pumpWidget(
    AppScope(controller: controller, child: const MaterialApp(home: ResidentsPage())),
  );
  await tester.tap(find.byTooltip('Actions for QA Resident'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Delete resident permanently'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Owner confirms the email before permanent deletion', (tester) async {
    final api = ResidentApi();
    await showResidents(tester, api);
    final confirm = find.widgetWithText(TextButton, 'Delete permanently');
    final email = find.widgetWithText(TextField, 'Resident email');
    expect(tester.widget<TextButton>(confirm).onPressed, isNull);
    await tester.enterText(email, 'wrong@example.test');
    await tester.pump();
    expect(tester.widget<TextButton>(confirm).onPressed, isNull);
    await tester.enterText(email, 'qa@example.test');
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(api.deletes, 1);
    expect(find.text('No matching residents.'), findsOneWidget);
  });

  testWidgets('Linked records stop deletion before confirmation', (tester) async {
    final api = ResidentApi(eligible: false);
    await showResidents(tester, api);
    expect(find.text('Linked records prevent this resident from being deleted.'), findsOneWidget);
    expect(find.text('Permanently delete resident?'), findsNothing);
    expect(api.deletes, 0);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pg_resident/app/controller.dart';
import 'package:pg_resident/features/management/entity_form.dart';

void main() {
  testWidgets('Resident edit lists rooms in the selected property with available beds', (tester) async {
    final app = AppController()..data = {
      'profile': {'role': 'owner'},
      'properties': [
        {'id': 0, 'name': 'QA primary'},
        {'id': 9, 'name': 'QA annex'},
      ],
      'rooms': [
        {'id': 1, 'name': 'Available 101', 'property_id': 0, 'beds': 2},
        {'id': 2, 'name': 'Full 102', 'property_id': 0, 'beds': 1},
        {'id': 3, 'name': 'Annex 201', 'property_id': 9, 'beds': 2},
      ],
      'residents': [
        {'id': 2, 'property_id': 0, 'room': 'Full 102', 'bed': 1},
        {'id': 3, 'property_id': 0, 'room': 'Available 101', 'bed': 1},
      ],
    };
    await tester.pumpWidget(AppScope(
      controller: app,
      child: const MaterialApp(home: EntityForm(
        kind: 'resident', id: 1,
        initial: {'name': 'Test resident', 'email': 'qa@example.test', 'room': '', 'bed': 0},
      )),
    ));
    final room = find.byKey(const ValueKey('room-0'));
    await tester.ensureVisible(room);
    await tester.tap(room);
    await tester.pumpAndSettle();
    expect(find.text('Available 101'), findsOneWidget);
    expect(find.text('Full 102'), findsNothing);
    expect(find.text('Annex 201'), findsNothing);
    await tester.tap(find.text('Available 101'));
    await tester.pumpAndSettle();
    final bed = find.byKey(const ValueKey('bed-0-Available 101'));
    await tester.ensureVisible(bed);
    await tester.tap(bed);
    await tester.pumpAndSettle();
    expect(find.text('Bed 2'), findsOneWidget);
    expect(find.text('Bed 1'), findsNothing);
  });
}

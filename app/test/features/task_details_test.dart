import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

/// Creates list [listName] with one task [title] and opens its details.
Future<void> openTask(
  WidgetTester tester, {
  String listName = 'L',
  String title = 'Trip',
}) async {
  await createList(tester, listName);
  await submitText(tester, find.byKey(const Key('quick-add')), title);
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('task-details')), findsOneWidget);
}

Finder inTile(String key, Finder finder) =>
    find.descendant(of: find.byKey(Key(key)), matching: finder);

void main() {
  testWidgets('due date can be set and cleared (FR-3.4)', (tester) async {
    final h = await pumpApp(tester);
    await openTask(tester);

    await tester.tap(find.byKey(const Key('due-tile')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Add due date'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('smart-planned')));
    await tester.pumpAndSettle();
    expect(find.text('Trip'), findsWidgets);

    await tester.tap(find.text('Trip').last);
    await tester.pumpAndSettle();
    await tester.tap(inTile('due-tile', find.byIcon(Icons.close)));
    await tester.pumpAndSettle();
    expect(find.text('Add due date'), findsOneWidget);

    await disposeApp(tester, h);
  });

  testWidgets('reminder picks a date and a time, and can be cleared (FR-3.5)',
      (tester) async {
    final h = await pumpApp(tester);
    await openTask(tester);

    await tester.tap(find.byKey(const Key('reminder-tile')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK')); // date
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK')); // time
    await tester.pumpAndSettle();
    expect(find.text('Remind me'), findsNothing);

    await tester.tap(inTile('reminder-tile', find.byIcon(Icons.close)));
    await tester.pumpAndSettle();
    expect(find.text('Remind me'), findsOneWidget);

    await disposeApp(tester, h);
  });

  testWidgets('cancelling the reminder date picker changes nothing',
      (tester) async {
    final h = await pumpApp(tester);
    await openTask(tester);

    await tester.tap(find.byKey(const Key('reminder-tile')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Remind me'), findsOneWidget);

    await disposeApp(tester, h);
  });

  testWidgets('repeat rule: daily every 2 days, weekly on chosen days (FR-3.6)',
      (tester) async {
    final h = await pumpApp(tester);
    await openTask(tester);

    await tester.tap(find.byKey(const Key('repeat-tile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('repeat-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Daily').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add).last);
    await tester.pump();
    expect(find.byKey(const Key('repeat-interval')), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.add).last);
    await tester.pump();
    await tester.tap(find.byKey(const Key('repeat-save')));
    await tester.pumpAndSettle();
    expect(inTile('repeat-tile', find.text('Daily')), findsOneWidget);

    await tester.tap(find.byKey(const Key('repeat-tile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('repeat-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weekly').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilterChip).first);
    await tester.pump();
    await tester.tap(find.byKey(const Key('repeat-save')));
    await tester.pumpAndSettle();
    expect(inTile('repeat-tile', find.text('Weekly')), findsOneWidget);

    await tester.tap(find.byKey(const Key('repeat-tile')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(inTile('repeat-tile', find.text('Weekly')), findsOneWidget);

    await disposeApp(tester, h);
  });

  testWidgets('a task can be moved to another list (FR-3.10)', (tester) async {
    final h = await pumpApp(tester);
    await createList(tester, 'Home');
    await openTask(tester, listName: 'Work');

    await tester.tap(find.byKey(const Key('move-list-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Home').first);
    await tester.pumpAndSettle();
    expect(find.text('Trip'), findsWidgets);

    await disposeApp(tester, h);
  });

  testWidgets('deleting a task can be undone (FR-3.12)', (tester) async {
    final h = await pumpApp(tester);
    await openTask(tester);

    await tester.tap(find.byKey(const Key('delete-task')));
    await tester.pumpAndSettle();
    expect(find.text('Task deleted'), findsOneWidget);
    expect(find.text('Trip'), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Trip'), findsOneWidget);

    await disposeApp(tester, h);
  });

  testWidgets('steps can be finished and deleted (FR-3.7)', (tester) async {
    final h = await pumpApp(tester);
    await openTask(tester);
    await submitText(tester, find.byKey(const Key('add-step')), 'Pack');
    expect(find.text('0 of 1'), findsOneWidget);

    final step = find.ancestor(
      of: find.text('Pack'),
      matching: find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('step-'),
      ),
    );
    await tester
        .tap(find.descendant(of: step, matching: find.byType(Checkbox)));
    await tester.pumpAndSettle();
    expect(find.text('1 of 1'), findsOneWidget);

    await tester
        .tap(find.descendant(of: step, matching: find.byIcon(Icons.close)));
    await tester.pumpAndSettle();
    expect(find.text('Pack'), findsNothing);

    await disposeApp(tester, h);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_todo/core/hlc.dart';
import 'package:future_todo/core/pref_keys.dart';
import 'package:future_todo/data/db/database.dart';
import 'package:future_todo/data/remote/remote_api.dart';
import 'package:future_todo/data/repository.dart';

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

  testWidgets('title, completion and importance are edited in the panel',
      (tester) async {
    final h = await pumpApp(tester);
    await openTask(tester);
    Future<Task> task() async =>
        (await tester.runAsync(() => h.db.select(h.db.tasks).getSingle()))!;

    await submitText(
      tester,
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('details-title-'),
      ),
      'Holiday',
    );
    expect((await task()).title, 'Holiday');

    await tester.tap(inTile('task-details', find.byIcon(Icons.star_border)));
    await tester.pumpAndSettle();
    expect((await task()).isImportant, isTrue);
    expect(inTile('task-details', find.byIcon(Icons.star)), findsOneWidget);

    await tester.tap(inTile('task-details', find.byType(Checkbox)).first);
    await tester.pumpAndSettle();
    expect((await task()).isCompleted, isTrue);

    await disposeApp(tester, h);
  });

  testWidgets('on a narrow screen deleting a task closes its details page',
      (tester) async {
    final h = await pumpApp(tester, size: const Size(900, 900));
    await openTask(tester);
    expect(find.byType(BackButton), findsOneWidget);

    await tester.tap(find.byKey(const Key('delete-task')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-details')), findsNothing);
    expect(find.text('Task deleted'), findsOneWidget);

    await disposeApp(tester, h);
  });

  testWidgets('tasks in a list shared with me can be assigned (FR-5.4)',
      (tester) async {
    final h = await pumpApp(
      tester,
      prefs: {
        PrefKeys.accessToken: 'a',
        PrefKeys.refreshToken: 'r',
        PrefKeys.userId: 'user-1',
        PrefKeys.userEmail: 'a@b.co',
      },
    );
    final listId = (await tester.runAsync(
      () => TodoRepository(h.db, HlcClock('other'))
          .createList('Shared', ownerId: 'user-9'),
    ))!;
    h.remote.members[listId] = const [
      ListMember(userId: 'user-9', name: 'Owner', isOwner: true),
      ListMember(userId: 'user-2', name: 'Bob', isOwner: false),
    ];
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shared'));
    await tester.pumpAndSettle();
    await submitText(tester, find.byKey(const Key('quick-add')), 'Trip');
    await tester.tap(find.text('Trip'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('assignee-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bob').last);
    await tester.pumpAndSettle();
    final task =
        (await tester.runAsync(() => h.db.select(h.db.tasks).getSingle()))!;
    expect(task.assigneeId, 'user-2');

    await disposeApp(tester, h);
  });

  testWidgets('tasks in my own unshared lists have no assignee picker',
      (tester) async {
    final h = await pumpApp(tester);
    await openTask(tester);
    expect(find.byKey(const Key('assignee-dropdown')), findsNothing);

    await disposeApp(tester, h);
  });
}

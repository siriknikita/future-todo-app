import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_todo/data/db/database.dart';

import '../helpers/pump_app.dart';

/// Opens the "more" menu inside the sidebar item with [key] and picks
/// [item].
Future<void> pickFromMenu(WidgetTester tester, Key key, String item) async {
  await tester.tap(
    find
        .descendant(of: find.byKey(key), matching: find.byIcon(Icons.more_vert))
        .first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

Future<void> answerPrompt(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('prompt-field')), text);
  await tester.tap(find.byKey(const Key('prompt-ok')));
  await tester.pumpAndSettle();
}

Future<TaskList> onlyList(WidgetTester tester, AppHarness h) async =>
    (await tester.runAsync(() => h.db.select(h.db.taskLists).getSingle()))!;

void main() {
  testWidgets(
      'a list can be renamed, given an icon and moved between groups '
      '(FR-2.1, FR-2.2, FR-2.3)', (tester) async {
    final h = await pumpApp(tester);
    await createList(tester, 'Errands');
    await tester.tap(find.byKey(const Key('new-group')));
    await tester.pumpAndSettle();
    await answerPrompt(tester, 'Home');
    final list = await onlyList(tester, h);
    final listKey = ValueKey('list-${list.id}');

    await pickFromMenu(tester, listKey, 'Rename');
    await answerPrompt(tester, 'Shopping');
    expect((await onlyList(tester, h)).name, 'Shopping');

    await pickFromMenu(tester, listKey, 'Set emoji icon');
    await answerPrompt(tester, '🛒');
    expect((await onlyList(tester, h)).icon, '🛒');
    expect(find.text('🛒'), findsOneWidget);

    await pickFromMenu(tester, listKey, 'Move to group');
    await tester.tap(find.text('Home').last);
    await tester.pumpAndSettle();
    final group = (await tester
        .runAsync(() => h.db.select(h.db.listGroups).getSingle()))!;
    expect((await onlyList(tester, h)).groupId, group.id);
    expect(
      find.descendant(
        of: find.byKey(ValueKey('group-${group.id}')),
        matching: find.text('Shopping'),
      ),
      findsOneWidget,
    );

    await pickFromMenu(tester, listKey, 'Move to group');
    await tester.tap(find.text('No group'));
    await tester.pumpAndSettle();
    expect((await onlyList(tester, h)).groupId, isNull);

    await disposeApp(tester, h);
  });

  testWidgets('a group can be renamed and dissolved (FR-2.3)', (tester) async {
    final h = await pumpApp(tester);
    await tester.tap(find.byKey(const Key('new-group')));
    await tester.pumpAndSettle();
    await answerPrompt(tester, 'Home');
    final group = (await tester
        .runAsync(() => h.db.select(h.db.listGroups).getSingle()))!;
    final groupKey = ValueKey('group-${group.id}');

    await pickFromMenu(tester, groupKey, 'Rename');
    await answerPrompt(tester, 'House');
    expect(find.text('House'), findsOneWidget);

    await pickFromMenu(tester, groupKey, 'Ungroup');
    expect(find.byKey(groupKey), findsNothing);
    final groups =
        (await tester.runAsync(() => h.db.select(h.db.listGroups).get()))!;
    expect(groups.single.deleted, isTrue);
    expect(groups.single.name, 'House');

    await disposeApp(tester, h);
  });

  testWidgets('deleting the open list switches back to My Day', (tester) async {
    final h = await pumpApp(tester);
    await createList(tester, 'Temp');
    final list = await onlyList(tester, h);
    final listKey = ValueKey('list-${list.id}');
    expect(tester.widget<ListTile>(find.byKey(listKey)).selected, isTrue);

    await pickFromMenu(tester, listKey, 'Delete');
    await tester.tap(find.byKey(const Key('confirm-delete-list')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('smart-myDay')))
          .selected,
      isTrue,
    );

    await disposeApp(tester, h);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('create a list, add a task, complete it (FR-2.1, 3.1, 3.2)',
      (tester) async {
    final h = await pumpApp(tester);

    await createList(tester, 'Work');
    expect(find.byKey(const Key('area-title')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('area-title'))).data,
      'Work',
    );

    await submitText(tester, find.byKey(const Key('quick-add')), 'Buy milk');
    expect(find.text('Buy milk'), findsOneWidget);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('Completed (1)'), findsOneWidget);

    await disposeApp(tester, h);
  });

  testWidgets('hide completed tasks (FR-3.14)', (tester) async {
    final h = await pumpApp(tester);
    await createList(tester, 'Home');
    await submitText(tester, find.byKey(const Key('quick-add')), 'Sweep');
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('Sweep'), findsOneWidget);

    await tester.tap(find.byKey(const Key('toggle-completed')));
    await tester.pumpAndSettle();
    expect(find.text('Sweep'), findsNothing);

    await tester.tap(find.byKey(const Key('toggle-completed')));
    await tester.pumpAndSettle();
    expect(find.text('Sweep'), findsOneWidget);

    await disposeApp(tester, h);
  });

  testWidgets('quick add in My Day creates a default list and shows the task',
      (tester) async {
    final h = await pumpApp(tester);
    await submitText(tester, find.byKey(const Key('quick-add')), 'Plan day');
    expect(find.text('Plan day'), findsOneWidget);
    expect(find.text('Tasks'), findsWidgets); // default list in the sidebar

    await tester.tap(find.byKey(const ValueKey('smart-all')));
    await tester.pumpAndSettle();
    expect(find.text('Plan day'), findsOneWidget);

    await disposeApp(tester, h);
  });

  testWidgets('important tasks appear in the Important smart list (FR-4.3)',
      (tester) async {
    final h = await pumpApp(tester);
    await createList(tester, 'L');
    await submitText(tester, find.byKey(const Key('quick-add')), 'Star me');
    await submitText(tester, find.byKey(const Key('quick-add')), 'Plain');

    // The sidebar's Important entry uses the same icon, so scope to the tile.
    final starMeTile = find.ancestor(
      of: find.text('Star me'),
      matching: find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            RegExp(r'^task-[0-9a-f-]{36}$')
                .hasMatch((w.key! as ValueKey<String>).value),
      ),
    );
    await tester.tap(
      find.descendant(of: starMeTile, matching: find.byIcon(Icons.star_border)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('smart-important')));
    await tester.pumpAndSettle();
    expect(find.text('Star me'), findsOneWidget);
    expect(find.text('Plain'), findsNothing);

    await disposeApp(tester, h);
  });

  testWidgets('details panel: steps, My Day and note (FR-3.7, 3.8, 4.1)',
      (tester) async {
    final h = await pumpApp(tester);
    await createList(tester, 'L');
    await submitText(tester, find.byKey(const Key('quick-add')), 'Trip');

    await tester.tap(find.text('Trip'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-details')), findsOneWidget);

    await submitText(tester, find.byKey(const Key('add-step')), 'Book hotel');
    expect(find.text('Book hotel'), findsOneWidget);
    expect(find.text('0 of 1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('my-day-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('smart-myDay')));
    await tester.pumpAndSettle();
    expect(find.text('Trip'), findsWidgets);

    await disposeApp(tester, h);
  });

  testWidgets('search finds tasks by title and step (FR-7.1, 7.2)',
      (tester) async {
    final h = await pumpApp(tester);
    await createList(tester, 'L');
    await submitText(tester, find.byKey(const Key('quick-add')), 'Alpha');
    await submitText(tester, find.byKey(const Key('quick-add')), 'Beta');

    await tester.enterText(find.byKey(const Key('search-field')), 'alp');
    await tester.pumpAndSettle();
    expect(find.text('Search results'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);

    await tester.enterText(find.byKey(const Key('search-field')), '');
    await tester.pumpAndSettle();
    expect(find.text('Beta'), findsOneWidget);

    await disposeApp(tester, h);
  });

  testWidgets('delete a list asks for confirmation (FR-2.1)', (tester) async {
    final h = await pumpApp(tester);
    await createList(tester, 'Temp');
    expect(find.text('Temp'), findsWidgets);

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete-list')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('new-list')), findsOneWidget);
    expect(find.text('Temp'), findsNothing);

    await disposeApp(tester, h);
  });
}

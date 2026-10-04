import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('shows sidebar with smart lists, task area and details hint',
      (tester) async {
    final h = await pumpApp(tester);

    expect(find.text('My Day'), findsWidgets);
    expect(find.text('Important'), findsOneWidget);
    expect(find.text('Planned'), findsOneWidget);
    expect(find.text('Assigned to me'), findsOneWidget);
    expect(find.byKey(const Key('quick-add')), findsOneWidget);
    expect(find.text('Select a task to see its details'), findsOneWidget);

    await disposeApp(tester, h);
  });

  testWidgets('language can be switched to Ukrainian (FR-9.2)', (tester) async {
    final h = await pumpApp(tester);

    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Українська'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Закрити')); // dialog is already localized
    await tester.pumpAndSettle();

    expect(find.text('Мій день'), findsWidgets);
    expect(find.text('Заплановане'), findsOneWidget);

    await disposeApp(tester, h);
  });

  testWidgets('theme can be switched to dark (FR-9.1)', (tester) async {
    final h = await pumpApp(tester);
    MaterialApp app() => tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app().themeMode, ThemeMode.system);

    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(app().themeMode, ThemeMode.dark);

    await disposeApp(tester, h);
  });

  testWidgets('saved language preference is applied at start', (tester) async {
    final h = await pumpApp(tester, prefs: {'language': 'uk'});
    expect(find.text('Важливе'), findsOneWidget);
    await disposeApp(tester, h);
  });

  testWidgets('narrow screens use a drawer', (tester) async {
    final h = await pumpApp(tester, size: const Size(500, 900));
    expect(find.byType(Drawer), findsNothing);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('Important'), findsOneWidget);
    await disposeApp(tester, h);
  });

  testWidgets('sync indicator shows local-only mode for guests (FR-8.4)',
      (tester) async {
    final h = await pumpApp(tester);
    expect(find.byKey(const Key('sync-guest')), findsOneWidget);
    await disposeApp(tester, h);
  });
}

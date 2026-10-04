import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_todo/app.dart';
import 'package:future_todo/main.dart' show openAppDatabase;
import 'package:future_todo/providers.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// End-to-end test on the real stack of the client: real Drift database
/// (SQLite WebAssembly in the browser), real UI, no mocks. The user works as
/// a guest, so no backend is needed.
///
/// Run on web (needs chromedriver):
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/app_test.dart -d chrome
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> start(WidgetTester tester, String dbName) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(openAppDatabase(name: dbName)),
        ],
        child: const FutureTodoApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('create a list, add a task, mark it done; data survives restart',
      (tester) async {
    final dbName = 'e2e_${DateTime.now().millisecondsSinceEpoch}';
    await start(tester, dbName);

    // Create a list.
    await tester.tap(find.byKey(const Key('new-list')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('prompt-field')), 'Groceries');
    await tester.tap(find.byKey(const Key('prompt-ok')));
    await tester.pumpAndSettle();
    expect(find.text('Groceries'), findsWidgets);

    // Add a task and see it in the list.
    await tester.enterText(find.byKey(const Key('quick-add')), 'Buy milk');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Buy milk'), findsOneWidget);

    // Mark it done.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('Completed (1)'), findsOneWidget);

    // Restart the app on the same database: the task is still there.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await start(tester, dbName);
    await tester.tap(find.byKey(const ValueKey('smart-all')));
    await tester.pumpAndSettle();
    expect(find.text('Buy milk'), findsOneWidget);
  });
}

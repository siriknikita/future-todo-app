import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_todo/app.dart';
import 'package:future_todo/data/db/database.dart';
import 'package:future_todo/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_remote.dart';

class AppHarness {
  AppHarness(this.db, this.remote);

  final AppDatabase db;
  final FakeRemoteApi remote;
}

/// Starts the whole app on an in-memory database and a fake backend.
Future<AppHarness> pumpApp(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  Size size = const Size(1400, 900),
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(prefs);
  final sharedPrefs = await SharedPreferences.getInstance();
  final db = AppDatabase(NativeDatabase.memory());
  final remote = FakeRemoteApi();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(sharedPrefs),
        appDatabaseProvider.overrideWithValue(db),
        remoteApiProvider.overrideWithValue(remote),
      ],
      child: const FutureTodoApp(),
    ),
  );
  await tester.pumpAndSettle();
  return AppHarness(db, remote);
}

/// Unmounts the app (cancels timers and streams) and closes the database.
Future<void> disposeApp(WidgetTester tester, AppHarness harness) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
  await harness.db.close();
}

Future<void> submitText(WidgetTester tester, Finder field, String text) async {
  await tester.enterText(field, text);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

/// Creates a list through the sidebar dialog.
Future<void> createList(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(const Key('new-list')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('prompt-field')), name);
  await tester.tap(find.byKey(const Key('prompt-ok')));
  await tester.pumpAndSettle();
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_todo/app.dart';
import 'package:future_todo/data/db/database.dart';
import 'package:future_todo/features/auth/auth_pages.dart';
import 'package:future_todo/l10n/app_localizations.dart';
import 'package:future_todo/main.dart' show openAppDatabase;
import 'package:future_todo/providers.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Level L5 of the "Pentagon" testing model: an end-to-end business scenario
/// from the user's point of view against a deployed environment (backend,
/// PostgreSQL and Mailpit started from the pipeline's Docker images).
///
/// Unlike `app_test.dart` (guest mode, no server), nothing here is local:
/// the account is registered through the UI, the confirmation link comes from
/// a real email, and the task travels phone -> server -> laptop through sync.
///
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/full_stack_test.dart \
///     -d web-server --web-port=8082 --browser-name=chrome --headless \
///     --dart-define=API_BASE_URL=http://localhost:8080 \
///     --dart-define=MAILPIT_URL=http://localhost:8025
const _mailpitUrl = String.fromEnvironment(
  'MAILPIT_URL',
  defaultValue: 'http://localhost:8025',
);

/// Limit for one HTTP call, and for anything the test waits to "eventually"
/// happen (an email arriving, sync delivering a change, a widget appearing).
const _httpTimeout = Duration(seconds: 10);
const _eventually = Duration(seconds: 30);

/// GET [uri] and decode the JSON body; any status but 200 fails the test.
Future<dynamic> _getJson(Uri uri, [Map<String, String>? headers]) async {
  final response = await http.get(uri, headers: headers).timeout(_httpTimeout);
  expect(response.statusCode, 200, reason: '$uri: ${response.body}');
  return jsonDecode(response.body);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final stamp = DateTime.now().millisecondsSinceEpoch;
  final email = 'l5-$stamp@e2e.test';
  const password = 'e2e-secret-password';
  final listName = 'Pre-prod list $stamp';
  const taskTitle = 'Buy milk on the phone';

  // Steps of the scenario; the driver saves them to
  // build/integration_response_data.json as a log of the run.
  final steps = <String>[];
  void step(String message) {
    steps.add('${DateTime.now().toIso8601String()} $message');
    binding.reportData = {'steps': steps};
    debugPrint('[L5] $message');
  }

  /// pumpAndSettle with a short limit: a signed-in app keeps timers and a
  /// WebSocket running, so never wait the default ten minutes.
  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 15),
      );

  AppDatabase? database;

  /// Unmounts the running app (stops its sync timer and WebSocket) and closes
  /// its database, like switching the device off.
  Future<void> stopDevice(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await database?.close();
    database = null;
  }

  /// Starts the app as a fresh device: own database, no saved session.
  Future<void> startDevice(WidgetTester tester, String device) async {
    await stopDevice(tester);
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    database = openAppDatabase(name: 'l5_${device}_$stamp');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(database!),
        ],
        child: const FutureTodoApp(),
      ),
    );
    await settle(tester);
  }

  /// Network calls and Drift's Web Worker finish in real time, outside the
  /// fake clock, so keep pumping until [finder] shows up.
  Future<void> pumpUntilFound(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = _eventually,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    }
    expect(finder, findsWidgets, reason: 'timed out waiting for $finder');
  }

  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(Scaffold).first));

  Future<void> signIn(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('login-email')), email);
    await tester.enterText(find.byKey(const Key('login-password')), password);
    await tester.tap(find.byKey(const Key('login-submit')));
    await pumpUntilFound(tester, find.byKey(const Key('new-list')));
  }

  /// Reads the confirmation link from the email the backend sent over SMTP.
  Future<String> confirmationLink() async {
    final deadline = DateTime.now().add(_eventually);
    final search = Uri.parse('$_mailpitUrl/api/v1/search').replace(
      queryParameters: {'query': 'to:"$email"'},
    );
    while (DateTime.now().isBefore(deadline)) {
      final messages = (await _getJson(search) as Map)['messages'] as List?;
      if (messages != null && messages.isNotEmpty) {
        final id = (messages.first as Map)['ID'];
        final message = await _getJson(
          Uri.parse('$_mailpitUrl/api/v1/message/$id'),
        ) as Map;
        final link = RegExp(r'/verify-email\?token=[A-Za-z0-9_\-]+')
            .firstMatch(message['Text'] as String);
        if (link != null) return link.group(0)!;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    fail('No confirmation email for $email in Mailpit');
  }

  /// Asks the server directly (as a third session) whether the task is there.
  Future<bool> serverHasTask() async {
    const api = '$apiBaseUrl/api/v1';
    final login = await http
        .post(
          Uri.parse('$api/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(_httpTimeout);
    expect(login.statusCode, 200, reason: login.body);
    final token = (jsonDecode(login.body) as Map)['accessToken'];
    final auth = {'Authorization': 'Bearer $token'};

    Future<bool> taskIsThere() async {
      final lists = await _getJson(Uri.parse('$api/lists'), auth) as List;
      final list = lists.cast<Map<dynamic, dynamic>>().where(
            (l) => l['name'] == listName,
          );
      if (list.isEmpty) return false;
      final tasks = await _getJson(
        Uri.parse('$api/lists/${list.first['id']}/tasks'),
        auth,
      ) as List;
      return tasks.any((t) => (t as Map)['title'] == taskTitle);
    }

    final deadline = DateTime.now().add(_eventually);
    while (DateTime.now().isBefore(deadline)) {
      if (await taskIsThere()) return true;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return false;
  }

  testWidgets(
      'register, confirm by email, create a task on one device '
      'and see it on another', (tester) async {
    // Device 1 ("phone"): register through the UI.
    addTearDown(() => stopDevice(tester));
    step('phone: start with an empty database, register $email');
    await startDevice(tester, 'phone');
    await tester.tap(find.byKey(const Key('open-account')));
    await settle(tester);
    await tester.tap(find.text(l10n(tester).createAccount));
    await settle(tester);
    expect(find.byType(RegisterPage), findsOneWidget);
    await tester.enterText(find.byKey(const Key('register-email')), email);
    await tester.enterText(
      find.byKey(const Key('register-password')),
      password,
    );
    await tester.tap(find.byKey(const Key('register-submit')));
    await pumpUntilFound(tester, find.byKey(const Key('register-sent')));

    // Open the link from the real email, as if the user clicked it.
    step('phone: read the confirmation email from Mailpit');
    final link = await confirmationLink();
    step('phone: open $link');
    GoRouter.of(tester.element(find.byKey(const Key('register-sent'))))
        .go(link);
    await pumpUntilFound(tester, find.byKey(const Key('verify-done')));

    // Sign in from the confirmation page.
    step('phone: email confirmed, sign in');
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(VerifyEmailPage),
        matching: find.byType(FilledButton),
      ),
    );
    await settle(tester);
    await signIn(tester);

    // Create a list and a task; auto-sync pushes them to the server.
    step('phone: create list "$listName" and task "$taskTitle"');
    await tester.tap(find.byKey(const Key('new-list')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('prompt-field')), listName);
    await tester.tap(find.byKey(const Key('prompt-ok')));
    await pumpUntilFound(tester, find.text(listName));
    await tester.tap(find.text(listName).first);
    await settle(tester);
    await tester.enterText(find.byKey(const Key('quick-add')), taskTitle);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await pumpUntilFound(tester, find.text(taskTitle));

    step('server: wait until sync delivered the task');
    expect(
      await serverHasTask(),
      isTrue,
      reason: 'the task never reached the server',
    );

    // Device 2 ("laptop"): empty database, sign in, the data is pulled down.
    step('laptop: start with an empty database and sign in');
    await startDevice(tester, 'laptop');
    expect(find.text(listName), findsNothing);
    await tester.tap(find.byKey(const Key('open-account')));
    await settle(tester);
    await signIn(tester);
    await pumpUntilFound(tester, find.text(listName));
    step('laptop: list pulled from the server, open it');
    await tester.tap(find.text(listName).first);
    await pumpUntilFound(tester, find.text(taskTitle));
    step('laptop: task "$taskTitle" is there - scenario passed');
  });
}

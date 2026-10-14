import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_todo/core/pref_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('login validates input and signs in (FR-1.x)', (tester) async {
    final h = await pumpApp(tester);

    await tester.tap(find.byKey(const Key('open-account')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login-submit')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('login-email')),
      'not-an-email',
    );
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('login-email')), 'a@b.co');
    await tester.enterText(
      find.byKey(const Key('login-password')),
      'correct-password',
    );
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    // Back on the home screen, now signed in; sync status is shown.
    expect(find.byKey(const Key('quick-add')), findsOneWidget);
    expect(h.remote.loginEmail, 'a@b.co');
    expect(find.byKey(const Key('sync-guest')), findsNothing);

    await disposeApp(tester, h);
  });

  testWidgets('wrong password shows an error and stays on the page',
      (tester) async {
    final h = await pumpApp(tester);
    await tester.tap(find.byKey(const Key('open-account')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('login-email')), 'a@b.co');
    await tester.enterText(find.byKey(const Key('login-password')), 'wrong');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Something went wrong'), findsOneWidget);
    expect(find.byKey(const Key('login-submit')), findsOneWidget);

    await disposeApp(tester, h);
  });

  testWidgets('registration asks to confirm the email (FR-1.1)',
      (tester) async {
    final h = await pumpApp(tester);
    await tester.tap(find.byKey(const Key('open-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('register-email')), 'new@b.co');
    await tester.enterText(
      find.byKey(const Key('register-password')),
      'long-enough-pw',
    );
    await tester.tap(find.byKey(const Key('register-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('register-sent')), findsOneWidget);
    expect(h.remote.calls, contains('register:new@b.co'));

    await disposeApp(tester, h);
  });

  testWidgets('password reset request (FR-1.3)', (tester) async {
    final h = await pumpApp(tester);
    await tester.tap(find.byKey(const Key('open-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('reset-email')), 'a@b.co');
    await tester.tap(find.byKey(const Key('reset-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reset-sent')), findsOneWidget);
    expect(h.remote.calls, contains('forgot:a@b.co'));

    await disposeApp(tester, h);
  });

  testWidgets('profile can be saved and the user can sign out (FR-1.4)',
      (tester) async {
    final h = await pumpApp(
      tester,
      prefs: {
        PrefKeys.accessToken: 'a',
        PrefKeys.refreshToken: 'r',
        PrefKeys.userId: 'user-1',
        PrefKeys.userEmail: 'me@x.co',
        PrefKeys.userName: 'Me',
      },
    );
    await tester.tap(find.byKey(const Key('open-account')));
    await tester.pumpAndSettle();
    expect(find.text('me@x.co'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('profile-name')), 'New Name');
    await tester.tap(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();
    expect(h.remote.calls, contains('profile:New Name'));

    await tester.tap(find.byKey(const Key('sign-out')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sync-guest')), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().intersection(PrefKeys.authKeys.toSet()), isEmpty);

    await disposeApp(tester, h);
  });
}

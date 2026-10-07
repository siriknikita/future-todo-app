import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_todo/core/hlc.dart';
import 'package:future_todo/data/remote/remote_api.dart';
import 'package:future_todo/data/repository.dart';

import '../helpers/pump_app.dart';

Future<void> signIn(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('open-account')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('login-email')), 'a@b.co');
  await tester.enterText(
    find.byKey(const Key('login-password')),
    'correct-password',
  );
  await tester.tap(find.byKey(const Key('login-submit')));
  await tester.pumpAndSettle();
}

Future<void> openShareDialog(WidgetTester tester, String listName) async {
  final menu = find.descendant(
    of: find.ancestor(of: find.text(listName), matching: find.byType(ListTile)),
    matching: find.byIcon(Icons.more_vert),
  );
  await tester.tap(menu.first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Share').last);
  await tester.pumpAndSettle();
}

/// A list someone else owns, as if it arrived through sync.
Future<void> addListOwnedByOther(
  WidgetTester tester,
  AppHarness h,
  String name,
) async {
  await tester.runAsync(
    () => TodoRepository(h.db, HlcClock('other'))
        .createList(name, ownerId: 'user-9'),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('guests are asked to sign in before sharing', (tester) async {
    final h = await pumpApp(tester);
    await createList(tester, 'Home');

    await openShareDialog(tester, 'Home');
    expect(
      find.text('Sign in to share lists with other people.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    await disposeApp(tester, h);
  });

  testWidgets('owner shares, revokes links and removes members (FR-5.x)',
      (tester) async {
    final h = await pumpApp(tester);
    await signIn(tester);
    await createList(tester, 'Home');
    final list = (await tester.runAsync(
      () => h.db.select(h.db.taskLists).get(),
    ))!
        .single;
    h.remote.members[list.id] = const [
      ListMember(userId: 'user-1', name: 'Test User', isOwner: true),
      ListMember(userId: 'user-2', name: 'Bob', isOwner: false),
    ];

    await openShareDialog(tester, 'Home');
    expect(find.text('Share "Home"'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Owner'), findsOneWidget);

    // The link itself needs a web origin (Uri.base), which tests do not have;
    // creating the invitation still marks the list as shared.
    await tester.tap(find.byKey(const Key('create-invite')));
    await tester.pumpAndSettle();
    final shared = (await tester.runAsync(
      () => h.db.select(h.db.taskLists).get(),
    ))!
        .single;
    expect(shared.isShared, isTrue);

    await tester.tap(find.byKey(const Key('revoke-invites')));
    await tester.pumpAndSettle();
    expect(h.remote.calls, contains('revoke:${list.id}'));
    expect(find.text('Old invitation links no longer work'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.person_remove_outlined));
    await tester.pumpAndSettle();
    expect(h.remote.calls, contains('remove:user-2'));

    await disposeApp(tester, h);
  });

  testWidgets('a member can leave a shared list (FR-5.5)', (tester) async {
    final h = await pumpApp(tester);
    await signIn(tester);
    await addListOwnedByOther(tester, h, 'Shared');

    await openShareDialog(tester, 'Shared');
    expect(find.byKey(const Key('create-invite')), findsNothing);
    await tester.tap(find.byKey(const Key('leave-list')));
    await tester.pumpAndSettle();
    expect(h.remote.calls, contains('remove:user-1'));
    expect(find.byType(AlertDialog), findsNothing);

    await disposeApp(tester, h);
  });

  testWidgets('server errors are shown as a message', (tester) async {
    final h = await pumpApp(tester);
    await signIn(tester);
    await addListOwnedByOther(tester, h, 'Shared');
    h.remote.failRemoveMember = true;

    await openShareDialog(tester, 'Shared');
    await tester.tap(find.byKey(const Key('leave-list')));
    await tester.pumpAndSettle();
    expect(find.text('Not allowed'), findsOneWidget);

    await disposeApp(tester, h);
  });
}

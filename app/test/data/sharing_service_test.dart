import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_todo/core/hlc.dart';
import 'package:future_todo/data/db/database.dart';
import 'package:future_todo/data/remote/remote_api.dart';
import 'package:future_todo/data/repository.dart';
import 'package:future_todo/data/sharing_service.dart';
import 'package:future_todo/data/sync/sync_service.dart';

import '../helpers/fake_remote.dart';

void main() {
  late AppDatabase db;
  late TodoRepository repo;
  late FakeRemoteApi remote;
  late SharingService sharing;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = TodoRepository(db, HlcClock('test-device'));
    remote = FakeRemoteApi();
    var cursor = 0;
    sharing = SharingService(
      remote: remote,
      repository: repo,
      sync: SyncService(
        repository: repo,
        remote: remote,
        loadCursor: () => cursor,
        saveCursor: (c) async => cursor = c,
      ),
      origin: () => 'https://todo.example',
    );
  });

  tearDown(() => db.close());

  test('an invite link marks the list as shared (FR-5.1)', () async {
    final listId = await repo.createList('Home');

    final link = await sharing.createInviteLink(listId);

    expect(link, 'https://todo.example/join/tok-$listId');
    expect((await repo.watchLists().first).single.isShared, isTrue);
  });

  test('members, revoking links and removing a member go to the server',
      () async {
    remote.members['l1'] = const [
      ListMember(userId: 'user-2', name: 'Bob', isOwner: false),
    ];

    expect((await sharing.members('l1')).single.name, 'Bob');
    await sharing.revokeInvites('l1');
    await sharing.removeMember('l1', 'user-2');

    expect(remote.calls, ['revoke:l1', 'remove:user-2']);
    expect(remote.pullCalls, 0);
  });

  test('leaving a list and joining by invite sync right away (FR-5.1, 5.5)',
      () async {
    await sharing.leaveList('l1', 'user-1');
    expect(remote.calls, ['remove:user-1']);
    expect(remote.pullCalls, 1);

    await sharing.joinByInvite('tok-9');
    expect(remote.calls, ['remove:user-1', 'join:tok-9']);
    expect(remote.pullCalls, 2);
  });

  test('a failed join does not sync', () async {
    remote.failJoin = true;

    await expectLater(
      sharing.joinByInvite('tok-9'),
      throwsA(isA<ApiException>()),
    );
    expect(remote.pullCalls, 0);
  });
}

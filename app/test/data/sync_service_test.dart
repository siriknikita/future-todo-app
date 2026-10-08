import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_todo/core/hlc.dart';
import 'package:future_todo/data/db/database.dart';
import 'package:future_todo/data/repository.dart';
import 'package:future_todo/data/sync/sync_service.dart';

import '../helpers/fake_remote.dart';

class Device {
  Device(this.name, this.remote, int Function() now) {
    db = AppDatabase(NativeDatabase.memory());
    repo = TodoRepository(db, HlcClock(name, now: now));
    sync = SyncService(
      repository: repo,
      remote: remote,
      loadCursor: () => cursor,
      saveCursor: (c) async => cursor = c,
    );
  }

  final String name;
  final FakeRemoteApi remote;
  late final AppDatabase db;
  late final TodoRepository repo;
  late final SyncService sync;
  int cursor = 0;

  Future<List<Task>> tasks() => repo.watchTasks().first;
}

void main() {
  late FakeRemoteApi server;
  late Device a;
  late Device b;
  var timeA = 1000;
  var timeB = 1000;

  setUp(() {
    server = FakeRemoteApi();
    timeA = 1000;
    timeB = 1000;
    a = Device('A', server, () => timeA);
    b = Device('B', server, () => timeB);
  });

  tearDown(() async {
    await a.db.close();
    await b.db.close();
  });

  test('offline changes are queued and pushed after reconnect (FR-8.2)',
      () async {
    final listId = await a.repo.createList('Inbox');
    await a.repo.createTask(listId, 'Offline task');
    expect(await a.repo.watchDirtyCount().first, 2);

    server.failNext = true;
    await a.sync.syncNow();
    expect(a.sync.last, SyncStatus.error);
    expect(await a.repo.watchDirtyCount().first, 2);

    await a.sync.syncNow();
    expect(a.sync.last, SyncStatus.ok);
    expect(await a.repo.watchDirtyCount().first, 0);
    expect(server.records.keys, hasLength(2));
  });

  test('a second device receives the data', () async {
    final listId = await a.repo.createList('Inbox');
    await a.repo.createTask(listId, 'Shared');
    await a.sync.syncNow();
    await b.sync.syncNow();

    expect((await b.repo.watchLists().first).single.name, 'Inbox');
    expect((await b.tasks()).single.title, 'Shared');
    expect(await b.repo.watchDirtyCount().first, 0);
  });

  test('edits to different fields on two devices both survive (FR-8.3)',
      () async {
    final listId = await a.repo.createList('L');
    final taskId = (await a.repo.createTask(listId, 'Task'))!;
    await a.sync.syncNow();
    await b.sync.syncNow();

    timeA = 2000;
    timeB = 2500;
    await a.repo.renameTask(taskId, 'Renamed on A');
    await b.repo.setNote(taskId, 'Note from B');
    await a.sync.syncNow();
    await b.sync.syncNow();
    await a.sync.syncNow();

    for (final d in [a, b]) {
      final t = (await d.tasks()).single;
      expect(t.title, 'Renamed on A');
      expect(t.note, 'Note from B');
    }
  });

  test('same field: last write wins, even when the loser syncs later',
      () async {
    final listId = await a.repo.createList('L');
    final taskId = (await a.repo.createTask(listId, 'Task'))!;
    await a.sync.syncNow();
    await b.sync.syncNow();

    timeA = 5000; // A edits later in real time
    timeB = 3000;
    await b.repo.renameTask(taskId, 'from B');
    await a.repo.renameTask(taskId, 'from A');
    await a.sync.syncNow();
    await b.sync.syncNow(); // B pushes an older stamp, pulls A's value
    await a.sync.syncNow();

    expect((await a.tasks()).single.title, 'from A');
    expect((await b.tasks()).single.title, 'from A');
  });

  test('deletes propagate as tombstones', () async {
    final listId = await a.repo.createList('L');
    final taskId = (await a.repo.createTask(listId, 'Doomed'))!;
    await a.sync.syncNow();
    await b.sync.syncNow();
    expect(await b.tasks(), hasLength(1));

    timeA = 4000;
    await a.repo.deleteTask(taskId);
    await a.sync.syncNow();
    await b.sync.syncNow();

    expect(await b.tasks(), isEmpty);
    final row = await b.repo.getTask(taskId);
    expect(row!.deleted, isTrue);
  });

  test('lists the server no longer exposes are removed locally (FR-5.5)',
      () async {
    final listId = await a.repo.createList('Shared with B');
    await a.repo.createTask(listId, 'T');
    await a.sync.syncNow();
    await b.sync.syncNow();
    expect(await b.repo.watchLists().first, hasLength(1));

    server.accessible = <String>[]; // B was removed from the list
    await b.sync.syncNow();
    expect(await b.repo.watchLists().first, isEmpty);
    expect(await b.tasks(), isEmpty);
    expect(await b.repo.watchDirtyCount().first, 0);
  });

  test('remote changes advance the local clock', () async {
    timeA = 9000;
    final listId = await a.repo.createList('L');
    await a.repo.createTask(listId, 'T');
    await a.sync.syncNow();

    timeB = 10; // B's clock is far behind
    await b.sync.syncNow();
    final taskId = (await b.tasks()).single.id;
    await b.repo.renameTask(taskId, 'B edit after seeing A');
    await b.sync.syncNow();
    await a.sync.syncNow();
    expect((await a.tasks()).single.title, 'B edit after seeing A');
  });
}

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_todo/data/db/database.dart';
import 'package:future_todo/data/sync_entities.dart';

void main() {
  late AppDatabase db;
  late SyncEntities entities;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    entities = SyncEntities(db);
  });

  tearDown(() => db.close());

  test('entities are pushed parents first and found by name', () {
    expect(entities.all.map((e) => e.name), ['group', 'list', 'task', 'step']);
    expect(entities.byName('task'), same(entities.task));
    expect(entities.byName('attachment'), isNull);
    expect(entities.group.name, 'group');
    expect(entities.list.name, 'list');
    expect(entities.step.name, 'step');
    expect(entities.list.localOnly, {'ownerId', 'isShared'});
    expect(entities.task.localOnly, {'createdAt'});
  });

  final samples = <String, Map<String, Object?>>{
    'group': {'name': 'G', 'position': 2},
    'list': {'name': 'L', 'icon': 'x', 'position': 2},
    'task': {
      'listId': 'l1',
      'title': 'T',
      'dueDate': '2025-01-08',
      'position': 2,
    },
    'step': {'taskId': 't1', 'title': 'S', 'position': 2},
  };
  const clearable = {
    'group': null,
    'list': 'icon',
    'task': 'dueDate',
    'step': null,
  };

  for (final name in samples.keys) {
    test('$name rows: upsert, find, clear a field, list dirty, mark clean',
        () async {
      final e = entities.byName(name)!;
      await e.upsertRow({
        ...e.defaults,
        ...samples[name]!,
        'id': 'r1',
        'clocks': '{"a":"1"}',
        'dirty': true,
      });

      final row = (await e.findRow('r1'))!;
      expect(row['position'], 2.0, reason: 'int positions become doubles');
      expect(await e.findRow('missing'), isNull);
      expect((await e.dirtyRows()).single['id'], 'r1');

      final field = clearable[name];
      if (field != null) {
        await e.upsertRow({...row, field: null});
        expect((await e.findRow('r1'))![field], isNull);
      }

      await e.markClean('r1', '{"a":"stale"}');
      expect(await e.dirtyRows(), hasLength(1));
      await e.markClean('r1', '{"a":"1"}');
      expect(await e.dirtyRows(), isEmpty);
    });
  }
}

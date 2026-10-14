import 'package:drift/drift.dart';
import 'package:future_todo/data/db/database.dart';
import 'package:future_todo/data/db/tables.dart';

/// Wire/JSON view of one synced table. Both the repository (local edits) and
/// the sync service (remote changes) read and write rows through this, so
/// per-field clocks are handled in a single place.
class SyncEntity {
  const SyncEntity({
    required this.name,
    required this.defaults,
    required this.localOnly,
    required this.dirtyRows,
    required this.findRow,
    required this.upsertRow,
    required this.markClean,
  });

  final String name;

  /// Fields that are never synced (no clock, never pushed).
  final Set<String> localOnly;

  /// Full field set for a row created from partial remote data.
  final Map<String, Object?> defaults;
  final Future<List<Map<String, Object?>>> Function() dirtyRows;
  final Future<Map<String, Object?>?> Function(String id) findRow;

  /// Writes the whole row. Goes through `toCompanion(false)` because Drift
  /// drops null fields from a data-class upsert, so a cleared field would
  /// keep its old value.
  final Future<void> Function(Map<String, Object?> json) upsertRow;

  /// Clears the dirty flag only if the row still has the pushed `clocks`.
  final Future<void> Function(String id, String clocks) markClean;
}

/// Entity type names used on the wire and in [SyncEntities.byName].
abstract final class EntityNames {
  static const group = 'group';
  static const list = 'list';
  static const task = 'task';
  static const step = 'step';
}

class SyncEntities {
  SyncEntities(AppDatabase db)
      : group = _entity(
          db,
          db.listGroups,
          name: EntityNames.group,
          localOnly: const {},
          defaults: const {'name': '', 'position': 0.0, 'deleted': false},
          toCompanion: (json) => ListGroup.fromJson(json).toCompanion(false),
        ),
        list = _entity(
          db,
          db.taskLists,
          name: EntityNames.list,
          localOnly: const {'ownerId', 'isShared'},
          defaults: const {
            'name': '',
            'icon': null,
            'groupId': null,
            'position': 0.0,
            'ownerId': null,
            'isShared': false,
            'deleted': false,
          },
          toCompanion: (json) => TaskList.fromJson(json).toCompanion(false),
        ),
        task = _entity(
          db,
          db.tasks,
          name: EntityNames.task,
          localOnly: const {'createdAt'},
          defaults: const {
            'listId': '',
            'title': '',
            'note': '',
            'isCompleted': false,
            'completedAt': null,
            'isImportant': false,
            'dueDate': null,
            'reminderAt': null,
            'repeatType': 'none',
            'repeatInterval': 1,
            'repeatDays': 0,
            'myDayDate': null,
            'position': 0.0,
            'createdAt': 0,
            'assigneeId': null,
            'deleted': false,
          },
          toCompanion: (json) => Task.fromJson(json).toCompanion(false),
        ),
        step = _entity(
          db,
          db.taskSteps,
          name: EntityNames.step,
          localOnly: const {},
          defaults: const {
            'taskId': '',
            'title': '',
            'isDone': false,
            'position': 0.0,
            'deleted': false,
          },
          toCompanion: (json) => TaskStep.fromJson(json).toCompanion(false),
        );

  final SyncEntity group;
  final SyncEntity list;
  final SyncEntity task;
  final SyncEntity step;

  /// Push order: parents before children.
  late final List<SyncEntity> all = [group, list, task, step];

  SyncEntity? byName(String name) {
    for (final e in all) {
      if (e.name == name) return e;
    }
    return null;
  }

  /// Builds the row access for one synced table. [toCompanion] turns a
  /// normalized JSON row into the companion that [SyncEntity.upsertRow]
  /// writes (it must use `toCompanion(false)`, see there).
  static SyncEntity _entity<T extends SyncColumns, D extends DataClass>(
    AppDatabase db,
    TableInfo<T, D> table, {
    required String name,
    required Set<String> localOnly,
    required Map<String, Object?> defaults,
    required Insertable<D> Function(Map<String, dynamic> json) toCompanion,
  }) =>
      SyncEntity(
        name: name,
        localOnly: localOnly,
        defaults: defaults,
        dirtyRows: () async =>
            (await (db.select(table)..where((t) => t.dirty.equals(true))).get())
                .map((r) => r.toJson())
                .toList(),
        findRow: (id) async => (await (db.select(table)
                  ..where((t) => t.id.equals(id)))
                .getSingleOrNull())
            ?.toJson(),
        upsertRow: (json) => db
            .into(table)
            .insertOnConflictUpdate(toCompanion(_normalize(json))),
        markClean: (id, clocks) => (db.update(table)
              ..where((t) => t.id.equals(id) & t.clocks.equals(clocks)))
            .write(RawValuesInsertable<D>({'dirty': const Variable(false)})),
      );
}

/// JSON numbers may arrive as ints where Drift expects doubles.
Map<String, dynamic> _normalize(Map<String, Object?> json) {
  final position = json['position'];
  return {
    ...json,
    if (position is num) 'position': position.toDouble(),
  };
}

/// Meta columns that are not synced fields.
const metaColumns = {'id', 'clocks', 'dirty'};

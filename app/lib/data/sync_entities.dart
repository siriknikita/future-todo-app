import 'package:drift/drift.dart';
import 'package:future_todo/data/db/database.dart';

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
  final Future<void> Function(Map<String, Object?> json) upsertRow;

  /// Clears the dirty flag only if the row still has the pushed [clocks].
  final Future<void> Function(String id, String clocks) markClean;
}

class SyncEntities {
  SyncEntities(AppDatabase db)
      : all = [
          SyncEntity(
            name: 'group',
            localOnly: const {},
            defaults: const {'name': '', 'position': 0.0, 'deleted': false},
            dirtyRows: () async => (await (db.select(db.listGroups)
                      ..where((t) => t.dirty.equals(true)))
                    .get())
                .map((r) => r.toJson())
                .toList(),
            findRow: (id) async => (await (db.select(db.listGroups)
                      ..where((t) => t.id.equals(id)))
                    .getSingleOrNull())
                ?.toJson(),
            upsertRow: (json) => db
                .into(db.listGroups)
                .insertOnConflictUpdate(ListGroup.fromJson(_normalize(json))),
            markClean: (id, clocks) => (db.update(db.listGroups)
                  ..where((t) => t.id.equals(id) & t.clocks.equals(clocks)))
                .write(const ListGroupsCompanion(dirty: Value(false))),
          ),
          SyncEntity(
            name: 'list',
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
            dirtyRows: () async => (await (db.select(db.taskLists)
                      ..where((t) => t.dirty.equals(true)))
                    .get())
                .map((r) => r.toJson())
                .toList(),
            findRow: (id) async => (await (db.select(db.taskLists)
                      ..where((t) => t.id.equals(id)))
                    .getSingleOrNull())
                ?.toJson(),
            upsertRow: (json) => db
                .into(db.taskLists)
                .insertOnConflictUpdate(TaskList.fromJson(_normalize(json))),
            markClean: (id, clocks) => (db.update(db.taskLists)
                  ..where((t) => t.id.equals(id) & t.clocks.equals(clocks)))
                .write(const TaskListsCompanion(dirty: Value(false))),
          ),
          SyncEntity(
            name: 'task',
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
            dirtyRows: () async => (await (db.select(db.tasks)
                      ..where((t) => t.dirty.equals(true)))
                    .get())
                .map((r) => r.toJson())
                .toList(),
            findRow: (id) async => (await (db.select(db.tasks)
                      ..where((t) => t.id.equals(id)))
                    .getSingleOrNull())
                ?.toJson(),
            upsertRow: (json) => db
                .into(db.tasks)
                .insertOnConflictUpdate(Task.fromJson(_normalize(json))),
            markClean: (id, clocks) => (db.update(db.tasks)
                  ..where((t) => t.id.equals(id) & t.clocks.equals(clocks)))
                .write(const TasksCompanion(dirty: Value(false))),
          ),
          SyncEntity(
            name: 'step',
            localOnly: const {},
            defaults: const {
              'taskId': '',
              'title': '',
              'isDone': false,
              'position': 0.0,
              'deleted': false,
            },
            dirtyRows: () async => (await (db.select(db.taskSteps)
                      ..where((t) => t.dirty.equals(true)))
                    .get())
                .map((r) => r.toJson())
                .toList(),
            findRow: (id) async => (await (db.select(db.taskSteps)
                      ..where((t) => t.id.equals(id)))
                    .getSingleOrNull())
                ?.toJson(),
            upsertRow: (json) => db
                .into(db.taskSteps)
                .insertOnConflictUpdate(TaskStep.fromJson(_normalize(json))),
            markClean: (id, clocks) => (db.update(db.taskSteps)
                  ..where((t) => t.id.equals(id) & t.clocks.equals(clocks)))
                .write(const TaskStepsCompanion(dirty: Value(false))),
          ),
        ];

  /// Push order: parents before children.
  final List<SyncEntity> all;

  SyncEntity? byName(String name) {
    for (final e in all) {
      if (e.name == name) return e;
    }
    return null;
  }

  SyncEntity get group => byName('group')!;
  SyncEntity get list => byName('list')!;
  SyncEntity get task => byName('task')!;
  SyncEntity get step => byName('step')!;
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

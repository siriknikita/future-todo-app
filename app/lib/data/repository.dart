import 'package:drift/drift.dart';
import 'package:future_todo/core/dates.dart';
import 'package:future_todo/core/hlc.dart';
import 'package:future_todo/core/lww.dart';
import 'package:future_todo/data/db/database.dart';
import 'package:future_todo/data/sync_entities.dart';
import 'package:future_todo/domain/repeat.dart';
import 'package:uuid/uuid.dart';

/// All local reads and writes. The UI only talks to this class (offline-first,
/// FR-8.1); the network is touched only by the sync service.
class TodoRepository {
  TodoRepository(
    this.db,
    this.clock, {
    DateTime Function()? now,
    Uuid uuid = const Uuid(),
  })  : entities = SyncEntities(db),
        _now = now ?? DateTime.now,
        _uuid = uuid;

  final AppDatabase db;
  final HlcClock clock;
  final SyncEntities entities;
  final DateTime Function() _now;
  final Uuid _uuid;

  // ---------------------------------------------------------------- watches

  Stream<List<ListGroup>> watchGroups() => (db.select(db.listGroups)
        ..where((t) => t.deleted.equals(false))
        ..orderBy([(t) => OrderingTerm.asc(t.position)]))
      .watch();

  Stream<List<TaskList>> watchLists() => (db.select(db.taskLists)
        ..where((t) => t.deleted.equals(false))
        ..orderBy([(t) => OrderingTerm.asc(t.position)]))
      .watch();

  Stream<List<Task>> watchTasks() =>
      (db.select(db.tasks)..where((t) => t.deleted.equals(false))).watch();

  Stream<List<TaskStep>> watchSteps() => (db.select(db.taskSteps)
        ..where((t) => t.deleted.equals(false))
        ..orderBy([(t) => OrderingTerm.asc(t.position)]))
      .watch();

  /// Number of rows with unpushed changes (for the sync indicator, FR-8.4).
  Stream<int> watchDirtyCount() => db
      .customSelect(
        'SELECT (SELECT COUNT(*) FROM tasks WHERE dirty = 1) + '
        '(SELECT COUNT(*) FROM task_lists WHERE dirty = 1) + '
        '(SELECT COUNT(*) FROM list_groups WHERE dirty = 1) + '
        '(SELECT COUNT(*) FROM task_steps WHERE dirty = 1) AS c',
        readsFrom: {db.tasks, db.taskLists, db.listGroups, db.taskSteps},
      )
      .watchSingle()
      .map((row) => row.read<int>('c'));

  // ------------------------------------------------------- generic mutation

  Future<String> _create(SyncEntity e, Map<String, Object?> fields) async {
    final id = _uuid.v4();
    final stamp = clock.send().toString();
    final full = {...e.defaults, ...fields};
    await e.upsertRow({
      ...full,
      'id': id,
      'clocks': encodeClocks({
        for (final k in full.keys)
          if (!e.localOnly.contains(k)) k: stamp,
      }),
      'dirty': true,
    });
    return id;
  }

  /// Changes fields of one row and stamps each with a fresh HLC.
  Future<void> _mutate(
    SyncEntity e,
    String id,
    Map<String, Object?> changes,
  ) async {
    final row = await e.findRow(id);
    if (row == null) return;
    final clocks = decodeClocks(row['clocks']);
    final stamp = clock.send().toString();
    final synced = changes.keys.where((k) => !e.localOnly.contains(k));
    for (final k in synced) {
      clocks[k] = stamp;
    }
    await e.upsertRow({
      ...row,
      ...changes,
      'clocks': encodeClocks(clocks),
      'dirty': synced.isNotEmpty || row['dirty'] == true,
    });
  }

  /// Removes lists the server no longer lets this user see (left a shared
  /// list or was removed). The tombstone gets the oldest possible clock so
  /// the list comes back if the user is invited again.
  Future<void> purgeInaccessibleLists(Set<String> accessibleIds) async {
    const oldest = '000000000000000:00000:purge';
    final lists = await (db.select(db.taskLists)
          ..where((t) => t.deleted.equals(false) & t.dirty.equals(false)))
        .get();
    for (final list in lists.where((l) => !accessibleIds.contains(l.id))) {
      final tasks = await (db.select(db.tasks)
            ..where((t) => t.listId.equals(list.id)))
          .get();
      for (final t in tasks) {
        for (final s in await (db.select(db.taskSteps)
              ..where((s) => s.taskId.equals(t.id)))
            .get()) {
          await _purge(entities.step, s.id, oldest);
        }
        await _purge(entities.task, t.id, oldest);
      }
      await _purge(entities.list, list.id, oldest);
    }
  }

  Future<void> _purge(SyncEntity e, String id, String stamp) async {
    final row = await e.findRow(id);
    if (row == null) return;
    final clocks = decodeClocks(row['clocks'])..['deleted'] = stamp;
    await e.upsertRow({
      ...row,
      'deleted': true,
      'clocks': encodeClocks(clocks),
      'dirty': false,
    });
  }

  Future<double> _nextPosition(Iterable<double> existing) async =>
      existing.isEmpty ? 1 : existing.reduce((a, b) => a > b ? a : b) + 1;

  // ----------------------------------------------------------------- groups

  Future<String> createGroup(String name) async {
    final groups = await (db.select(db.listGroups)
          ..where((t) => t.deleted.equals(false)))
        .get();
    final lists = await (db.select(db.taskLists)
          ..where((t) => t.deleted.equals(false)))
        .get();
    final pos = await _nextPosition(
      [...groups.map((g) => g.position), ...lists.map((l) => l.position)],
    );
    return _create(entities.group, {'name': name, 'position': pos});
  }

  Future<void> renameGroup(String id, String name) =>
      _mutate(entities.group, id, {'name': name});

  /// Dissolves a group: lists stay, the group becomes a tombstone (FR-2.3).
  Future<void> ungroup(String id) async {
    final lists = await (db.select(db.taskLists)
          ..where((t) => t.groupId.equals(id) & t.deleted.equals(false)))
        .get();
    for (final l in lists) {
      await _mutate(entities.list, l.id, {'groupId': null});
    }
    await _mutate(entities.group, id, {'deleted': true});
  }

  // ------------------------------------------------------------------ lists

  Future<String> createList(
    String name, {
    String? groupId,
    String? icon,
    String? ownerId,
  }) async {
    final groups = await (db.select(db.listGroups)
          ..where((t) => t.deleted.equals(false)))
        .get();
    final lists = await (db.select(db.taskLists)
          ..where((t) => t.deleted.equals(false)))
        .get();
    final pos = await _nextPosition(
      [...groups.map((g) => g.position), ...lists.map((l) => l.position)],
    );
    return _create(entities.list, {
      'name': name,
      'groupId': groupId,
      'icon': icon,
      'ownerId': ownerId,
      'position': pos,
    });
  }

  Future<void> renameList(String id, String name) =>
      _mutate(entities.list, id, {'name': name});

  Future<void> setListIcon(String id, String? icon) =>
      _mutate(entities.list, id, {'icon': icon});

  Future<void> setListShared(String id, {required bool shared}) =>
      _mutate(entities.list, id, {'isShared': shared});

  Future<void> moveListToGroup(String id, String? groupId) =>
      _mutate(entities.list, id, {'groupId': groupId});

  /// Deletes a list with its tasks and steps (tombstones).
  Future<void> deleteList(String id) async {
    final tasks = await (db.select(db.tasks)
          ..where((t) => t.listId.equals(id) & t.deleted.equals(false)))
        .get();
    for (final t in tasks) {
      await deleteTask(t.id);
    }
    await _mutate(entities.list, id, {'deleted': true});
  }

  /// Assigns positions 1..n in the given order. [ids] may mix lists and
  /// groups (they share one position space at the top level, FR-2.4).
  Future<void> reorderSidebar({
    required List<String> ids,
    required Set<String> groupIds,
  }) async {
    for (var i = 0; i < ids.length; i++) {
      final e = groupIds.contains(ids[i]) ? entities.group : entities.list;
      await _mutate(e, ids[i], {'position': i + 1.0});
    }
  }

  // ------------------------------------------------------------------ tasks

  /// Quick add (FR-3.1): title only, up to 255 characters.
  Future<String?> createTask(
    String listId,
    String title, {
    bool important = false,
    bool inMyDay = false,
    String? dueDate,
    String? assigneeId,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return null;
    final existing = await (db.select(db.tasks)
          ..where((t) => t.listId.equals(listId) & t.deleted.equals(false)))
        .get();
    final pos = await _nextPosition(existing.map((t) => t.position));
    return _create(entities.task, {
      'listId': listId,
      'title': trimmed.length > 255 ? trimmed.substring(0, 255) : trimmed,
      'isImportant': important,
      'dueDate': dueDate,
      'myDayDate': inMyDay ? dateKey(_now()) : null,
      'assigneeId': assigneeId,
      'position': pos,
      'createdAt': _now().millisecondsSinceEpoch,
    });
  }

  Future<Task?> getTask(String id) =>
      (db.select(db.tasks)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> renameTask(String id, String title) => _mutate(
        entities.task,
        id,
        {'title': title.length > 255 ? title.substring(0, 255) : title},
      );

  Future<void> setNote(String id, String note) =>
      _mutate(entities.task, id, {'note': note});

  Future<void> setImportant(String id, {required bool important}) =>
      _mutate(entities.task, id, {'isImportant': important});

  Future<void> setDueDate(String id, DateTime? date) => _mutate(
        entities.task,
        id,
        {'dueDate': date == null ? null : dateKey(date)},
      );

  Future<void> setReminder(String id, DateTime? at) => _mutate(
        entities.task,
        id,
        {'reminderAt': at?.millisecondsSinceEpoch},
      );

  Future<void> setRepeat(String id, RepeatRule rule) => _mutate(
        entities.task,
        id,
        {
          'repeatType': rule.type.name,
          'repeatInterval': rule.interval,
          'repeatDays': rule.weekdayMask,
        },
      );

  Future<void> setMyDay(String id, {required bool inMyDay}) => _mutate(
        entities.task,
        id,
        {'myDayDate': inMyDay ? dateKey(_now()) : null},
      );

  Future<void> setAssignee(String id, String? userId) =>
      _mutate(entities.task, id, {'assigneeId': userId});

  Future<void> moveTask(String id, String listId) =>
      _mutate(entities.task, id, {'listId': listId});

  /// Marks a task done or not done (FR-3.2). Completing a repeating task
  /// creates the next occurrence (FR-3.6).
  Future<void> setCompleted(String id, {required bool completed}) async {
    final task = await getTask(id);
    if (task == null || task.isCompleted == completed) return;
    await _mutate(entities.task, id, {
      'isCompleted': completed,
      'completedAt': completed ? _now().millisecondsSinceEpoch : null,
    });
    if (!completed) return;
    final rule = RepeatRule.fromStorage(
      task.repeatType,
      task.repeatInterval,
      task.repeatDays,
    );
    final base = task.dueDate == null ? _now() : parseDateKey(task.dueDate!);
    final next = nextOccurrence(rule, base);
    if (next == null) return;
    int? reminder;
    if (task.reminderAt != null) {
      final r = task.reminderAt!;
      final shifted = DateTime(
        next.year,
        next.month,
        next.day,
        r.hour,
        r.minute,
      );
      reminder = shifted.millisecondsSinceEpoch;
    }
    final newId = await _create(entities.task, {
      'listId': task.listId,
      'title': task.title,
      'note': task.note,
      'isImportant': task.isImportant,
      'dueDate': dateKey(next),
      'reminderAt': reminder,
      'repeatType': task.repeatType,
      'repeatInterval': task.repeatInterval,
      'repeatDays': task.repeatDays,
      'assigneeId': task.assigneeId,
      'position': task.position,
      'createdAt': _now().millisecondsSinceEpoch,
    });
    final steps = await stepsOf(id);
    for (final s in steps) {
      await addStep(newId, s.title);
    }
  }

  Future<void> deleteTask(String id) async {
    for (final s in await stepsOf(id)) {
      await _mutate(entities.step, s.id, {'deleted': true});
    }
    await _mutate(entities.task, id, {'deleted': true});
  }

  /// Undo for FR-3.12: brings a deleted task (and its steps) back.
  Future<void> restoreTask(String id) async {
    await _mutate(entities.task, id, {'deleted': false});
    final steps = await (db.select(db.taskSteps)
          ..where((t) => t.taskId.equals(id)))
        .get();
    for (final s in steps) {
      await _mutate(entities.step, s.id, {'deleted': false});
    }
  }

  // ------------------------------------------------------------------ steps

  Future<List<TaskStep>> stepsOf(String taskId) => (db.select(db.taskSteps)
        ..where((t) => t.taskId.equals(taskId) & t.deleted.equals(false))
        ..orderBy([(t) => OrderingTerm.asc(t.position)]))
      .get();

  Future<String?> addStep(String taskId, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return null;
    final existing = await stepsOf(taskId);
    final pos = await _nextPosition(existing.map((s) => s.position));
    return _create(
      entities.step,
      {'taskId': taskId, 'title': trimmed, 'position': pos},
    );
  }

  Future<void> setStepDone(String id, {required bool done}) =>
      _mutate(entities.step, id, {'isDone': done});

  Future<void> renameStep(String id, String title) =>
      _mutate(entities.step, id, {'title': title});

  Future<void> deleteStep(String id) =>
      _mutate(entities.step, id, {'deleted': true});

  Future<void> reorderSteps(List<String> orderedIds) async {
    for (var i = 0; i < orderedIds.length; i++) {
      await _mutate(entities.step, orderedIds[i], {'position': i + 1.0});
    }
  }
}

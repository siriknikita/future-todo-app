import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_todo/core/hlc.dart';
import 'package:future_todo/core/lww.dart';
import 'package:future_todo/data/db/database.dart';
import 'package:future_todo/data/repository.dart';
import 'package:future_todo/domain/repeat.dart';

void main() {
  late AppDatabase db;
  late TodoRepository repo;
  var current = DateTime(2025, 1, 8, 10);

  setUp(() {
    current = DateTime(2025, 1, 8, 10);
    db = AppDatabase(NativeDatabase.memory());
    repo = TodoRepository(
      db,
      HlcClock('test-device'),
      now: () => current,
    );
  });

  tearDown(() => db.close());

  Future<List<Task>> tasks() => repo.watchTasks().first;

  test('creates a list and a task (FR-2.1, FR-3.1)', () async {
    final listId = await repo.createList('Work');
    final taskId = await repo.createTask(listId, '  Write report  ');

    final lists = await repo.watchLists().first;
    expect(lists.single.name, 'Work');
    final all = await tasks();
    expect(all.single.id, taskId);
    expect(all.single.title, 'Write report');
    expect(all.single.dirty, isTrue);
  });

  test('empty titles are rejected and long titles are cut to 255', () async {
    final listId = await repo.createList('L');
    expect(await repo.createTask(listId, '   '), isNull);
    await repo.createTask(listId, 'x' * 300);
    expect((await tasks()).single.title.length, 255);
  });

  test('every written field gets its own clock', () async {
    final listId = await repo.createList('L');
    final id = (await repo.createTask(listId, 'A'))!;
    final before = decodeClocks((await repo.getTask(id))!.clocks);
    await repo.setNote(id, 'hello');
    final after = decodeClocks((await repo.getTask(id))!.clocks);
    expect(Hlc.parse(after['note']!) > Hlc.parse(before['note']!), isTrue);
    expect(after['title'], before['title']);
  });

  test('complete / uncomplete (FR-3.2)', () async {
    final listId = await repo.createList('L');
    final id = (await repo.createTask(listId, 'A'))!;
    await repo.setCompleted(id, completed: true);
    expect((await repo.getTask(id))!.isCompleted, isTrue);
    expect((await repo.getTask(id))!.completedAt, isNotNull);
    await repo.setCompleted(id, completed: false);
    expect((await repo.getTask(id))!.isCompleted, isFalse);
    expect((await repo.getTask(id))!.completedAt, isNull);
  });

  test('completing a repeating task creates the next occurrence (FR-3.6)',
      () async {
    final listId = await repo.createList('L');
    final id = (await repo.createTask(listId, 'Water plants'))!;
    await repo.setDueDate(id, DateTime(2025, 1, 8));
    await repo.setRepeat(id, const RepeatRule(RepeatType.weekly));
    await repo.addStep(id, 'Kitchen');
    await repo.setCompleted(id, completed: true);

    final all = await tasks();
    expect(all, hasLength(2));
    final next = all.firstWhere((t) => t.id != id);
    expect(next.isCompleted, isFalse);
    expect(next.dueDate, '2025-01-15');
    expect(next.repeatType, 'weekly');
    expect((await repo.stepsOf(next.id)).single.title, 'Kitchen');
  });

  test('delete is a tombstone and can be undone (FR-3.12)', () async {
    final listId = await repo.createList('L');
    final id = (await repo.createTask(listId, 'A'))!;
    await repo.addStep(id, 'S');
    await repo.deleteTask(id);

    expect(await tasks(), isEmpty);
    expect((await repo.getTask(id))!.deleted, isTrue);
    expect(await repo.stepsOf(id), isEmpty);

    await repo.restoreTask(id);
    expect(await tasks(), hasLength(1));
    expect(await repo.stepsOf(id), hasLength(1));
  });

  test('deleting a list tombstones its tasks', () async {
    final listId = await repo.createList('L');
    await repo.createTask(listId, 'A');
    await repo.deleteList(listId);
    expect(await repo.watchLists().first, isEmpty);
    expect(await tasks(), isEmpty);
  });

  test('groups: group lists, then dissolve the group (FR-2.3)', () async {
    final g = await repo.createGroup('Home');
    final l = await repo.createList('Shopping', groupId: g);
    await repo.renameGroup(g, 'House');
    expect((await repo.watchGroups().first).single.name, 'House');

    await repo.ungroup(g);
    expect(await repo.watchGroups().first, isEmpty);
    expect((await repo.watchLists().first).single.id, l);
    expect((await repo.watchLists().first).single.groupId, isNull);
  });

  test('reorder assigns new positions (FR-2.4)', () async {
    final a = await repo.createList('A');
    final b = await repo.createList('B');
    await repo.reorderSidebar(ids: [b, a], groupIds: {});
    final lists = await repo.watchLists().first;
    expect(lists.map((l) => l.id), [b, a]);
  });

  test('steps: add, finish, reorder, delete (FR-3.7)', () async {
    final listId = await repo.createList('L');
    final id = (await repo.createTask(listId, 'A'))!;
    final s1 = (await repo.addStep(id, 'one'))!;
    final s2 = (await repo.addStep(id, 'two'))!;
    await repo.setStepDone(s1, done: true);
    await repo.reorderSteps([s2, s1]);
    final steps = await repo.stepsOf(id);
    expect(steps.map((s) => s.id), [s2, s1]);
    expect(steps.last.isDone, isTrue);
    await repo.deleteStep(s2);
    expect(await repo.stepsOf(id), hasLength(1));
  });

  test('My Day stores the local date and can be cleared (FR-4.1)', () async {
    final listId = await repo.createList('L');
    final id = (await repo.createTask(listId, 'A', inMyDay: true))!;
    expect((await repo.getTask(id))!.myDayDate, '2025-01-08');
    await repo.setMyDay(id, inMyDay: false);
    expect((await repo.getTask(id))!.myDayDate, isNull);
  });

  test('due date, reminder, note, importance, move (FR-3.3-3.5, 3.8, 3.11)',
      () async {
    final l1 = await repo.createList('L1');
    final l2 = await repo.createList('L2');
    final id = (await repo.createTask(l1, 'A'))!;
    final reminder = DateTime(2025, 1, 9, 9, 30);
    await repo.setDueDate(id, DateTime(2025, 1, 9));
    await repo.setReminder(id, reminder);
    await repo.setNote(id, 'note');
    await repo.setImportant(id, important: true);
    await repo.moveTask(id, l2);
    final t = (await repo.getTask(id))!;
    expect(t.dueDate, '2025-01-09');
    expect(
      t.reminderAt!.millisecondsSinceEpoch,
      reminder.millisecondsSinceEpoch,
    );
    expect(t.note, 'note');
    expect(t.isImportant, isTrue);
    expect(t.listId, l2);
  });

  test('dirty count reflects unpushed rows', () async {
    final listId = await repo.createList('L');
    await repo.createTask(listId, 'A');
    expect(await repo.watchDirtyCount().first, 2);
  });
}

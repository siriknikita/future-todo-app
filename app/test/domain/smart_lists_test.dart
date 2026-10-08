import 'package:flutter_test/flutter_test.dart';
import 'package:future_todo/domain/smart_lists.dart';

import '../helpers/factories.dart';

void main() {
  // Wednesday, 2025-01-08.
  final now = DateTime(2025, 1, 8, 12);

  group('My Day (FR-4.1)', () {
    test('contains tasks added today only', () {
      final today = makeTask(id: 'a', myDayDate: '2025-01-08');
      final yesterday = makeTask(id: 'b', myDayDate: '2025-01-07');
      final never = makeTask(id: 'c');
      final result =
          filterSmartList(SmartList.myDay, [today, yesterday, never], now: now);
      expect(result.map((t) => t.id), ['a']);
    });

    test('resets at local midnight, tasks themselves stay', () {
      final task = makeTask(myDayDate: '2025-01-08');
      expect(isInMyDay(task, DateTime(2025, 1, 8, 23, 59, 59)), isTrue);
      expect(isInMyDay(task, DateTime(2025, 1, 9)), isFalse);
      expect(task.deleted, isFalse);
    });
  });

  test('Important lists important tasks', () {
    final result = filterSmartList(
      SmartList.important,
      [makeTask(id: 'a', isImportant: true), makeTask(id: 'b')],
      now: now,
    );
    expect(result.map((t) => t.id), ['a']);
  });

  test('Planned lists tasks with a due date', () {
    final result = filterSmartList(
      SmartList.planned,
      [makeTask(id: 'a', dueDate: '2025-02-01'), makeTask(id: 'b')],
      now: now,
    );
    expect(result.map((t) => t.id), ['a']);
  });

  test('Assigned to me needs a current user and matching assignee', () {
    final tasks = [
      makeTask(id: 'a', assigneeId: 'me'),
      makeTask(id: 'b', assigneeId: 'other'),
      makeTask(id: 'c'),
    ];
    expect(
      filterSmartList(
        SmartList.assignedToMe,
        tasks,
        now: now,
        currentUserId: 'me',
      ).map((t) => t.id),
      ['a'],
    );
    expect(filterSmartList(SmartList.assignedToMe, tasks, now: now), isEmpty);
  });

  test('All and Completed ignore tombstones', () {
    final tasks = [
      makeTask(id: 'a', isCompleted: true),
      makeTask(id: 'b'),
      makeTask(id: 'c', deleted: true, isCompleted: true),
    ];
    expect(filterSmartList(SmartList.all, tasks, now: now), hasLength(2));
    expect(
      filterSmartList(SmartList.completed, tasks, now: now).map((t) => t.id),
      ['a'],
    );
  });

  group('Planned buckets (FR-4.4)', () {
    test('classifies by date relative to now (Wed)', () {
      expect(plannedBucket('2025-01-07', now), PlannedBucket.overdue);
      expect(plannedBucket('2025-01-08', now), PlannedBucket.today);
      expect(plannedBucket('2025-01-09', now), PlannedBucket.tomorrow);
      expect(
        plannedBucket('2025-01-12', now),
        PlannedBucket.thisWeek,
      ); // Sunday
      expect(
        plannedBucket('2025-01-13', now),
        PlannedBucket.later,
      ); // next Monday
    });

    test('on Sunday only today/tomorrow come before "later"', () {
      final sunday = DateTime(2025, 1, 12);
      expect(plannedBucket('2025-01-13', sunday), PlannedBucket.tomorrow);
      expect(plannedBucket('2025-01-14', sunday), PlannedBucket.later);
    });

    test('groupPlanned sorts inside buckets and skips undated tasks', () {
      final grouped = groupPlanned(
        [
          makeTask(id: 'b', dueDate: '2025-01-11'),
          makeTask(id: 'a', dueDate: '2025-01-10'),
          makeTask(id: 'x'),
        ],
        now,
      );
      expect(grouped[PlannedBucket.thisWeek]!.map((t) => t.id), ['a', 'b']);
      expect(grouped.values.expand((e) => e), hasLength(2));
    });
  });

  group('My Day suggestions (FR-4.2)', () {
    test('suggests due today, overdue and previously added tasks', () {
      final tasks = [
        makeTask(id: 'due-today', dueDate: '2025-01-08'),
        makeTask(id: 'overdue', dueDate: '2025-01-01'),
        makeTask(id: 'earlier', myDayDate: '2025-01-05'),
        makeTask(id: 'future', dueDate: '2025-02-01'),
        makeTask(id: 'in-day', dueDate: '2025-01-08', myDayDate: '2025-01-08'),
        makeTask(id: 'done', dueDate: '2025-01-08', isCompleted: true),
      ];
      expect(
        suggestForMyDay(tasks, now).map((t) => t.id),
        ['due-today', 'overdue', 'earlier'],
      );
    });
  });
}

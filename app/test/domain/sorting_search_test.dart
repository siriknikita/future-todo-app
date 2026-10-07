import 'package:flutter_test/flutter_test.dart';
import 'package:future_todo/domain/search.dart';
import 'package:future_todo/domain/sorting.dart';

import '../helpers/factories.dart';

void main() {
  final tasks = [
    makeTask(
      id: 'b',
      title: 'banana',
      createdAt: DateTime(2025, 1, 2),
      position: 2,
    ),
    makeTask(
      id: 'a',
      title: 'Apple',
      isImportant: true,
      dueDate: '2025-03-01',
      createdAt: DateTime(2025, 1, 3),
      position: 3,
    ),
    makeTask(
      id: 'c',
      title: 'cherry',
      dueDate: '2025-02-01',
      createdAt: DateTime(2025),
      position: 1,
    ),
  ];

  List<String> ids(SortMode m) => sortTasks(tasks, m).map((t) => t.id).toList();

  test(
    'manual sorts by position',
    () => expect(ids(SortMode.manual), ['c', 'b', 'a']),
  );
  test('importance puts important first', () {
    expect(ids(SortMode.importance).first, 'a');
  });
  test('due date puts undated last', () {
    expect(ids(SortMode.dueDate), ['c', 'a', 'b']);
  });
  test('alphabetical ignores case', () {
    expect(ids(SortMode.alphabetical), ['a', 'b', 'c']);
  });
  test('created puts newest first', () {
    expect(ids(SortMode.createdAt), ['a', 'b', 'c']);
  });

  group('search (FR-7.1, FR-7.3)', () {
    final data = [
      makeTask(id: '1', title: 'Buy milk'),
      makeTask(id: '2', title: 'Call', note: 'about the MILK order'),
      makeTask(id: '3', title: 'Plan trip'),
      makeTask(id: '4', title: 'Milkshake', isCompleted: true),
      makeTask(id: '5', title: 'milk gone', deleted: true),
    ];
    final steps = [makeStep(taskId: '3', title: 'book milk-train')];

    test('matches title, note and steps, ignoring deleted', () {
      final r = searchTasks(tasks: data, steps: steps, query: 'milk');
      expect(r.map((t) => t.id), ['1', '2', '3', '4']);
    });

    test('can exclude completed tasks', () {
      final r = searchTasks(
        tasks: data,
        steps: steps,
        query: 'milk',
        includeCompleted: false,
      );
      expect(r.map((t) => t.id), ['1', '2', '3']);
    });

    test('empty query yields nothing', () {
      expect(searchTasks(tasks: data, steps: steps, query: '  '), isEmpty);
    });
  });
}

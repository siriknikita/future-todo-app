import 'package:future_todo/data/db/database.dart';

enum SortMode { manual, importance, dueDate, alphabetical, createdAt }

/// Returns a sorted copy of [tasks] (FR-3.13).
List<Task> sortTasks(Iterable<Task> tasks, SortMode mode) {
  final list = tasks.toList();
  int byCreated(Task a, Task b) => a.createdAt.compareTo(b.createdAt);
  switch (mode) {
    case SortMode.manual:
      list.sort((a, b) {
        final c = a.position.compareTo(b.position);
        return c != 0 ? c : byCreated(a, b);
      });
    case SortMode.importance:
      list.sort((a, b) {
        if (a.isImportant != b.isImportant) return a.isImportant ? -1 : 1;
        return byCreated(a, b);
      });
    case SortMode.dueDate:
      list.sort((a, b) {
        if (a.dueDate == null && b.dueDate == null) return byCreated(a, b);
        if (a.dueDate == null) return 1;
        if (b.dueDate == null) return -1;
        final c = a.dueDate!.compareTo(b.dueDate!);
        return c != 0 ? c : byCreated(a, b);
      });
    case SortMode.alphabetical:
      list.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    case SortMode.createdAt:
      list.sort((a, b) => byCreated(b, a));
  }
  return list;
}

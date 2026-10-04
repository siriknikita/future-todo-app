import 'package:future_todo/data/db/database.dart';

/// Search over task titles, notes and step titles in all lists (FR-7.1).
/// Case-insensitive substring match done in memory over the local data.
List<Task> searchTasks({
  required Iterable<Task> tasks,
  required Iterable<TaskStep> steps,
  required String query,
  bool includeCompleted = true,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final stepsByTask = <String, List<TaskStep>>{};
  for (final s in steps.where((s) => !s.deleted)) {
    stepsByTask.putIfAbsent(s.taskId, () => []).add(s);
  }
  return tasks.where((t) {
    if (t.deleted) return false;
    if (!includeCompleted && t.isCompleted) return false;
    if (t.title.toLowerCase().contains(q)) return true;
    if (t.note.toLowerCase().contains(q)) return true;
    return (stepsByTask[t.id] ?? const [])
        .any((s) => s.title.toLowerCase().contains(q));
  }).toList();
}

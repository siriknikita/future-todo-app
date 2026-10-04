import 'package:future_todo/core/dates.dart';
import 'package:future_todo/data/db/database.dart';

enum SmartList { myDay, important, planned, assignedToMe, all, completed }

enum PlannedBucket { overdue, today, tomorrow, thisWeek, later }

/// Whether [task] is in "My Day" for the local day of [now] (FR-4.1).
/// "My Day" is cleared at local midnight simply because the stored date no
/// longer equals today's date; the task itself is untouched.
bool isInMyDay(Task task, DateTime now) => task.myDayDate == dateKey(now);

List<Task> filterSmartList(
  SmartList list,
  Iterable<Task> tasks, {
  required DateTime now,
  String? currentUserId,
}) {
  final live = tasks.where((t) => !t.deleted);
  switch (list) {
    case SmartList.myDay:
      return live.where((t) => isInMyDay(t, now)).toList();
    case SmartList.important:
      return live.where((t) => t.isImportant).toList();
    case SmartList.planned:
      return live.where((t) => t.dueDate != null).toList();
    case SmartList.assignedToMe:
      return live
          .where((t) => currentUserId != null && t.assigneeId == currentUserId)
          .toList();
    case SmartList.all:
      return live.toList();
    case SmartList.completed:
      return live.where((t) => t.isCompleted).toList();
  }
}

/// Date bucket for the "Planned" list (FR-4.4). The week ends on Sunday.
PlannedBucket plannedBucket(String dueDate, DateTime now) {
  final today = dateOnly(now);
  final due = parseDateKey(dueDate);
  final diff = daysBetween(today, due);
  if (diff < 0) return PlannedBucket.overdue;
  if (diff == 0) return PlannedBucket.today;
  if (diff == 1) return PlannedBucket.tomorrow;
  final daysToNextWeek = 8 - today.weekday;
  if (diff < daysToNextWeek) return PlannedBucket.thisWeek;
  return PlannedBucket.later;
}

Map<PlannedBucket, List<Task>> groupPlanned(
  Iterable<Task> tasks,
  DateTime now,
) {
  final result = {for (final b in PlannedBucket.values) b: <Task>[]};
  for (final t in tasks) {
    if (t.dueDate == null) continue;
    result[plannedBucket(t.dueDate!, now)]!.add(t);
  }
  for (final list in result.values) {
    list.sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
  }
  return result;
}

/// Suggestions for "My Day" (FR-4.2): due today, overdue, or added to
/// "My Day" on an earlier day. Completed tasks and tasks already in
/// today's "My Day" are not suggested.
List<Task> suggestForMyDay(Iterable<Task> tasks, DateTime now) {
  final today = dateKey(now);
  return tasks.where((t) {
    if (t.deleted || t.isCompleted || t.myDayDate == today) return false;
    final dueSoon = t.dueDate != null && t.dueDate!.compareTo(today) <= 0;
    final earlier = t.myDayDate != null;
    return dueSoon || earlier;
  }).toList();
}

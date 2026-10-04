import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:future_todo/data/db/database.dart';
import 'package:future_todo/domain/repeat.dart';
import 'package:future_todo/features/tasks/task_details.dart';
import 'package:future_todo/l10n/app_localizations.dart';
import 'package:future_todo/providers.dart';
import 'package:intl/intl.dart';

const wideBreakpoint = 1000.0;

/// Opens the details panel: inline on wide screens, a full page otherwise.
void openTaskDetails(BuildContext context, WidgetRef ref, String taskId) {
  ref.read(selectedTaskIdProvider.notifier).state = taskId;
  if (MediaQuery.sizeOf(context).width < wideBreakpoint) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(),
          body: TaskDetails(taskId: taskId),
        ),
      ),
    );
  }
}

class TaskTile extends ConsumerWidget {
  const TaskTile({
    required this.task,
    super.key,
    this.listName,
    this.trailing,
  });

  final Task task;

  /// Shown in smart lists and search results.
  final String? listName;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final repo = ref.read(repositoryProvider);
    final selected = ref.watch(selectedTaskIdProvider) == task.id;
    final steps = (ref.watch(stepsProvider).valueOrNull ?? const <TaskStep>[])
        .where((s) => s.taskId == task.id)
        .toList();
    final locale = Localizations.localeOf(context).toString();

    final info = <String>[
      if (listName != null) listName!,
      if (steps.isNotEmpty)
        l.stepsProgress(steps.where((s) => s.isDone).length, steps.length),
      if (task.dueDate != null)
        DateFormat.MMMd(locale).format(DateTime.parse(task.dueDate!)),
    ];

    return ListTile(
      key: ValueKey('task-${task.id}'),
      selected: selected,
      leading: Checkbox(
        key: Key('check-${task.id}'),
        shape: const CircleBorder(),
        value: task.isCompleted,
        onChanged: (v) => repo.setCompleted(task.id, completed: v ?? false),
      ),
      title: Text(
        task.title,
        style: task.isCompleted
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
      subtitle: info.isEmpty && task.repeatType == 'none'
          ? null
          : Row(
              children: [
                Flexible(
                  child: Text(
                    info.join(' · '),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (task.repeatType != RepeatType.none.name)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.repeat, size: 14),
                  ),
                if (task.reminderAt != null)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.notifications_none, size: 14),
                  ),
                if (task.note.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.notes, size: 14),
                  ),
              ],
            ),
      trailing: trailing ??
          IconButton(
            key: Key('star-${task.id}'),
            tooltip: l.important,
            icon: Icon(
              task.isImportant ? Icons.star : Icons.star_border,
              color: task.isImportant ? Colors.amber : null,
            ),
            onPressed: () =>
                repo.setImportant(task.id, important: !task.isImportant),
          ),
      onTap: () => openTaskDetails(context, ref, task.id),
    );
  }
}

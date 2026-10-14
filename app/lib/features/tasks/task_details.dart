import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:future_todo/core/dates.dart';
import 'package:future_todo/core/limits.dart';
import 'package:future_todo/data/db/database.dart';
import 'package:future_todo/data/remote/remote_api.dart';
import 'package:future_todo/domain/repeat.dart';
import 'package:future_todo/domain/smart_lists.dart';
import 'package:future_todo/features/common/labels.dart';
import 'package:future_todo/features/common/widgets.dart';
import 'package:future_todo/features/tasks/task_tile.dart';
import 'package:future_todo/l10n/app_localizations.dart';
import 'package:future_todo/providers.dart';
import 'package:intl/intl.dart';

/// Details panel of one task: title, steps, My Day, due date, reminder,
/// repeat, assignee, list, note, delete.
class TaskDetails extends ConsumerWidget {
  const TaskDetails({required this.taskId, super.key});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final tasks = ref.watch(tasksProvider).valueOrNull ?? const <Task>[];
    final task = tasks.where((t) => t.id == taskId).firstOrNull;
    if (task == null) return Center(child: Text(l.selectTaskHint));

    final lists = ref.watch(listsProvider).valueOrNull ?? const <TaskList>[];
    final steps = (ref.watch(stepsProvider).valueOrNull ?? const <TaskStep>[])
        .where((s) => s.taskId == taskId)
        .toList();
    final now = ref.watch(todayProvider).valueOrNull ?? DateTime.now();
    final list = lists.where((li) => li.id == task.listId).firstOrNull;
    final auth = ref.watch(authProvider);
    final myId = auth.user?.id;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: ListView(
        key: const Key('task-details'),
        padding: const EdgeInsets.all(12),
        children: [
          _TitleRow(task: task),
          _StepsList(steps: steps),
          _AddStepField(taskId: task.id),
          const Divider(),
          _MyDaySwitch(task: task, now: now),
          _DueDateTile(task: task, now: now),
          _ReminderTile(task: task, now: now),
          _RepeatTile(task: task),
          if (list != null &&
              auth.signedIn &&
              (list.isShared || (list.ownerId != null && list.ownerId != myId)))
            _AssigneeTile(task: task, list: list),
          _MoveToListTile(task: task, lists: lists),
          const Divider(),
          // Keyed so the note keeps its draft and focus when the assignee
          // tile above it appears or disappears.
          _NoteField(key: ValueKey('note-${task.id}'), task: task),
          const SizedBox(height: 16),
          _DeleteTaskButton(taskId: task.id),
        ],
      ),
    );
  }
}

/// Completion checkbox, editable title and importance star.
class _TitleRow extends ConsumerWidget {
  const _TitleRow({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final repo = ref.read(repositoryProvider);
    return Row(
      children: [
        Checkbox(
          shape: const CircleBorder(),
          value: task.isCompleted,
          onChanged: (v) => repo.setCompleted(task.id, completed: v ?? false),
        ),
        Expanded(
          child: CommitTextField(
            key: Key('details-title-${task.id}'),
            value: task.title,
            maxLength: maxTitleLength,
            style: Theme.of(context).textTheme.titleMedium,
            onCommit: (v) {
              if (v.trim().isNotEmpty) repo.renameTask(task.id, v.trim());
            },
          ),
        ),
        IconButton(
          tooltip: l.important,
          icon: Icon(
            task.isImportant ? Icons.star : Icons.star_border,
            color: task.isImportant ? Colors.amber : null,
          ),
          onPressed: () =>
              repo.setImportant(task.id, important: !task.isImportant),
        ),
      ],
    );
  }
}

/// Steps of the task, finishable, deletable and reorderable (FR-3.7).
class _StepsList extends ConsumerWidget {
  const _StepsList({required this.steps});

  final List<TaskStep> steps;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final repo = ref.read(repositoryProvider);
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorder: (oldIndex, newIndex) {
        if (newIndex > oldIndex) newIndex -= 1;
        final ids = steps.map((s) => s.id).toList();
        ids.insert(newIndex, ids.removeAt(oldIndex));
        repo.reorderSteps(ids);
      },
      children: [
        for (var i = 0; i < steps.length; i++)
          ListTile(
            key: ValueKey('step-${steps[i].id}'),
            dense: true,
            leading: Checkbox(
              shape: const CircleBorder(),
              value: steps[i].isDone,
              onChanged: (v) => repo.setStepDone(steps[i].id, done: v ?? false),
            ),
            title: Text(
              steps[i].title,
              style: steps[i].isDone
                  ? const TextStyle(decoration: TextDecoration.lineThrough)
                  : null,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: l.delete,
                  onPressed: () => repo.deleteStep(steps[i].id),
                ),
                ReorderableDragStartListener(
                  index: i,
                  child: const Icon(Icons.drag_handle, size: 18),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Adds the task to or removes it from "My Day" (FR-4.1).
class _MyDaySwitch extends ConsumerWidget {
  const _MyDaySwitch({required this.task, required this.now});

  final Task task;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final inMyDay = isInMyDay(task, now);
    return SwitchListTile(
      key: const Key('my-day-switch'),
      secondary: const Icon(Icons.wb_sunny_outlined),
      title: Text(inMyDay ? l.removeFromMyDay : l.addToMyDay),
      value: inMyDay,
      onChanged: (v) =>
          ref.read(repositoryProvider).setMyDay(task.id, inMyDay: v),
    );
  }
}

/// Due date: pick with a date picker, clear with the close button (FR-3.4).
class _DueDateTile extends ConsumerWidget {
  const _DueDateTile({required this.task, required this.now});

  final Task task;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final repo = ref.read(repositoryProvider);
    final due = task.dueDate == null ? null : parseDateKey(task.dueDate!);
    return ListTile(
      key: const Key('due-tile'),
      leading: const Icon(Icons.event_outlined),
      title: Text(
        due == null ? l.addDueDate : DateFormat.yMMMEd(locale).format(due),
      ),
      trailing: due == null
          ? null
          : IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => repo.setDueDate(task.id, null),
            ),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: due ?? now,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) await repo.setDueDate(task.id, picked);
      },
    );
  }
}

/// Reminder: a date and then a time, clear with the close button (FR-3.5).
class _ReminderTile extends ConsumerWidget {
  const _ReminderTile({required this.task, required this.now});

  final Task task;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final repo = ref.read(repositoryProvider);
    return ListTile(
      key: const Key('reminder-tile'),
      leading: const Icon(Icons.notifications_none),
      title: Text(
        task.reminderAt == null
            ? l.addReminder
            : DateFormat.yMMMEd(locale).add_Hm().format(task.reminderAt!),
      ),
      trailing: task.reminderAt == null
          ? null
          : IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => repo.setReminder(task.id, null),
            ),
      onTap: () async {
        final at = await _pickDateTime(
          context,
          task.reminderAt ?? now.add(const Duration(hours: 1)),
        );
        if (at != null) await repo.setReminder(task.id, at);
      },
    );
  }
}

/// Shows a date picker and then a time picker; null if either is cancelled.
Future<DateTime?> _pickDateTime(BuildContext context, DateTime initial) async {
  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

/// Opens [RepeatDialog] (FR-3.6).
class _RepeatTile extends ConsumerWidget {
  const _RepeatTile({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final rule = RepeatRule.fromStorage(
      task.repeatType,
      task.repeatInterval,
      task.repeatDays,
    );
    return ListTile(
      key: const Key('repeat-tile'),
      leading: const Icon(Icons.repeat),
      title: Text(repeatLabel(l, rule.type)),
      onTap: () async {
        final repo = ref.read(repositoryProvider);
        final result = await showDialog<RepeatRule>(
          context: context,
          builder: (_) => RepeatDialog(initial: rule),
        );
        if (result != null) await repo.setRepeat(task.id, result);
      },
    );
  }
}

/// Moves the task to another list (FR-3.10).
class _MoveToListTile extends ConsumerWidget {
  const _MoveToListTile({required this.task, required this.lists});

  final Task task;
  final List<TaskList> lists;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return ListTile(
      leading: const Icon(Icons.drive_file_move_outline),
      title: Text(l.moveToList),
      trailing: DropdownButton<String>(
        key: const Key('move-list-dropdown'),
        value: lists.any((li) => li.id == task.listId) ? task.listId : null,
        items: [
          for (final li in lists)
            DropdownMenuItem(value: li.id, child: Text(li.name)),
        ],
        onChanged: (v) {
          if (v != null) ref.read(repositoryProvider).moveTask(task.id, v);
        },
      ),
    );
  }
}

/// Free-text note (FR-3.8).
class _NoteField extends ConsumerWidget {
  const _NoteField({required this.task, super.key});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return CommitTextField(
      key: Key('details-note-${task.id}'),
      value: task.note,
      maxLines: 6,
      decoration: InputDecoration(
        hintText: l.addNote,
        border: const OutlineInputBorder(),
      ),
      onCommit: (v) => ref.read(repositoryProvider).setNote(task.id, v),
    );
  }
}

/// Deletes the task and offers to undo it for 5 seconds (FR-3.12).
class _DeleteTaskButton extends ConsumerWidget {
  const _DeleteTaskButton({required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        key: const Key('delete-task'),
        icon: const Icon(Icons.delete_outline),
        label: Text(l.deleteTask),
        onPressed: () async {
          final repo = ref.read(repositoryProvider);
          final messenger = ScaffoldMessenger.of(context);
          final navigator = Navigator.of(context);
          final narrow = MediaQuery.sizeOf(context).width < wideBreakpoint;
          await repo.deleteTask(taskId);
          ref.read(selectedTaskIdProvider.notifier).state = null;
          if (navigator.canPop() && narrow) navigator.pop();
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(l.taskDeleted),
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: l.undo,
                  onPressed: () => repo.restoreTask(taskId),
                ),
              ),
            );
        },
      ),
    );
  }
}

class _AddStepField extends ConsumerStatefulWidget {
  const _AddStepField({required this.taskId});

  final String taskId;

  @override
  ConsumerState<_AddStepField> createState() => _AddStepFieldState();
}

class _AddStepFieldState extends ConsumerState<_AddStepField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return TextField(
      key: const Key('add-step'),
      controller: _controller,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.add),
        hintText: l.addStep,
        border: InputBorder.none,
      ),
      onSubmitted: (v) async {
        await ref.read(repositoryProvider).addStep(widget.taskId, v);
        if (!mounted) return;
        _controller.clear();
      },
    );
  }
}

class _AssigneeTile extends ConsumerWidget {
  const _AssigneeTile({required this.task, required this.list});

  final Task task;
  final TaskList list;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final members = ref.watch(listMembersProvider(list.id)).valueOrNull ??
        const <ListMember>[];
    final value = members.any((m) => m.userId == task.assigneeId)
        ? task.assigneeId
        : null;
    return ListTile(
      leading: const Icon(Icons.person_add_alt_outlined),
      title: Text(l.assignTo),
      trailing: DropdownButton<String?>(
        key: const Key('assignee-dropdown'),
        value: value,
        hint: Text(l.unassigned),
        items: [
          DropdownMenuItem<String?>(child: Text(l.unassigned)),
          for (final m in members)
            DropdownMenuItem<String?>(value: m.userId, child: Text(m.name)),
        ],
        onChanged: (v) => ref.read(repositoryProvider).setAssignee(task.id, v),
      ),
    );
  }
}

/// Dialog to choose a repeat rule (FR-3.6).
class RepeatDialog extends StatefulWidget {
  const RepeatDialog({required this.initial, super.key});

  final RepeatRule initial;

  @override
  State<RepeatDialog> createState() => _RepeatDialogState();
}

class _RepeatDialogState extends State<RepeatDialog> {
  late RepeatType _type = widget.initial.type;
  late int _interval = widget.initial.interval;
  late int _mask = widget.initial.weekdayMask;

  bool get _usesInterval => const {
        RepeatType.daily,
        RepeatType.weekly,
        RepeatType.monthly,
        RepeatType.yearly,
        RepeatType.custom,
      }.contains(_type);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    // 2025-01-06 is a Monday.
    final weekdayNames = [
      for (var i = 0; i < 7; i++)
        DateFormat.E(locale).format(DateTime(2025, 1, 6 + i)),
    ];
    return AlertDialog(
      title: Text(l.repeat),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButton<RepeatType>(
              key: const Key('repeat-type'),
              value: _type,
              isExpanded: true,
              items: [
                for (final t in RepeatType.values)
                  DropdownMenuItem(value: t, child: Text(repeatLabel(l, t))),
              ],
              onChanged: (v) => setState(() => _type = v ?? RepeatType.none),
            ),
            if (_usesInterval)
              Row(
                children: [
                  Text(l.repeatEvery),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: _interval > 1
                        ? () => setState(() => _interval--)
                        : null,
                  ),
                  Text('$_interval', key: const Key('repeat-interval')),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => setState(() => _interval++),
                  ),
                ],
              ),
            if (_type == RepeatType.weekly)
              Wrap(
                spacing: 4,
                children: [
                  for (var i = 0; i < 7; i++)
                    FilterChip(
                      label: Text(weekdayNames[i]),
                      selected: _mask & (1 << i) != 0,
                      onSelected: (v) => setState(() {
                        _mask = v ? _mask | (1 << i) : _mask & ~(1 << i);
                      }),
                    ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('repeat-save'),
          onPressed: () => Navigator.pop(
            context,
            RepeatRule(
              _type,
              interval: _usesInterval ? _interval : 1,
              weekdayMask: _type == RepeatType.weekly ? _mask : 0,
            ),
          ),
          child: Text(l.save),
        ),
      ],
    );
  }
}

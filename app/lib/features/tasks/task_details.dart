import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:future_todo/core/dates.dart';
import 'package:future_todo/data/db/database.dart';
import 'package:future_todo/data/remote/remote_api.dart';
import 'package:future_todo/domain/repeat.dart';
import 'package:future_todo/features/common/labels.dart';
import 'package:future_todo/features/common/widgets.dart';
import 'package:future_todo/features/sharing/share_dialog.dart';
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

    final repo = ref.read(repositoryProvider);
    final lists = ref.watch(listsProvider).valueOrNull ?? const <TaskList>[];
    final steps = (ref.watch(stepsProvider).valueOrNull ?? const <TaskStep>[])
        .where((s) => s.taskId == taskId)
        .toList();
    final now = ref.watch(todayProvider).valueOrNull ?? DateTime.now();
    final locale = Localizations.localeOf(context).toString();
    final inMyDay = task.myDayDate == dateKey(now);
    final rule = RepeatRule.fromStorage(
      task.repeatType,
      task.repeatInterval,
      task.repeatDays,
    );
    final list = lists.where((li) => li.id == task.listId).firstOrNull;
    final signedIn = ref.watch(authProvider).signedIn;
    final myId = ref.watch(authProvider).user?.id;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: ListView(
        key: const Key('task-details'),
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              Checkbox(
                shape: const CircleBorder(),
                value: task.isCompleted,
                onChanged: (v) =>
                    repo.setCompleted(task.id, completed: v ?? false),
              ),
              Expanded(
                child: CommitTextField(
                  key: Key('details-title-${task.id}'),
                  value: task.title,
                  maxLength: 255,
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
          ),
          // Steps (FR-3.7)
          ReorderableListView(
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
                    onChanged: (v) =>
                        repo.setStepDone(steps[i].id, done: v ?? false),
                  ),
                  title: Text(
                    steps[i].title,
                    style: steps[i].isDone
                        ? const TextStyle(
                            decoration: TextDecoration.lineThrough,
                          )
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
          ),
          _AddStepField(taskId: task.id),
          const Divider(),
          SwitchListTile(
            key: const Key('my-day-switch'),
            secondary: const Icon(Icons.wb_sunny_outlined),
            title: Text(inMyDay ? l.removeFromMyDay : l.addToMyDay),
            value: inMyDay,
            onChanged: (v) => repo.setMyDay(task.id, inMyDay: v),
          ),
          ListTile(
            key: const Key('due-tile'),
            leading: const Icon(Icons.event_outlined),
            title: Text(
              task.dueDate == null
                  ? l.addDueDate
                  : DateFormat.yMMMEd(locale).format(parseDateKey(task.dueDate!)),
            ),
            trailing: task.dueDate == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => repo.setDueDate(task.id, null),
                  ),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: task.dueDate == null
                    ? now
                    : parseDateKey(task.dueDate!),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) await repo.setDueDate(task.id, picked);
            },
          ),
          ListTile(
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
              final base = task.reminderAt ?? now.add(const Duration(hours: 1));
              final date = await showDatePicker(
                context: context,
                initialDate: base,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (date == null || !context.mounted) return;
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(base),
              );
              if (time == null) return;
              await repo.setReminder(
                task.id,
                DateTime(date.year, date.month, date.day, time.hour, time.minute),
              );
            },
          ),
          ListTile(
            key: const Key('repeat-tile'),
            leading: const Icon(Icons.repeat),
            title: Text(repeatLabel(l, rule.type)),
            onTap: () async {
              final result = await showDialog<RepeatRule>(
                context: context,
                builder: (_) => RepeatDialog(initial: rule),
              );
              if (result != null) await repo.setRepeat(task.id, result);
            },
          ),
          if (list != null &&
              signedIn &&
              (list.isShared || (list.ownerId != null && list.ownerId != myId)))
            _AssigneeTile(task: task, list: list),
          ListTile(
            leading: const Icon(Icons.drive_file_move_outline),
            title: Text(l.moveToList),
            trailing: DropdownButton<String>(
              key: const Key('move-list-dropdown'),
              value: lists.any((li) => li.id == task.listId)
                  ? task.listId
                  : null,
              items: [
                for (final li in lists)
                  DropdownMenuItem(value: li.id, child: Text(li.name)),
              ],
              onChanged: (v) {
                if (v != null) repo.moveTask(task.id, v);
              },
            ),
          ),
          const Divider(),
          CommitTextField(
            key: Key('details-note-${task.id}'),
            value: task.note,
            maxLines: 6,
            decoration: InputDecoration(
              hintText: l.addNote,
              border: const OutlineInputBorder(),
            ),
            onCommit: (v) => repo.setNote(task.id, v),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const Key('delete-task'),
              icon: const Icon(Icons.delete_outline),
              label: Text(l.deleteTask),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await repo.deleteTask(task.id);
                ref.read(selectedTaskIdProvider.notifier).state = null;
                if (Navigator.of(context).canPop() &&
                    MediaQuery.sizeOf(context).width < 1000) {
                  Navigator.of(context).pop();
                }
                // Undo within 5 seconds (FR-3.12).
                messenger
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(l.taskDeleted),
                      duration: const Duration(seconds: 5),
                      action: SnackBarAction(
                        label: l.undo,
                        onPressed: () => repo.restoreTask(task.id),
                      ),
                    ),
                  );
              },
            ),
          ),
        ],
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

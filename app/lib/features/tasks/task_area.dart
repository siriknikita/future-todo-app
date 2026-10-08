import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:future_todo/core/dates.dart';
import 'package:future_todo/data/db/database.dart';
import 'package:future_todo/domain/search.dart';
import 'package:future_todo/domain/smart_lists.dart';
import 'package:future_todo/domain/sorting.dart';
import 'package:future_todo/features/common/labels.dart';
import 'package:future_todo/features/tasks/task_tile.dart';
import 'package:future_todo/l10n/app_localizations.dart';
import 'package:future_todo/providers.dart';

/// Main area: header with sort / hide-completed, quick add, task list.
class TaskArea extends ConsumerWidget {
  const TaskArea({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final view = ref.watch(selectedViewProvider);
    final query = ref.watch(searchQueryProvider);
    final settings = ref.watch(settingsProvider);
    final now = ref.watch(todayProvider).valueOrNull ?? DateTime.now();
    final lists = ref.watch(listsProvider).valueOrNull ?? const <TaskList>[];
    final tasks = ref.watch(tasksProvider).valueOrNull ?? const <Task>[];
    final steps = ref.watch(stepsProvider).valueOrNull ?? const <TaskStep>[];
    final userId = ref.watch(authProvider).user?.id;
    final listNames = {for (final li in lists) li.id: li.name};

    final searching = query.trim().isNotEmpty;
    final includeCompleted = ref.watch(searchIncludeCompletedProvider);

    String title;
    List<Task> visible;
    var showListNames = true;
    if (searching) {
      title = l.searchResults;
      visible = searchTasks(
        tasks: tasks,
        steps: steps,
        query: query,
        includeCompleted: includeCompleted,
      );
    } else if (view.smart != null) {
      title = smartListLabel(l, view.smart!);
      visible = filterSmartList(
        view.smart!,
        tasks,
        now: now,
        currentUserId: userId,
      );
    } else {
      final list = lists.where((li) => li.id == view.listId).firstOrNull;
      title = list?.name ?? '';
      visible = tasks.where((t) => t.listId == view.listId).toList();
      showListNames = false;
    }

    final sorted = sortTasks(visible, settings.sortMode);
    final open = sorted.where((t) => !t.isCompleted).toList();
    final done = sorted.where((t) => t.isCompleted).toList();
    final showDone =
        !settings.hideCompleted && view.smart != SmartList.completed;

    Widget tile(Task t) => TaskTile(
          task: t,
          listName: showListNames ? listNames[t.listId] : null,
        );

    final children = <Widget>[];
    if (!searching && view.smart == SmartList.planned) {
      final grouped = groupPlanned(
        settings.hideCompleted ? sorted.where((t) => !t.isCompleted) : sorted,
        now,
      );
      for (final entry in grouped.entries) {
        if (entry.value.isEmpty) continue;
        children
          ..add(_SectionHeader(bucketLabel(l, entry.key)))
          ..addAll(entry.value.map(tile));
      }
    } else {
      children.addAll(open.map(tile));
      if (showDone && done.isNotEmpty) {
        children
          ..add(_SectionHeader('${l.completed} (${done.length})'))
          ..addAll(done.map(tile));
      } else if (view.smart == SmartList.completed) {
        children.addAll(done.map(tile));
      }
    }

    if (!searching && view.smart == SmartList.myDay) {
      final suggestions = suggestForMyDay(tasks, now);
      if (suggestions.isNotEmpty) {
        children
          ..add(_SectionHeader(l.suggestions))
          ..addAll(
            suggestions.map(
              (t) => TaskTile(
                task: t,
                listName: listNames[t.listId],
                trailing: IconButton(
                  key: Key('suggest-add-${t.id}'),
                  tooltip: l.addToMyDay,
                  icon: const Icon(Icons.add),
                  onPressed: () => ref
                      .read(repositoryProvider)
                      .setMyDay(t.id, inMyDay: true),
                ),
              ),
            ),
          );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  key: const Key('area-title'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              if (searching)
                FilterChip(
                  key: const Key('search-include-completed'),
                  label: Text(l.includeCompleted),
                  selected: includeCompleted,
                  onSelected: (v) => ref
                      .read(searchIncludeCompletedProvider.notifier)
                      .state = v,
                )
              else ...[
                PopupMenuButton<SortMode>(
                  key: const Key('sort-menu'),
                  tooltip: l.sortBy,
                  icon: const Icon(Icons.sort),
                  initialValue: settings.sortMode,
                  onSelected: (m) =>
                      ref.read(settingsProvider.notifier).setSortMode(m),
                  itemBuilder: (_) => [
                    for (final m in SortMode.values)
                      PopupMenuItem(value: m, child: Text(sortLabel(l, m))),
                  ],
                ),
                IconButton(
                  key: const Key('toggle-completed'),
                  tooltip: settings.hideCompleted
                      ? l.showCompleted
                      : l.hideCompleted,
                  icon: Icon(
                    settings.hideCompleted
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () => ref
                      .read(settingsProvider.notifier)
                      .setHideCompleted(hide: !settings.hideCompleted),
                ),
              ],
            ],
          ),
        ),
        if (!searching &&
            view.smart != SmartList.assignedToMe &&
            view.smart != SmartList.completed)
          _QuickAdd(view: view),
        Expanded(
          child: children.isEmpty
              ? Center(child: Text(l.emptyTasks))
              : ListView(key: const Key('task-list'), children: children),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}

/// Quick add (FR-3.1): type a title and press Enter.
class _QuickAdd extends ConsumerStatefulWidget {
  const _QuickAdd({required this.view});

  final ViewSelection view;

  @override
  ConsumerState<_QuickAdd> createState() => _QuickAddState();
}

class _QuickAddState extends ConsumerState<_QuickAdd> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit(String text) async {
    if (text.trim().isEmpty) return;
    final repo = ref.read(repositoryProvider);
    final l = AppLocalizations.of(context);
    final view = widget.view;
    final userId = ref.read(authProvider).user?.id;

    var listId = view.listId;
    if (listId == null) {
      // Smart lists add to the first list, creating a default one if needed.
      final lists = ref.read(listsProvider).valueOrNull ?? const <TaskList>[];
      listId = lists.isNotEmpty
          ? lists.first.id
          : await repo.createList(l.defaultListName, ownerId: userId);
    }
    final now = ref.read(todayProvider).valueOrNull ?? DateTime.now();
    await repo.createTask(
      listId,
      text,
      inMyDay: view.smart == SmartList.myDay,
      important: view.smart == SmartList.important,
      dueDate: view.smart == SmartList.planned ? dateKey(now) : null,
    );
    _controller.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        key: const Key('quick-add'),
        controller: _controller,
        focusNode: _focus,
        inputFormatters: [LengthLimitingTextInputFormatter(255)],
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.add),
          hintText: l.addTask,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: _submit,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:future_todo/data/db/database.dart';
import 'package:future_todo/domain/smart_lists.dart';
import 'package:future_todo/features/common/labels.dart';
import 'package:future_todo/features/common/widgets.dart';
import 'package:future_todo/features/settings/settings_dialog.dart';
import 'package:future_todo/features/sharing/share_dialog.dart';
import 'package:future_todo/l10n/app_localizations.dart';
import 'package:future_todo/providers.dart';
import 'package:go_router/go_router.dart';

/// Either a group or a list shown at the top level of the sidebar.
class _TopItem {
  _TopItem.group(ListGroup this.group)
      : list = null,
        position = group.position;
  _TopItem.list(TaskList this.list)
      : group = null,
        position = list.position;

  final ListGroup? group;
  final TaskList? list;
  final double position;

  String get id => group?.id ?? list!.id;
}

class Sidebar extends ConsumerWidget {
  const Sidebar({super.key, this.onSelected});

  /// Called after the user picks a view (used to close the drawer).
  final VoidCallback? onSelected;

  void _select(WidgetRef ref, ViewSelection view) {
    ref.read(selectedViewProvider.notifier).state = view;
    ref.read(selectedTaskIdProvider.notifier).state = null;
    ref.read(searchQueryProvider.notifier).state = '';
    onSelected?.call();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final selected = ref.watch(selectedViewProvider);
    final lists = ref.watch(listsProvider).valueOrNull ?? const <TaskList>[];
    final groups = ref.watch(groupsProvider).valueOrNull ?? const <ListGroup>[];
    final tasks = ref.watch(tasksProvider).valueOrNull ?? const <Task>[];
    final signedIn = ref.watch(authProvider).signedIn;
    final repo = ref.read(repositoryProvider);

    final top = <_TopItem>[
      for (final g in groups) _TopItem.group(g),
      for (final li in lists.where((li) => li.groupId == null))
        _TopItem.list(li),
    ]..sort((a, b) => a.position.compareTo(b.position));

    int openCount(String listId) =>
        tasks.where((t) => t.listId == listId && !t.isCompleted).length;

    Widget listTile(TaskList list, {double indent = 0}) => ListTile(
          key: ValueKey('list-${list.id}'),
          contentPadding: EdgeInsets.only(left: 16 + indent, right: 4),
          dense: true,
          selected: selected.listId == list.id,
          leading: list.icon != null
              ? Text(list.icon!, style: const TextStyle(fontSize: 20))
              : Icon(list.isShared ? Icons.people_outline : Icons.list),
          title: Text(list.name, overflow: TextOverflow.ellipsis),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${openCount(list.id)}'),
              _ListMenu(list: list, groups: groups),
            ],
          ),
          onTap: () => _select(ref, ViewSelection.list(list.id)),
        );

    Widget groupTile(ListGroup group) {
      final children = lists.where((li) => li.groupId == group.id).toList();
      return ExpansionTile(
        key: ValueKey('group-${group.id}'),
        initiallyExpanded: true,
        leading: const Icon(Icons.folder_outlined),
        title: Row(
          children: [
            Expanded(child: Text(group.name, overflow: TextOverflow.ellipsis)),
            PopupMenuButton<String>(
              tooltip: '',
              onSelected: (v) async {
                if (v == 'rename') {
                  final name = await promptText(
                    context,
                    title: l.rename,
                    initial: group.name,
                  );
                  if (name != null) await repo.renameGroup(group.id, name);
                } else {
                  await repo.ungroup(group.id);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'rename', child: Text(l.rename)),
                PopupMenuItem(value: 'ungroup', child: Text(l.ungroup)),
              ],
            ),
          ],
        ),
        children: [for (final li in children) listTile(li, indent: 16)],
      );
    }

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.appTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const SyncIndicatorIcon(),
                  IconButton(
                    key: const Key('open-settings'),
                    tooltip: l.settings,
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => showSettingsDialog(context),
                  ),
                  IconButton(
                    key: const Key('open-account'),
                    tooltip: signedIn ? l.profile : l.signIn,
                    icon: Icon(
                      signedIn ? Icons.account_circle : Icons.login,
                    ),
                    onPressed: () =>
                        context.push(signedIn ? '/profile' : '/login'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: TextField(
                key: const Key('search-field'),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search),
                  hintText: l.search,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) =>
                    ref.read(searchQueryProvider.notifier).state = v,
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final s in SmartList.values)
                    ListTile(
                      key: ValueKey('smart-${s.name}'),
                      dense: true,
                      selected: selected.smart == s,
                      leading: Icon(smartListIcon(s)),
                      title: Text(smartListLabel(l, s)),
                      onTap: () => _select(ref, ViewSelection.smart(s)),
                    ),
                  const Divider(),
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: top.length,
                    onReorder: (oldIndex, newIndex) {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final ids = top.map((e) => e.id).toList();
                      ids.insert(newIndex, ids.removeAt(oldIndex));
                      repo.reorderSidebar(
                        ids: ids,
                        groupIds: {for (final g in groups) g.id},
                      );
                    },
                    itemBuilder: (context, i) {
                      final item = top[i];
                      return ReorderableDelayedDragStartListener(
                        key: ValueKey('top-${item.id}'),
                        index: i,
                        child: item.group != null
                            ? groupTile(item.group!)
                            : listTile(item.list!),
                      );
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    key: const Key('new-list'),
                    icon: const Icon(Icons.add),
                    label: Text(l.newList),
                    onPressed: () async {
                      final name = await promptText(
                        context,
                        title: l.newList,
                        hint: l.listName,
                      );
                      if (name == null) return;
                      final id = await repo.createList(
                        name,
                        ownerId: ref.read(authProvider).user?.id,
                      );
                      _select(ref, ViewSelection.list(id));
                    },
                  ),
                ),
                IconButton(
                  key: const Key('new-group'),
                  tooltip: l.newGroup,
                  icon: const Icon(Icons.create_new_folder_outlined),
                  onPressed: () async {
                    final name = await promptText(
                      context,
                      title: l.newGroup,
                      hint: l.groupName,
                    );
                    if (name != null) await repo.createGroup(name);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ListMenu extends ConsumerWidget {
  const _ListMenu({required this.list, required this.groups});

  final TaskList list;
  final List<ListGroup> groups;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final repo = ref.read(repositoryProvider);
    return PopupMenuButton<String>(
      key: Key('list-menu-${list.id}'),
      tooltip: '',
      onSelected: (v) async {
        switch (v) {
          case 'rename':
            final name =
                await promptText(context, title: l.rename, initial: list.name);
            if (name != null) await repo.renameList(list.id, name);
          case 'icon':
            final icon = await promptText(
              context,
              title: l.listIcon,
              initial: list.icon ?? '',
              maxLength: 8,
            );
            if (icon != null) await repo.setListIcon(list.id, icon);
          case 'group':
            if (!context.mounted) return;
            final choice = await _pickGroup(context);
            if (choice != null) {
              await repo.moveListToGroup(
                list.id,
                choice == '' ? null : choice,
              );
            }
          case 'share':
            if (!context.mounted) return;
            await showShareDialog(context, list);
          case 'delete':
            if (!context.mounted) return;
            final ok = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(l.deleteListQuestion(list.name)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(l.cancel),
                  ),
                  FilledButton(
                    key: const Key('confirm-delete-list'),
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(l.delete),
                  ),
                ],
              ),
            );
            if (ok ?? false) {
              await repo.deleteList(list.id);
              final sel = ref.read(selectedViewProvider);
              if (sel.listId == list.id) {
                ref.read(selectedViewProvider.notifier).state =
                    const ViewSelection.smart(SmartList.myDay);
              }
            }
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'rename', child: Text(l.rename)),
        PopupMenuItem(value: 'icon', child: Text(l.listIcon)),
        PopupMenuItem(value: 'group', child: Text(l.moveToGroup)),
        PopupMenuItem(value: 'share', child: Text(l.share)),
        PopupMenuItem(
          key: Key('delete-list-${list.id}'),
          value: 'delete',
          child: Text(l.delete),
        ),
      ],
    );
  }

  /// Returns a group id, `''` for "no group", or null when cancelled.
  Future<String?> _pickGroup(BuildContext context) {
    final l = AppLocalizations.of(context);
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l.moveToGroup),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, ''),
            child: Text(l.noGroup),
          ),
          for (final g in groups)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, g.id),
              child: Text(g.name),
            ),
        ],
      ),
    );
  }
}

/// Sync state icon (FR-8.4): synced, pending, error, or local-only guest.
class SyncIndicatorIcon extends ConsumerWidget {
  const SyncIndicatorIcon({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final state = ref.watch(syncIndicatorProvider);
    final (icon, label) = switch (state) {
      SyncIndicator.guest => (Icons.cloud_off_outlined, l.syncGuest),
      SyncIndicator.synced => (Icons.cloud_done_outlined, l.syncSynced),
      SyncIndicator.pending => (Icons.cloud_upload_outlined, l.syncPending),
      SyncIndicator.error => (Icons.error_outline, l.syncError),
    };
    return Tooltip(
      message: label,
      child: Icon(
        icon,
        key: Key('sync-${state.name}'),
        semanticLabel: label,
      ),
    );
  }
}

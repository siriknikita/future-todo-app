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
    final repo = ref.read(repositoryProvider);
    void select(ViewSelection view) => _select(ref, view);

    final top = <_TopItem>[
      for (final g in groups) _TopItem.group(g),
      for (final li in lists.where((li) => li.groupId == null))
        _TopItem.list(li),
    ]..sort((a, b) => a.position.compareTo(b.position));

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SafeArea(
        child: Column(
          children: [
            const _SidebarHeader(),
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
                      onTap: () => select(ViewSelection.smart(s)),
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
                            ? _GroupTile(
                                group: item.group!,
                                lists: [
                                  for (final li in lists)
                                    if (li.groupId == item.group!.id) li,
                                ],
                                groups: groups,
                                onSelect: select,
                              )
                            : _ListTile(
                                list: item.list!,
                                groups: groups,
                                onSelect: select,
                              ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            _SidebarFooter(onSelect: select),
          ],
        ),
      ),
    );
  }
}

/// App title, sync state, settings and account buttons.
class _SidebarHeader extends ConsumerWidget {
  const _SidebarHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final signedIn = ref.watch(authProvider).signedIn;
    return Padding(
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
            icon: Icon(signedIn ? Icons.account_circle : Icons.login),
            onPressed: () => context.push(signedIn ? '/profile' : '/login'),
          ),
        ],
      ),
    );
  }
}

/// "New list" and "New group" buttons.
class _SidebarFooter extends ConsumerWidget {
  const _SidebarFooter({required this.onSelect});

  final ValueChanged<ViewSelection> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final repo = ref.read(repositoryProvider);
    return Row(
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
              onSelect(ViewSelection.list(id));
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
    );
  }
}

/// One list: icon, name, number of open tasks and its menu.
class _ListTile extends ConsumerWidget {
  const _ListTile({
    required this.list,
    required this.groups,
    required this.onSelect,
    this.indent = 0,
  });

  final TaskList list;
  final List<ListGroup> groups;
  final ValueChanged<ViewSelection> onSelect;
  final double indent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedViewProvider).listId == list.id;
    final tasks = ref.watch(tasksProvider).valueOrNull ?? const <Task>[];
    final openCount =
        tasks.where((t) => t.listId == list.id && !t.isCompleted).length;
    return ListTile(
      key: ValueKey('list-${list.id}'),
      contentPadding: EdgeInsets.only(left: 16 + indent, right: 4),
      dense: true,
      selected: selected,
      leading: list.icon != null
          ? Text(list.icon!, style: const TextStyle(fontSize: 20))
          : Icon(list.isShared ? Icons.people_outline : Icons.list),
      title: Text(list.name, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$openCount'),
          _ListMenu(list: list, groups: groups),
        ],
      ),
      onTap: () => onSelect(ViewSelection.list(list.id)),
    );
  }
}

enum _GroupAction { rename, ungroup }

/// A group of lists (FR-2.3), expanded, with its rename/ungroup menu.
class _GroupTile extends ConsumerWidget {
  const _GroupTile({
    required this.group,
    required this.lists,
    required this.groups,
    required this.onSelect,
  });

  final ListGroup group;

  /// The lists in this group.
  final List<TaskList> lists;
  final List<ListGroup> groups;
  final ValueChanged<ViewSelection> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final repo = ref.read(repositoryProvider);
    return ExpansionTile(
      key: ValueKey('group-${group.id}'),
      initiallyExpanded: true,
      leading: const Icon(Icons.folder_outlined),
      title: Row(
        children: [
          Expanded(child: Text(group.name, overflow: TextOverflow.ellipsis)),
          _ActionMenu<_GroupAction>(
            actions: _GroupAction.values,
            label: (action) => switch (action) {
              _GroupAction.rename => l.rename,
              _GroupAction.ungroup => l.ungroup,
            },
            onSelected: (action) async {
              switch (action) {
                case _GroupAction.rename:
                  final name = await promptText(
                    context,
                    title: l.rename,
                    initial: group.name,
                  );
                  if (name != null) await repo.renameGroup(group.id, name);
                case _GroupAction.ungroup:
                  await repo.ungroup(group.id);
              }
            },
          ),
        ],
      ),
      children: [
        for (final li in lists)
          _ListTile(list: li, groups: groups, onSelect: onSelect, indent: 16),
      ],
    );
  }
}

/// The "more" popup menu of a sidebar item, with one entry per action.
class _ActionMenu<T extends Enum> extends StatelessWidget {
  const _ActionMenu({
    required this.actions,
    required this.label,
    required this.onSelected,
    this.menuKey,
    this.itemKey,
  });

  final List<T> actions;
  final String Function(T action) label;
  final void Function(T action) onSelected;

  /// Key of the menu button itself.
  final Key? menuKey;
  final Key? Function(T action)? itemKey;

  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
        key: menuKey,
        // An empty tooltip turns off the default "Show menu" tooltip, which
        // would otherwise pop up over the sidebar rows.
        tooltip: '',
        onSelected: onSelected,
        itemBuilder: (_) => [
          for (final action in actions)
            PopupMenuItem(
              key: itemKey?.call(action),
              value: action,
              child: Text(label(action)),
            ),
        ],
      );
}

enum _ListAction { rename, icon, group, share, delete }

class _ListMenu extends ConsumerWidget {
  const _ListMenu({required this.list, required this.groups});

  final TaskList list;
  final List<ListGroup> groups;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final repo = ref.read(repositoryProvider);
    return _ActionMenu<_ListAction>(
      menuKey: Key('list-menu-${list.id}'),
      actions: _ListAction.values,
      label: (action) => switch (action) {
        _ListAction.rename => l.rename,
        _ListAction.icon => l.listIcon,
        _ListAction.group => l.moveToGroup,
        _ListAction.share => l.share,
        _ListAction.delete => l.delete,
      },
      itemKey: (action) =>
          action == _ListAction.delete ? Key('delete-list-${list.id}') : null,
      onSelected: (action) async {
        switch (action) {
          case _ListAction.rename:
            final name =
                await promptText(context, title: l.rename, initial: list.name);
            if (name != null) await repo.renameList(list.id, name);
          case _ListAction.icon:
            final icon = await promptText(
              context,
              title: l.listIcon,
              initial: list.icon ?? '',
              maxLength: 8,
            );
            if (icon != null) await repo.setListIcon(list.id, icon);
          case _ListAction.group:
            if (!context.mounted) return;
            final choice = await _pickGroup(context);
            if (choice != null) {
              await repo.moveListToGroup(
                list.id,
                choice == '' ? null : choice,
              );
            }
          case _ListAction.share:
            if (!context.mounted) return;
            await showShareDialog(context, list);
          case _ListAction.delete:
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

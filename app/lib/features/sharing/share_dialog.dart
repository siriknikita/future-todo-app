import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:future_todo/data/db/database.dart';
import 'package:future_todo/data/remote/remote_api.dart';
import 'package:future_todo/features/common/widgets.dart';
import 'package:future_todo/l10n/app_localizations.dart';
import 'package:future_todo/providers.dart';

Future<void> showShareDialog(BuildContext context, TaskList list) =>
    showDialog<void>(
      context: context,
      builder: (_) => ShareDialog(list: list),
    );

/// Members of a shared list. They are read from the server on demand: the
/// local schema has no members table yet (deviation from "UI reads only the
/// local DB", see report).
final listMembersProvider =
    FutureProvider.family.autoDispose<List<ListMember>, String>(
  (ref, listId) => ref.watch(remoteApiProvider).listMembers(listId),
);

/// Sharing UI: invitation link (FR-5.1), revoking old links (FR-5.2),
/// participants (FR-5.3) and removing / leaving (FR-5.5).
class ShareDialog extends ConsumerStatefulWidget {
  const ShareDialog({required this.list, super.key});

  final TaskList list;

  @override
  ConsumerState<ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends ConsumerState<ShareDialog> {
  String? _link;

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on Object catch (e) {
      if (mounted) showMessage(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final auth = ref.watch(authProvider);
    final api = ref.read(remoteApiProvider);
    final repo = ref.read(repositoryProvider);
    final list = widget.list;

    if (!auth.signedIn) {
      return AlertDialog(
        title: Text(l.share),
        content: Text(l.signInToShare),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.close),
          ),
        ],
      );
    }

    final isOwner = list.ownerId == null || list.ownerId == auth.user!.id;
    final members = ref.watch(listMembersProvider(list.id));

    return AlertDialog(
      title: Text(l.shareList(list.name)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isOwner) ...[
                FilledButton.icon(
                  key: const Key('create-invite'),
                  icon: const Icon(Icons.link),
                  label: Text(l.createInviteLink),
                  onPressed: () => _run(() async {
                    final token = await api.createInvitation(list.id);
                    await repo.setListShared(list.id, shared: true);
                    setState(() => _link = '${Uri.base.origin}/join/$token');
                  }),
                ),
                if (_link != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: SelectableText(_link!),
                    trailing: IconButton(
                      tooltip: l.copy,
                      icon: const Icon(Icons.copy),
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: _link!)),
                    ),
                  ),
                TextButton(
                  key: const Key('revoke-invites'),
                  onPressed: () => _run(() async {
                    await api.revokeInvitations(list.id);
                    setState(() => _link = null);
                    if (context.mounted) showMessage(context, l.linksRevoked);
                  }),
                  child: Text(l.revokeLinks),
                ),
              ],
              const Divider(),
              Text(l.members, style: Theme.of(context).textTheme.titleSmall),
              members.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text(e.toString()),
                data: (items) => Column(
                  children: [
                    for (final m in items)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.person_outline),
                        title: Text(m.name),
                        subtitle: m.isOwner ? Text(l.owner) : null,
                        trailing: isOwner && !m.isOwner
                            ? IconButton(
                                tooltip: l.removeMember,
                                icon: const Icon(Icons.person_remove_outlined),
                                onPressed: () => _run(() async {
                                  await api.removeMember(list.id, m.userId);
                                  ref.invalidate(listMembersProvider(list.id));
                                }),
                              )
                            : null,
                      ),
                  ],
                ),
              ),
              if (!isOwner)
                TextButton(
                  key: const Key('leave-list'),
                  onPressed: () => _run(() async {
                    await api.removeMember(list.id, auth.user!.id);
                    await ref.read(syncServiceProvider).syncNow();
                    if (context.mounted) Navigator.pop(context);
                  }),
                  child: Text(l.leaveList),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.close),
        ),
      ],
    );
  }
}

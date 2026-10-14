import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:future_todo/data/db/database.dart';
import 'package:future_todo/features/common/widgets.dart';
import 'package:future_todo/l10n/app_localizations.dart';
import 'package:future_todo/providers.dart';

Future<void> showShareDialog(BuildContext context, TaskList list) =>
    showDialog<void>(
      context: context,
      builder: (_) => ShareDialog(list: list),
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
    final sharing = ref.read(sharingServiceProvider);
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
                    final link = await sharing.createInviteLink(list.id);
                    if (!context.mounted) return;
                    setState(() => _link = link);
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
                    await sharing.revokeInvites(list.id);
                    if (!context.mounted) return;
                    setState(() => _link = null);
                    showMessage(context, l.linksRevoked);
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
                                  await sharing.removeMember(
                                    list.id,
                                    m.userId,
                                  );
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
                    await sharing.leaveList(list.id, auth.user!.id);
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

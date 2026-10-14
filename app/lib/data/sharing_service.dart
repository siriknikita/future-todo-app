import 'package:future_todo/data/remote/remote_api.dart';
import 'package:future_todo/data/repository.dart';
import 'package:future_todo/data/sync/sync_service.dart';

/// Sharing operations (FR-5.x). They need the server, so the UI goes through
/// this service instead of calling [RemoteApi] itself.
class SharingService {
  SharingService({
    required this.remote,
    required this.repository,
    required this.sync,
    String Function()? origin,
  }) : _origin = origin ?? (() => Uri.base.origin);

  final RemoteApi remote;
  final TodoRepository repository;
  final SyncService sync;

  /// Origin the invitation link points to (the web app's own origin).
  final String Function() _origin;

  /// Members of a shared list, read from the server: the local schema has no
  /// members table yet (FR-5.3).
  Future<List<ListMember>> members(String listId) => remote.listMembers(listId);

  /// Creates an invitation, marks the list as shared and returns the link
  /// to send (FR-5.1).
  Future<String> createInviteLink(String listId) async {
    final token = await remote.createInvitation(listId);
    await repository.setListShared(listId, shared: true);
    return '${_origin()}/join/$token';
  }

  /// Makes every earlier invitation link stop working (FR-5.2).
  Future<void> revokeInvites(String listId) => remote.revokeInvitations(listId);

  /// The owner removes another member (FR-5.5).
  Future<void> removeMember(String listId, String userId) =>
      remote.removeMember(listId, userId);

  /// The current user leaves a list shared with them (FR-5.5); the sync
  /// then removes the list locally.
  Future<void> leaveList(String listId, String userId) async {
    await remote.removeMember(listId, userId);
    await sync.syncNow();
  }

  /// Joins a list from an invitation link and pulls it in right away.
  Future<void> joinByInvite(String token) async {
    await remote.joinByInvite(token);
    await sync.syncNow();
  }
}

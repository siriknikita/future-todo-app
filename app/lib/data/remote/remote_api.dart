/// The only network boundary of the client.
///
/// PLACEHOLDER: ARCHITECTURE.md says the API client is generated from
/// `api/openapi.json` (openapi-generator `dart-dio`). Until that client is
/// generated, this small interface is what the rest of the app depends on;
/// the generated client should be wrapped in an implementation of it
/// (replacing `HttpRemoteApi`). The paths and DTO shapes used by
/// `HttpRemoteApi` follow `api/openapi.json`.
library;

class AuthUser {
  const AuthUser({required this.id, required this.email, this.name});

  final String id;
  final String email;
  final String? name;
}

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final AuthUser user;
}

/// One changed record in the client's own field vocabulary (the wire
/// mapping lives in `wire_mapper.dart`). Only fields that have an entry in
/// [clocks] are meaningful.
class RemoteChange {
  const RemoteChange({
    required this.entity,
    required this.id,
    required this.fields,
    required this.clocks,
  });

  /// `group`, `list`, `task` or `step`.
  final String entity;
  final String id;
  final Map<String, Object?> fields;
  final Map<String, String> clocks;
}

class PullResult {
  const PullResult({
    required this.changes,
    required this.cursor,
    this.hasMore = false,
    this.accessibleListIds,
  });

  final List<RemoteChange> changes;

  /// Sequence number to send as `since` next time.
  final int cursor;

  /// More changes are waiting: pull again with [cursor].
  final bool hasMore;

  /// Lists the caller can currently access; lists not in it were removed
  /// from the caller (left, or removed by the owner).
  final List<String>? accessibleListIds;
}

class ListMember {
  const ListMember({
    required this.userId,
    required this.name,
    required this.isOwner,
  });

  final String userId;
  final String name;
  final bool isOwner;
}

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;

  /// Machine-readable code from the error body (e.g. `EMAIL_TAKEN`).
  final String? code;

  @override
  String toString() => message;
}

abstract class RemoteApi {
  /// Tokens used for authenticated requests. When the access token expires
  /// the implementation refreshes it and reports the new pair through
  /// [onTokens].
  String? accessToken;
  String? refreshToken;
  void Function(String accessToken, String refreshToken)? onTokens;

  /// This device's id, sent with pushes.
  String? deviceId;

  // Accounts (FR-1.x)
  Future<void> register({
    required String email,
    required String password,
    String? name,
  });
  Future<void> verifyEmail(String token);
  Future<AuthSession> login({required String email, required String password});
  Future<void> requestPasswordReset(String email);
  Future<void> resetPassword({
    required String token,
    required String newPassword,
  });
  Future<AuthUser> updateProfile({String? name});
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });
  Future<void> logout();

  // Sync (FR-8.x)
  Future<void> push(List<RemoteChange> changes);
  Future<PullResult> pull(int cursor);

  // Sharing (FR-5.x)
  /// Returns the invitation token; the client builds the link.
  Future<String> createInvitation(String listId);
  Future<void> revokeInvitations(String listId);
  Future<List<ListMember>> listMembers(String listId);

  /// Owner removes a member, or a member leaves (userId = own id).
  Future<void> removeMember(String listId, String userId);
  Future<void> joinByInvite(String token);

  /// WebSocket URL for real-time change notifications (FR-5.6), or null.
  Uri? realtimeUri();
}

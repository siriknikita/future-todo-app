import 'package:future_todo/core/lww.dart';
import 'package:future_todo/data/remote/remote_api.dart';

/// In-memory stand-in for the backend: applies per-field LWW on push and
/// serves changes after a cursor on pull.
class FakeRemoteApi implements RemoteApi {
  final Map<String, RemoteChange> records = {};
  final List<(int, String)> log = [];
  int _seq = 0;
  int pushCalls = 0;
  bool failNext = false;

  final Map<String, List<ListMember>> members = {};
  final List<String> calls = [];
  String? loginEmail;
  bool failRemoveMember = false;

  /// Lists returned as `accessibleListIds`; null means "not reported".
  List<String>? accessible;

  @override
  String? accessToken;
  @override
  String? refreshToken;
  @override
  void Function(String accessToken, String refreshToken)? onTokens;
  @override
  String? deviceId;

  @override
  Future<void> push(List<RemoteChange> changes) async {
    if (failNext) {
      failNext = false;
      throw const ApiException('boom', statusCode: 500);
    }
    pushCalls++;
    for (final c in changes) {
      final key = '${c.entity}/${c.id}';
      final existing = records[key];
      if (existing == null) {
        records[key] = c;
      } else {
        final merged = mergeFields(
          localFields: existing.fields,
          localClocks: existing.clocks,
          remoteFields: c.fields,
          remoteClocks: c.clocks,
        );
        records[key] = RemoteChange(
          entity: c.entity,
          id: c.id,
          fields: merged.fields,
          clocks: merged.clocks,
        );
      }
      log.add((++_seq, key));
    }
  }

  @override
  Future<PullResult> pull(int cursor) async {
    final keys = {for (final e in log.where((e) => e.$1 > cursor)) e.$2};
    return PullResult(
      changes: [for (final k in keys) records[k]!],
      cursor: _seq,
      accessibleListIds: accessible,
    );
  }

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    if (password != 'correct-password') {
      throw const ApiException('bad credentials', statusCode: 401);
    }
    loginEmail = email;
    return AuthSession(
      accessToken: 'access',
      refreshToken: 'refresh',
      user: AuthUser(id: 'user-1', email: email, name: 'Test User'),
    );
  }

  @override
  Future<void> register({
    required String email,
    required String password,
    String? name,
  }) async =>
      calls.add('register:$email');

  @override
  Future<void> verifyEmail(String token) async => calls.add('verify:$token');

  @override
  Future<void> requestPasswordReset(String email) async =>
      calls.add('forgot:$email');

  @override
  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async =>
      calls.add('reset:$token');

  @override
  Future<AuthUser> updateProfile({String? name}) async {
    calls.add('profile:$name');
    return AuthUser(id: 'user-1', email: loginEmail ?? 'a@b.c', name: name);
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async =>
      calls.add('password');

  @override
  Future<void> logout() async => calls.add('logout');

  @override
  Future<String> createInvitation(String listId) async => 'tok-$listId';

  @override
  Future<void> revokeInvitations(String listId) async =>
      calls.add('revoke:$listId');

  @override
  Future<List<ListMember>> listMembers(String listId) async =>
      members[listId] ?? const [];

  @override
  Future<void> removeMember(String listId, String userId) async {
    if (failRemoveMember) {
      throw const ApiException('Not allowed', statusCode: 403);
    }
    calls.add('remove:$userId');
  }

  @override
  Future<void> joinByInvite(String token) async => calls.add('join:$token');

  @override
  Uri? realtimeUri() => null;
}

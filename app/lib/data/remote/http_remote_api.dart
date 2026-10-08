import 'dart:convert';

import 'package:future_todo/data/remote/remote_api.dart';
import 'package:future_todo/data/remote/wire_mapper.dart';
import 'package:http/http.dart' as http;

/// PLACEHOLDER implementation of [RemoteApi], written by hand with
/// `package:http` because the Dart client cannot be generated yet.
/// Paths and JSON shapes follow `api/openapi.json`. Replace the body of every
/// method with calls to the generated `dart-dio` client (keep the interface).
class HttpRemoteApi implements RemoteApi {
  HttpRemoteApi({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  /// Server root, e.g. `http://localhost:8080`; `/api/v1` is added here.
  final String baseUrl;
  final http.Client _client;

  @override
  String? accessToken;
  @override
  String? refreshToken;
  @override
  void Function(String accessToken, String refreshToken)? onTokens;
  @override
  String? deviceId;

  Future<Object?> _send(
    String method,
    String path, {
    Object? body,
    bool auth = true,
    bool retry = true,
  }) async {
    final request = http.Request(method, Uri.parse('$baseUrl/api/v1$path'))
      ..headers['Content-Type'] = 'application/json';
    if (auth && accessToken != null) {
      request.headers['Authorization'] = 'Bearer $accessToken';
    }
    if (body != null) request.body = jsonEncode(body);
    final response =
        await http.Response.fromStream(await _client.send(request));

    if (response.statusCode == 401 && auth && retry && refreshToken != null) {
      if (await _refresh()) {
        return _send(method, path, body: body, auth: auth, retry: false);
      }
    }
    if (response.statusCode >= 400) {
      String? code;
      var message = response.body;
      try {
        final j = jsonDecode(response.body) as Map<String, dynamic>;
        code = j['code'] as String?;
        message = (j['message'] as String?) ?? message;
      } on Object {
        // Not a JSON error body.
      }
      throw ApiException(message, statusCode: response.statusCode, code: code);
    }
    if (response.body.isEmpty) return null;
    return jsonDecode(response.body);
  }

  Future<bool> _refresh() async {
    try {
      final j = (await _send(
        'POST',
        '/auth/refresh',
        body: {'refreshToken': refreshToken},
        auth: false,
      ))! as Map<String, dynamic>;
      accessToken = j['accessToken'] as String;
      refreshToken = j['refreshToken'] as String;
      onTokens?.call(accessToken!, refreshToken!);
      return true;
    } on ApiException {
      return false;
    }
  }

  AuthUser _user(Map<String, dynamic> j) => AuthUser(
        id: j['id'] as String,
        email: j['email'] as String,
        name: j['displayName'] as String?,
      );

  @override
  Future<void> register({
    required String email,
    required String password,
    String? name,
  }) =>
      _send(
        'POST',
        '/auth/register',
        auth: false,
        body: {
          'email': email,
          'password': password,
          if (name != null) 'displayName': name,
        },
      );

  @override
  Future<void> verifyEmail(String token) =>
      _send('POST', '/auth/verify-email', auth: false, body: {'token': token});

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final j = (await _send(
      'POST',
      '/auth/login',
      auth: false,
      body: {
        'email': email,
        'password': password,
        'deviceName': 'Web',
        'platform': 'web',
      },
    ))! as Map<String, dynamic>;
    return AuthSession(
      accessToken: j['accessToken'] as String,
      refreshToken: j['refreshToken'] as String,
      user: _user(j['user'] as Map<String, dynamic>),
    );
  }

  @override
  Future<void> requestPasswordReset(String email) => _send(
        'POST',
        '/auth/forgot-password',
        auth: false,
        body: {'email': email},
      );

  @override
  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) =>
      _send(
        'POST',
        '/auth/reset-password',
        auth: false,
        body: {'token': token, 'newPassword': newPassword},
      );

  @override
  Future<AuthUser> updateProfile({String? name}) async => _user(
        (await _send('PATCH', '/me', body: {'displayName': name}))!
            as Map<String, dynamic>,
      );

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) =>
      _send(
        'POST',
        '/me/password',
        body: {'currentPassword': currentPassword, 'newPassword': newPassword},
      );

  @override
  Future<void> logout() async {
    if (refreshToken == null) return;
    await _send(
      'POST',
      '/auth/logout',
      auth: false,
      body: {'refreshToken': refreshToken},
    );
  }

  @override
  Future<void> push(List<RemoteChange> changes) async {
    final wire = [
      for (final c in changes) toPushChange(c),
    ].whereType<Map<String, Object?>>().toList();
    if (wire.isEmpty) return;
    await _send(
      'POST',
      '/sync/push',
      body: {'deviceId': deviceId, 'changes': wire},
    );
  }

  @override
  Future<PullResult> pull(int cursor) async {
    final j = (await _send('GET', '/sync/pull?since=$cursor'))!
        as Map<String, dynamic>;
    final raw = (j['changes'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    return PullResult(
      changes: [
        for (final c in raw) fromSyncChange(c),
      ].whereType<RemoteChange>().toList(),
      cursor: (j['nextSeq'] as num?)?.toInt() ?? cursor,
      hasMore: (j['hasMore'] as bool?) ?? false,
      accessibleListIds:
          (j['accessibleListIds'] as List<dynamic>?)?.cast<String>(),
    );
  }

  @override
  Future<String> createInvitation(String listId) async {
    final j = (await _send('POST', '/lists/$listId/invitations'))!
        as Map<String, dynamic>;
    return j['token'] as String;
  }

  @override
  Future<void> revokeInvitations(String listId) =>
      _send('DELETE', '/lists/$listId/invitations');

  @override
  Future<List<ListMember>> listMembers(String listId) async {
    final raw =
        ((await _send('GET', '/lists/$listId/members'))! as List<dynamic>)
            .cast<Map<String, dynamic>>();
    return [
      for (final m in raw)
        ListMember(
          userId: m['userId'] as String,
          name: (m['displayName'] as String?) ?? '',
          isOwner: m['role'] == 'OWNER',
        ),
    ];
  }

  @override
  Future<void> removeMember(String listId, String userId) =>
      _send('DELETE', '/lists/$listId/members/$userId');

  @override
  Future<void> joinByInvite(String token) =>
      _send('POST', '/invitations/$token/accept');

  @override
  Uri? realtimeUri() {
    final token = accessToken;
    if (token == null) return null;
    final base = Uri.parse(baseUrl);
    return Uri(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '/api/v1/ws',
      queryParameters: {'token': token},
    );
  }
}

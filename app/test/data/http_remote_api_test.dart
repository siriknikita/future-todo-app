import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:future_todo/data/remote/http_remote_api.dart';
import 'package:future_todo/data/remote/remote_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Records requests and answers them from [handler].
class Server {
  Server(this.handler);

  final http.Response Function(http.Request request) handler;
  final requests = <http.Request>[];

  late final client = MockClient((request) async {
    requests.add(request);
    return handler(request);
  });

  http.Request get last => requests.last;
  Map<String, dynamic> get lastBody =>
      jsonDecode(last.body) as Map<String, dynamic>;
}

http.Response json(Object? body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

const hlc = '000000000001000:00000:a';

void main() {
  HttpRemoteApi api(Server server) =>
      HttpRemoteApi(baseUrl: 'http://api.test', client: server.client);

  group('requests follow api/openapi.json', () {
    test('register and verify are anonymous', () async {
      final server = Server((_) => http.Response('', 201));
      final remote = api(server)..accessToken = 'secret';
      await remote.register(email: 'a@b.c', password: 'pw', name: 'Ann');
      expect(server.last.method, 'POST');
      expect(
        server.last.url.toString(),
        'http://api.test/api/v1/auth/register',
      );
      expect(server.last.headers['Authorization'], isNull);
      expect(server.lastBody, {
        'email': 'a@b.c',
        'password': 'pw',
        'displayName': 'Ann',
      });

      await remote.verifyEmail('tok');
      expect(server.last.url.path, '/api/v1/auth/verify-email');
      expect(server.lastBody, {'token': 'tok'});
    });

    test('login returns the session and user (FR-1.2)', () async {
      final server = Server(
        (_) => json({
          'accessToken': 'at',
          'refreshToken': 'rt',
          'user': {'id': 'u1', 'email': 'a@b.c', 'displayName': 'Ann'},
        }),
      );
      final session = await api(server).login(email: 'a@b.c', password: 'pw');
      expect(session.accessToken, 'at');
      expect(session.refreshToken, 'rt');
      expect(session.user.id, 'u1');
      expect(session.user.name, 'Ann');
      expect(server.lastBody['platform'], 'web');
    });

    test('password reset, profile and password change', () async {
      final server = Server(
        (r) => r.url.path.endsWith('/me')
            ? json({'id': 'u1', 'email': 'a@b.c', 'displayName': 'Bob'})
            : http.Response('', 204),
      );
      final remote = api(server)..accessToken = 'at';

      await remote.requestPasswordReset('a@b.c');
      expect(server.last.url.path, '/api/v1/auth/forgot-password');

      await remote.resetPassword(token: 't', newPassword: 'new');
      expect(server.lastBody, {'token': 't', 'newPassword': 'new'});

      final user = await remote.updateProfile(name: 'Bob');
      expect(server.last.method, 'PATCH');
      expect(server.last.headers['Authorization'], 'Bearer at');
      expect(user.name, 'Bob');

      await remote.changePassword(currentPassword: 'old', newPassword: 'new');
      expect(server.last.url.path, '/api/v1/me/password');
    });

    test('logout sends the refresh token, and is a no-op without one',
        () async {
      final server = Server((_) => http.Response('', 204));
      final remote = api(server);
      await remote.logout();
      expect(server.requests, isEmpty);

      remote.refreshToken = 'rt';
      await remote.logout();
      expect(server.lastBody, {'refreshToken': 'rt'});
    });

    test('push sends wire changes with the device id (FR-8.2)', () async {
      final server = Server((_) => json({'applied': 1}));
      final remote = api(server)..deviceId = 'dev1';

      await remote.push(const []);
      expect(server.requests, isEmpty, reason: 'nothing to push');

      await remote.push(const [
        RemoteChange(
          entity: 'task',
          id: 't1',
          fields: {'title': 'Milk', 'isImportant': true},
          clocks: {'title': hlc, 'isImportant': hlc},
        ),
      ]);
      final body = server.lastBody;
      expect(body['deviceId'], 'dev1');
      final change = (body['changes'] as List).single as Map<String, dynamic>;
      expect(change['entityType'], 'task');
      expect(change['entityId'], 't1');
      expect((change['fields'] as Map)['important'], {
        'value': true,
        'hlc': hlc,
      });
    });

    test('pull maps changes, cursor and accessible lists', () async {
      final server = Server(
        (_) => json({
          'changes': [
            {
              'seq': 7,
              'entityType': 'list',
              'entityId': 'l1',
              'payload': {
                'name': 'Home',
                'clocks': {'name': hlc},
              },
            },
            {'entityType': 'alien', 'entityId': 'x'},
          ],
          'nextSeq': 7,
          'hasMore': true,
          'accessibleListIds': ['l1'],
        }),
      );
      final result = await api(server).pull(3);
      expect(
        server.last.url.toString(),
        'http://api.test/api/v1/sync/pull?since=3',
      );
      expect(result.changes.single.fields['name'], 'Home');
      expect(result.cursor, 7);
      expect(result.hasMore, isTrue);
      expect(result.accessibleListIds, ['l1']);
    });

    test('pull keeps the cursor when the server sends none', () async {
      final server = Server((_) => json(<String, Object?>{}));
      final result = await api(server).pull(3);
      expect(result.changes, isEmpty);
      expect(result.cursor, 3);
      expect(result.hasMore, isFalse);
    });

    test('sharing endpoints (FR-5.x)', () async {
      final server = Server((r) {
        if (r.url.path.endsWith('/invitations') && r.method == 'POST') {
          return json({'token': 'inv'});
        }
        if (r.url.path.endsWith('/members')) {
          return json([
            {'userId': 'u1', 'displayName': 'Ann', 'role': 'OWNER'},
            {'userId': 'u2', 'role': 'MEMBER'},
          ]);
        }
        return http.Response('', 204);
      });
      final remote = api(server);

      expect(await remote.createInvitation('l1'), 'inv');
      await remote.revokeInvitations('l1');
      expect(server.last.method, 'DELETE');

      final members = await remote.listMembers('l1');
      expect(members.map((m) => m.isOwner), [true, false]);
      expect(members.last.name, '');

      await remote.removeMember('l1', 'u2');
      expect(server.last.url.path, '/api/v1/lists/l1/members/u2');
      await remote.joinByInvite('inv');
      expect(server.last.url.path, '/api/v1/invitations/inv/accept');
    });
  });

  group('errors and token refresh', () {
    test('error bodies become ApiException with code', () async {
      final server = Server(
        (_) => json({'code': 'EMAIL_TAKEN', 'message': 'Taken'}, 409),
      );
      await expectLater(
        api(server).register(email: 'a@b.c', password: 'pw'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 409)
              .having((e) => e.code, 'code', 'EMAIL_TAKEN')
              .having((e) => e.message, 'message', 'Taken'),
        ),
      );
    });

    test('non-JSON error bodies keep the raw text', () async {
      final server = Server((_) => http.Response('Bad gateway', 502));
      await expectLater(
        api(server).verifyEmail('t'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', 'Bad gateway')
              .having((e) => e.code, 'code', isNull),
        ),
      );
    });

    test('401 refreshes the tokens once and retries', () async {
      final server = Server((r) {
        if (r.url.path.endsWith('/auth/refresh')) {
          return json({'accessToken': 'at2', 'refreshToken': 'rt2'});
        }
        return r.headers['Authorization'] == 'Bearer at2'
            ? json({'token': 'inv'})
            : http.Response('', 401);
      });
      String? reported;
      final remote = api(server)
        ..accessToken = 'at1'
        ..refreshToken = 'rt1'
        ..onTokens = (access, refresh) => reported = '$access/$refresh';

      expect(await remote.createInvitation('l1'), 'inv');
      expect(reported, 'at2/rt2');
      expect(remote.accessToken, 'at2');
      expect(server.requests.map((r) => r.url.path), [
        '/api/v1/lists/l1/invitations',
        '/api/v1/auth/refresh',
        '/api/v1/lists/l1/invitations',
      ]);
    });

    test('a failed refresh surfaces the original 401', () async {
      final server = Server((_) => http.Response('', 401));
      final remote = api(server)
        ..accessToken = 'at'
        ..refreshToken = 'rt';
      await expectLater(
        remote.createInvitation('l1'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
      );
    });
  });

  test('realtimeUri uses ws/wss with the access token (FR-5.6)', () {
    final server = Server((_) => http.Response('', 200));
    expect(api(server).realtimeUri(), isNull);

    final local = HttpRemoteApi(baseUrl: 'http://localhost:8080')
      ..accessToken = 't';
    expect(
      local.realtimeUri().toString(),
      'ws://localhost:8080/api/v1/ws?token=t',
    );

    final secure = HttpRemoteApi(baseUrl: 'https://todo.example')
      ..accessToken = 't';
    expect(secure.realtimeUri()!.scheme, 'wss');
  });
}

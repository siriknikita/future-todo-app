import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Listens to the server's WebSocket and calls [onChanges] when it says
/// `{"type":"changes"}`, so the sync component pulls right away instead of
/// waiting for the next poll (FR-5.6, PR-3). Reconnects when the socket
/// closes. WebSockets are not part of the OpenAPI document, so this is
/// hand-written by design.
class RealtimeListener {
  RealtimeListener({
    required this.uriProvider,
    required this.onChanges,
    WebSocketChannel Function(Uri uri)? connect,
    this.retryDelay = const Duration(seconds: 5),
  }) : _connect = connect ?? WebSocketChannel.connect;

  final Uri? Function() uriProvider;
  final void Function() onChanges;
  final WebSocketChannel Function(Uri uri) _connect;
  final Duration retryDelay;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retry;
  bool _stopped = true;

  void start() {
    _stopped = false;
    _open();
  }

  void _open() {
    if (_stopped) return;
    final uri = uriProvider();
    if (uri == null) {
      _scheduleRetry();
      return;
    }
    try {
      final channel = _connect(uri);
      _channel = channel;
      _subscription = channel.stream.listen(
        handleMessage,
        onError: (_) => _scheduleRetry(),
        onDone: _scheduleRetry,
        cancelOnError: true,
      );
    } on Object {
      _scheduleRetry();
    }
  }

  /// Handles one text frame from the server.
  void handleMessage(Object? message) {
    if (message is! String) return;
    try {
      final json = jsonDecode(message);
      if (json is Map<String, dynamic> && json['type'] == 'changes') {
        onChanges();
      }
    } on FormatException {
      // `pong` and other non-JSON frames are ignored.
    }
  }

  void _scheduleRetry() {
    if (_stopped) return;
    unawaited(_subscription?.cancel());
    _retry?.cancel();
    _retry = Timer(retryDelay, _open);
  }

  void stop() {
    _stopped = true;
    _retry?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(_channel?.sink.close());
  }
}

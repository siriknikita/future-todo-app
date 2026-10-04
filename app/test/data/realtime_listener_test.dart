import 'package:flutter_test/flutter_test.dart';
import 'package:future_todo/data/sync/realtime_listener.dart';

void main() {
  test('only "changes" frames trigger a sync', () {
    var calls = 0;
    RealtimeListener(
      uriProvider: () => null,
      onChanges: () => calls++,
    )
      ..handleMessage('{"type":"changes","seq":3}')
      ..handleMessage('{"type":"notification","id":"1"}')
      ..handleMessage('pong')
      ..handleMessage(42)
      ..stop();
    expect(calls, 1);
  });
}

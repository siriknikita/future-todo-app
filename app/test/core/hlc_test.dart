import 'package:flutter_test/flutter_test.dart';
import 'package:future_todo/core/hlc.dart';

void main() {
  group('Hlc', () {
    test('string form round-trips', () {
      const hlc = Hlc(1700000000000, 3, 'dev-1');
      expect(Hlc.parse(hlc.toString()), hlc);
    });

    test('string order equals logical order', () {
      const a = Hlc(100, 0, 'a');
      const b = Hlc(100, 1, 'a');
      const c = Hlc(101, 0, 'a');
      expect(a.toString().compareTo(b.toString()) < 0, isTrue);
      expect(b.toString().compareTo(c.toString()) < 0, isTrue);
      expect(c > b && b > a, isTrue);
    });

    test('node id breaks ties', () {
      expect(const Hlc(5, 0, 'b') > const Hlc(5, 0, 'a'), isTrue);
    });
  });

  group('HlcClock', () {
    test('send is monotonic when the physical clock does not advance', () {
      final clock = HlcClock('n', now: () => 1000);
      final first = clock.send();
      final second = clock.send();
      expect(second > first, isTrue);
      expect(second.counter, 1);
    });

    test('send resets counter when physical time advances', () {
      var t = 1000;
      final clock = HlcClock('n', now: () => t)..send();
      t = 2000;
      final next = clock.send();
      expect(next.millis, 2000);
      expect(next.counter, 0);
    });

    test('receive orders later local changes after a remote future stamp', () {
      final clock = HlcClock('n', now: () => 1000);
      const remote = Hlc(5000, 2, 'other');
      clock.receive(remote);
      expect(clock.send() > remote, isTrue);
    });

    test('a device with a slow clock still wins after seeing newer data', () {
      final slow = HlcClock('slow', now: () => 10);
      const remote = Hlc(999, 0, 'fast');
      slow.receive(remote);
      expect(slow.send() > remote, isTrue);
    });
  });
}

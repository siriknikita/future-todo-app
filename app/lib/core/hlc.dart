import 'dart:math';

/// Hybrid logical clock timestamp: physical time + counter + node id.
/// The string form sorts lexicographically in the same order as [compareTo].
class Hlc implements Comparable<Hlc> {
  const Hlc(this.millis, this.counter, this.node);

  factory Hlc.parse(String value) {
    final parts = value.split(':');
    return Hlc(
      int.parse(parts[0]),
      int.parse(parts[1]),
      parts.sublist(2).join(':'),
    );
  }

  final int millis;
  final int counter;
  final String node;

  @override
  String toString() =>
      '${millis.toString().padLeft(15, '0')}:'
      '${counter.toString().padLeft(5, '0')}:$node';

  @override
  int compareTo(Hlc other) {
    if (millis != other.millis) return millis.compareTo(other.millis);
    if (counter != other.counter) return counter.compareTo(other.counter);
    return node.compareTo(other.node);
  }

  bool operator >(Hlc other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) => other is Hlc && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(millis, counter, node);
}

/// Generates monotonically increasing [Hlc] values for one device.
class HlcClock {
  HlcClock(this.node, {int Function()? now})
      : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch),
        _last = Hlc(0, 0, node);

  final String node;
  final int Function() _now;
  Hlc _last;

  /// Timestamp for a local change.
  Hlc send() {
    final physical = _now();
    if (physical > _last.millis) {
      _last = Hlc(physical, 0, node);
    } else {
      _last = Hlc(_last.millis, _last.counter + 1, node);
    }
    return _last;
  }

  /// Merges a timestamp seen from another device so that later local
  /// changes are ordered after it even if this device's clock is behind.
  Hlc receive(Hlc remote) {
    final physical = _now();
    final maxMillis = max(physical, max(_last.millis, remote.millis));
    final int counter;
    if (maxMillis == _last.millis && maxMillis == remote.millis) {
      counter = max(_last.counter, remote.counter) + 1;
    } else if (maxMillis == _last.millis) {
      counter = _last.counter + 1;
    } else if (maxMillis == remote.millis) {
      counter = remote.counter + 1;
    } else {
      counter = 0;
    }
    _last = Hlc(maxMillis, counter, node);
    return _last;
  }
}

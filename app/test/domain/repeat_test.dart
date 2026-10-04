import 'package:flutter_test/flutter_test.dart';
import 'package:future_todo/domain/repeat.dart';

void main() {
  DateTime? next(RepeatRule rule, DateTime from) => nextOccurrence(rule, from);

  test('none does not repeat', () {
    expect(next(const RepeatRule(RepeatType.none), DateTime(2025, 1, 1)), isNull);
  });

  test('daily adds one day, across month end', () {
    expect(
      next(const RepeatRule(RepeatType.daily), DateTime(2025, 1, 31)),
      DateTime(2025, 2),
    );
  });

  test('custom interval adds N days', () {
    expect(
      next(const RepeatRule(RepeatType.custom, interval: 10), DateTime(2025, 1, 25)),
      DateTime(2025, 2, 4),
    );
  });

  test('weekdays skips the weekend', () {
    // 2025-01-03 is a Friday.
    expect(
      next(const RepeatRule(RepeatType.weekdays), DateTime(2025, 1, 3)),
      DateTime(2025, 1, 6),
    );
    expect(
      next(const RepeatRule(RepeatType.weekdays), DateTime(2025, 1, 6)),
      DateTime(2025, 1, 7),
    );
  });

  test('weekly without days repeats on the same weekday', () {
    expect(
      next(const RepeatRule(RepeatType.weekly), DateTime(2025, 1, 6)),
      DateTime(2025, 1, 13),
    );
  });

  test('weekly with selected days picks the next selected day', () {
    // Mon + Wed + Fri
    const mask = 1 | 4 | 16;
    const rule = RepeatRule(RepeatType.weekly, weekdayMask: mask);
    expect(next(rule, DateTime(2025, 1, 6)), DateTime(2025, 1, 8)); // Mon -> Wed
    expect(next(rule, DateTime(2025, 1, 8)), DateTime(2025, 1, 10)); // Wed -> Fri
    expect(next(rule, DateTime(2025, 1, 10)), DateTime(2025, 1, 13)); // Fri -> Mon
  });

  test('weekly every 2 weeks skips a whole week', () {
    const rule = RepeatRule(RepeatType.weekly, interval: 2, weekdayMask: 1 | 4);
    expect(next(rule, DateTime(2025, 1, 6)), DateTime(2025, 1, 8));
    expect(next(rule, DateTime(2025, 1, 8)), DateTime(2025, 1, 20));
  });

  test('monthly clamps to the last day of shorter months', () {
    expect(
      next(const RepeatRule(RepeatType.monthly), DateTime(2025, 1, 31)),
      DateTime(2025, 2, 28),
    );
    expect(
      next(const RepeatRule(RepeatType.monthly, interval: 2), DateTime(2025, 11, 15)),
      DateTime(2026, 1, 15),
    );
  });

  test('yearly handles leap day', () {
    expect(
      next(const RepeatRule(RepeatType.yearly), DateTime(2024, 2, 29)),
      DateTime(2025, 2, 28),
    );
  });

  test('time of day is ignored', () {
    expect(
      next(const RepeatRule(RepeatType.daily), DateTime(2025, 3, 1, 23, 59)),
      DateTime(2025, 3, 2),
    );
  });

  test('fromStorage falls back to none and clamps interval', () {
    final rule = RepeatRule.fromStorage('bogus', 0, 0);
    expect(rule.type, RepeatType.none);
    expect(rule.interval, 1);
  });
}

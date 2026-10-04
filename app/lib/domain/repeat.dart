import 'package:future_todo/core/dates.dart';

enum RepeatType { none, daily, weekdays, weekly, monthly, yearly, custom }

/// Repeat rule of a task (FR-3.6).
///
/// [weekdayMask] is used by [RepeatType.weekly]: bit 0 = Monday ... bit 6 =
/// Sunday. A weekly rule with an empty mask repeats on the same weekday.
/// [RepeatType.custom] means "every [interval] days".
class RepeatRule {
  const RepeatRule(this.type, {this.interval = 1, this.weekdayMask = 0});

  factory RepeatRule.fromStorage(String type, int interval, int mask) =>
      RepeatRule(
        RepeatType.values.firstWhere(
          (t) => t.name == type,
          orElse: () => RepeatType.none,
        ),
        interval: interval < 1 ? 1 : interval,
        weekdayMask: mask,
      );

  final RepeatType type;
  final int interval;
  final int weekdayMask;

  bool hasWeekday(int weekday) => weekdayMask & (1 << (weekday - 1)) != 0;
}

/// Date of the next occurrence strictly after [from] (time is ignored), or
/// null when the rule does not repeat.
DateTime? nextOccurrence(RepeatRule rule, DateTime from) {
  final base = dateOnly(from);
  final interval = rule.interval < 1 ? 1 : rule.interval;
  switch (rule.type) {
    case RepeatType.none:
      return null;
    case RepeatType.daily:
    case RepeatType.custom:
      return DateTime(base.year, base.month, base.day + interval);
    case RepeatType.weekdays:
      var d = base;
      do {
        d = DateTime(d.year, d.month, d.day + 1);
      } while (d.weekday > DateTime.friday);
      return d;
    case RepeatType.weekly:
      if (rule.weekdayMask == 0) {
        return DateTime(base.year, base.month, base.day + 7 * interval);
      }
      final weekStart =
          DateTime(base.year, base.month, base.day - (base.weekday - 1));
      for (var i = 1; i <= 7 * interval + 7; i++) {
        final d = DateTime(base.year, base.month, base.day + i);
        final dWeekStart = DateTime(d.year, d.month, d.day - (d.weekday - 1));
        final weeks = daysBetween(weekStart, dWeekStart) ~/ 7;
        if (rule.hasWeekday(d.weekday) && weeks % interval == 0) return d;
      }
      return null;
    case RepeatType.monthly:
      return _addMonths(base, interval);
    case RepeatType.yearly:
      return _addMonths(base, 12 * interval);
  }
}

DateTime _addMonths(DateTime d, int months) {
  final total = d.year * 12 + (d.month - 1) + months;
  final year = total ~/ 12;
  final month = total % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, d.day > lastDay ? lastDay : d.day);
}

import 'package:flutter/material.dart';
import 'package:future_todo/domain/repeat.dart';
import 'package:future_todo/domain/smart_lists.dart';
import 'package:future_todo/domain/sorting.dart';
import 'package:future_todo/l10n/app_localizations.dart';

String smartListLabel(AppLocalizations l, SmartList s) => switch (s) {
      SmartList.myDay => l.myDay,
      SmartList.important => l.important,
      SmartList.planned => l.planned,
      SmartList.assignedToMe => l.assignedToMe,
      SmartList.all => l.allTasks,
      SmartList.completed => l.completedTasks,
    };

IconData smartListIcon(SmartList s) => switch (s) {
      SmartList.myDay => Icons.wb_sunny_outlined,
      SmartList.important => Icons.star_border,
      SmartList.planned => Icons.event_outlined,
      SmartList.assignedToMe => Icons.person_outline,
      SmartList.all => Icons.all_inbox_outlined,
      SmartList.completed => Icons.check_circle_outline,
    };

String bucketLabel(AppLocalizations l, PlannedBucket b) => switch (b) {
      PlannedBucket.overdue => l.bucketOverdue,
      PlannedBucket.today => l.bucketToday,
      PlannedBucket.tomorrow => l.bucketTomorrow,
      PlannedBucket.thisWeek => l.bucketThisWeek,
      PlannedBucket.later => l.bucketLater,
    };

String sortLabel(AppLocalizations l, SortMode m) => switch (m) {
      SortMode.manual => l.sortManual,
      SortMode.importance => l.sortImportance,
      SortMode.dueDate => l.sortDueDate,
      SortMode.alphabetical => l.sortAlphabetical,
      SortMode.createdAt => l.sortCreated,
    };

String repeatLabel(AppLocalizations l, RepeatType t) => switch (t) {
      RepeatType.none => l.repeatNone,
      RepeatType.daily => l.repeatDaily,
      RepeatType.weekdays => l.repeatWeekdays,
      RepeatType.weekly => l.repeatWeekly,
      RepeatType.monthly => l.repeatMonthly,
      RepeatType.yearly => l.repeatYearly,
      RepeatType.custom => l.repeatCustom,
    };

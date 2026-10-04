import 'package:drift/drift.dart';
import 'package:future_todo/data/db/tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [ListGroups, TaskLists, Tasks, TaskSteps])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;
}

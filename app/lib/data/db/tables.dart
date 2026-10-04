import 'package:drift/drift.dart';

/// Columns shared by every synced table.
///
/// - [clocks]: JSON map `field name -> HLC string` (per-field LWW, FR-8.3).
/// - [deleted]: tombstone; rows are never physically removed.
/// - [dirty]: true while local changes are not yet pushed.
mixin SyncColumns on Table {
  TextColumn get id => text()();
  TextColumn get clocks => text().withDefault(const Constant('{}'))();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ListGroup')
class ListGroups extends Table with SyncColumns {
  TextColumn get name => text()();
  RealColumn get position => real().withDefault(const Constant(0))();
}

@DataClassName('TaskList')
class TaskLists extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get icon => text().nullable()();
  TextColumn get groupId => text().nullable()();
  RealColumn get position => real().withDefault(const Constant(0))();
  TextColumn get ownerId => text().nullable()();
  BoolColumn get isShared => boolean().withDefault(const Constant(false))();
}

@DataClassName('Task')
class Tasks extends Table with SyncColumns {
  TextColumn get listId => text()();
  TextColumn get title => text()();
  TextColumn get note => text().withDefault(const Constant(''))();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get completedAt => dateTime().nullable()();
  BoolColumn get isImportant => boolean().withDefault(const Constant(false))();

  /// Local calendar date `yyyy-MM-dd`.
  TextColumn get dueDate => text().nullable()();
  DateTimeColumn get reminderAt => dateTime().nullable()();

  /// One of `none, daily, weekdays, weekly, monthly, yearly, custom`.
  TextColumn get repeatType => text().withDefault(const Constant('none'))();
  IntColumn get repeatInterval => integer().withDefault(const Constant(1))();

  /// Bit mask for weekly repeat, bit 0 = Monday ... bit 6 = Sunday.
  IntColumn get repeatDays => integer().withDefault(const Constant(0))();

  /// Local date `yyyy-MM-dd` the task was added to "My Day" (FR-4.1).
  TextColumn get myDayDate => text().nullable()();
  RealColumn get position => real().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get assigneeId => text().nullable()();
}

@DataClassName('TaskStep')
class TaskSteps extends Table with SyncColumns {
  TextColumn get taskId => text()();
  TextColumn get title => text()();
  BoolColumn get isDone => boolean().withDefault(const Constant(false))();
  RealColumn get position => real().withDefault(const Constant(0))();
}

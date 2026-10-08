import 'package:future_todo/data/db/database.dart';

Task makeTask({
  String id = 't1',
  String listId = 'l1',
  String title = 'Task',
  String note = '',
  bool isCompleted = false,
  bool isImportant = false,
  String? dueDate,
  String? myDayDate,
  String? assigneeId,
  double position = 0,
  DateTime? createdAt,
  bool deleted = false,
}) =>
    Task(
      id: id,
      clocks: '{}',
      deleted: deleted,
      dirty: false,
      listId: listId,
      title: title,
      note: note,
      isCompleted: isCompleted,
      isImportant: isImportant,
      dueDate: dueDate,
      repeatType: 'none',
      repeatInterval: 1,
      repeatDays: 0,
      myDayDate: myDayDate,
      position: position,
      createdAt: createdAt ?? DateTime(2025),
      assigneeId: assigneeId,
    );

TaskStep makeStep({
  String id = 's1',
  String taskId = 't1',
  String title = 'Step',
  bool isDone = false,
}) =>
    TaskStep(
      id: id,
      clocks: '{}',
      deleted: false,
      dirty: false,
      taskId: taskId,
      title: title,
      isDone: isDone,
      position: 0,
    );

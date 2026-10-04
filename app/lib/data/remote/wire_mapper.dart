import 'package:future_todo/data/remote/remote_api.dart';

/// Translates between the client's local field vocabulary (Drift columns)
/// and the wire format of `api/openapi.json` (`PushChange` / `SyncChange`).
///
/// Differences handled here: `isCompleted`/`isDone` -> `completed`,
/// `isImportant` -> `important`, timestamps (epoch millis <-> RFC 3339),
/// repeat type names, `repeatDays` (bit mask <-> `"MON,WED"`), and fields
/// that exist only on one side.

const _localToWire = <String, Map<String, String>>{
  'group': {'name': 'name', 'position': 'position', 'deleted': 'deleted'},
  'list': {
    'name': 'name',
    'icon': 'icon',
    'groupId': 'groupId',
    'position': 'position',
    'deleted': 'deleted',
  },
  'task': {
    'listId': 'listId',
    'title': 'title',
    'note': 'note',
    'isCompleted': 'completed',
    'completedAt': 'completedAt',
    'isImportant': 'important',
    'dueDate': 'dueDate',
    'reminderAt': 'reminderAt',
    'repeatType': 'repeatType',
    'repeatInterval': 'repeatInterval',
    'repeatDays': 'repeatDays',
    'myDayDate': 'myDayDate',
    'assigneeId': 'assigneeId',
    'position': 'position',
    'deleted': 'deleted',
  },
  'step': {
    'taskId': 'taskId',
    'title': 'title',
    'isDone': 'completed',
    'position': 'position',
    'deleted': 'deleted',
  },
};

/// Wire fields the server sends that carry no clock (set once by the
/// server) but that the client wants to store.
const _readOnlyFromWire = <String, Map<String, String>>{
  'list': {'ownerId': 'ownerId'},
  'task': {'createdAt': 'createdAt'},
  'step': <String, String>{},
  'group': <String, String>{},
};

const _days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

String? maskToDays(int mask) {
  final names = [
    for (var i = 0; i < 7; i++)
      if (mask & (1 << i) != 0) _days[i],
  ];
  return names.isEmpty ? null : names.join(',');
}

int daysToMask(String? days) {
  if (days == null || days.isEmpty) return 0;
  var mask = 0;
  for (final d in days.split(',')) {
    final i = _days.indexOf(d.trim().toUpperCase());
    if (i >= 0) mask |= 1 << i;
  }
  return mask;
}

String? _repeatToWire(Object? local) => switch (local) {
      'daily' || 'custom' => 'DAILY',
      'weekdays' => 'WEEKDAYS',
      'weekly' => 'WEEKLY',
      'monthly' => 'MONTHLY',
      'yearly' => 'YEARLY',
      _ => null,
    };

String _repeatFromWire(Object? wire) => switch (wire) {
      'DAILY' => 'daily',
      'WEEKDAYS' => 'weekdays',
      'WEEKLY' => 'weekly',
      'MONTHLY' => 'monthly',
      'YEARLY' => 'yearly',
      _ => 'none',
    };

String? _millisToIso(Object? v) => v is int
    ? DateTime.fromMillisecondsSinceEpoch(v, isUtc: true).toIso8601String()
    : null;

int? _isoToMillis(Object? v) =>
    v is String ? DateTime.parse(v).millisecondsSinceEpoch : null;

Object? _valueToWire(String localField, Object? value) => switch (localField) {
      'completedAt' || 'reminderAt' => _millisToIso(value),
      'repeatType' => _repeatToWire(value),
      'repeatDays' => value is int ? maskToDays(value) : null,
      _ => value,
    };

Object? _valueFromWire(String localField, Object? value) =>
    switch (localField) {
      'completedAt' || 'reminderAt' || 'createdAt' => _isoToMillis(value),
      'repeatType' => _repeatFromWire(value),
      'repeatDays' => value is String ? daysToMask(value) : 0,
      'position' when value is num => value.toDouble(),
      _ => value,
    };

/// `PushChange` JSON for [change]; null if nothing in it can be pushed.
Map<String, Object?>? toPushChange(RemoteChange change) {
  final names = _localToWire[change.entity];
  if (names == null) return null;
  final fields = <String, Object?>{};
  for (final entry in change.clocks.entries) {
    final wireName = names[entry.key];
    if (wireName == null) continue;
    fields[wireName] = {
      'value': _valueToWire(entry.key, change.fields[entry.key]),
      'hlc': entry.value,
    };
  }
  if (fields.isEmpty) return null;
  return {
    'entityType': change.entity,
    'entityId': change.id,
    'fields': fields,
  };
}

/// Converts a `SyncChange` JSON object into a [RemoteChange], or null for
/// unknown entity types.
RemoteChange? fromSyncChange(Map<String, dynamic> json) {
  final entity = json['entityType'] as String?;
  final names = _localToWire[entity];
  if (entity == null || names == null) return null;
  final payload = (json['payload'] as Map<String, dynamic>?) ?? const {};
  final wireClocks = Map<String, dynamic>.from(
    (payload['clocks'] as Map<String, dynamic>?) ?? const {},
  );
  final fields = <String, Object?>{};
  final clocks = <String, String>{};
  for (final entry in names.entries) {
    final localName = entry.key;
    final wireName = entry.value;
    if (payload.containsKey(wireName)) {
      fields[localName] = _valueFromWire(localName, payload[wireName]);
    }
    final clock = wireClocks[wireName];
    if (clock is String) clocks[localName] = clock;
  }
  for (final entry in _readOnlyFromWire[entity]!.entries) {
    if (payload.containsKey(entry.value)) {
      fields[entry.key] = _valueFromWire(entry.key, payload[entry.value]);
    }
  }
  if (json['deleted'] == true && !fields.containsKey('deleted')) {
    fields['deleted'] = true;
  }
  return RemoteChange(
    entity: entity,
    id: json['entityId'] as String,
    fields: fields,
    clocks: clocks,
  );
}

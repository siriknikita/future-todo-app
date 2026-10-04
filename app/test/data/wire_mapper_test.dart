import 'package:flutter_test/flutter_test.dart';
import 'package:future_todo/data/remote/remote_api.dart';
import 'package:future_todo/data/remote/wire_mapper.dart';

const hlc = '000000000001000:00000:dev';

void main() {
  test('local task fields become PushChange with wire names and values', () {
    final reminder = DateTime.utc(2025, 1, 9, 9, 30).millisecondsSinceEpoch;
    final json = toPushChange(
      RemoteChange(
        entity: 'task',
        id: 't1',
        fields: {
          'title': 'Milk',
          'isCompleted': true,
          'isImportant': true,
          'reminderAt': reminder,
          'repeatType': 'weekly',
          'repeatDays': 1 | 4,
          'createdAt': 1,
        },
        clocks: {
          'title': hlc,
          'isCompleted': hlc,
          'isImportant': hlc,
          'reminderAt': hlc,
          'repeatType': hlc,
          'repeatDays': hlc,
        },
      ),
    )!;
    expect(json['entityType'], 'task');
    expect(json['entityId'], 't1');
    final fields = json['fields']! as Map<String, Object?>;
    Object? value(String k) => (fields[k]! as Map)['value'];
    expect(value('completed'), true);
    expect(value('important'), true);
    expect(value('reminderAt'), '2025-01-09T09:30:00.000Z');
    expect(value('repeatType'), 'WEEKLY');
    expect(value('repeatDays'), 'MON,WED');
    expect((fields['title']! as Map)['hlc'], hlc);
    expect(fields.containsKey('isCompleted'), isFalse);
    expect(fields.containsKey('createdAt'), isFalse);
  });

  test('none repeat and custom interval map to server vocabulary', () {
    Object? repeat(String local) {
      final j = toPushChange(
        RemoteChange(
          entity: 'task',
          id: 't',
          fields: {'repeatType': local},
          clocks: {'repeatType': hlc},
        ),
      )!;
      return ((j['fields']! as Map)['repeatType'] as Map)['value'];
    }

    expect(repeat('none'), isNull);
    expect(repeat('custom'), 'DAILY');
    expect(repeat('monthly'), 'MONTHLY');
  });

  test('local-only fields are never pushed', () {
    expect(
      toPushChange(
        const RemoteChange(
          entity: 'list',
          id: 'l',
          fields: {'ownerId': 'u', 'isShared': true},
          clocks: {'ownerId': hlc, 'isShared': hlc},
        ),
      ),
      isNull,
    );
  });

  test('SyncChange payload becomes local fields and clocks', () {
    final change = fromSyncChange({
      'seq': 5,
      'entityType': 'task',
      'entityId': 't1',
      'deleted': false,
      'payload': {
        'id': 't1',
        'listId': 'l1',
        'title': 'Milk',
        'completed': true,
        'important': false,
        'completedAt': '2025-01-09T09:30:00Z',
        'repeatType': 'WEEKLY',
        'repeatDays': 'MON,FRI',
        'position': 2,
        'createdAt': '2025-01-01T00:00:00Z',
        'deleted': false,
        'steps': <Object?>[],
        'clocks': {'title': hlc, 'completed': hlc, 'repeatType': hlc},
      },
    })!;
    expect(change.entity, 'task');
    expect(change.fields['isCompleted'], true);
    expect(change.fields['isImportant'], false);
    expect(
      change.fields['completedAt'],
      DateTime.utc(2025, 1, 9, 9, 30).millisecondsSinceEpoch,
    );
    expect(change.fields['repeatType'], 'weekly');
    expect(change.fields['repeatDays'], 1 | 16);
    expect(change.fields['position'], 2.0);
    expect(change.fields['createdAt'], isA<int>());
    expect(change.clocks, {
      'title': hlc,
      'isCompleted': hlc,
      'repeatType': hlc,
    });
  });

  test('step payload and unknown entity types', () {
    final change = fromSyncChange({
      'entityType': 'step',
      'entityId': 's1',
      'payload': {
        'taskId': 't',
        'completed': true,
        'clocks': {'completed': hlc},
      },
    })!;
    expect(change.fields['isDone'], true);
    expect(fromSyncChange({'entityType': 'alien', 'entityId': 'x'}), isNull);
  });

  test('day mask conversion round-trips', () {
    expect(maskToDays(0), isNull);
    expect(daysToMask(maskToDays(127)), 127);
    expect(daysToMask('SUN'), 64);
  });
}

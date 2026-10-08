import 'package:flutter_test/flutter_test.dart';
import 'package:future_todo/core/hlc.dart';
import 'package:future_todo/core/lww.dart';

String h(int ms, [String node = 'a']) => Hlc(ms, 0, node).toString();

void main() {
  test('newer remote field overwrites local', () {
    final r = mergeFields(
      localFields: {'title': 'old'},
      localClocks: {'title': h(1)},
      remoteFields: {'title': 'new'},
      remoteClocks: {'title': h(2, 'b')},
    );
    expect(r.fields['title'], 'new');
    expect(r.clocks['title'], h(2, 'b'));
    expect(r.localWon, isFalse);
  });

  test('newer local field survives and stays dirty', () {
    final r = mergeFields(
      localFields: {'title': 'mine'},
      localClocks: {'title': h(5)},
      remoteFields: {'title': 'theirs'},
      remoteClocks: {'title': h(2, 'b')},
    );
    expect(r.fields['title'], 'mine');
    expect(r.localWon, isTrue);
  });

  test('edits to different fields both survive', () {
    final r = mergeFields(
      localFields: {'title': 'local title', 'note': ''},
      localClocks: {'title': h(5), 'note': h(1)},
      remoteFields: {'title': 't', 'note': 'remote note'},
      remoteClocks: {'title': h(2, 'b'), 'note': h(4, 'b')},
    );
    expect(r.fields['title'], 'local title');
    expect(r.fields['note'], 'remote note');
    expect(r.localWon, isTrue);
  });

  test('tie keeps local value', () {
    final r = mergeFields(
      localFields: {'title': 'local'},
      localClocks: {'title': h(3)},
      remoteFields: {'title': 'remote'},
      remoteClocks: {'title': h(3)},
    );
    expect(r.fields['title'], 'local');
    expect(r.localWon, isFalse);
  });

  test('tombstone is just a field: later delete wins over earlier edit', () {
    final r = mergeFields(
      localFields: {'title': 'edited', 'deleted': false},
      localClocks: {'title': h(3), 'deleted': h(1)},
      remoteFields: {'deleted': true},
      remoteClocks: {'deleted': h(9, 'b')},
    );
    expect(r.fields['deleted'], isTrue);
    expect(r.fields['title'], 'edited');
  });

  test('clock encoding round-trips', () {
    final clocks = {'a': h(1), 'b': h(2)};
    expect(decodeClocks(encodeClocks(clocks)), clocks);
    expect(decodeClocks('{}'), isEmpty);
  });
}

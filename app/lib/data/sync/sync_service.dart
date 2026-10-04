import 'dart:async';
import 'dart:convert';

import 'package:future_todo/core/hlc.dart';
import 'package:future_todo/core/lww.dart';
import 'package:future_todo/data/remote/remote_api.dart';
import 'package:future_todo/data/sync_entities.dart';
import 'package:future_todo/data/repository.dart';

/// Result of the last sync attempt; combined with the dirty count in the UI
/// to show synced / pending / error (FR-8.4).
enum SyncStatus { idle, running, ok, error }

/// Moves changes between the local database and the server (FR-8.2).
/// This and the auth/sharing calls are the only code that uses the network.
class SyncService {
  SyncService({
    required this.repository,
    required this.remote,
    required this.loadCursor,
    required this.saveCursor,
  });

  final TodoRepository repository;
  final RemoteApi remote;
  final int Function() loadCursor;
  final Future<void> Function(int cursor) saveCursor;

  SyncEntities get _entities => repository.entities;
  HlcClock get _clock => repository.clock;

  final _status = StreamController<SyncStatus>.broadcast();
  SyncStatus last = SyncStatus.idle;
  bool _running = false;

  Stream<SyncStatus> get statuses => _status.stream;

  void _emit(SyncStatus s) {
    last = s;
    if (!_status.isClosed) _status.add(s);
  }

  /// Push local changes, then pull remote ones. Never throws.
  Future<void> syncNow() async {
    if (_running) return;
    _running = true;
    _emit(SyncStatus.running);
    try {
      await push();
      await pull();
      _emit(SyncStatus.ok);
    } on Object {
      _emit(SyncStatus.error);
    } finally {
      _running = false;
    }
  }

  Future<int> push() async {
    final changes = <RemoteChange>[];
    for (final entity in _entities.all) {
      for (final row in await entity.dirtyRows()) {
        final clocks = decodeClocks(row['clocks']);
        changes.add(
          RemoteChange(
            entity: entity.name,
            id: row['id']! as String,
            fields: {
              for (final k in clocks.keys) k: row[k],
            },
            clocks: clocks,
          ),
        );
      }
    }
    if (changes.isEmpty) return 0;
    await remote.push(changes);
    for (final c in changes) {
      await _entities.byName(c.entity)!.markClean(c.id, encodeClocks(c.clocks));
    }
    return changes.length;
  }

  Future<int> pull() async {
    var count = 0;
    PullResult result;
    do {
      result = await remote.pull(loadCursor());
      for (final change in result.changes) {
        await applyRemote(change);
      }
      count += result.changes.length;
      await saveCursor(result.cursor);
    } while (result.hasMore);
    final accessible = result.accessibleListIds;
    if (accessible != null) {
      await repository.purgeInaccessibleLists(accessible.toSet());
    }
    return count;
  }

  /// Merges one remote record into the local database, field by field
  /// (last write wins by HLC; deletes are tombstone fields).
  Future<void> applyRemote(RemoteChange change) async {
    final entity = _entities.byName(change.entity);
    if (entity == null) return;
    for (final stamp in change.clocks.values) {
      _clock.receive(Hlc.parse(stamp));
    }
    final local = await entity.findRow(change.id);
    if (local == null) {
      await entity.upsertRow({
        ...entity.defaults,
        ...change.fields,
        'id': change.id,
        'clocks': jsonEncode(change.clocks),
        'dirty': false,
      });
      return;
    }
    final merged = mergeFields(
      localFields: {
        for (final e in local.entries)
          if (!metaColumns.contains(e.key)) e.key: e.value,
      },
      localClocks: decodeClocks(local['clocks']),
      remoteFields: change.fields,
      remoteClocks: change.clocks,
    );
    await entity.upsertRow({
      ...local,
      ...merged.fields,
      'id': change.id,
      'clocks': encodeClocks(merged.clocks),
      'dirty': merged.localWon,
    });
  }

  Future<void> dispose() => _status.close();
}

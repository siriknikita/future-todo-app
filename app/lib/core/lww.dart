import 'dart:convert';

import 'package:future_todo/core/hlc.dart';

/// Result of merging a remote record into a local one, field by field.
class MergeResult {
  const MergeResult({
    required this.fields,
    required this.clocks,
    required this.localWon,
  });

  final Map<String, Object?> fields;
  final Map<String, String> clocks;

  /// True if at least one local field is newer than the remote one (or the
  /// remote does not know it), so the record still has to be pushed.
  final bool localWon;
}

/// Field-level last-write-wins merge (FR-8.3). Every field has its own HLC;
/// the newer timestamp wins, ties keep the local value.
MergeResult mergeFields({
  required Map<String, Object?> localFields,
  required Map<String, String> localClocks,
  required Map<String, Object?> remoteFields,
  required Map<String, String> remoteClocks,
}) {
  final fields = Map<String, Object?>.of(localFields);
  final clocks = Map<String, String>.of(localClocks);
  var localWon = false;

  for (final entry in remoteClocks.entries) {
    final local = localClocks[entry.key];
    final remote = Hlc.parse(entry.value);
    if (local == null || remote > Hlc.parse(local)) {
      fields[entry.key] = remoteFields[entry.key];
      clocks[entry.key] = entry.value;
    }
  }
  for (final entry in localClocks.entries) {
    final remote = remoteClocks[entry.key];
    if (remote == null || Hlc.parse(entry.value) > Hlc.parse(remote)) {
      localWon = true;
    }
  }
  return MergeResult(fields: fields, clocks: clocks, localWon: localWon);
}

Map<String, String> decodeClocks(Object? raw) {
  if (raw == null || (raw is String && raw.isEmpty)) return {};
  final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
  return decoded.map((key, value) => MapEntry(key, value as String));
}

String encodeClocks(Map<String, String> clocks) => jsonEncode(clocks);

import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Reads domain objects out of the replica.
///
/// The part every local-first repository shares: query a local table in the
/// server's own order, rehydrate each row through the same `fromJson` the
/// network path uses, and fall back to the network when the replica cannot
/// answer.
///
/// Shared so the two rules that are easy to get wrong live in one place:
///
/// **The payload is returned verbatim.** Read DTOs have `fromJson` and no
/// `toJson`, so a record reassembled from the extracted columns could not be
/// sent back — and for items it would be worse than useless, because
/// `updateItem` replaces the whole variation tree and a lossy rebuild would
/// delete what it missed.
///
/// **An empty replica is not an empty workspace.** Until a sync has completed,
/// no rows means "nothing synced yet", and answering with an empty list would
/// show a workspace with nothing in it.
class ReplicaReader {
  const ReplicaReader({
    required Future<Database?> Function() replica,
    required bool Function() isHydrated,
  }) : _replica = replica,
       _isHydrated = isHydrated;

  final Future<Database?> Function() _replica;
  final bool Function() _isHydrated;

  /// The replica, or null when it should not be trusted yet.
  Future<Database?> available() async {
    if (!_isHydrated()) return null;
    return _replica();
  }

  /// Every row of [table], in [orderBy], rehydrated by [fromJson].
  ///
  /// Returns null — not an empty list — when the replica cannot answer, so a
  /// caller can tell "nothing here" from "ask the network".
  Future<List<T>?> readAll<T>(
    String table, {
    required String orderBy,
    required T? Function(Map<String, dynamic>) fromJson,
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final db = await available();
    if (db == null) return null;
    final rows = await db.query(
      table,
      columns: const <String>['raw_payload_json'],
      orderBy: orderBy,
      where: where,
      whereArgs: whereArgs,
    );
    if (rows.isEmpty) return null;
    return rows
        .map((row) => _decode(row, fromJson))
        .whereType<T>()
        .toList(growable: false);
  }

  /// One row by its key, or null to ask the network.
  ///
  /// A miss is not proof of absence: the replica may not have caught up with a
  /// record created moments ago.
  Future<T?> readOne<T>(
    String table, {
    required String keyColumn,
    required Object key,
    required T? Function(Map<String, dynamic>) fromJson,
  }) async {
    final db = await available();
    if (db == null) return null;
    final rows = await db.query(
      table,
      columns: const <String>['raw_payload_json'],
      where: '$keyColumn = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _decode(rows.first, fromJson);
  }

  T? _decode<T>(Map<String, Object?> row, T? Function(Map<String, dynamic>) fromJson) {
    final raw = row['raw_payload_json'];
    if (raw is! String || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return fromJson(decoded.cast<String, dynamic>());
    } catch (_) {
      // One unreadable row costs that row, not the list. A screen rendering
      // nothing because a single payload was truncated is the worse outcome.
      return null;
    }
  }
}

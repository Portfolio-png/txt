import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// What the replica remembers between launches.
///
/// The important entry is the changelog cursor. Without it the app starts from
/// zero every time and re-downloads the whole workspace — which is what it did
/// before, and the reason a launch cost 235 KB whether anything had changed or
/// not. With it, a launch asks only "what happened while I was closed?".
class SyncMetadataStore {
  SyncMetadataStore(this._db);

  final DatabaseExecutor _db;

  static const String lastChangelogIdKey = 'last_changelog_id';
  static const String lastSyncAtKey = 'last_sync_at';
  static const String schemaVersionKey = 'snapshot_version';

  Future<String?> read(String key) async {
    final rows = await _db.query(
      'sync_metadata',
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> write(String key, String value) async {
    await _db.insert(
      'sync_metadata',
      <String, Object?>{
        'key': key,
        'value': value,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Where the replay got to. Zero means "nothing yet", which is what a first
  /// install and a discarded replica both look like — and both correctly lead
  /// to a full snapshot.
  Future<int> lastChangelogId() async {
    final raw = await read(lastChangelogIdKey);
    return int.tryParse(raw ?? '') ?? 0;
  }

  /// Advances the cursor.
  ///
  /// Never moves backwards. Events can arrive out of order across a reconnect,
  /// and a cursor that went backwards would replay changes already applied —
  /// harmless in itself, but it would also mask a genuine gap.
  Future<void> setLastChangelogId(int id) async {
    if (id <= 0) return;
    final current = await lastChangelogId();
    if (id <= current) return;
    await write(lastChangelogIdKey, '$id');
    await write(lastSyncAtKey, DateTime.now().toUtc().toIso8601String());
  }

  /// Forgets the position, so the next sync takes a full snapshot. Used when
  /// the replica cannot be trusted rather than pretending it can.
  Future<void> reset() async {
    await write(lastChangelogIdKey, '0');
  }
}

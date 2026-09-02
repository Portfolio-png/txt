import 'dart:async';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database/local_database_helper.dart';
import '../database/sync_metadata_store.dart';
import 'delta_sync_engine.dart';
import 'replica_bindings.dart';

/// Keeps the local replica current.
///
/// Owns the loop that Tier 3 turns on: open this user's replica, remember where
/// the replay got to, ask the server only for what changed since, and tell
/// whoever is on screen which tables moved.
///
/// It does **not** serve reads. Repositories do that, straight off the replica.
/// Keeping the two apart means a screen never waits on a sync: it paints from
/// whatever is on disk, and this quietly makes that better.
class ReplicaSyncService {
  ReplicaSyncService({
    required RecordFetcher fetchRecord,
    required ListFetcher fetchList,
    required Future<List<TableChange>> Function(int since) fetchChangesSince,
    LocalDatabaseHelper? helper,
    Duration batchWindow = const Duration(milliseconds: 250),
  }) : _fetchRecord = fetchRecord,
       _fetchList = fetchList,
       _fetchChangesSince = fetchChangesSince,
       _helper = helper ?? LocalDatabaseHelper.instance,
       _batchWindow = batchWindow;

  final RecordFetcher _fetchRecord;
  final ListFetcher _fetchList;

  /// Replays the changelog from a position. Used to catch up after the app has
  /// been closed, which is the case a persisted cursor exists for.
  final Future<List<TableChange>> Function(int since) _fetchChangesSince;

  final LocalDatabaseHelper _helper;
  final Duration _batchWindow;

  DeltaSyncEngine? _engine;
  SyncMetadataStore? _cursor;

  final _changed = StreamController<Set<String>>.broadcast();

  /// Which local tables just changed. A provider listens and re-reads only what
  /// it cares about, instead of every provider refreshing on every event.
  Stream<Set<String>> get changedTables => _changed.stream;

  final List<TableChange> _pending = <TableChange>[];
  Timer? _batchTimer;
  bool _started = false;

  /// True once the replica holds a first copy. Until then a repository should
  /// delegate to the network rather than serve an empty list, which would look
  /// like a workspace with nothing in it.
  bool get isHydrated => _hydrated;
  bool _hydrated = false;

  Future<void> start(String userNamespace) async {
    await stop();
    await _helper.useNamespace(userNamespace);
    final db = await _helper.database;
    _cursor = SyncMetadataStore(db);
    _engine = DeltaSyncEngine(
      database: db,
      fetchRecord: _fetchRecord,
      fetchList: _fetchList,
    );
    _hydrated = await _looksHydrated(db);
    _started = true;
  }

  /// Whether anything has ever been written here.
  ///
  /// A cursor above zero is the honest signal: rows could legitimately be empty
  /// (a brand-new workspace), but a cursor means a sync has completed at least
  /// once and an empty list is then the truth rather than a gap.
  Future<bool> _looksHydrated(Database db) async {
    final position = await SyncMetadataStore(db).lastChangelogId();
    return position > 0;
  }

  /// Catches up everything that happened while the app was closed.
  ///
  /// Returns the number of changes applied. On a first run the cursor is 0 and
  /// the server has nothing to replay from, so this pulls the lists instead —
  /// the one time the replica costs a full download, and the reason every
  /// launch afterwards costs almost nothing.
  Future<int> catchUp() async {
    final engine = _engine;
    final cursor = _cursor;
    if (engine == null || cursor == null) return 0;

    final since = await cursor.lastChangelogId();
    if (since <= 0) {
      await _hydrateFromLists();
      return 0;
    }

    List<TableChange> changes;
    try {
      changes = await _fetchChangesSince(since);
    } catch (_) {
      // Offline. The replica is stale but usable, which is the entire point of
      // having it — far better than a screen that cannot paint.
      return 0;
    }
    if (changes.isEmpty) return 0;

    await engine.apply(changes, cursor: cursor);
    _announce(changes);
    return changes.length;
  }

  /// Pulls every replicable list once, for a replica with no position to
  /// replay from.
  Future<void> _hydrateFromLists() async {
    final engine = _engine;
    if (engine == null) return;

    // Only the tables a list can fill. `viaParent` and `ignore` bindings have
    // no list of their own; their rows arrive with their parents.
    final tables = <String>{
      for (final entry in kReplicaBindings.entries)
        if (entry.value.localTable != null &&
            entry.value.strategy != DeltaStrategy.viaParent)
          entry.key,
    };

    final synthetic = <TableChange>[
      for (final table in tables)
        TableChange(table: table, recordId: 0, action: 'INSERT'),
    ];
    // Routed through the engine rather than written directly, so hydration and
    // steady-state use one code path — two would drift, and the second would be
    // the one nobody tests.
    await engine.hydrateLists(tables);
    _announce(synthetic);
    _hydrated = true;
  }

  /// Feeds a live change in. Batched, because a single user action announces
  /// several rows and applying each separately would fetch the same record more
  /// than once.
  void onTableChange(TableChange change) {
    if (!_started) return;
    _pending.add(change);
    _batchTimer?.cancel();
    _batchTimer = Timer(_batchWindow, _drain);
  }

  Future<void> _drain() async {
    final engine = _engine;
    if (engine == null || _pending.isEmpty) return;
    final batch = List<TableChange>.from(_pending);
    _pending.clear();
    await engine.apply(batch, cursor: _cursor);
    _announce(batch);
  }

  void _announce(Iterable<TableChange> changes) {
    final tables = <String>{};
    for (final change in changes) {
      final binding = kReplicaBindings[change.table];
      final local = binding?.localTable ??
          kReplicaBindings[binding?.parentTable]?.localTable;
      if (local != null) tables.add(local);
    }
    if (tables.isNotEmpty && !_changed.isClosed) _changed.add(tables);
  }

  /// Throws the replica away and starts again.
  ///
  /// For when it cannot be trusted — a cursor pointing at history the server
  /// has pruned, or a schema this build no longer understands. Always available
  /// because the server can rebuild it, which is what makes the whole design
  /// safe to get wrong occasionally.
  Future<void> resync() async {
    await _cursor?.reset();
    await _helper.destroy();
    _hydrated = false;
    final db = await _helper.database;
    _cursor = SyncMetadataStore(db);
    _engine = DeltaSyncEngine(
      database: db,
      fetchRecord: _fetchRecord,
      fetchList: _fetchList,
    );
    await _hydrateFromLists();
  }

  Future<void> stop() async {
    _batchTimer?.cancel();
    _batchTimer = null;
    _pending.clear();
    _started = false;
    _engine = null;
    _cursor = null;
  }

  Future<void> dispose() async {
    await stop();
    await _changed.close();
  }
}

import '../database/sync_metadata_store.dart';
import 'delta_sync_engine.dart';

/// One page of `GET /api/changes`.
class ChangesPage {
  const ChangesPage({
    required this.changes,
    this.hasMore = false,
    this.oldestAvailable = 0,
    this.head = 0,
  });

  final List<TableChange> changes;

  /// More changes follow this page; ask again from the last one applied.
  final bool hasMore;

  /// The oldest change the server still holds. A cursor below it points at
  /// pruned history, and replaying from it would skip what was pruned.
  final int oldestAvailable;

  /// The newest change the server holds.
  final int head;
}

/// `GET /api/replica/bootstrap`: every list, and the head to start from.
class ReplicaBootstrap {
  const ReplicaBootstrap({
    required this.head,
    required this.lists,
    this.missing = const <String>{},
  });

  final int head;
  final Map<String, List<Map<String, dynamic>>> lists;

  /// Lists that failed to load on the server. Ones the user may not read are
  /// in neither [lists] nor here: there is nothing to retry for them.
  final Set<String> missing;
}

typedef ChangesPageFetcher = Future<ChangesPage> Function(int since);
typedef BootstrapFetcher = Future<ReplicaBootstrap?> Function();

/// How a replica comes up to date: replay from its cursor when it has one it
/// can trust, take a fresh copy when it does not.
///
/// Kept apart from [ReplicaSyncService] so it can run against an in-memory
/// database in a test; the service owns the lifecycle, this owns the decision.
class ReplicaCatchUp {
  ReplicaCatchUp({
    required DeltaSyncEngine engine,
    required SyncMetadataStore cursor,
    required ChangesPageFetcher fetchChangesPage,
    required Iterable<String> listTables,
    BootstrapFetcher? fetchBootstrap,
    bool Function(TableChange change)? inScope,
  }) : _engine = engine,
       _cursor = cursor,
       _fetchChangesPage = fetchChangesPage,
       _listTables = listTables.toList(growable: false),
       _fetchBootstrap = fetchBootstrap,
       _inScope = inScope;

  final DeltaSyncEngine _engine;
  final SyncMetadataStore _cursor;
  final ChangesPageFetcher _fetchChangesPage;
  final List<String> _listTables;
  final BootstrapFetcher? _fetchBootstrap;

  /// Which changes this replica holds. A replica of some tables only (the
  /// phone's) skips the rest — fetching a record it does not keep would cost
  /// a request for nothing — and still moves its cursor past them.
  final bool Function(TableChange change)? _inScope;

  /// The largest changelog id there could be. Asking for changes after it
  /// returns none, and the head — the cheapest way to learn where the log is.
  static const int _beyondAnyId = 9007199254740991;

  /// Brings the replica up to date. Returns the changes replayed, and whether
  /// it took a fresh copy instead (the caller announces every table then).
  ///
  /// Throws when the server cannot be reached; the replica is left as it was,
  /// stale but usable.
  Future<({List<TableChange> replayed, bool hydrated})> run() async {
    var since = await _cursor.lastChangelogId();
    if (since <= 0) {
      await _hydrate();
      return (replayed: const <TableChange>[], hydrated: true);
    }

    final replayed = <TableChange>[];
    while (true) {
      final page = await _fetchChangesPage(since);
      // The next change this replica needs is since + 1. If the server no longer
      // holds it, every change between was pruned, and only a fresh copy is
      // correct.
      if (page.oldestAvailable > 0 && since + 1 < page.oldestAvailable) {
        await _cursor.reset();
        await _hydrate();
        return (replayed: replayed, hydrated: true);
      }
      // A cursor past the server's last change was not made on this log: the
      // database was restored from a backup, or rebuilt. Nothing would ever
      // replay, and the copy would stay the other log's for good.
      if (page.head > 0 && since > page.head) {
        await _cursor.reset();
        await _hydrate();
        return (replayed: replayed, hydrated: true);
      }
      if (page.changes.isEmpty) break;
      final inScope = _inScope;
      final mine = inScope == null
          ? page.changes
          : page.changes.where(inScope).toList(growable: false);
      if (mine.isNotEmpty) {
        await _engine.apply(mine, cursor: _cursor);
        replayed.addAll(mine);
      }
      // Past the changes this replica skips, but only once every one it keeps
      // has landed: the engine holds the cursor before a change it could not
      // apply, and that must not be jumped.
      final lastMine = mine.isEmpty ? 0 : mine.map((c) => c.changelogId).reduce((a, b) => a > b ? a : b);
      if (await _cursor.lastChangelogId() >= lastMine) {
        final pageEnd = page.changes.map((c) => c.changelogId).reduce((a, b) => a > b ? a : b);
        await _cursor.setLastChangelogId(pageEnd);
      }
      final reached = await _cursor.lastChangelogId();
      // A change that could not be applied holds the cursor where it is; asking
      // again would only fail on it again. The next sync retries.
      if (reached <= since) break;
      since = reached;
      if (!page.hasMore) break;
    }
    return (replayed: replayed, hydrated: false);
  }

  /// A fresh copy, and the head it is a copy as of.
  ///
  /// The head is taken BEFORE the lists are read (the bootstrap does the same
  /// on the server), so a write landing in between is replayed next time
  /// rather than skipped. Without a head recorded here the cursor stayed at 0
  /// and every launch downloaded every list again (B41).
  ///
  /// The head is recorded only when every list the user can read arrived. A
  /// table that failed would otherwise sit empty behind a cursor that says the
  /// copy is complete, and only single-record changes would ever reach it; left
  /// at 0, the next launch takes the copy again.
  Future<void> _hydrate() async {
    final bootstrap = _fetchBootstrap == null ? null : await _fetchBootstrap();
    if (bootstrap != null) {
      await _engine.applyListRows(bootstrap.lists);
      final retry = bootstrap.missing.where(_listTables.contains).toList(growable: false);
      final filled = retry.isEmpty ? 0 : await _engine.hydrateLists(retry);
      if (filled == retry.length) await _cursor.setLastChangelogId(bootstrap.head);
      return;
    }
    final head = (await _fetchChangesPage(_beyondAnyId)).head;
    final filled = await _engine.hydrateLists(_listTables);
    if (filled == _listTables.length) await _cursor.setLastChangelogId(head);
  }
}

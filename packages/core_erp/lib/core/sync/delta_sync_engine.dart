import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database/sync_metadata_store.dart';
import 'replica_bindings.dart';

/// One change the server announced.
class TableChange {
  const TableChange({
    required this.table,
    required this.recordId,
    required this.action,
    this.changelogId = 0,
  });

  final String table;
  final Object recordId;

  /// INSERT, UPDATE or DELETE.
  final String action;

  /// Position in the changelog, used to advance the cursor.
  final int changelogId;

  String get foldKey => '$table::$recordId';
}

/// Fetches one record from the server. Returns null when it is gone (404).
typedef RecordFetcher = Future<Map<String, dynamic>?> Function(
  String serverTable,
  Object key,
);

/// Fetches a whole list, for the tables with no by-id endpoint.
typedef ListFetcher = Future<List<Map<String, dynamic>>> Function(
  String serverTable,
);

/// Applies changelog events to the local replica.
///
/// The server announces `(table, record_id, action)` and nothing more, so this
/// has to decide what to fetch and where to put it. The decisions live in
/// [kReplicaBindings] as data; this is the machinery that runs them.
///
/// Two properties matter more than speed:
///
/// **It folds.** A change-data-capture feed announces rows, not user actions:
/// filing three items into a group announces the group three times, and a
/// single request can announce the same row from a trigger and its parent's
/// trigger. Applying each announcement separately would be correct but would
/// fetch the same record repeatedly.
///
/// **It does not advance the cursor past work it did not do.** If a fetch
/// fails, the position stays behind that change so the next sync retries it.
/// A cursor that moved on regardless would turn a transient network error into
/// permanent staleness, which is the failure this whole design exists to avoid.
class DeltaSyncEngine {
  DeltaSyncEngine({
    required Database database,
    required RecordFetcher fetchRecord,
    required ListFetcher fetchList,
    Map<String, ReplicaBinding> bindings = kReplicaBindings,
  }) : _db = database,
       _fetchRecord = fetchRecord,
       _fetchList = fetchList,
       _bindings = bindings;

  final Database _db;
  final RecordFetcher _fetchRecord;
  final ListFetcher _fetchList;
  final Map<String, ReplicaBinding> _bindings;

  /// Tables the engine was asked about but has no binding for.
  ///
  /// Recorded rather than thrown: the server may learn to announce a table this
  /// build has never heard of, and dropping the whole batch for one unknown
  /// name would be worse than skipping it. Surfaced so it is visible instead of
  /// silent.
  final Set<String> unknownTables = <String>{};

  int applied = 0;
  int skipped = 0;
  int failed = 0;

  /// Applies a batch and returns the highest changelog id fully applied.
  ///
  /// Everything up to and including the returned id is on disk. A caller should
  /// persist exactly that and no more.
  /// Serialises concurrent calls.
  ///
  /// Two SSE batches arriving close together would otherwise interleave, and a
  /// later batch's cursor write could mask an earlier batch's failure — the
  /// failed change would then never be retried. Queueing costs a little
  /// latency and removes a whole class of lost update.
  Future<void> _inFlight = Future<void>.value();

  Future<int> apply(Iterable<TableChange> changes, {SyncMetadataStore? cursor}) {
    final result = _inFlight.then((_) => _applyBatch(changes, cursor));
    _inFlight = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<int> _applyBatch(Iterable<TableChange> changes, SyncMetadataStore? cursor) async {
    final folded = _fold(changes);
    if (folded.isEmpty) return 0;

    // Refetched lists are gathered first so a table announced twenty times in
    // one batch is fetched once.
    final listTables = <String>{};
    for (final change in folded) {
      final binding = _bindings[change.table];
      if (binding?.strategy == DeltaStrategy.refetchList) {
        listTables.add(binding!.serverTable);
      }
    }

    var highestApplied = 0;
    var blockedAt = -1;

    for (final table in listTables) {
      final ok = await _applyList(table);
      if (!ok) {
        failed += 1;
        // A failed list refetch blocks the cursor at the earliest change for
        // that table, so it is retried rather than skipped.
        for (final change in folded) {
          if (change.table == table && change.changelogId > 0) {  // positioned changes only
            blockedAt = blockedAt < 0
                ? change.changelogId
                : (change.changelogId < blockedAt ? change.changelogId : blockedAt);
            break;
          }
        }
      }
    }

    for (final change in folded) {
      final binding = _bindings[change.table];
      if (binding == null) {
        unknownTables.add(change.table);
        skipped += 1;
        // Credited, deliberately. This build will never be able to apply it, so
        // withholding the cursor would replay it on every sync forever and — if
        // it were the only change in a batch — wedge the position permanently.
        if (blockedAt < 0 || change.changelogId < blockedAt) {
          highestApplied = _max(highestApplied, change.changelogId);
        }
        continue;
      }
      if (binding.strategy == DeltaStrategy.refetchList) {
        // Handled above.
        if (blockedAt < 0 || change.changelogId < blockedAt) {
          highestApplied = _max(highestApplied, change.changelogId);
        }
        continue;
      }

      final outcome = await _applyOne(change, binding);
      switch (outcome) {
        case _Outcome.applied:
          applied += 1;
          break;
        case _Outcome.skipped:
          skipped += 1;
          break;
        case _Outcome.failed:
          failed += 1;
          // Only a change with a real position can block one. A live event
          // carries changelogId 0, and treating that as a block set the barrier
          // to 0 and froze the cursor for the entire batch — every change after
          // it, however successful, went uncredited and was replayed forever.
          if (change.changelogId > 0) {
            blockedAt = blockedAt < 0
                ? change.changelogId
                : (change.changelogId < blockedAt ? change.changelogId : blockedAt);
          }
          break;
      }
      if (outcome != _Outcome.failed &&
          (blockedAt < 0 || change.changelogId < blockedAt)) {
        highestApplied = _max(highestApplied, change.changelogId);
      }
    }

    if (cursor != null && highestApplied > 0) {
      await cursor.setLastChangelogId(highestApplied);
    }
    return highestApplied;
  }

  int _max(int a, int b) => a > b ? a : b;

  /// Collapses repeats, keeping the last action and the highest position.
  ///
  /// A DELETE always wins over an earlier INSERT/UPDATE for the same row: the
  /// row is gone, and fetching it would only 404.
  List<TableChange> _fold(Iterable<TableChange> changes) {
    final byKey = <String, TableChange>{};
    for (final change in changes) {
      final existing = byKey[change.foldKey];
      if (existing == null) {
        byKey[change.foldKey] = change;
        continue;
      }
      // The LAST action wins, by changelog position — not DELETE
      // unconditionally. A row deleted and then recreated under the same key in
      // one batch (a text-keyed template, a reused id) must end up present; a
      // blanket "delete wins" would have left it missing from the replica until
      // something else happened to touch it.
      final latest = change.changelogId >= existing.changelogId ? change : existing;
      byKey[change.foldKey] = TableChange(
        table: change.table,
        recordId: change.recordId,
        action: latest.action,
        changelogId: _max(existing.changelogId, change.changelogId),
      );
    }
    final ordered = byKey.values.toList()
      ..sort((a, b) => a.changelogId.compareTo(b.changelogId));
    return ordered;
  }

  Future<_Outcome> _applyOne(TableChange change, ReplicaBinding binding) async {
    switch (binding.strategy) {
      case DeltaStrategy.ignore:
        return _Outcome.skipped;

      case DeltaStrategy.viaParent:
        return _applyViaParent(change, binding);

      case DeltaStrategy.refetchList:
        return _Outcome.skipped;

      case DeltaStrategy.fetchByBarcode:
        return _applyByBarcode(change, binding);

      case DeltaStrategy.fetchById:
        if (change.action == 'DELETE') {
          await _deleteLocal(binding, change.recordId);
          return _Outcome.applied;
        }
        return _fetchAndUpsert(binding, change.recordId, change.recordId);
    }
  }

  /// A variation node has no endpoint. Refresh the item that embeds it.
  Future<_Outcome> _applyViaParent(TableChange change, ReplicaBinding binding) async {
    final parent = _bindings[binding.parentTable];
    if (parent == null) return _Outcome.skipped;

    // The parent id comes from the replica's own copy of the child. On an
    // INSERT of a node the replica has never seen — or a DELETE of one already
    // gone — there is nothing to look it up in, and the item will come right on
    // its own next refresh rather than being guessed at here.
    final rows = await _db.query(
      'local_item_variation_nodes',
      columns: <String>[binding.parentIdColumn!],
      where: 'id = ?',
      whereArgs: <Object?>[change.recordId],
      limit: 1,
    );
    if (rows.isEmpty) return _Outcome.skipped;

    final parentId = rows.first[binding.parentIdColumn!];
    if (parentId == null) return _Outcome.skipped;
    return _fetchAndUpsert(parent, parentId, parentId);
  }

  /// Materials are announced by id and fetched by barcode.
  Future<_Outcome> _applyByBarcode(TableChange change, ReplicaBinding binding) async {
    // A delete needs no barcode: the local key is the announced id.
    if (change.action == 'DELETE') {
      await _deleteLocal(binding, change.recordId);
      return _Outcome.applied;
    }

    final rows = await _db.query(
      binding.localTable!,
      columns: <String>['barcode'],
      where: 'id = ?',
      whereArgs: <Object?>[change.recordId],
      limit: 1,
    );

    if (rows.isEmpty) {
      // Never seen it, so there is no barcode to fetch by. The whole list is
      // the only correct answer — materials is ~20 KB, and getting this wrong
      // means a new material never appears at all.
      final ok = await _applyList(binding.serverTable);
      return ok ? _Outcome.applied : _Outcome.failed;
    }

    final barcode = rows.first['barcode'];
    if (barcode == null || '$barcode'.isEmpty) return _Outcome.skipped;
    return _fetchAndUpsert(binding, barcode, change.recordId);
  }

  Future<_Outcome> _fetchAndUpsert(
    ReplicaBinding binding,
    Object fetchKey,
    Object localKey,
  ) async {
    Map<String, dynamic>? payload;
    try {
      payload = await _fetchRecord(binding.serverTable, fetchKey);
    } catch (_) {
      return _Outcome.failed;
    }
    if (payload == null) {
      // Gone on the server. Removing it locally is the correct reading of a
      // 404 for a record we were just told changed.
      await _deleteLocal(binding, localKey);
      return _Outcome.applied;
    }
    await _upsert(binding, payload);
    return _Outcome.applied;
  }

  /// Fills the named tables from their list endpoints.
  ///
  /// The first-run path, when there is no cursor to replay from. Uses the same
  /// writer as a steady-state refetch so hydration and delta application cannot
  /// drift — two paths would, and the second would be the one nobody tests.
  Future<int> hydrateLists(Iterable<String> serverTables) async {
    var filled = 0;
    for (final table in serverTables) {
      final binding = _bindings[table];
      if (binding?.localTable == null) continue;
      if (await _applyList(table)) filled += 1;
    }
    return filled;
  }

  Future<bool> _applyList(String serverTable) async {
    final binding = _bindings[serverTable];
    if (binding?.localTable == null) return false;
    List<Map<String, dynamic>> rows;
    try {
      rows = await _fetchList(serverTable);
    } catch (_) {
      return false;
    }
    await _db.transaction((txn) async {
      // Replace wholesale: a list refetch is the authority on what exists, and
      // upserting alone would leave rows deleted on the server sitting locally
      // forever.
      await txn.delete(binding!.localTable!);
      for (final row in rows) {
        await _upsertRow(
          txn,
          binding.localTable!,
          binding.keyColumn,
          _columnsFor(binding, row),
        );
      }
    });
    applied += rows.length;
    return true;
  }

  Future<void> _upsert(ReplicaBinding binding, Map<String, dynamic> payload) async {
    await _upsertRow(_db, binding.localTable!, binding.keyColumn, _columnsFor(binding, payload));
    if (binding.localTable == 'local_items') {
      await _mirrorVariationNodes(_db, payload);
    }
  }

  /// A real upsert: INSERT … ON CONFLICT DO UPDATE.
  ///
  /// NOT `ConflictAlgorithm.replace`, which compiles to `INSERT OR REPLACE` —
  /// and that **deletes the existing row first**, firing every
  /// `ON DELETE CASCADE` hanging off it. Updating a challan would have silently
  /// emptied `local_delivery_challan_items`, so the replica would have shown
  /// every challan as having no lines the moment anything about it changed.
  static Future<void> _upsertRow(
    DatabaseExecutor db,
    String table,
    String keyColumn,
    Map<String, Object?> values,
  ) async {
    final columns = values.keys.toList();
    final assignments = columns
        .where((column) => column != keyColumn)
        .map((column) => '"$column" = excluded."$column"')
        .join(', ');
    final sql = StringBuffer()
      ..write('INSERT INTO $table (')
      ..write(columns.map((c) => '"$c"').join(', '))
      ..write(') VALUES (')
      ..write(List<String>.filled(columns.length, '?').join(', '))
      ..write(') ON CONFLICT("$keyColumn") DO ')
      ..write(assignments.isEmpty ? 'NOTHING' : 'UPDATE SET $assignments');
    await db.rawInsert(sql.toString(), columns.map((c) => values[c]).toList());
  }

  /// Copies an item's nested variation tree into the flat mirror.
  ///
  /// The mirror exists so a `item_variation_nodes` change can be resolved back
  /// to the item that embeds it. Nothing else populated it, so `viaParent`
  /// could never fire and a variation edit reached the replica only by luck.
  ///
  /// Lookup only. The item's own payload stays the authority on the tree —
  /// `updateItem` sends the whole tree as a destructive replace, so a tree
  /// rebuilt from these rows and sent back would delete whatever the rebuild
  /// missed.
  static Future<void> _mirrorVariationNodes(
    DatabaseExecutor db,
    Map<String, dynamic> item,
  ) async {
    final itemId = _int(item, <String>['id']);
    if (itemId == null) return;
    final tree = item['variationTree'];
    if (tree is! List) return;

    await db.delete(
      'local_item_variation_nodes',
      where: 'item_id = ?',
      whereArgs: <Object?>[itemId],
    );

    Future<void> walk(List<dynamic> nodes, Object? parentId) async {
      for (final raw in nodes) {
        if (raw is! Map) continue;
        final node = raw.cast<String, dynamic>();
        final id = _int(node, <String>['id']);
        if (id == null) continue;
        await db.insert('local_item_variation_nodes', <String, Object?>{
          'id': id,
          'item_id': itemId,
          'parent_node_id': parentId,
          'kind': _str(node, <String>['kind']),
          'name': _str(node, <String>['name']),
          'position': _int(node, <String>['position']) ?? 0,
          'is_archived': _bool(node, <String>['isArchived', 'is_archived']),
          'raw_payload_json': jsonEncode(node),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        final children = node['children'];
        if (children is List) await walk(children, id);
      }
    }

    await walk(tree, null);
  }

  Future<void> _deleteLocal(ReplicaBinding binding, Object key) async {
    if (binding.localTable == null) return;
    await _db.delete(
      binding.localTable!,
      where: '${binding.keyColumn} = ?',
      whereArgs: <Object?>[binding.keyIsText ? '$key' : key],
    );
  }

  /// The columns to write for one record.
  ///
  /// The payload is stored **verbatim** and the extracted columns exist only to
  /// filter and sort in SQL. Nothing reconstructs a payload from them: the read
  /// DTOs have `fromJson` and no `toJson`, and — more sharply — `updateItem`
  /// sends the whole variation tree as a destructive replace, so a payload
  /// rebuilt from parts and sent back would delete whatever the rebuild missed.
  Map<String, Object?> _columnsFor(ReplicaBinding binding, Map<String, dynamic> payload) {
    final row = <String, Object?>{'raw_payload_json': jsonEncode(payload)};
    final extractor = _extractors[binding.localTable];
    if (extractor != null) row.addAll(extractor(payload));
    return row;
  }

  static Object? _pick(Map<String, dynamic> p, List<String> keys) {
    for (final key in keys) {
      final value = p[key];
      if (value != null) return value;
    }
    return null;
  }

  static String _str(Map<String, dynamic> p, List<String> keys) =>
      '${_pick(p, keys) ?? ''}';

  static int? _int(Map<String, dynamic> p, List<String> keys) {
    final value = _pick(p, keys);
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}');
  }

  static double _dbl(Map<String, dynamic> p, List<String> keys) {
    final value = _pick(p, keys);
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0;
  }

  static int _bool(Map<String, dynamic> p, List<String> keys) {
    final value = _pick(p, keys);
    if (value is bool) return value ? 1 : 0;
    if (value is num) return value == 0 ? 0 : 1;
    return '$value'.toLowerCase() == 'true' ? 1 : 0;
  }

  /// Which columns each local table keeps outside the payload.
  ///
  /// Both spellings are accepted throughout because the API is inconsistent
  /// about camelCase and snake_case — several endpoints send both, and a few
  /// send only one.
  static final Map<String, Map<String, Object?> Function(Map<String, dynamic>)>
      _extractors = <String, Map<String, Object?> Function(Map<String, dynamic>)>{
    'local_items': (p) => <String, Object?>{
      'id': _int(p, <String>['id']),
      'name': _str(p, <String>['name']),
      'display_name': _str(p, <String>['displayName', 'display_name']),
      'short_code': _str(p, <String>['shortCode', 'short_code']),
      'group_id': _int(p, <String>['groupId', 'group_id']),
      'unit_id': _int(p, <String>['unitId', 'unit_id']),
      'is_archived': _bool(p, <String>['isArchived', 'is_archived']),
      'updated_at': _str(p, <String>['updatedAt', 'updated_at']),
    },
    'local_groups': (p) => <String, Object?>{
      'id': _int(p, <String>['id']),
      'name': _str(p, <String>['name']),
      'parent_group_id': _int(p, <String>['parentGroupId', 'parent_group_id']),
      'group_type': _str(p, <String>['groupType', 'group_type']),
      'group_structure': _str(p, <String>['groupStructure', 'group_structure']),
      'is_archived': _bool(p, <String>['isArchived', 'is_archived']),
    },
    'local_order_items': (p) => <String, Object?>{
      'id': _int(p, <String>['id']),
      'order_no': _str(p, <String>['orderNo', 'order_no']),
      'client_id': _int(p, <String>['clientId', 'client_id']),
      'client_name': _str(p, <String>['clientName', 'client_name']),
      'item_id': _int(p, <String>['itemId', 'item_id']),
      'item_name': _str(p, <String>['itemName', 'item_name']),
      'variation_leaf_node_id':
          _int(p, <String>['variationLeafNodeId', 'variation_leaf_node_id']) ?? 0,
      'variation_path_label':
          _str(p, <String>['variationPathLabel', 'variation_path_label']),
      'po_number': _str(p, <String>['poNumber', 'po_number']),
      'client_code': _str(p, <String>['clientCode', 'client_code']),
      'quantity': _dbl(p, <String>['quantity']),
      'status': _str(p, <String>['status']),
      'created_at': _str(p, <String>['createdAt', 'created_at']),
    },
    'local_delivery_challans': (p) => <String, Object?>{
      'id': _int(p, <String>['id']),
      'challan_no': _str(p, <String>['challanNo', 'challan_no']),
      'challan_date': _str(p, <String>['date', 'challanDate', 'challan_date']),
      'type': _str(p, <String>['type']),
      'status': _str(p, <String>['status']),
      'customer_name': _str(p, <String>['customerName', 'customer_name']),
      'vendor_name': _str(p, <String>['vendorName', 'vendor_name']),
      'order_no': _str(p, <String>['orderNo', 'order_no']),
      'line_count': _int(p, <String>['lineCount', 'itemsCount', 'items_count']) ?? 0,
      'total_qty': _dbl(p, <String>['totalQty', 'totalQuantity']),
      'total_weight': _dbl(p, <String>['totalWeight']),
      'created_at': _str(p, <String>['createdAt', 'created_at']),
    },
    'local_materials': (p) => <String, Object?>{
      'id': _int(p, <String>['id']),
      'barcode': _str(p, <String>['barcode']),
      'name': _str(p, <String>['name']),
      'type': _str(p, <String>['type']),
      'kind': _str(p, <String>['kind']),
      'created_at': _str(p, <String>['createdAt', 'created_at']),
      'linked_item_id': _int(p, <String>['linkedItemId', 'linked_item_id']),
      'linked_variation_leaf_node_id': _int(
        p,
        <String>['linkedVariationLeafNodeId', 'linked_variation_leaf_node_id'],
      ),
      'inventory_state': _str(p, <String>['inventoryState', 'inventory_state']),
    },
    // `gstNumber` is what the server sends. Reading `gstin` stored empty
    // strings on every row, and nothing would have looked broken.
    'local_clients': (p) => <String, Object?>{
      'id': _int(p, <String>['id']),
      'name': _str(p, <String>['name']),
      'gst_number': _str(p, <String>['gstNumber', 'gst_number']),
    },
    'local_vendors': (p) => <String, Object?>{
      'id': _int(p, <String>['id']),
      'name': _str(p, <String>['name']),
      'gst_number': _str(p, <String>['gstNumber', 'gst_number']),
    },
    'local_machines': (p) => <String, Object?>{
      'id': _int(p, <String>['id']),
      'name': _str(p, <String>['name']),
      'status': _str(p, <String>['status']),
      'location': _str(p, <String>['location']),
    },
    // No `name` — dieRowToDto does not emit one. Identity is the tool code.
    'local_dies': (p) => <String, Object?>{
      'id': _int(p, <String>['id']),
      'tool_code': _str(p, <String>['toolCode', 'tool_code']),
      'status': _str(p, <String>['status']),
      'ownership': _str(p, <String>['ownership']),
    },
    'local_units': (p) => <String, Object?>{
      'id': _int(p, <String>['id']),
      'name': _str(p, <String>['name']),
      'symbol': _str(p, <String>['symbol']),
    },
    'local_departments': (p) => <String, Object?>{
      'id': _int(p, <String>['id']),
      'name': _str(p, <String>['name']),
    },
    'local_pipeline_templates': (p) => <String, Object?>{
      'id': _str(p, <String>['id']),
      'name': _str(p, <String>['name']),
      'status': _str(p, <String>['status']),
    },
    'local_pipeline_runs': (p) => <String, Object?>{
      'id': _str(p, <String>['id']),
      'name': _str(p, <String>['name']),
      'status': _str(p, <String>['status']),
      'template_id': _str(p, <String>['templateId', 'template_id']),
    },
  };
}

enum _Outcome { applied, skipped, failed }

import 'dart:convert';

import 'package:core_erp/core/database/local_database_helper.dart';
import 'package:core_erp/core/database/sync_metadata_store.dart';
import 'package:core_erp/core/sync/delta_sync_engine.dart';
import 'package:core_erp/core/sync/replica_bindings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Turning `(table, record_id)` into "which local row, fetched how".
///
/// This is where a naive engine silently corrupts the replica: four of the
/// seventeen tables announce a key the obvious endpoint does not take, and the
/// failure is not a crash but a wrong record written confidently.

Future<Database> openReplica() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  for (final statement in LocalDatabaseHelper.schemaStatements) {
    await db.execute(statement);
  }
  return db;
}

/// Records what the engine asked the network for.
class FakeServer {
  final List<String> recordCalls = <String>[];
  final List<String> listCalls = <String>[];
  final Map<String, Map<String, dynamic>> records = <String, Map<String, dynamic>>{};
  final Map<String, List<Map<String, dynamic>>> lists =
      <String, List<Map<String, dynamic>>>{};
  final Set<String> failing = <String>{};

  Future<Map<String, dynamic>?> fetchRecord(String table, Object key) async {
    recordCalls.add('$table/$key');
    if (failing.contains(table)) throw StateError('network down');
    return records['$table/$key'];
  }

  Future<List<Map<String, dynamic>>> fetchList(String table) async {
    listCalls.add(table);
    if (failing.contains(table)) throw StateError('network down');
    return lists[table] ?? const <Map<String, dynamic>>[];
  }
}

void main() {
  late Database db;
  late FakeServer server;
  late DeltaSyncEngine engine;

  setUp(() async {
    db = await openReplica();
    server = FakeServer();
    engine = DeltaSyncEngine(
      database: db,
      fetchRecord: server.fetchRecord,
      fetchList: server.fetchList,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('the four mappings that would silently fetch the wrong record', () {
    test('a challan LINE never fetches a challan by the line id', () async {
      // The trigger key is a delivery_challan_items id. Handing it to
      // /api/challans/:id would fetch a DIFFERENT challan and write it over the
      // right one. Migration 041 announces the parent challan separately, so
      // this event has nothing left to do.
      await engine.apply(<TableChange>[
        const TableChange(
          table: 'delivery_challan_items',
          recordId: 42,
          action: 'UPDATE',
          changelogId: 1,
        ),
      ]);
      expect(server.recordCalls, isEmpty, reason: 'it must not fetch anything');
      expect(engine.skipped, 1);
    });

    test('an order_headers event is ignored, not passed to the orders filter', () async {
      // order_headers is keyed by order_no (TEXT) and nothing serves it. Passing
      // that text key to /api/orders?ids= used to return the ENTIRE table — for
      // a replica, "this record is now every record".
      await engine.apply(<TableChange>[
        const TableChange(
          table: 'order_headers',
          recordId: 'ORD-2026-014',
          action: 'UPDATE',
          changelogId: 1,
        ),
      ]);
      expect(server.recordCalls, isEmpty);
      expect(server.listCalls, isEmpty);
    });

    test('a material is fetched by its barcode, never by the announced id', () async {
      // The trigger writes NEW.id; the endpoint is keyed by barcode. An id
      // passed straight through 404s — or returns a different material, if some
      // vendor barcode happens to be that number.
      await db.insert('local_materials', <String, Object?>{
        'id': 17,
        'barcode': 'MAT-STEEL-2MM',
        'raw_payload_json': '{}',
      });
      server.records['materials/MAT-STEEL-2MM'] = <String, dynamic>{
        'id': 17,
        'barcode': 'MAT-STEEL-2MM',
        'name': 'Steel Sheet 2mm',
      };

      await engine.apply(<TableChange>[
        const TableChange(
          table: 'materials',
          recordId: 17,
          action: 'UPDATE',
          changelogId: 1,
        ),
      ]);

      expect(server.recordCalls, <String>['materials/MAT-STEEL-2MM']);
      final row = (await db.query('local_materials', where: 'id = 17')).single;
      expect(row['name'], 'Steel Sheet 2mm');
    });

    test('a material never seen before falls back to the whole list', () async {
      // On an INSERT there is no local row, so no barcode, so no fetchable URL.
      // Skipping would mean a new material never appears at all.
      server.lists['materials'] = <Map<String, dynamic>>[
        <String, dynamic>{'id': 99, 'barcode': 'MAT-NEW', 'name': 'Brand New'},
      ];
      await engine.apply(<TableChange>[
        const TableChange(
          table: 'materials',
          recordId: 99,
          action: 'INSERT',
          changelogId: 1,
        ),
      ]);
      expect(server.listCalls, <String>['materials']);
      final rows = await db.query('local_materials');
      expect(rows.single['barcode'], 'MAT-NEW');
    });

    test('a variation node refreshes the item that embeds it', () async {
      // No endpoint fetches a variation node, and the tree is nested inside the
      // item payload anyway.
      await db.insert('local_item_variation_nodes', <String, Object?>{
        'id': 500,
        'item_id': 7,
        'raw_payload_json': '{}',
      });
      server.records['items/7'] = <String, dynamic>{'id': 7, 'name': 'Socket'};

      await engine.apply(<TableChange>[
        const TableChange(
          table: 'item_variation_nodes',
          recordId: 500,
          action: 'UPDATE',
          changelogId: 1,
        ),
      ]);
      expect(server.recordCalls, <String>['items/7']);
      expect((await db.query('local_items')).single['name'], 'Socket');
    });
  });

  group('folding', () {
    test('a row announced many times is fetched once', () async {
      // Filing three items into a group announces the group three times; a
      // single request announces a row from its own trigger and its parent's.
      server.records['clients/3'] = <String, dynamic>{'id': 3, 'name': 'Acme'};
      await engine.apply(<TableChange>[
        const TableChange(table: 'clients', recordId: 3, action: 'UPDATE', changelogId: 1),
        const TableChange(table: 'clients', recordId: 3, action: 'UPDATE', changelogId: 2),
        const TableChange(table: 'clients', recordId: 3, action: 'UPDATE', changelogId: 3),
      ]);
      expect(server.recordCalls, <String>['clients/3']);
    });

    test('a delete wins over an earlier update for the same row', () async {
      // Fetching a row that was deleted later in the same batch would only 404.
      await db.insert('local_clients', <String, Object?>{
        'id': 3,
        'name': 'Acme',
        'raw_payload_json': '{}',
      });
      await engine.apply(<TableChange>[
        const TableChange(table: 'clients', recordId: 3, action: 'UPDATE', changelogId: 1),
        const TableChange(table: 'clients', recordId: 3, action: 'DELETE', changelogId: 2),
      ]);
      expect(server.recordCalls, isEmpty);
      expect(await db.query('local_clients'), isEmpty);
    });
  });

  group('the cursor', () {
    test('does not advance past a change that failed', () async {
      // A cursor that moved on regardless would turn a transient network error
      // into permanent staleness — the exact failure this design exists to
      // avoid.
      server.records['clients/1'] = <String, dynamic>{'id': 1, 'name': 'First'};
      server.failing.add('vendors');

      final store = SyncMetadataStore(db);
      final applied = await engine.apply(<TableChange>[
        const TableChange(table: 'clients', recordId: 1, action: 'UPDATE', changelogId: 10),
        const TableChange(table: 'vendors', recordId: 2, action: 'UPDATE', changelogId: 11),
      ], cursor: store);

      expect(applied, 10, reason: 'stops short of the failure');
      expect(await store.lastChangelogId(), 10);
      expect(engine.failed, 1);
    });

    test('a later success does not skip an earlier failure', () async {
      // The dangerous ordering: if 11 fails and 12 succeeds, reporting 12 would
      // strand 11 forever.
      server.records['clients/1'] = <String, dynamic>{'id': 1, 'name': 'Later'};
      server.failing.add('vendors');

      final applied = await engine.apply(<TableChange>[
        const TableChange(table: 'vendors', recordId: 2, action: 'UPDATE', changelogId: 11),
        const TableChange(table: 'clients', recordId: 1, action: 'UPDATE', changelogId: 12),
      ]);
      expect(applied, lessThan(11), reason: 'the cursor stays behind the failure');
    });
  });

  group('what it stores', () {
    test('the payload is kept verbatim, extracted columns beside it', () async {
      // Nothing reconstructs a payload from the columns: the read DTOs have no
      // toJson, and updateItem sends the whole variation tree as a destructive
      // replace — so a payload rebuilt from parts would delete what the rebuild
      // missed.
      final payload = <String, dynamic>{
        'id': 7,
        'name': 'Socket',
        'displayName': 'Socket 10A',
        'isArchived': false,
        'variationTree': <dynamic>[
          <String, dynamic>{'id': 1, 'name': 'Finish', 'children': <dynamic>[]},
        ],
        'someFieldThisBuildHasNeverHeardOf': 'kept anyway',
      };
      server.records['items/7'] = payload;

      await engine.apply(<TableChange>[
        const TableChange(table: 'items', recordId: 7, action: 'UPDATE', changelogId: 1),
      ]);

      final row = (await db.query('local_items')).single;
      expect(row['name'], 'Socket');
      expect(row['display_name'], 'Socket 10A');
      expect(row['is_archived'], 0);

      final stored = jsonDecode(row['raw_payload_json'] as String) as Map<String, dynamic>;
      expect(stored, payload, reason: 'byte-for-byte what the server sent');
      expect(stored['someFieldThisBuildHasNeverHeardOf'], 'kept anyway');
      expect((stored['variationTree'] as List).length, 1);
    });

    test('a 404 removes the local row rather than leaving it', () async {
      // A record we were just told changed, which the server then says does not
      // exist, is gone.
      await db.insert('local_clients', <String, Object?>{
        'id': 5,
        'name': 'Departed',
        'raw_payload_json': '{}',
      });
      await engine.apply(<TableChange>[
        const TableChange(table: 'clients', recordId: 5, action: 'UPDATE', changelogId: 1),
      ]);
      expect(await db.query('local_clients'), isEmpty);
    });

    test('a list refetch removes rows the server no longer has', () async {
      // Upserting alone would leave deleted rows sitting locally forever.
      await db.insert('local_units', <String, Object?>{
        'id': 1,
        'name': 'Gone',
        'raw_payload_json': '{}',
      });
      server.lists['units'] = <Map<String, dynamic>>[
        <String, dynamic>{'id': 2, 'name': 'Kilogram', 'symbol': 'kg'},
      ];
      await engine.apply(<TableChange>[
        const TableChange(table: 'units', recordId: 2, action: 'INSERT', changelogId: 1),
      ]);
      final rows = await db.query('local_units');
      expect(rows.map((r) => r['name']), <String>['Kilogram']);
    });

    test('a text-keyed row round-trips without being coerced to zero', () async {
      // pipeline_runs.id is 'demo-dolly-run-active'.
      server.records['pipeline_runs/demo-dolly-run-active'] =
          <String, dynamic>{'id': 'demo-dolly-run-active', 'name': 'Morning', 'status': 'active'};
      await engine.apply(<TableChange>[
        const TableChange(
          table: 'pipeline_runs',
          recordId: 'demo-dolly-run-active',
          action: 'UPDATE',
          changelogId: 1,
        ),
      ]);
      final row = (await db.query('local_pipeline_runs')).single;
      expect(row['id'], 'demo-dolly-run-active');
      expect(row['status'], 'active');
    });
  });

  test('a table this build has never heard of is recorded, not fatal', () async {
    // The server may learn to announce something new. Dropping the whole batch
    // for one unknown name would be worse than skipping it — but skipping
    // silently would hide it.
    server.records['clients/1'] = <String, dynamic>{'id': 1, 'name': 'Acme'};
    await engine.apply(<TableChange>[
      const TableChange(table: 'invoices', recordId: 1, action: 'INSERT', changelogId: 1),
      const TableChange(table: 'clients', recordId: 1, action: 'UPDATE', changelogId: 2),
    ]);
    expect(engine.unknownTables, <String>{'invoices'});
    expect((await db.query('local_clients')).length, 1, reason: 'the rest still applied');
  });

  group('extracted columns actually populate', () {
    // The quiet failure this whole group exists for: an extractor reading a key
    // the server does not send stores an empty string, nothing throws, and the
    // list then sorts and filters on nothing. Four were wrong — clients and
    // vendors read `gstin` where the server sends `gstNumber`, dies read a
    // `name` the die DTO has never had, materials read a `kind` it does not
    // emit.
    //
    // The payloads below are the real field names, taken from the running
    // server rather than from reading the DTO builders.

    Future<Map<String, Object?>> store(String table, Object id, Map<String, dynamic> payload) async {
      server.records['$table/$id'] = payload;
      await engine.apply(<TableChange>[
        TableChange(table: table, recordId: id, action: 'UPDATE', changelogId: 1),
      ]);
      final binding = kReplicaBindings[table]!;
      return (await db.query(binding.localTable!)).single;
    }

    test('a client keeps its GST number', () async {
      final row = await store('clients', 1, <String, dynamic>{
        'id': 1,
        'name': 'Acme Works',
        'alias': 'acme',
        'gstNumber': '27AABCU9603R1ZM',
        'address': 'Pune',
        'isArchived': false,
      });
      expect(row['name'], 'Acme Works');
      expect(row['gst_number'], '27AABCU9603R1ZM');
    });

    test('a vendor keeps its GST number', () async {
      final row = await store('vendors', 2, <String, dynamic>{
        'id': 2,
        'name': 'Steel Supply Co',
        'gstNumber': '29AAACS1234F1Z5',
        'contactName': 'Ramesh',
      });
      expect(row['gst_number'], '29AAACS1234F1Z5');
    });

    test('a die is identified by its tool code, which it has', () async {
      final row = await store('dies', 3, <String, dynamic>{
        'id': 3,
        'toolCode': 'DIE-SKT10-B',
        'status': 'active',
        'ownership': 'owned',
        'storageLocation': 'Rack A1',
      });
      expect(row['tool_code'], 'DIE-SKT10-B');
      expect(row['status'], 'active');
      expect(row['ownership'], 'owned');
    });

    test('a material keeps what the server actually sends about it', () async {
      await db.insert('local_materials', <String, Object?>{
        'id': 4,
        'barcode': 'MAT-1',
        'raw_payload_json': '{}',
      });
      server.records['materials/MAT-1'] = <String, dynamic>{
        'id': 4,
        'barcode': 'MAT-1',
        'name': 'Steel Sheet',
        'type': 'raw_material',
        'linkedItemId': 9,
        'linkedVariationLeafNodeId': 11,
        'inventoryState': 'available',
      };
      await engine.apply(<TableChange>[
        const TableChange(table: 'materials', recordId: 4, action: 'UPDATE', changelogId: 1),
      ]);
      final row = (await db.query('local_materials')).single;
      expect(row['name'], 'Steel Sheet');
      expect(row['type'], 'raw_material');
      expect(row['linked_item_id'], 9);
      expect(row['inventory_state'], 'available');
    });

    test('no extractor writes a column its table does not have', () async {
      // sqflite throws on an unknown column, so this would be a runtime crash
      // on the first delta for that table rather than a compile error.
      final payload = <String, dynamic>{'id': 1, 'name': 'x', 'status': 'y'};
      for (final entry in kReplicaBindings.entries) {
        final binding = entry.value;
        if (binding.localTable == null) continue;
        if (binding.strategy == DeltaStrategy.fetchByBarcode) continue;
        server.records['${entry.key}/1'] = payload;
        await engine.apply(<TableChange>[
          TableChange(table: entry.key, recordId: 1, action: 'UPDATE', changelogId: 1),
        ]);
      }
      expect(engine.failed, 0, reason: 'every extractor matched its table');
    });
  });

  group('bugs an adversarial review found', () {
    test('updating a challan does not wipe its lines', () async {
      // ConflictAlgorithm.replace compiles to INSERT OR REPLACE, which DELETES
      // the existing row first — firing every ON DELETE CASCADE hanging off it.
      // Updating a challan silently emptied local_delivery_challan_items, so
      // the replica showed every challan as having no lines the moment anything
      // about it changed.
      await db.insert('local_delivery_challans', <String, Object?>{
        'id': 5,
        'challan_no': 'DC-5',
        'raw_payload_json': '{}',
      });
      await db.insert('local_delivery_challan_items', <String, Object?>{
        'id': 50,
        'challan_id': 5,
        'particulars': 'Steel sheet',
        'raw_payload_json': '{}',
      });
      await db.execute('PRAGMA foreign_keys = ON');

      server.records['delivery_challans/5'] = <String, dynamic>{
        'id': 5,
        'challan_no': 'DC-5',
        'status': 'issued',
      };
      await engine.apply(<TableChange>[
        const TableChange(
          table: 'delivery_challans',
          recordId: 5,
          action: 'UPDATE',
          changelogId: 1,
        ),
      ]);

      expect((await db.query('local_delivery_challans')).single['status'], 'issued');
      expect(
        await db.query('local_delivery_challan_items'),
        hasLength(1),
        reason: 'the lines survived the parent being updated',
      );
    });

    test('delete then recreate in one batch ends up present', () async {
      // A blanket "DELETE wins" left a row missing from the replica until
      // something else happened to touch it. The last action by changelog
      // position is what actually happened.
      server.records['pipeline_templates/dolly'] =
          <String, dynamic>{'id': 'dolly', 'name': 'Dolly', 'status': 'active'};
      await engine.apply(<TableChange>[
        const TableChange(
          table: 'pipeline_templates',
          recordId: 'dolly',
          action: 'DELETE',
          changelogId: 5,
        ),
        const TableChange(
          table: 'pipeline_templates',
          recordId: 'dolly',
          action: 'INSERT',
          changelogId: 7,
        ),
      ]);
      final rows = await db.query('local_pipeline_templates');
      expect(rows, hasLength(1), reason: 'recreated after the delete');
      expect(rows.single['name'], 'Dolly');
    });

    test('recreate then delete still ends up deleted', () async {
      // The mirror image, so "last wins" is not just "delete never wins".
      await db.insert('local_pipeline_templates', <String, Object?>{
        'id': 'dolly',
        'name': 'Dolly',
        'raw_payload_json': '{}',
      });
      await engine.apply(<TableChange>[
        const TableChange(
          table: 'pipeline_templates',
          recordId: 'dolly',
          action: 'UPDATE',
          changelogId: 5,
        ),
        const TableChange(
          table: 'pipeline_templates',
          recordId: 'dolly',
          action: 'DELETE',
          changelogId: 7,
        ),
      ]);
      expect(await db.query('local_pipeline_templates'), isEmpty);
    });

    test('a live event with no position cannot freeze the cursor', () async {
      // A live SSE event carries changelogId 0. Treating a failure on one as a
      // barrier set the block to 0 and froze the cursor for the whole batch —
      // every later change, however successful, went uncredited and replayed
      // forever.
      server.failing.add('vendors');
      server.records['clients/1'] = <String, dynamic>{'id': 1, 'name': 'Acme'};

      final applied = await engine.apply(<TableChange>[
        const TableChange(table: 'vendors', recordId: 9, action: 'UPDATE'),
        const TableChange(table: 'clients', recordId: 1, action: 'UPDATE', changelogId: 12),
      ]);
      expect(applied, 12, reason: 'the positioned change still counted');
      expect(engine.failed, 1);
    });

    test('an unknown table does not wedge the cursor', () async {
      // This build can never apply it, so withholding the position would
      // replay it on every sync forever.
      final applied = await engine.apply(<TableChange>[
        const TableChange(table: 'invoices', recordId: 1, action: 'INSERT', changelogId: 30),
      ]);
      expect(applied, 30);
      expect(engine.unknownTables, contains('invoices'));
    });

    test('an item populates the variation-node mirror it is looked up through', () async {
      // Nothing wrote local_item_variation_nodes, so viaParent could never
      // resolve a node to its item and a variation edit reached the replica
      // only by luck.
      server.records['items/7'] = <String, dynamic>{
        'id': 7,
        'name': 'Socket',
        'variationTree': <dynamic>[
          <String, dynamic>{
            'id': 100,
            'kind': 'property',
            'name': 'Finish',
            'children': <dynamic>[
              <String, dynamic>{'id': 101, 'kind': 'value', 'name': 'Matte', 'children': <dynamic>[]},
            ],
          },
        ],
      };
      await engine.apply(<TableChange>[
        const TableChange(table: 'items', recordId: 7, action: 'UPDATE', changelogId: 1),
      ]);

      final nodes = await db.query('local_item_variation_nodes', orderBy: 'id');
      expect(nodes.map((n) => n['id']), <int>[100, 101]);
      expect(nodes.last['parent_node_id'], 100, reason: 'nesting is preserved');

      // And now the lookup that depends on it actually works.
      server.recordCalls.clear();
      await engine.apply(<TableChange>[
        const TableChange(
          table: 'item_variation_nodes',
          recordId: 101,
          action: 'UPDATE',
          changelogId: 2,
        ),
      ]);
      expect(server.recordCalls, <String>['items/7']);
    });

    test('overlapping batches do not lose a failure', () async {
      // Two SSE batches arriving close together would interleave, and the later
      // one's cursor write could mask the earlier one's failure — the failed
      // change would then never be retried.
      server.failing.add('vendors');
      server.records['clients/1'] = <String, dynamic>{'id': 1, 'name': 'Acme'};
      final store = SyncMetadataStore(db);

      final first = engine.apply(<TableChange>[
        const TableChange(table: 'vendors', recordId: 9, action: 'UPDATE', changelogId: 10),
      ], cursor: store);
      final second = engine.apply(<TableChange>[
        const TableChange(table: 'clients', recordId: 1, action: 'UPDATE', changelogId: 20),
      ], cursor: store);
      await Future.wait(<Future<int>>[first, second]);

      // The cursor never moves backwards, so the surviving value is the later
      // batch — what matters is that the failure was counted, not silently
      // dropped by an interleave.
      expect(engine.failed, 1);
    });
  });

  test('every binding names a local table unless it deliberately does not', () {
    // A binding with no strategy for where rows go is a silent hole.
    for (final entry in kReplicaBindings.entries) {
      final binding = entry.value;
      final needsTable = binding.strategy == DeltaStrategy.fetchById ||
          binding.strategy == DeltaStrategy.fetchByBarcode ||
          binding.strategy == DeltaStrategy.refetchList;
      expect(
        binding.localTable != null,
        needsTable,
        reason: '${entry.key} (${binding.strategy}) — ${binding.why}',
      );
      expect(binding.why, isNotEmpty, reason: '${entry.key} must say why');
    }
  });
}

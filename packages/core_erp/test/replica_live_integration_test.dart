@Tags(<String>['live'])
library;

import 'dart:convert';

import 'package:core_erp/core/database/local_database_helper.dart';
import 'package:core_erp/core/database/sync_metadata_store.dart';
import 'package:core_erp/core/sync/delta_sync_engine.dart';
import 'package:core_erp/core/sync/replica_api.dart';
import 'package:core_erp/core/sync/replica_bindings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The replica against the real backend.
///
/// Every other test here uses a fake server, which proves the engine's logic
/// and nothing about whether the endpoints exist, the envelopes match, or the
/// field names are what the extractors expect. Those are exactly the mistakes
/// that do not throw — they hydrate an empty replica and the app looks like a
/// workspace with no data in it.
///
/// Skipped unless PAPER_LIVE_PORT is set, so the ordinary suite stays hermetic.
/// Run with: tool/run_live_replica_test.sh

const int livePort = int.fromEnvironment('PAPER_LIVE_PORT', defaultValue: 0);
const String liveToken = String.fromEnvironment('PAPER_LIVE_TOKEN');

class _TokenClient extends http.BaseClient {
  _TokenClient(this._inner, this._token);
  final http.Client _inner;
  final String _token;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_token';
    return _inner.send(request);
  }
}

Future<Database> openReplica() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  for (final statement in LocalDatabaseHelper.schemaStatements) {
    await db.execute(statement);
  }
  return db;
}

void main() {
  if (livePort == 0) {
    test('live replica integration (skipped: PAPER_LIVE_PORT not set)', () {}, skip: true);
    return;
  }

  late Database db;
  late ReplicaApi api;
  late DeltaSyncEngine engine;
  late http.Client client;

  setUp(() async {
    db = await openReplica();
    client = _TokenClient(http.Client(), liveToken);
    api = ReplicaApi(client: client, baseUrl: 'http://127.0.0.1:$livePort');
    engine = DeltaSyncEngine(
      database: db,
      fetchRecord: api.fetchRecord,
      fetchList: api.fetchList,
    );
  });

  tearDown(() async {
    client.close();
    await db.close();
  });

  test('every list endpoint hydrates its local table', () async {
    // The check a fake server cannot make: that each path resolves, each
    // envelope unwraps, and each extractor's key names match what this backend
    // actually sends.
    final tables = <String>{
      for (final entry in kReplicaBindings.entries)
        if (entry.value.localTable != null &&
            entry.value.strategy != DeltaStrategy.viaParent)
          entry.key,
    };

    await engine.hydrateLists(tables);

    final empty = <String>[];
    final filled = <String, int>{};
    for (final table in tables) {
      final local = kReplicaBindings[table]!.localTable!;
      final rows = await db.query(local);
      filled[local] = rows.length;
      if (rows.isEmpty) empty.add(table);
    }

    // A workspace legitimately has empty tables, so this reports rather than
    // asserts non-empty — but the ones the live database is known to hold must
    // be there, or something is wrong with the path, the envelope or the shape.
    expect(filled['local_items'], greaterThan(0), reason: 'items: $filled');
    expect(filled['local_order_items'], greaterThan(0), reason: 'orders: $filled');
    expect(filled['local_delivery_challans'], greaterThan(0), reason: 'challans: $filled');
    expect(filled['local_materials'], greaterThan(0), reason: 'materials: $filled');
    // ignore: avoid_print
    print('LIVE hydrated: $filled  (empty: $empty)');
  });

  test('extracted columns are populated, not silently blank', () async {
    // The failure mode this whole exercise is about: an extractor reading a key
    // the server does not send stores an empty string, nothing throws, and any
    // list sorting or filtering on that column sorts on nothing.
    await engine.hydrateLists(<String>['items', 'order_items', 'delivery_challans', 'materials']);

    final item = (await db.query('local_items', limit: 1)).single;
    expect(item['name'], isNot(''), reason: 'item name');
    expect(item['id'], isNotNull);

    final order = (await db.query('local_order_items', limit: 1)).single;
    expect(order['order_no'], isNot(''), reason: 'order_no');
    expect(order['status'], isNot(''), reason: 'the computed status');
    expect(order['created_at'], isNot(''), reason: 'created_at drives the ordering');

    final challan = (await db.query('local_delivery_challans', limit: 1)).single;
    expect(challan['challan_no'], isNot(''), reason: 'challan_no');
    expect(challan['type'], isNot(''), reason: 'type');

    final material = (await db.query('local_materials', limit: 1)).single;
    expect(material['barcode'], isNot(''), reason: 'barcode is the fetch key');
    expect(material['id'], isNotNull, reason: 'id is how a delta finds it');
  });

  test('the stored payload is the server payload', () async {
    // What the repository hands back is this map parsed by the same fromJson
    // the network path uses, so it has to be exactly what arrived.
    await engine.hydrateLists(<String>['items']);
    final row = (await db.query('local_items', limit: 1)).single;
    final stored = jsonDecode(row['raw_payload_json'] as String) as Map<String, dynamic>;

    final live = await api.fetchRecord('items', stored['id']!);
    expect(live, isNotNull, reason: 'GET /api/items/:id resolves');
    expect(
      stored['variationTree'],
      live!['variationTree'],
      reason: 'the tree survives the round trip through the replica',
    );
  });

  test('a single record fetch works for every by-id binding', () async {
    // Nine tables claim a by-id endpoint. If one is wrong the delta engine
    // silently stops updating that table.
    await engine.hydrateLists(ReplicaApi.listPaths.keys);

    final failures = <String>[];
    for (final entry in kReplicaBindings.entries) {
      final binding = entry.value;
      if (binding.strategy != DeltaStrategy.fetchById) continue;
      if (!ReplicaApi.recordPaths.containsKey(entry.key)) continue;
      final rows = await db.query(binding.localTable!, limit: 1);
      if (rows.isEmpty) continue;
      final key = rows.single[binding.keyColumn];
      try {
        final record = await api.fetchRecord(entry.key, key!);
        if (record == null) failures.add('${entry.key}: 404 for $key');
      } catch (error) {
        failures.add('${entry.key}: $error');
      }
    }
    expect(failures, isEmpty);
  });

  test('the catch-up endpoint answers and states its floor', () async {
    final changes = await api.fetchChangesSince(0);
    expect(changes, isNotEmpty, reason: 'the seeded workspace wrote a changelog');
    expect(changes.first.table, isNotEmpty);
    expect(changes.first.changelogId, greaterThan(0));

    // And the cursor advances through a real apply.
    final store = SyncMetadataStore(db);
    final applied = await engine.apply(changes.take(20).toList(), cursor: store);
    expect(applied, greaterThan(0));
    expect(await store.lastChangelogId(), applied);
  });
}

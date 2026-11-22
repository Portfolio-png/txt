import 'dart:convert';

import 'package:core_erp/core/database/local_database_helper.dart';
import 'package:core_erp/core/database/sync_metadata_store.dart';
import 'package:core_erp/core/services/socket_service.dart';
import 'package:core_erp/core/sync/delta_sync_engine.dart';
import 'package:core_erp/core/sync/replica_catch_up.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// How a replica comes up to date (stage 2e, step 5).
//
// The replica's whole promise is that a second launch costs almost nothing.
// It did not keep it: a full copy recorded no head and live changes carried no
// changelog id, so the cursor never left 0 and every launch downloaded every
// list again (B41). These pin the cursor at every way into the replica.

Future<Database> _openReplica() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  for (final statement in LocalDatabaseHelper.schemaStatements) {
    await db.execute(statement);
  }
  return db;
}

Map<String, dynamic> _item(int id, String name) => <String, dynamic>{
      'id': id,
      'name': name,
      'variationTree': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': id * 10,
          'kind': 'property',
          'name': 'Finish',
          'children': <Map<String, dynamic>>[
            <String, dynamic>{'id': id * 10 + 1, 'kind': 'value', 'name': 'Zinc', 'children': <dynamic>[]},
          ],
        },
      ],
    };

class _Server {
  final List<String> calls = <String>[];
  final Map<String, List<Map<String, dynamic>>> lists = <String, List<Map<String, dynamic>>>{};
  final Map<String, Map<String, dynamic>> records = <String, Map<String, dynamic>>{};
  final List<TableChange> log = <TableChange>[];
  final Set<String> failingLists = <String>{};
  int oldest = 0;
  int pageSize = 1000;
  bool hasBootstrap = true;
  Set<String> bootstrapMissing = <String>{};

  int get head => log.isEmpty ? 0 : log.last.changelogId;

  Future<Map<String, dynamic>?> fetchRecord(String table, Object key) async {
    calls.add('record $table/$key');
    return records['$table/$key'];
  }

  Future<List<Map<String, dynamic>>> fetchList(String table) async {
    calls.add('list $table');
    if (failingLists.contains(table)) throw StateError('down');
    return lists[table] ?? const <Map<String, dynamic>>[];
  }

  Future<ChangesPage> fetchChangesPage(int since) async {
    calls.add('changes $since');
    final after = log.where((c) => c.changelogId > since).toList();
    final page = after.take(pageSize).toList();
    return ChangesPage(
      changes: page,
      hasMore: after.length > page.length,
      oldestAvailable: oldest > 0 ? oldest : (log.isEmpty ? 0 : log.first.changelogId),
      head: head,
    );
  }

  Future<ReplicaBootstrap?> fetchBootstrap() async {
    calls.add('bootstrap');
    if (!hasBootstrap) return null;
    return ReplicaBootstrap(
      head: head,
      lists: <String, List<Map<String, dynamic>>>{
        for (final entry in lists.entries)
          if (!bootstrapMissing.contains(entry.key)) entry.key: entry.value,
      },
      missing: bootstrapMissing,
    );
  }
}

void main() {
  late Database db;
  late _Server server;
  late DeltaSyncEngine engine;
  late SyncMetadataStore cursor;

  ReplicaCatchUp catchUp({bool bootstrap = true}) => ReplicaCatchUp(
        engine: engine,
        cursor: cursor,
        fetchChangesPage: server.fetchChangesPage,
        fetchBootstrap: bootstrap ? server.fetchBootstrap : null,
        listTables: const <String>['items', 'vendors'],
      );

  setUp(() async {
    db = await _openReplica();
    server = _Server()
      ..lists['items'] = <Map<String, dynamic>>[_item(1, 'Patti'), _item(2, 'Bracket')]
      ..lists['vendors'] = <Map<String, dynamic>>[<String, dynamic>{'id': 7, 'name': 'Steel Co'}]
      ..log.addAll(<TableChange>[
        const TableChange(table: 'items', recordId: 1, action: 'INSERT', changelogId: 40),
        const TableChange(table: 'items', recordId: 2, action: 'INSERT', changelogId: 41),
      ]);
    engine = DeltaSyncEngine(database: db, fetchRecord: server.fetchRecord, fetchList: server.fetchList);
    cursor = SyncMetadataStore(db);
  });

  tearDown(() => db.close());

  test('a cold replica is one bootstrap request, and remembers where it is', () async {
    final result = await catchUp().run();

    expect(result.hydrated, isTrue);
    expect(server.calls, <String>['bootstrap'], reason: 'one request, not one per list');
    expect(await cursor.lastChangelogId(), 41, reason: 'the head it is a copy as of (B41)');
    expect((await db.query('local_items')).length, 2);
    expect((await db.query('local_vendors')).length, 1);
  });

  test('the second launch replays from the head instead of copying again', () async {
    await catchUp().run();
    server.calls.clear();

    final result = await catchUp().run();
    expect(result.hydrated, isFalse);
    expect(server.calls, <String>['changes 41'], reason: 'nothing changed, so one small request');
  });

  test('a first fill mirrors the item variation nodes (B40)', () async {
    await catchUp().run();
    final nodes = await db.query('local_item_variation_nodes', orderBy: 'id');
    expect(nodes.map((n) => n['id']), <Object?>[10, 11, 20, 21]);
    expect(nodes.firstWhere((n) => n['id'] == 21)['item_id'], 2);
  });

  test('without a bootstrap, the head is taken before the lists', () async {
    server.hasBootstrap = false;
    await catchUp(bootstrap: false).run();

    expect(server.calls.first, startsWith('changes '), reason: 'the head is asked for first');
    expect(server.calls.where((c) => c.startsWith('list ')).toSet(), <String>{'list items', 'list vendors'});
    expect(await cursor.lastChangelogId(), 41);
  });

  test('a list that failed leaves the cursor at 0, so the next launch copies again', () async {
    server.hasBootstrap = false;
    server.failingLists.add('vendors');
    await catchUp(bootstrap: false).run();
    expect(await cursor.lastChangelogId(), 0, reason: 'the copy is not complete, so it must not say so');
  });

  test('a list the bootstrap could not load is fetched on its own', () async {
    server.bootstrapMissing = <String>{'vendors'};
    await catchUp().run();
    expect(server.calls, <String>['bootstrap', 'list vendors']);
    expect(await cursor.lastChangelogId(), 41);
    expect((await db.query('local_vendors')).length, 1);
  });

  test('a long gap is replayed page by page, not just the first page', () async {
    await catchUp().run();
    server.pageSize = 2;
    for (var i = 0; i < 5; i += 1) {
      server.records['vendors/${100 + i}'] = <String, dynamic>{'id': 100 + i, 'name': 'Vendor $i'};
      server.log.add(TableChange(table: 'vendors', recordId: 100 + i, action: 'INSERT', changelogId: 50 + i));
    }
    server.calls.clear();

    final result = await catchUp().run();
    expect(result.replayed.length, 5);
    expect(await cursor.lastChangelogId(), 54);
    expect(server.calls.where((c) => c.startsWith('changes ')), <String>['changes 41', 'changes 51', 'changes 53']);
    expect((await db.query('local_vendors')).length, 6);
  });

  test('a cursor the server has pruned past takes a fresh copy, not a partial replay', () async {
    await catchUp().run();
    server.log.add(const TableChange(table: 'vendors', recordId: 7, action: 'UPDATE', changelogId: 900));
    server.oldest = 500;
    server.calls.clear();

    final result = await catchUp().run();
    expect(result.hydrated, isTrue);
    expect(server.calls, <String>['changes 41', 'bootstrap']);
    expect(await cursor.lastChangelogId(), 900);
  });

  test('a cursor past the end of the server\'s log takes a fresh copy', () async {
    // The copy was made on another log: a server restored from a backup, or
    // another server altogether. Its cursor is ahead, so nothing ever replays.
    await catchUp().run();
    await cursor.setLastChangelogId(8989);
    server.lists['items'] = <Map<String, dynamic>>[_item(4, 'Primary')];
    server.calls.clear();

    final result = await catchUp().run();
    expect(result.hydrated, isTrue);
    expect(server.calls, <String>['changes 8989', 'bootstrap']);
    expect(await cursor.lastChangelogId(), server.head);
  });

  test('a replica of some tables skips the rest, and still moves past them', () async {
    await catchUp().run();
    server.records['vendors/7'] = <String, dynamic>{'id': 7, 'name': 'Steel Co'};
    server.log.addAll(const <TableChange>[
      TableChange(table: 'machines', recordId: 3, action: 'UPDATE', changelogId: 60),
      TableChange(table: 'vendors', recordId: 7, action: 'UPDATE', changelogId: 61),
      TableChange(table: 'dies', recordId: 4, action: 'UPDATE', changelogId: 62),
    ]);
    server.calls.clear();

    final scoped = ReplicaCatchUp(
      engine: engine,
      cursor: cursor,
      fetchChangesPage: server.fetchChangesPage,
      fetchBootstrap: server.fetchBootstrap,
      listTables: const <String>['items', 'vendors'],
      inScope: (change) => const <String>{'items', 'vendors'}.contains(change.table),
    );
    final result = await scoped.run();

    expect(result.replayed.map((c) => c.table), <String>['vendors']);
    expect(server.calls.where((c) => c.startsWith('record ')), <String>['record vendors/7'],
        reason: 'no request for a machine or a die it does not keep');
    expect(await cursor.lastChangelogId(), 62, reason: 'past the skipped die at the end of the page');
  });

  test("a live change carries its changelog id to whoever listens (B41)", () async {
    final seen = <Map<dynamic, dynamic>>[];
    void listener(dynamic data) => seen.add(data as Map);
    SocketService.instance.on('table-change', listener);
    addTearDown(() => SocketService.instance.off('table-change', listener));

    final data = jsonEncode(<String, dynamic>{'table_name': 'vendors', 'record_id': 7, 'event_type': 'UPDATE'});
    SocketService.instance.processEventForTest('id: 77\nevent: table-change\ndata: $data');
    SocketService.instance.processEventForTest('event: table-change\ndata: $data');

    expect(seen.first['changelogId'], 77);
    expect(seen.last.containsKey('changelogId'), isFalse,
        reason: 'a block without an id does not borrow the previous one');
  });
}

import 'package:core_erp/core/database/local_database_helper.dart';
import 'package:core_erp/core/database/sync_metadata_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The replica's foundations: a schema that matches what the server actually
/// sends, and a cursor that survives a restart.
///
/// The cursor is the whole point. Without it a launch starts from zero and
/// re-downloads the workspace — which is what the app did before, and why a
/// launch cost 235 KB whether anything had changed or not.

Future<Database> openReplica() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  for (final statement in LocalDatabaseHelper.schemaStatements) {
    await db.execute(statement);
  }
  return db;
}

void main() {
  late Database db;
  late SyncMetadataStore store;

  setUp(() async {
    db = await openReplica();
    store = SyncMetadataStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('the sync cursor', () {
    test('starts at zero, which means "take a snapshot"', () async {
      // A first install and a discarded replica look identical, and both
      // correctly lead to a full sync rather than a silent partial one.
      expect(await store.lastChangelogId(), 0);
    });

    test('survives being written and read back', () async {
      await store.setLastChangelogId(4211);
      expect(await store.lastChangelogId(), 4211);

      // A fresh reader over the same database — the restart case.
      expect(await SyncMetadataStore(db).lastChangelogId(), 4211);
    });

    test('never moves backwards', () async {
      // Events can arrive out of order across a reconnect. A cursor that went
      // backwards would replay applied changes — harmless in itself, but it
      // would also hide a genuine gap behind the noise.
      await store.setLastChangelogId(500);
      await store.setLastChangelogId(499);
      await store.setLastChangelogId(0);
      await store.setLastChangelogId(-1);
      expect(await store.lastChangelogId(), 500);
    });

    test('reset forgets the position rather than pretending', () async {
      await store.setLastChangelogId(900);
      await store.reset();
      expect(
        await store.lastChangelogId(),
        0,
        reason: 'a replica that cannot be trusted asks for everything again',
      );
    });

    test('records when it last synced, so staleness is answerable', () async {
      await store.setLastChangelogId(7);
      final at = await store.read(SyncMetadataStore.lastSyncAtKey);
      expect(at, isNotNull);
      expect(DateTime.tryParse(at!), isNotNull);
    });
  });

  group('the schema', () {
    Future<Set<String>> tables() async {
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      return rows.map((row) => row['name'] as String).toSet();
    }

    test('stores orders at the grain the server sends them', () async {
      // /api/orders selects FROM order_items — one row per order line, with a
      // status computed from its pipeline runs. A table of order *headers*
      // would mirror something the app never reads.
      final names = await tables();
      expect(names, contains('local_order_items'));
      expect(names, isNot(contains('local_order_headers')));
    });

    test('keeps the server payload verbatim on every replicated table', () async {
      // Extracted columns exist to filter and sort in SQL; the payload exists
      // so a row can be handed to the same fromJson the network path uses.
      // Without it, every new field the server learns to send would need a
      // migration here before the app could see it.
      final names = (await tables())
          .where((name) => name.startsWith('local_'))
          .toList();
      expect(names, isNotEmpty);
      for (final table in names) {
        final columns = await db.rawQuery('PRAGMA table_info($table)');
        expect(
          columns.map((column) => column['name']),
          contains('raw_payload_json'),
          reason: '$table must be able to reconstruct the server DTO',
        );
      }
    });

    test('text-keyed server tables stay text-keyed here', () async {
      // pipeline_templates.id is 'sheet-metal-flow'; pipeline_runs.id is
      // 'demo-dolly-run-active'. Coercing those to integers would map every
      // one of them onto 0.
      for (final table in <String>['local_pipeline_templates', 'local_pipeline_runs']) {
        final columns = await db.rawQuery('PRAGMA table_info($table)');
        final pk = columns.firstWhere((column) => (column['pk'] as int) > 0);
        expect(pk['type'], 'TEXT', reason: '$table is keyed by a string');
      }
    });

    test('a challan line goes when its challan does', () async {
      // Orphaned lines would be counted by aggregates and rendered by the
      // detail panel of a challan that no longer exists.
      await db.insert('local_delivery_challans', <String, Object?>{
        'id': 1,
        'challan_no': 'DC-1',
        'raw_payload_json': '{}',
      });
      await db.insert('local_delivery_challan_items', <String, Object?>{
        'id': 10,
        'challan_id': 1,
        'raw_payload_json': '{}',
      });

      await db.execute('PRAGMA foreign_keys = ON');
      await db.delete('local_delivery_challans', where: 'id = ?', whereArgs: <Object?>[1]);

      final orphans = await db.query('local_delivery_challan_items');
      expect(orphans, isEmpty);
    });

    test('the lists the app opens with are all replicable', () async {
      // The brief: no module should lag because its rows were never mirrored.
      final names = await tables();
      for (final required in <String>[
        'local_items', 'local_item_variation_nodes', 'local_groups',
        'local_order_items', 'local_delivery_challans', 'local_delivery_challan_items',
        'local_materials', 'local_clients', 'local_vendors', 'local_machines',
        'local_dies', 'local_units', 'local_departments',
        'local_pipeline_templates', 'local_pipeline_runs',
      ]) {
        expect(names, contains(required));
      }
    });
  });
}

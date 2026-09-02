import 'dart:convert';

import 'package:core_erp/core/database/local_database_helper.dart';
import 'package:core_erp/features/items/data/repositories/local_first_item_repository.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_item_repository.dart';

/// Reading items off the replica instead of the wire.
///
/// The two things that must hold: what comes back is the server's own payload
/// parsed by the server's own fromJson — never reassembled from the extracted
/// columns — and an empty replica falls through to the network rather than
/// reporting a workspace with nothing in it.

Future<Database> openReplica() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  for (final statement in LocalDatabaseHelper.schemaStatements) {
    await db.execute(statement);
  }
  return db;
}

Map<String, dynamic> itemPayload({
  required int id,
  required String name,
  bool archived = false,
  List<dynamic>? tree,
}) => <String, dynamic>{
  'id': id,
  'name': name,
  'alias': '',
  'displayName': name,
  'quantity': 0,
  'groupId': 1,
  'unitId': 1,
  'isArchived': archived,
  'usageCount': 0,
  'createdAt': '2026-01-01T00:00:00.000Z',
  'updatedAt': '2026-01-01T00:00:00.000Z',
  'variationTree': tree ?? <dynamic>[],
};

void main() {
  late Database db;
  late FakeItemRepository remote;
  late LocalFirstItemRepository repository;
  var hydrated = true;

  Future<void> seed(Map<String, dynamic> payload, {bool archived = false}) async {
    await db.insert('local_items', <String, Object?>{
      'id': payload['id'],
      'name': payload['name'],
      'is_archived': archived ? 1 : 0,
      'raw_payload_json': jsonEncode(payload),
    });
  }

  setUp(() async {
    db = await openReplica();
    remote = FakeItemRepository();
    hydrated = true;
    repository = LocalFirstItemRepository(
      remote: remote,
      replica: () async => db,
      isHydrated: () => hydrated,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('items come from the replica without touching the network', () async {
    await seed(itemPayload(id: 1, name: 'Socket'));
    final items = await repository.getItems();
    expect(items.map((i) => i.name), <String>['Socket']);
    expect(remote.getItemsCalls, 0, reason: 'this is the whole point');
  });

  test('the variation tree survives verbatim', () async {
    // It is 59% of the items payload and every picker in the app reads it. It
    // must come back intact, from the stored payload — reassembling it from
    // local_item_variation_nodes and saving would delete whatever the rebuild
    // missed, because updateItem is a destructive replace.
    await seed(itemPayload(id: 7, name: 'Socket', tree: <dynamic>[
      <String, dynamic>{
        'id': 100,
        'itemId': 7,
        'parentNodeId': null,
        'kind': 'property',
        'name': 'Finish',
        'displayName': 'Finish',
        'position': 0,
        'isArchived': false,
        'createdAt': '2026-01-01T00:00:00.000Z',
        'updatedAt': '2026-01-01T00:00:00.000Z',
        'children': <dynamic>[
          <String, dynamic>{
            'id': 101,
            'itemId': 7,
            'parentNodeId': 100,
            'kind': 'value',
            'name': 'Matte',
            'displayName': 'Matte',
            'position': 0,
            'isArchived': false,
            'createdAt': '2026-01-01T00:00:00.000Z',
            'updatedAt': '2026-01-01T00:00:00.000Z',
            'children': <dynamic>[],
          },
        ],
      },
    ]));

    final item = (await repository.getItems()).single;
    expect(item.variationTree, hasLength(1));
    expect(item.variationTree.single.name, 'Finish');
    expect(item.variationTree.single.children.single.name, 'Matte');
  });

  test('archived items are returned, not filtered', () async {
    // getItemsWithUsage has no WHERE clause, and orders archived last. A local
    // `WHERE is_archived = 0` would silently drop rows the app renders.
    await seed(itemPayload(id: 1, name: 'Zebra', archived: true), archived: true);
    await seed(itemPayload(id: 2, name: 'apple'));
    final items = await repository.getItems();
    expect(
      items.map((i) => i.name),
      <String>['apple', 'Zebra'],
      reason: 'unarchived first, then case-insensitive by name',
    );
  });

  test('an empty replica asks the network rather than reporting no items', () async {
    remote.items = <ItemDefinition>[
      ItemDtoParse.parse(itemPayload(id: 5, name: 'From server')),
    ];
    final items = await repository.getItems();
    expect(items.single.name, 'From server');
    expect(remote.getItemsCalls, 1);
  });

  test('an unsynced replica asks the network even if rows exist', () async {
    // Rows without a completed sync could be a partial hydration. The cursor,
    // not the row count, is what says the copy can be trusted.
    await seed(itemPayload(id: 1, name: 'Stale'));
    hydrated = false;
    remote.items = <ItemDefinition>[ItemDtoParse.parse(itemPayload(id: 9, name: 'Fresh'))];
    expect((await repository.getItems()).single.name, 'Fresh');
  });

  test('a single item missing locally is asked for, not reported absent', () async {
    // The replica may simply not have caught up with a just-created item.
    remote.items = <ItemDefinition>[ItemDtoParse.parse(itemPayload(id: 42, name: 'New'))];
    final item = await repository.getItem(42);
    expect(item?.name, 'New');
    expect(remote.getItemCalls, 1);
  });

  test('one corrupt row costs that row, not the list', () async {
    await seed(itemPayload(id: 1, name: 'Good'));
    await db.insert('local_items', <String, Object?>{
      'id': 2,
      'name': 'Broken',
      'raw_payload_json': '{not json',
    });
    final items = await repository.getItems();
    expect(items.map((i) => i.name), <String>['Good']);
  });

  test('writes always go to the server', () async {
    // Nothing here may be answered locally: the server mints ids and node ids,
    // and updateItem is a destructive tree replace.
    await repository.deleteItem(1);
    expect(remote.deleteCalls, <int>[1]);
  });
}

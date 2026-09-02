import 'dart:convert';

import 'package:core_erp/core/database/local_database_helper.dart';
import 'package:core_erp/features/orders/data/models/order_api_models.dart';
import 'package:core_erp/features/orders/data/repositories/local_first_order_repository.dart';
import 'package:core_erp/features/orders/data/repositories/order_repository.dart';
import 'package:core_erp/features/orders/domain/order_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Orders off the replica — and, more importantly, when NOT to.
///
/// The server understands search, client, status, ids, limit and offset, and
/// its search runs across eight columns in SQL. Reimplementing that here would
/// mean two filters that must agree exactly, and the way they would disagree is
/// a user searching for an order that exists and being told it does not.

class _FakeOrders implements OrderRepository {
  List<OrderEntry> result = const <OrderEntry>[];
  final List<Map<String, Object?>> calls = <Map<String, Object?>>[];

  @override
  Future<void> init() async {}

  @override
  Future<List<OrderEntry>> getOrders({
    String search = '',
    int? clientId,
    List<String> statuses = const <String>[],
    List<int> ids = const <int>[],
    int? limit,
    int offset = 0,
  }) async {
    calls.add(<String, Object?>{
      'search': search,
      'clientId': clientId,
      'statuses': statuses,
      'ids': ids,
      'limit': limit,
      'offset': offset,
    });
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} should not be reached');
}

Map<String, dynamic> orderPayload({
  required int id,
  required String orderNo,
  required String createdAt,
  String status = 'notStarted',
}) => <String, dynamic>{
  'id': id,
  'orderNo': orderNo,
  'clientId': 1,
  'clientName': 'Acme',
  'clientCode': 'AC',
  'poNumber': 'PO-1',
  'itemId': 1,
  'itemName': 'Socket',
  'variationLeafNodeId': 0,
  'variationPathLabel': '',
  'variationPathNodeIds': <dynamic>[],
  'customVariationValues': <String, dynamic>{},
  'quantity': 10,
  'status': status,
  'createdAt': createdAt,
};

void main() {
  late Database db;
  late _FakeOrders remote;
  late LocalFirstOrderRepository repository;
  var hydrated = true;

  Future<void> seed(Map<String, dynamic> payload) async {
    await db.insert('local_order_items', <String, Object?>{
      'id': payload['id'],
      'order_no': payload['orderNo'],
      'status': payload['status'],
      'created_at': payload['createdAt'],
      'raw_payload_json': jsonEncode(payload),
    });
  }

  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    for (final statement in LocalDatabaseHelper.schemaStatements) {
      await db.execute(statement);
    }
    remote = _FakeOrders();
    hydrated = true;
    repository = LocalFirstOrderRepository(
      remote: remote,
      replica: () async => db,
      isHydrated: () => hydrated,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('the plain list comes off the replica', () async {
    await seed(orderPayload(id: 1, orderNo: 'ORD-1', createdAt: '2026-01-01T00:00:00.000Z'));
    final orders = await repository.getOrders();
    expect(orders.single.orderNo, 'ORD-1');
    expect(remote.calls, isEmpty);
  });

  test('newest first, with the id breaking a tie', () async {
    // `ORDER BY datetime(created_at) DESC, id DESC`. Dropping the id leg
    // reorders rows created in the same second, which is what a bulk import
    // produces.
    const sameSecond = '2026-01-01T00:00:00.000Z';
    await seed(orderPayload(id: 1, orderNo: 'ORD-1', createdAt: sameSecond));
    await seed(orderPayload(id: 2, orderNo: 'ORD-2', createdAt: sameSecond));
    await seed(orderPayload(id: 3, orderNo: 'ORD-3', createdAt: '2026-02-01T00:00:00.000Z'));

    final orders = await repository.getOrders();
    expect(orders.map((o) => o.orderNo), <String>['ORD-3', 'ORD-2', 'ORD-1']);
  });

  test('every narrowed request goes to the server', () async {
    // Not reimplemented locally, deliberately: the server searches eight
    // columns and two filters that must agree exactly would eventually not.
    await seed(orderPayload(id: 1, orderNo: 'ORD-1', createdAt: '2026-01-01T00:00:00.000Z'));

    await repository.getOrders(search: 'acme');
    await repository.getOrders(clientId: 3);
    await repository.getOrders(statuses: <String>['inProgress']);
    await repository.getOrders(ids: <int>[7]);
    await repository.getOrders(limit: 20);
    await repository.getOrders(offset: 20);

    expect(remote.calls, hasLength(6));
    expect(remote.calls.first['search'], 'acme');
    expect(remote.calls[1]['clientId'], 3);
  });

  test('an unsynced replica asks the server even with rows present', () async {
    await seed(orderPayload(id: 1, orderNo: 'ORD-STALE', createdAt: '2026-01-01T00:00:00.000Z'));
    hydrated = false;
    remote.result = <OrderEntry>[
      OrderDto.fromJson(
        orderPayload(id: 9, orderNo: 'ORD-FRESH', createdAt: '2026-01-01T00:00:00.000Z'),
      ).toDomain(),
    ];
    final orders = await repository.getOrders();
    expect(orders.single.orderNo, 'ORD-FRESH');
  });

  test('an empty replica asks rather than reporting no orders', () async {
    remote.result = <OrderEntry>[
      OrderDto.fromJson(
        orderPayload(id: 9, orderNo: 'ORD-FRESH', createdAt: '2026-01-01T00:00:00.000Z'),
      ).toDomain(),
    ];
    expect((await repository.getOrders()).single.orderNo, 'ORD-FRESH');
  });

  test('the computed status survives the round trip', () async {
    // `status` is COALESCEd from the pipeline runs assigned to the line, not
    // read off order_items — and migrations 041/042 exist so a run completing
    // announces the line. It has to arrive intact.
    await seed(orderPayload(
      id: 1,
      orderNo: 'ORD-1',
      createdAt: '2026-01-01T00:00:00.000Z',
      status: 'completed',
    ));
    final order = (await repository.getOrders()).single;
    expect(order.status.name, 'completed');
  });
}

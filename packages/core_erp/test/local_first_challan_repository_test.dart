import 'dart:convert';

import 'package:core_erp/core/database/local_database_helper.dart';
import 'package:core_erp/features/delivery_challans/data/delivery_challan_repository.dart';
import 'package:core_erp/features/delivery_challans/data/local_first_challan_repository.dart';
import 'package:core_erp/features/delivery_challans/domain/delivery_challan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Challans off the replica — the list only.
///
/// Two limits matter more than the feature, and both would fail silently:
/// the replica holds the SUMMARY shape (no nested lines), and several of the
/// list's filters cannot be answered from a mirror of it at all.

class _FakeChallans implements ChallanRepository {
  List<DeliveryChallan> result = const <DeliveryChallan>[];
  final List<Map<String, Object?>> listCalls = <Map<String, Object?>>[];
  final List<int> detailCalls = <int>[];

  @override
  Future<List<DeliveryChallan>> getChallans({
    ChallanType? type,
    DeliveryChallanStatus? status,
    String search = '',
    DateTime? dateFrom,
    DateTime? dateTo,
    int? orderId,
    int? itemId,
    int? variationLeafNodeId,
    bool mineOnly = false,
  }) async {
    listCalls.add(<String, Object?>{
      'type': type,
      'status': status,
      'search': search,
      'orderId': orderId,
      'itemId': itemId,
      'mineOnly': mineOnly,
    });
    return result;
  }

  @override
  Future<DeliveryChallan> getChallan(int id) async {
    detailCalls.add(id);
    return DeliveryChallan.fromJson(challanPayload(id: id, no: 'DETAIL', date: '2026-01-01'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} should not be reached');
}

Map<String, dynamic> challanPayload({
  required int id,
  required String no,
  required String date,
  int lineCount = 2,
}) => <String, dynamic>{
  'id': id,
  'challan_no': no,
  'date': date,
  'type': 'delivery',
  'status': 'issued',
  'customer_name': 'Acme',
  'vendor_name': '',
  'order_no': '',
  // The summary shape: aggregates instead of the nested array.
  'lineCount': lineCount,
  'itemsCount': lineCount,
  'totalQty': 5,
  'totalWeight': 0,
  'created_at': '$date' 'T00:00:00.000Z',
};

void main() {
  late Database db;
  late _FakeChallans remote;
  late LocalFirstChallanRepository repository;
  var hydrated = true;

  Future<void> seed(Map<String, dynamic> payload) async {
    await db.insert('local_delivery_challans', <String, Object?>{
      'id': payload['id'],
      'challan_no': payload['challan_no'],
      'challan_date': payload['date'],
      'type': payload['type'],
      'status': payload['status'],
      'line_count': payload['lineCount'],
      'raw_payload_json': jsonEncode(payload),
    });
  }

  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    for (final statement in LocalDatabaseHelper.schemaStatements) {
      await db.execute(statement);
    }
    remote = _FakeChallans();
    hydrated = true;
    repository = LocalFirstChallanRepository(
      remote: remote,
      replica: () async => db,
      isHydrated: () => hydrated,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('the plain list comes off the replica', () async {
    await seed(challanPayload(id: 1, no: 'DC-1', date: '2026-01-01'));
    final challans = await repository.getChallans();
    expect(challans.single.challanNo, 'DC-1');
    expect(remote.listCalls, isEmpty);
  });

  test('newest first, with the id breaking a tie', () async {
    // `ORDER BY date(dc.date) DESC, dc.id DESC`. Challans routinely share a
    // date, so the id leg is doing real work.
    await seed(challanPayload(id: 1, no: 'DC-1', date: '2026-01-01'));
    await seed(challanPayload(id: 2, no: 'DC-2', date: '2026-01-01'));
    await seed(challanPayload(id: 3, no: 'DC-3', date: '2026-03-01'));
    final order = (await repository.getChallans()).map((c) => c.challanNo);
    expect(order, <String>['DC-3', 'DC-2', 'DC-1']);
  });

  test('the summary shape survives: aggregates without lines', () async {
    // The list stopped carrying the nested `items` array and sends counts
    // instead. A row read back has no lines, and the list must still be able to
    // say "2 items".
    await seed(challanPayload(id: 1, no: 'DC-1', date: '2026-01-01', lineCount: 2));
    final challan = (await repository.getChallans()).single;
    expect(challan.items, isEmpty);
    expect(challan.itemsCount, 2, reason: 'the count comes from the aggregate');
  });

  test('detail always goes to the server', () async {
    // The replica holds summaries. Answering getChallan from it would hand the
    // editor and the printable document a challan with no lines — the exact
    // regression that detail-hydration fixed on the client side.
    await seed(challanPayload(id: 1, no: 'DC-1', date: '2026-01-01'));
    final detail = await repository.getChallan(1);
    expect(remote.detailCalls, <int>[1]);
    expect(detail.challanNo, 'DETAIL');
  });

  test('every narrowed request goes to the server', () async {
    // mineOnly resolves server-side to dc.created_by = req.user.id, and item /
    // variation filters are a line-level EXISTS over rows the replica does not
    // hold. Approximating any of them locally would quietly return the wrong
    // set.
    await seed(challanPayload(id: 1, no: 'DC-1', date: '2026-01-01'));
    await repository.getChallans(mineOnly: true);
    await repository.getChallans(itemId: 3);
    await repository.getChallans(variationLeafNodeId: 9);
    await repository.getChallans(type: ChallanType.reception);
    await repository.getChallans(search: 'acme');
    expect(remote.listCalls, hasLength(5));
    expect(remote.listCalls.first['mineOnly'], true);
    expect(remote.listCalls[1]['itemId'], 3);
  });

  test('an unsynced replica asks the server', () async {
    await seed(challanPayload(id: 1, no: 'DC-STALE', date: '2026-01-01'));
    hydrated = false;
    remote.result = <DeliveryChallan>[
      DeliveryChallan.fromJson(challanPayload(id: 9, no: 'DC-FRESH', date: '2026-01-01')),
    ];
    expect((await repository.getChallans()).single.challanNo, 'DC-FRESH');
  });
}

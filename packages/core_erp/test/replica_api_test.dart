import 'package:core_erp/core/sync/replica_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pulling records out of whatever envelope an endpoint used.
///
/// The API is not consistent — `{items: []}`, `{data: []}`, `{orders: []}`,
/// `{challans: []}` — and getting this wrong does not throw. It returns an
/// empty list, the replica hydrates with nothing, and the app looks like a
/// workspace with no data in it.

void main() {
  group('lists', () {
    test('reads whichever envelope the endpoint chose', () {
      for (final body in <String>[
        '{"success":true,"items":[{"id":1}],"error":null}',
        '{"success":true,"data":[{"id":1}],"error":null}',
        '{"success":true,"orders":[{"id":1}],"error":null}',
        '{"success":true,"challans":[{"id":1}],"error":null}',
        '[{"id":1}]',
      ]) {
        final rows = ReplicaApi.unwrapList(body);
        expect(rows, hasLength(1), reason: body);
        expect(rows.single['id'], 1);
      }
    });

    test('an empty list is empty, not a failure', () {
      expect(ReplicaApi.unwrapList('{"success":true,"items":[]}'), isEmpty);
    });

    test('a body with no list at all yields nothing rather than throwing', () {
      expect(ReplicaApi.unwrapList('{"success":false,"error":"nope"}'), isEmpty);
    });
  });

  group('single records', () {
    test('reads the record past the envelope keys', () {
      for (final body in <String>[
        '{"success":true,"item":{"id":7,"name":"Socket"},"error":null}',
        '{"success":true,"order":{"id":7,"name":"Socket"},"error":null}',
        '{"success":true,"data":{"id":7,"name":"Socket"},"error":null}',
      ]) {
        final record = ReplicaApi.unwrapRecord(body);
        expect(record?['id'], 7, reason: body);
        expect(record?['name'], 'Socket');
      }
    });

    test('an unwrapped record is taken as itself', () {
      final record = ReplicaApi.unwrapRecord('{"id":7,"name":"Socket"}');
      expect(record?['id'], 7);
    });

    test('success and error are never mistaken for the record', () {
      // The trap: `success` is the first key in every response. Returning it
      // would store `true` as an item.
      final record = ReplicaApi.unwrapRecord('{"success":true,"item":{"id":7}}');
      expect(record?['id'], 7);
    });
  });

  group('the endpoint map', () {
    test('every path a binding needs is present', () {
      // Not derivable from the table name: order_items is served by
      // /api/orders, delivery_challans by /api/challans, and the pipeline
      // routes have no /api prefix at all.
      expect(ReplicaApi.listPaths['order_items'], '/api/orders');
      expect(ReplicaApi.listPaths['delivery_challans'], '/api/challans');
      expect(ReplicaApi.listPaths['pipeline_runs'], '/runs');
      expect(ReplicaApi.recordPaths['pipeline_templates'], '/templates');
    });

    test('a table with no by-id route is absent rather than guessed', () {
      // groups, units and departments have no by-id endpoint — their bindings
      // refetch the list. Inventing `/api/groups/:id` would 404 on every delta.
      for (final table in <String>['groups', 'units', 'departments']) {
        expect(ReplicaApi.recordPaths.containsKey(table), isFalse, reason: table);
        expect(ReplicaApi.listPaths.containsKey(table), isTrue, reason: table);
      }
    });
  });
}

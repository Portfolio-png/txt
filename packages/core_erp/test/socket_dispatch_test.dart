import 'dart:convert';

import 'package:core_erp/core/services/socket_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the realtime stream does with a change.
///
/// Twelve of the seventeen tables the server logs had no branch in the
/// dispatcher, so their events arrived and were dropped — a machine renamed, a
/// unit added, a pipeline template edited, an order line's status moving, all
/// invisible until someone reloaded. That is exactly the "lag because a row was
/// never appended" this work is about, and it lived on the client.

String block(String table, Object id, String action, {int? eventId}) {
  final data = jsonEncode(<String, dynamic>{
    'table_name': table,
    'record_id': id,
    'event_type': action,
  });
  return <String>[
    if (eventId != null) 'id: $eventId',
    'event: table-change',
    'data: $data',
  ].join('\n');
}

void main() {
  late SocketService service;
  late List<dynamic> generic;

  setUp(() {
    service = SocketService.instance;
    generic = <dynamic>[];
    service.on('table-change', generic.add);
  });

  tearDown(() {
    service.off('table-change');
  });

  test('every replicated table reaches a listener, not just the wired five', () {
    const tables = <String>[
      'items', 'item_variation_nodes', 'groups', 'order_items', 'order_headers',
      'delivery_challans', 'delivery_challan_items', 'materials',
      'inventory_stock_positions', 'clients', 'vendors', 'machines', 'dies',
      'units', 'departments', 'pipeline_templates', 'pipeline_runs',
    ];
    for (final table in tables) {
      service.processEventForTest(block(table, 1, 'UPDATE'));
    }
    expect(
      generic.map((event) => (event as Map)['table']).toList(),
      tables,
      reason: 'a table with no branch used to be dropped here',
    );
  });

  test('a text record id survives the trip', () {
    // pipeline_runs.id is 'demo-dolly-run-active'. Coercing to int would map
    // every run onto null.
    service.processEventForTest(
      block('pipeline_runs', 'demo-dolly-run-active', 'INSERT'),
    );
    expect((generic.single as Map)['id'], 'demo-dolly-run-active');
  });

  test('the named events providers already listen for still fire', () {
    // The migration has to be non-breaking: existing providers subscribe to
    // these names and must keep working while the delta engine is built.
    final heard = <String>[];
    for (final name in <String>[
      'item_updated', 'client_added', 'vendor_deleted',
      'groups_changed', 'challan_updated', 'inventory_updated',
    ]) {
      service.on(name, (_) => heard.add(name));
    }
    service.processEventForTest(block('items', 1, 'UPDATE'));
    service.processEventForTest(block('clients', 2, 'INSERT'));
    service.processEventForTest(block('vendors', 3, 'DELETE'));
    service.processEventForTest(block('groups', 4, 'UPDATE'));
    service.processEventForTest(block('delivery_challans', 5, 'UPDATE'));
    service.processEventForTest(block('materials', 6, 'UPDATE'));

    expect(heard, <String>[
      'item_updated', 'client_added', 'vendor_deleted',
      'groups_changed', 'challan_updated', 'inventory_updated',
    ]);
    for (final name in heard) {
      service.off(name);
    }
  });

  test('a variation node change tells whoever is rendering the tree', () {
    // The case the audit found: editing a variation writes
    // item_variation_nodes, which had no branch, so every picker in the app
    // kept the old tree.
    final heard = <String>[];
    service.on('groups_changed', (_) => heard.add('groups_changed'));
    service.processEventForTest(block('item_variation_nodes', 9, 'UPDATE'));
    expect(heard, hasLength(1));
    service.off('groups_changed');
  });

  test('the cursor is handed to storage as events arrive', () async {
    // Held in memory alone it resets to 0 on every launch, and the app asks for
    // the whole workspace again — which is what it used to do.
    final saved = <int>[];
    service.saveCursor = (id) async => saved.add(id);
    service.processEventForTest(block('items', 1, 'UPDATE', eventId: 4211));
    await Future<void>.delayed(Duration.zero);
    expect(saved, contains(4211));
    service.saveCursor = null;
  });

  test('a malformed block is ignored rather than killing the stream', () {
    // One bad frame must not end realtime for the session.
    service.processEventForTest('event: table-change\ndata: {not json');
    service.processEventForTest(block('items', 1, 'UPDATE'));
    expect(generic, hasLength(1), reason: 'the good block still arrived');
  });
}

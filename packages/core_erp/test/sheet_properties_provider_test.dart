import 'dart:convert';

import 'package:core_erp/core/services/socket_service.dart';
import 'package:core_erp/features/items/data/sheet_property_repository.dart';
import 'package:core_erp/features/items/presentation/providers/sheet_properties_provider.dart';
import 'package:flutter_test/flutter_test.dart';

// The sheet's property columns as every window holds them.

void main() {
  setUp(ApiSheetPropertyRepository.debugResetMockStore);

  SheetPropertiesProvider make() {
    final provider = SheetPropertiesProvider(
      repository: ApiSheetPropertyRepository(useMockResponses: true),
    );
    addTearDown(provider.dispose);
    return provider;
  }

  test('a name already on the sheet answers with that column', () async {
    final provider = make();
    await provider.ensureLoaded();
    final first = await provider.create(name: 'Plating', kind: 'list');
    final again = await provider.create(name: ' plating ', kind: 'text');
    expect(again!.id, first!.id);
    expect(provider.properties, hasLength(1));
  });

  test('a value added joins the list once', () async {
    final provider = make();
    await provider.ensureLoaded();
    final plating =
        await provider.create(name: 'Plating', kind: 'text', options: ['Nickel']);
    await provider.addOption(plating!.id, 'Gold');
    await provider.addOption(plating.id, 'gold');
    expect(provider.byKey('plating')!.options, ['Nickel', 'Gold']);
  });

  test('a change in another window is picked up from the stream', () async {
    final provider = make();
    await provider.ensureLoaded();
    expect(provider.properties, isEmpty);

    // Another window adds one; the server announces it.
    await ApiSheetPropertyRepository(useMockResponses: true)
        .create(name: 'Temper', kind: 'list');
    SocketService.instance.processEventForTest(
      'event: table-change\ndata: ${jsonEncode({
            'table_name': 'item_sheet_properties',
            'record_id': 1,
            'event_type': 'INSERT',
          })}',
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(provider.byKey('temper'), isNotNull);
  });
}

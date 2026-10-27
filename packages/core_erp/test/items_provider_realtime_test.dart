import 'dart:convert';

import 'package:core_erp/core/services/socket_service.dart';
import 'package:core_erp/features/items/data/repositories/item_repository.dart';
import 'package:core_erp/features/items/domain/developed_for.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:flutter_test/flutter_test.dart';

// What an open window does when a part changes somewhere else.
//
// The desktop hears changes over SSE, and every one arrives as `{'id': N}`.
// The provider parsed that as a whole row: a part with no name, no group, no
// dies and an updatedAt of "now" — which beat the real one, so it replaced it.
// Every window saw the part go blank, and saving it from there wiped the rest.

String _change(String table, int id, String action) {
  final data = jsonEncode(<String, dynamic>{
    'table_name': table,
    'record_id': id,
    'event_type': action,
  });
  return 'event: table-change\ndata: $data';
}

ItemDefinition _part(int id, String name, {DateTime? at}) => ItemDefinition(
      id: id,
      name: name,
      alias: '',
      displayName: name,
      quantity: 0,
      groupId: 3,
      unitId: 7,
      partCode: 'SAP$id',
      developedFor: const DevelopedFor(
        kind: DevelopedForKind.client,
        clientId: 44,
        quotationAmount: 85000,
      ),
      dies: const [ItemDieLink(id: '70', toolCode: 'CDSAP1')],
      isArchived: false,
      usageCount: 0,
      createdAt: DateTime(2026),
      updatedAt: at ?? DateTime(2026, 5, 1),
      variationTree: const [],
    );

class _Repo implements ItemRepository {
  _Repo(this.server);

  /// What the server holds now.
  final Map<int, ItemDefinition> server;

  /// What a lagging replica would still answer with.
  List<ItemDefinition> listed = const [];
  final List<int> fetched = [];

  @override
  Future<void> init() async {}

  @override
  Future<List<ItemDefinition>> getItems() async => listed;

  @override
  Future<ItemDefinition?> getItemFresh(int id) async {
    fetched.add(id);
    return server[id];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final socket = SocketService.instance;

  Future<(ItemsProvider, _Repo)> open() async {
    final repo = _Repo({1: _part(1, 'Patti')})..listed = [_part(1, 'Patti')];
    final provider = ItemsProvider(repository: repo);
    await provider.initialize();
    addTearDown(provider.dispose);
    return (provider, repo);
  }

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 200));

  test('an id-only change is fetched, not taken as a blank part', () async {
    final (provider, repo) = await open();
    repo.server[1] = _part(1, 'Patti B', at: DateTime(2026, 6, 1));

    socket.processEventForTest(_change('items', 1, 'UPDATE'));
    // Not blanked in the meantime either.
    expect(provider.items.single.name, 'Patti');
    await settle();

    final part = provider.items.single;
    expect(part.name, 'Patti B');
    expect(part.groupId, 3);
    expect(part.dies.single.toolCode, 'CDSAP1');
    expect(part.developedFor.quotationAmount, 85000);
  });

  test('a burst of changes to one part is one fetch', () async {
    final (_, repo) = await open();
    for (var i = 0; i < 5; i += 1) {
      socket.processEventForTest(_change('items', 1, 'UPDATE'));
    }
    await settle();
    expect(repo.fetched, [1]);
  });

  test('a part the server no longer has is dropped', () async {
    final (provider, repo) = await open();
    repo.server.remove(1);
    socket.processEventForTest(_change('items', 1, 'UPDATE'));
    await settle();
    expect(provider.items, isEmpty);
  });

  test('a part made elsewhere arrives whole', () async {
    final (provider, repo) = await open();
    repo.server[2] = _part(2, 'Dabbi');
    socket.processEventForTest(_change('items', 2, 'INSERT'));
    await settle();
    expect(provider.items.map((p) => p.name), containsAll(['Patti', 'Dabbi']));
  });

  test('disposing one listener leaves the others subscribed', () async {
    final heard = <dynamic>[];
    void other(dynamic data) => heard.add(data);
    socket.on('item_updated', other);
    addTearDown(() => socket.off('item_updated', other));

    final provider = ItemsProvider(repository: _Repo({1: _part(1, 'Patti')}));
    await provider.initialize();
    provider.dispose();
    socket.processEventForTest(_change('items', 1, 'UPDATE'));
    expect(heard, hasLength(1));
  });
}

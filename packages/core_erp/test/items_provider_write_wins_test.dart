import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/domain/item_inputs.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_item_repository.dart';

/// Reads come off the local replica, which the changelog reaches a moment
/// after a write returns. This fake reproduces exactly that: a write is
/// answered in full, while the list read keeps returning the old row until
/// the test says the replica has caught up.
class _LaggingReplicaRepository extends FakeItemRepository {
  int updateCalls = 0;

  @override
  Future<ItemDefinition> updateItem(UpdateItemInput input) async {
    updateCalls += 1;
    final current = items.firstWhere((item) => item.id == input.id);
    return _item(
      id: input.id,
      name: input.name,
      machineIds: input.machineIds,
      updatedAt: current.updatedAt.add(const Duration(seconds: 1)),
    );
  }

  @override
  Future<ItemDefinition> createItem(CreateItemInput input) async {
    return _item(id: 77, name: input.name, updatedAt: DateTime(2026, 9, 9, 12));
  }
}

ItemDefinition _item({
  required int id,
  required String name,
  List<String> machineIds = const [],
  DateTime? updatedAt,
}) {
  final stamp = updatedAt ?? DateTime(2026, 9, 9, 10);
  return ItemDefinition(
    id: id,
    name: name,
    alias: '',
    displayName: name,
    quantity: 0,
    groupId: 9,
    unitId: 1,
    isArchived: false,
    usageCount: 0,
    createdAt: DateTime(2026, 9, 1),
    updatedAt: stamp,
    variationTree: const [],
    machines: [
      for (final id in machineIds) ItemMachineLink(id: id, name: 'Press $id'),
    ],
    dies: const [],
  );
}

void main() {
  late _LaggingReplicaRepository repository;
  late ItemsProvider provider;

  setUp(() async {
    repository = _LaggingReplicaRepository();
    repository.items = [_item(id: 1, name: 'Body Casting')];
    provider = ItemsProvider(repository: repository);
    await provider.refresh();
  });

  test('an attachment shows on the first save, not the second', () async {
    expect(provider.items.single.machines, isEmpty);

    await provider.setItemLinks(1, machineIds: const ['m1']);

    // The read that followed the save still answered with the old row, and
    // must not have put it back.
    expect(provider.items.single.machines.map((machine) => machine.id), ['m1']);
    expect(repository.updateCalls, 1);
  });

  test('two attachments in a row each land as they are made', () async {
    await provider.setItemLinks(1, machineIds: const ['m1']);
    await provider.setItemLinks(1, machineIds: const ['m1', 'm2']);

    expect(provider.items.single.machines.map((machine) => machine.id), [
      'm1',
      'm2',
    ]);
  });

  test('the read takes over once the replica has caught up', () async {
    await provider.setItemLinks(1, machineIds: const ['m1']);

    // The replica arrives with someone else's later edit on the same row.
    repository.items = [
      _item(
        id: 1,
        name: 'Body Casting',
        machineIds: const ['m1', 'm9'],
        updatedAt: DateTime(2026, 9, 9, 18),
      ),
    ];
    await provider.refresh();

    expect(provider.items.single.machines.map((machine) => machine.id), [
      'm1',
      'm9',
    ]);
  });

  test(
    'a new item is not dropped by the read that has never seen it',
    () async {
      await provider.createItem(
        const CreateItemInput(
          name: 'Stem',
          displayName: 'Stem',
          groupId: 9,
          unitId: 1,
        ),
      );

      expect(provider.items.map((item) => item.name), contains('Stem'));

      // And it stops being held the moment the read can answer for it.
      repository.items = [
        ...repository.items,
        _item(id: 77, name: 'Stem', updatedAt: DateTime(2026, 9, 9, 12)),
      ];
      await provider.refresh();
      expect(provider.items.where((item) => item.id == 77), hasLength(1));
    },
  );
}

import 'package:core_erp/features/items/data/repositories/item_repository.dart';
import 'package:core_erp/features/items/domain/developed_for.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/domain/item_inputs.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:flutter_test/flutter_test.dart';

// Attaching a die must not quietly change what the part is.
//
// `setItemLinks` preserves the rest of the item by rebuilding it through
// `_toInput`, which copied seven fields of a variation node and dropped five:
// `inputType`, `nameJoin`, both numeric bounds and `materialTypeId`. So linking
// a die to a part reset every Gauge and Material property to Text, and lost the
// bounds on a Numeric one. The part looked unchanged until somebody opened its
// variations.
//
// The item sheet sets Thickness as a Gauge and Alloy as a Material, so this
// would have fired on the first part anyone gave tooling to.

class _Repo implements ItemRepository {
  _Repo(this.stored);

  final List<ItemDefinition> stored;
  final List<UpdateItemInput> updated = [];

  @override
  Future<void> init() async {}

  @override
  Future<List<ItemDefinition>> getItems() async => List.of(stored);

  @override
  Future<ItemDefinition> updateItem(UpdateItemInput input) async {
    updated.add(input);
    return stored.first;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ItemVariationNodeDefinition _node({
  required int id,
  required String name,
  required String inputType,
  double? numericMin,
  double? numericMax,
  int? materialTypeId,
  String nameJoin = '',
  List<ItemVariationNodeDefinition> children = const [],
}) {
  return ItemVariationNodeDefinition(
    id: id,
    itemId: 500,
    parentNodeId: null,
    kind: ItemVariationNodeKind.property,
    name: name,
    displayName: name,
    position: 0,
    isArchived: false,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    children: children,
    inputType: inputType,
    nameJoin: nameJoin,
    numericMin: numericMin,
    numericMax: numericMax,
    materialTypeId: materialTypeId,
  );
}

void main() {
  test('linking a die leaves the variation tree exactly as it was', () async {
    final part = ItemDefinition(
      id: 500,
      name: 'Patti',
      alias: '',
      displayName: 'Patti',
      partNo: 48,
      partCode: 'SADP48',
      quantity: 0,
      groupId: 11,
      unitId: 7,
      developedFor: DevelopedFor.empty,
      isArchived: false,
      usageCount: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      variationTree: [
        _node(id: 1, name: 'Thickness', inputType: 'Gauge'),
        _node(id: 2, name: 'Alloy', inputType: 'Material', materialTypeId: 9),
        _node(
          id: 3,
          name: 'Length',
          inputType: 'Numeric',
          numericMin: 10,
          numericMax: 90,
          nameJoin: '-',
        ),
      ],
    );

    final repo = _Repo([part]);
    final items = ItemsProvider(repository: repo);
    await items.refresh();

    await items.setItemLinks(500, dieIds: ['7']);

    expect(repo.updated, hasLength(1));
    final tree = repo.updated.single.variationTree;
    expect(tree, hasLength(3));

    final thickness = tree.firstWhere((n) => n.name == 'Thickness');
    expect(thickness.inputType, 'Gauge',
        reason: 'a Gauge property must not come back as Text');

    final alloy = tree.firstWhere((n) => n.name == 'Alloy');
    expect(alloy.inputType, 'Material');
    expect(alloy.materialTypeId, 9);

    final length = tree.firstWhere((n) => n.name == 'Length');
    expect(length.inputType, 'Numeric');
    expect(length.numericMin, 10);
    expect(length.numericMax, 90);
    expect(length.nameJoin, '-');
  });
}

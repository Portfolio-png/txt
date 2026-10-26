import 'package:core_erp/features/groups/data/repositories/group_repository.dart';
import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/groups/domain/group_inputs.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/items/data/item_sheet_binding.dart';
import 'package:core_erp/features/items/data/repositories/item_repository.dart';
import 'package:core_erp/features/items/domain/developed_for.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/domain/item_inputs.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/features/materials/data/material_repository.dart';
import 'package:core_erp/features/materials/presentation/providers/materials_provider.dart';
import 'package:core_erp/sheet/sheet.dart';
import 'package:flutter_test/flutter_test.dart';

// Turning sheet rows into real items.
//
// The engine had no way in or out: a cell was keyed by `columnId` alone, so a
// mapper had nothing to key off, and `saveItem()` assigned the literal id 5012
// and wrote nothing. These tests drive the binding directly, with no widget in
// sight, because that is where the entity knowledge now lives.

class _FakeGroupRepository implements GroupRepository {
  _FakeGroupRepository(this.groups);

  final List<GroupDefinition> groups;
  final List<CreateGroupInput> created = [];
  int _nextId = 100;

  @override
  Future<void> init() async {}

  @override
  Future<List<GroupDefinition>> getGroups({bool withCovers = false}) async =>
      List.of(groups);

  /// Makes every create throw, the way a refused POST surfaces.
  bool failCreate = false;

  @override
  Future<GroupDefinition> createGroup(CreateGroupInput input) async {
    if (failCreate) throw Exception('refused');
    created.add(input);
    final group = GroupDefinition(
      id: _nextId++,
      name: input.name,
      groupType: input.groupType,
      groupStructure: input.groupStructure,
      parentGroupId: input.parentGroupId,
      unitId: input.unitId,
      isArchived: false,
      usageCount: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    groups.add(group);
    return group;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeItemRepository implements ItemRepository {
  final List<CreateItemInput> created = [];
  final List<ItemDefinition> stored = [];
  int _nextId = 500;

  /// Simulates the provider's re-entrancy answer: null, with no error.
  bool refuseSilently = false;

  @override
  Future<void> init() async {}

  @override
  Future<List<ItemDefinition>> getItems() async => List.of(stored);

  @override
  Future<ItemDefinition> createItem(CreateItemInput input) async {
    created.add(input);
    final item = ItemDefinition(
      id: _nextId++,
      name: input.name,
      alias: '',
      displayName: input.displayName,
      partNo: input.partNo,
      partCode: input.partCode ?? 'AUTO${_nextId}',
      quantity: 0,
      groupId: input.groupId,
      unitId: input.unitId,
      developedFor: input.developedFor ?? DevelopedFor.empty,
      isArchived: false,
      usageCount: 0,
      createdAt: DateTime(2026, 5, 15, 10, 5),
      updatedAt: DateTime(2026, 5, 15, 10, 5),
      variationTree: const [],
    );
    stored.add(item);
    return item;
  }

  /// What each update carried — the full-replace payload a save sends.
  final List<UpdateItemInput> updated = [];

  @override
  Future<ItemDefinition> updateItem(UpdateItemInput input) async {
    updated.add(input);
    final index = stored.indexWhere((item) => item.id == input.id);
    final before = stored[index];
    final after = ItemDefinition(
      id: before.id,
      name: input.name,
      alias: input.alias,
      displayName: input.displayName,
      partNo: before.partNo,
      partCode: before.partCode,
      quantity: before.quantity,
      groupId: input.groupId,
      unitId: input.unitId,
      developedFor: input.developedFor ?? before.developedFor,
      isArchived: false,
      usageCount: 0,
      createdAt: before.createdAt,
      updatedAt: before.updatedAt.add(const Duration(minutes: 1)),
      variationTree: before.variationTree,
    );
    stored[index] = after;
    return after;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The real ten-column item sheet.
///
/// Deliberately `itemSheetColumns` and not a copy of it. These tests used to
/// declare their own ten columns with bindings on them, which is how the
/// production sheet came to declare NONE while every test here passed: a
/// binding handed the real sheet could map nothing, so a save would have
/// written an item with no name and no group. Pointing at the production
/// constant means that cannot happen twice.
SheetDef _itemSheet({bool withPlating = false}) {
  final sheet = SheetDef(
    id: 1,
    key: 'item',
    title: 'Item Master 1',
    columns: itemSheetColumns,
  );
  if (!withPlating) return sheet;
  // A property added the way the + button adds one. Ids run 1..10, so this
  // lands on 11.
  return sheet.addColumn(
    label: 'Plating',
    kind: ColumnKind.text,
    bindsTo: SheetBindsTo.variation('Plating'),
  );
}

/// The id [_itemSheet] gives the added Plating column.
const int _platingColumnId = 11;

SheetDraft _row({
  String? group,
  String? type,
  String? name,
  int? partNo,
  String? partCode,
  String? alloy,
  String? thickness,
  String? plating,
}) {
  final draft = SheetDraft(sheetKey: 'item');
  void put(int id, String? label, {int? intValue}) {
    if (label == null && intValue == null) return;
    draft.set(
      id,
      CellValue(
        columnId: id,
        optionLabel: label,
        textValue: label,
        intValue: intValue,
      ),
    );
  }

  put(1, group);
  put(2, type);
  put(3, name);
  // Identity cells are written as TYPED. A derived preview is never sent — the
  // server stamps it — so a test about what the sheet sends has to say the
  // user entered these.
  if (partNo != null) {
    draft.set(
      4,
      CellValue(
        columnId: 4,
        intValue: partNo,
        textValue: '$partNo',
        mode: ValueMode.edit,
      ),
    );
  }
  if (partCode != null) {
    draft.set(
      5,
      CellValue(
        columnId: 5,
        optionLabel: partCode,
        textValue: partCode,
        mode: ValueMode.edit,
      ),
    );
  }
  put(6, alloy);
  put(7, thickness);
  put(_platingColumnId, plating);
  return draft;
}

({ItemSheetBinding binding, _FakeItemRepository itemRepo, _FakeGroupRepository groupRepo})
    _harness({List<GroupDefinition>? groups}) {
  final groupRepo = _FakeGroupRepository(groups ??
      [
        GroupDefinition(
          id: 1,
          name: 'Switch Action',
          groupStructure: 'hierarchical',
          parentGroupId: null,
          unitId: 7,
          isArchived: false,
          usageCount: 0,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ]);
  final itemRepo = _FakeItemRepository();
  final groupsProvider = GroupsProvider(repository: groupRepo);
  final itemsProvider = ItemsProvider(repository: itemRepo);
  return (
    binding: ItemSheetBinding(
      items: itemsProvider,
      groups: groupsProvider,
      itemSheet: _itemSheet(),
    ),
    itemRepo: itemRepo,
    groupRepo: groupRepo,
  );
}

void main() {
  group('ItemSheetBinding.save', () {
    test('files a part under the Type, creating it under the Group', () async {
      final h = _harness();
      await h.groupRepo.getGroups();
      final groups = GroupsProvider(repository: h.groupRepo);
      await groups.refresh();

      final binding = ItemSheetBinding(
        items: ItemsProvider(repository: h.itemRepo),
        groups: groups,
        itemSheet: _itemSheet(),
      );

      final saved = await binding.save([
        _row(group: 'Switch Action', type: 'Dolly', name: 'Patti'),
      ]);

      expect(saved, isNotNull, reason: binding.lastError ?? '');
      expect(h.groupRepo.created, hasLength(1));
      expect(h.groupRepo.created.single.name, 'Dolly');
      expect(
        h.groupRepo.created.single.parentGroupId,
        1,
        reason: 'Dolly is a child of Switch Action, not a second root',
      );
      // The part files under the DEEPEST group named.
      expect(h.itemRepo.created.single.groupId, isNot(1));
    });

    test('reuses an existing group rather than making a second one', () async {
      final groups = [
        GroupDefinition(
          id: 1,
          name: 'Switch Action',
          groupStructure: 'hierarchical',
          parentGroupId: null,
          unitId: 7,
          isArchived: false,
          usageCount: 0,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
        GroupDefinition(
          id: 2,
          name: 'Dolly',
          groupStructure: 'hierarchical',
          parentGroupId: 1,
          unitId: 7,
          isArchived: false,
          usageCount: 0,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ];
      final groupRepo = _FakeGroupRepository(groups);
      final itemRepo = _FakeItemRepository();
      final groupsProvider = GroupsProvider(repository: groupRepo);
      await groupsProvider.refresh();

      final binding = ItemSheetBinding(
        items: ItemsProvider(repository: itemRepo),
        groups: groupsProvider,
        itemSheet: _itemSheet(),
      );

      // Matched case-insensitively and whitespace-normalised, the way
      // GroupsProvider's own duplicate check normalises.
      await binding.save([
        _row(group: '  switch   action ', type: 'DOLLY', name: 'Patti'),
      ]);

      expect(groupRepo.created, isEmpty, reason: 'both groups already existed');
      expect(itemRepo.created.single.groupId, 2);
    });

    test('a name unique only among siblings does not collide across parents',
        () async {
      // Two parents each with a "Dolly". Resolving must be scoped, or a part
      // lands under the wrong company's set.
      final groups = [
        GroupDefinition(
          id: 1, name: 'Switch Action', groupStructure: 'hierarchical',
          parentGroupId: null, unitId: 7, isArchived: false, usageCount: 0,
          createdAt: DateTime(2026), updatedAt: DateTime(2026),
        ),
        GroupDefinition(
          id: 2, name: 'Dolly', groupStructure: 'hierarchical',
          parentGroupId: 1, unitId: 7, isArchived: false, usageCount: 0,
          createdAt: DateTime(2026), updatedAt: DateTime(2026),
        ),
        GroupDefinition(
          id: 3, name: 'Cutout', groupStructure: 'hierarchical',
          parentGroupId: null, unitId: 7, isArchived: false, usageCount: 0,
          createdAt: DateTime(2026), updatedAt: DateTime(2026),
        ),
        GroupDefinition(
          id: 4, name: 'Dolly', groupStructure: 'hierarchical',
          parentGroupId: 3, unitId: 7, isArchived: false, usageCount: 0,
          createdAt: DateTime(2026), updatedAt: DateTime(2026),
        ),
      ];
      final groupRepo = _FakeGroupRepository(groups);
      final itemRepo = _FakeItemRepository();
      final groupsProvider = GroupsProvider(repository: groupRepo);
      await groupsProvider.refresh();

      final binding = ItemSheetBinding(
        items: ItemsProvider(repository: itemRepo),
        groups: groupsProvider,
        itemSheet: _itemSheet(),
      );

      await binding.save([_row(group: 'Cutout', type: 'Dolly', name: 'Patti')]);
      expect(itemRepo.created.single.groupId, 4, reason: "Cutout's Dolly, not Switch Action's");
      expect(groupRepo.created, isEmpty);
    });

    test('part no and part code go together, or neither does', () async {
      // The server auto-stamps only when NEITHER arrives. Sending one turns
      // the stamp off and leaves the part half-named.
      final h = _harness();
      final groups = GroupsProvider(repository: h.groupRepo);
      await groups.refresh();
      final binding = ItemSheetBinding(
        items: ItemsProvider(repository: h.itemRepo),
        groups: groups,
        itemSheet: _itemSheet(),
      );

      await binding.save([
        _row(group: 'Switch Action', name: 'Both', partNo: 48, partCode: 'SADP48'),
        _row(group: 'Switch Action', name: 'Only a number', partNo: 49),
        _row(group: 'Switch Action', name: 'Only a code', partCode: 'SADP50'),
        _row(group: 'Switch Action', name: 'Neither'),
      ]);

      final created = h.itemRepo.created;
      expect(created, hasLength(4));

      expect(created[0].partNo, 48);
      expect(created[0].partCode, 'SADP48');

      for (final partial in [created[1], created[2], created[3]]) {
        expect(partial.partNo, isNull);
        expect(
          partial.partCode,
          isNull,
          reason: 'half an identity must become none, so the server stamps',
        );
      }
    });

    test('the recipe columns become variation properties with the right types',
        () async {
      final h = _harness();
      final groups = GroupsProvider(repository: h.groupRepo);
      await groups.refresh();
      final binding = ItemSheetBinding(
        items: ItemsProvider(repository: h.itemRepo),
        groups: groups,
        itemSheet: _itemSheet(withPlating: true),
      );

      await binding.save([
        _row(
          group: 'Switch Action',
          name: 'Patti',
          alloy: 'Brass',
          thickness: '22 Gauge',
          plating: 'Satin Nickel',
        ),
      ]);

      final tree = h.itemRepo.created.single.variationTree;
      expect(tree, hasLength(3));

      final alloy = tree.firstWhere((n) => n.name == 'Alloy');
      expect(alloy.inputType, 'Material');
      expect(alloy.children.single.name, 'Brass');

      // A Gauge property carries its value like every other kind.
      //
      // It used to be sent with no children, on the grounds that "the value
      // lives on the property itself". It did not: the server blanks a
      // property's displayName, so a childless property read back as its own
      // NAME — a saved part showed the word "Thickness" in its Thickness cell
      // and the typed gauge was gone. It also put the gauge out of reach of
      // the part code, which is built from the property values.
      final thickness = tree.firstWhere((n) => n.name == 'Thickness');
      expect(thickness.inputType, 'Gauge');
      expect(thickness.children.single.name, '22 Gauge');

      // A property added with the + reaches the save like the two the sheet
      // ships with, and a plain-text one carries its value the same way.
      final plating = tree.firstWhere((n) => n.name == 'Plating');
      expect(plating.inputType, 'Text');
      expect(plating.children.single.name, 'Satin Nickel');
    });

    test('a chosen Alloy carries its material id, not just its name', () async {
      // The cell looked right and pointed at nothing: the value node went up
      // with `material_type_id = NULL`, so the items screen's variation panel
      // rendered the saved alloy as "material missing".
      final h = _harness();
      final groups = GroupsProvider(repository: h.groupRepo);
      await groups.refresh();

      final materials = MaterialsProvider(
        repository: MaterialRepository(useMockResponses: true),
      );
      await materials.ensureLoaded();

      final binding = ItemSheetBinding(
        items: ItemsProvider(repository: h.itemRepo),
        groups: groups,
        materials: materials,
        itemSheet: _itemSheet(),
      );

      await binding.save([
        _row(group: 'Switch Action', name: 'Patti', alloy: 'Brass'),
      ]);

      final alloy = h.itemRepo.created.single.variationTree
          .firstWhere((n) => n.name == 'Alloy');
      expect(
        alloy.children.single.materialTypeId,
        materials.byName('Brass')!.id,
      );
    });

    test('an alloy no material answers to stays unlinked rather than guessing',
        () async {
      final h = _harness();
      final groups = GroupsProvider(repository: h.groupRepo);
      await groups.refresh();

      final materials = MaterialsProvider(
        repository: MaterialRepository(useMockResponses: true),
      );
      await materials.ensureLoaded();

      final binding = ItemSheetBinding(
        items: ItemsProvider(repository: h.itemRepo),
        groups: groups,
        materials: materials,
        itemSheet: _itemSheet(),
      );

      await binding.save([
        _row(group: 'Switch Action', name: 'Patti', alloy: 'Unobtainium'),
      ]);

      final alloy = h.itemRepo.created.single.variationTree
          .firstWhere((n) => n.name == 'Alloy');
      expect(alloy.children.single.name, 'Unobtainium');
      expect(
        alloy.children.single.materialTypeId,
        isNull,
        reason: 'the master is the authority on what is a material',
      );
    });

    test('an empty recipe column adds no property at all', () async {
      final h = _harness();
      final groups = GroupsProvider(repository: h.groupRepo);
      await groups.refresh();
      final binding = ItemSheetBinding(
        items: ItemsProvider(repository: h.itemRepo),
        groups: groups,
        itemSheet: _itemSheet(),
      );

      await binding.save([
        _row(group: 'Switch Action', name: 'Patti', alloy: 'Brass'),
      ]);
      expect(h.itemRepo.created.single.variationTree, hasLength(1));
    });

    test('blank rows are skipped, not refused', () async {
      final h = _harness();
      final groups = GroupsProvider(repository: h.groupRepo);
      await groups.refresh();
      final binding = ItemSheetBinding(
        items: ItemsProvider(repository: h.itemRepo),
        groups: groups,
        itemSheet: _itemSheet(),
      );

      final saved = await binding.save([
        _row(group: 'Switch Action', name: 'Patti'),
        SheetDraft(sheetKey: 'item'),
      ]);

      expect(saved, hasLength(1), reason: 'a sheet opens with blank rows');
      expect(h.itemRepo.created, hasLength(1));
    });

    test('a part with no name is refused with a reason', () async {
      final h = _harness();
      final groups = GroupsProvider(repository: h.groupRepo);
      await groups.refresh();
      final binding = ItemSheetBinding(
        items: ItemsProvider(repository: h.itemRepo),
        groups: groups,
        itemSheet: _itemSheet(),
      );

      final saved = await binding.save([_row(group: 'Switch Action', partNo: 1)]);
      expect(saved, isNull);
      expect(binding.lastError, contains('name'));
      expect(h.itemRepo.created, isEmpty);
    });

    test('a group with no unit is refused rather than saved wrong', () async {
      // unitId is required by the contract; a part saved under a unitless group
      // would be rejected by the server with a less useful message.
      final groupRepo = _FakeGroupRepository([
        GroupDefinition(
          id: 1, name: 'Unitless', groupStructure: 'hierarchical',
          parentGroupId: null, unitId: null, isArchived: false, usageCount: 0,
          createdAt: DateTime(2026), updatedAt: DateTime(2026),
        ),
      ]);
      final itemRepo = _FakeItemRepository();
      final groupsProvider = GroupsProvider(repository: groupRepo);
      await groupsProvider.refresh();
      final binding = ItemSheetBinding(
        items: ItemsProvider(repository: itemRepo),
        groups: groupsProvider,
        itemSheet: _itemSheet(),
      );

      final saved = await binding.save([_row(group: 'Unitless', name: 'Patti')]);
      expect(saved, isNull);
      expect(binding.lastError, contains('unit'));
      expect(itemRepo.created, isEmpty);
    });

    test('a Type inherits its parent group’s unit', () async {
      final h = _harness();
      final groups = GroupsProvider(repository: h.groupRepo);
      await groups.refresh();
      final binding = ItemSheetBinding(
        items: ItemsProvider(repository: h.itemRepo),
        groups: groups,
        itemSheet: _itemSheet(),
      );

      // Dolly is created with no unit of its own; Switch Action has unit 7.
      await binding.save([
        _row(group: 'Switch Action', type: 'Dolly', name: 'Patti'),
      ]);
      expect(h.itemRepo.created.single.unitId, 7);
    });
  });

  group('ItemSheetBinding.toDrafts', () {
    test('projects a saved item back into a row', () async {
      final groups = [
        GroupDefinition(
          id: 1, name: 'Switch Action', groupStructure: 'hierarchical',
          parentGroupId: null, unitId: 7, isArchived: false, usageCount: 0,
          createdAt: DateTime(2026), updatedAt: DateTime(2026),
        ),
        GroupDefinition(
          id: 2, name: 'Dolly', groupStructure: 'hierarchical',
          parentGroupId: 1, unitId: 7, isArchived: false, usageCount: 0,
          createdAt: DateTime(2026), updatedAt: DateTime(2026),
        ),
      ];
      final groupRepo = _FakeGroupRepository(groups);
      final groupsProvider = GroupsProvider(repository: groupRepo);
      await groupsProvider.refresh();

      final binding = ItemSheetBinding(
        items: ItemsProvider(repository: _FakeItemRepository()),
        groups: groupsProvider,
        itemSheet: _itemSheet(),
      );

      final item = ItemDefinition(
        id: 5,
        name: 'Patti',
        alias: '',
        displayName: 'Patti',
        partNo: 48,
        partCode: 'SADP48',
        quantity: 0,
        groupId: 2,
        unitId: 7,
        isArchived: false,
        usageCount: 0,
        createdAt: DateTime(2026, 5, 15, 10, 5),
        updatedAt: DateTime(2026, 5, 15, 10, 5),
        variationTree: const [],
      );

      final draft = binding.toDrafts([item]).single;

      expect(draft.get(3)?.textValue, 'Patti');
      expect(draft.get(4)?.intValue, 48);
      expect(draft.get(5)?.textValue, 'SADP48');
      // Group shows the TOP of the hierarchy and Type the child beneath it.
      expect(draft.get(1)?.optionLabel, 'Switch Action');
      expect(draft.get(2)?.optionLabel, 'Dolly');
      // The stamps come from the item, not from a hardcoded string — and in
      // the same shape a just-saved row is stamped with, or every saved row
      // differs from its own reload.
      expect(draft.get(9)?.textValue, '15/05/26');
      expect(draft.get(10)?.textValue, '10:05');
    });

    test('a part filed straight under a group has no Type', () async {
      final groupRepo = _FakeGroupRepository([
        GroupDefinition(
          id: 1, name: 'Switch Action', groupStructure: 'hierarchical',
          parentGroupId: null, unitId: 7, isArchived: false, usageCount: 0,
          createdAt: DateTime(2026), updatedAt: DateTime(2026),
        ),
      ]);
      final groupsProvider = GroupsProvider(repository: groupRepo);
      await groupsProvider.refresh();
      final binding = ItemSheetBinding(
        items: ItemsProvider(repository: _FakeItemRepository()),
        groups: groupsProvider,
        itemSheet: _itemSheet(),
      );

      final draft = binding.toDrafts([
        ItemDefinition(
          id: 5, name: 'Patti', alias: '', displayName: 'Patti',
          quantity: 0, groupId: 1, unitId: 7, isArchived: false, usageCount: 0,
          createdAt: DateTime(2026), updatedAt: DateTime(2026),
          variationTree: const [],
        ),
      ]).single;

      expect(draft.get(1)?.optionLabel, 'Switch Action');
      expect(draft.get(2)?.optionLabel, isNull);
    });
  });

  group('ItemSheetBinding update keeps what the sheet does not own', () {
    ItemVariationNodeDefinition node(
      int id,
      String name, {
      ItemVariationNodeKind kind = ItemVariationNodeKind.property,
      List<ItemVariationNodeDefinition> children = const [],
      String inputType = 'Text',
    }) =>
        ItemVariationNodeDefinition(
          id: id,
          itemId: 900,
          parentNodeId: null,
          kind: kind,
          name: name,
          displayName: name,
          position: 0,
          isArchived: false,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          children: children,
          inputType: inputType,
        );

    final at = DateTime.utc(2026, 3, 1, 9);
    ItemDefinition stored({DevelopedFor? deal}) => ItemDefinition(
          id: 900,
          name: 'Patti',
          alias: '',
          displayName: 'Patti — long form',
          partNo: 4,
          partCode: 'SAP4',
          quantity: 0,
          groupId: 1,
          // Its own unit, set apart from the group's 7.
          unitId: 12,
          developedFor: deal ??
              DevelopedFor(
                kind: DevelopedForKind.contractor,
                clientId: 44,
                subContractorId: 9,
                at: at,
                quotationAmount: 85000,
                costAmount: 61200,
              ),
          isArchived: false,
          usageCount: 0,
          createdAt: DateTime(2026, 5, 15, 10, 5),
          updatedAt: DateTime(2026, 5, 15, 10, 5),
          variationTree: [
            node(10, 'Alloy', inputType: 'Material', children: [
              node(11, 'Brass', kind: ItemVariationNodeKind.value),
              node(12, 'Copper', kind: ItemVariationNodeKind.value),
            ]),
            node(20, 'Finish', children: [
              node(21, 'Nickel', kind: ItemVariationNodeKind.value),
            ]),
          ],
        );

    SheetDraft deal({int? party, String? quotation}) {
      final draft = SheetDraft(sheetKey: 'item_party');
      final partyCol = SheetDef(id: 2, key: 'item_party', title: '', columns: dealSheetColumns)
          .columnBoundTo(SheetBindsTo.developedForParty)!;
      final quoteCol = SheetDef(id: 2, key: 'item_party', title: '', columns: dealSheetColumns)
          .columnBoundTo(SheetBindsTo.developedForQuotation)!;
      if (party != null) {
        draft.set(partyCol.id, CellValue(columnId: partyCol.id, refId: party));
      }
      if (quotation != null) {
        draft.set(quoteCol.id, CellValue(columnId: quoteCol.id, textValue: quotation));
      }
      return draft;
    }

    Future<({ItemSheetBinding binding, _FakeItemRepository repo})> open(
      ItemDefinition item, {
      SheetDraft? dealRow,
      SheetDef? live,
    }) async {
      final h = _harness();
      h.itemRepo.stored.add(item);
      await h.binding.items.refresh();
      await h.binding.groups.refresh();
      final binding = ItemSheetBinding(
        items: h.binding.items,
        groups: h.binding.groups,
        itemSheet: _itemSheet(),
        liveItemSheet: live == null ? null : () => live,
        partySheet: SheetDef(id: 2, key: 'item_party', title: '', columns: dealSheetColumns),
        dealDraft: dealRow == null ? null : () => dealRow,
      );
      return (binding: binding, repo: h.itemRepo);
    }

    test('unit, display name, other properties and node ids survive an edit',
        () async {
      final o = await open(stored());
      final row = o.binding.toDrafts([stored()]).single;
      // Change only the Alloy.
      row.set(6, const CellValue(columnId: 6, optionLabel: 'Aluminium'));

      final saved = await o.binding.saveRow(row);
      expect(saved, isNotNull, reason: o.binding.lastError ?? '');
      final sent = o.repo.updated.single;
      expect(sent.unitId, 12, reason: 'the part keeps its own unit');
      expect(sent.displayName, 'Patti — long form');

      final alloy = sent.variationTree.firstWhere((n) => n.name == 'Alloy');
      expect(alloy.id, 10, reason: 'the property keeps its id');
      expect(alloy.children.first.id, 11, reason: 'the edited value keeps its id');
      expect(alloy.children.first.name, 'Aluminium');
      expect(alloy.children.map((c) => c.name), contains('Copper'),
          reason: 'the second value is not dropped');
      expect(sent.variationTree.map((n) => n.name), contains('Finish'),
          reason: 'a property the sheet has no column for is kept');
    });

    test('the deal keeps its date, cost and contractor when untouched', () async {
      final o = await open(
        stored(),
        dealRow: deal(party: 44, quotation: '85000'),
      );
      final row = o.binding.toDrafts([stored()]).single;
      row.set(3, const CellValue(columnId: 3, textValue: 'Patti B'));

      await o.binding.saveRow(row);
      final sent = o.repo.updated.single.developedFor!;
      expect(sent.kind, DevelopedForKind.contractor);
      expect(sent.subContractorId, 9);
      expect(sent.at, at, reason: 'nothing about the deal changed');
      expect(sent.costAmount, 61200, reason: 'the sheet has no cost column');
    });

    test('a quotation of 12.50 is twelve rupees fifty, not 1250', () async {
      final o = await open(
        stored(deal: const DevelopedFor(kind: DevelopedForKind.client, clientId: 44)),
        dealRow: deal(party: 44, quotation: '12.50'),
      );
      final row = o.binding.toDrafts([stored()]).single;
      row.set(3, const CellValue(columnId: 3, textValue: 'Patti C'));

      await o.binding.saveRow(row);
      expect(o.repo.updated.single.developedFor!.quotationAmount, 12.5);
    });

    test('a property added with + reaches the save through the live sheet',
        () async {
      final live = _itemSheet(withPlating: true);
      final o = await open(stored(), live: live);
      final row = o.binding.toDrafts([stored()]).single;
      row.set(_platingColumnId,
          const CellValue(columnId: _platingColumnId, optionLabel: 'Chrome'));

      await o.binding.saveRow(row);
      final plating = o.repo.updated.single.variationTree
          .where((n) => n.name == 'Plating');
      expect(plating, hasLength(1));
      expect(plating.single.children.single.name, 'Chrome');
    });

    test('a Type that cannot be made stops the save instead of filing it '
        'under the Group', () async {
      final h = _harness();
      await h.binding.groups.refresh();
      h.groupRepo.failCreate = true;
      final saved = await h.binding.saveRow(
        _row(group: 'Switch Action', type: 'Dolly', name: 'Patti'),
      );
      expect(saved, isNull);
      expect(h.itemRepo.created, isEmpty);
    });

    test('a stored path is matched whatever its case', () async {
      final o = await open(stored());
      final data = await o.binding.referenceData();
      expect(data.existingPaths, contains('switch action › patti'));
    });
  });
}

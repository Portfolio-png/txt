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
import 'package:core_erp/sheet/sheet.dart';
import 'package:flutter_test/flutter_test.dart';

// A Group and Type typed new on the item sheet must become real groups.
//
// They never could: the sheet created them with no unit, the server refuses
// any item group without one ("unitId is required for non-machine
// hierarchical groups"), and the sheet then replaced that reason with "Could
// not file this part under a group." This fake refuses exactly as the server
// does, and files a new top-level group under Primary Group as the server does.

GroupDefinition _group(int id, String name, {int? parent, int? unitId}) =>
    GroupDefinition(
      id: id,
      name: name,
      groupType: 'item',
      groupStructure: 'hierarchical',
      description: '',
      parentGroupId: parent,
      unitId: unitId,
      isArchived: false,
      usageCount: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

class _ServerLikeGroups implements GroupRepository {
  _ServerLikeGroups(this.groups);
  final List<GroupDefinition> groups;
  final List<CreateGroupInput> created = [];
  int _next = 100;

  @override
  Future<void> init() async {}

  @override
  Future<List<GroupDefinition>> getGroups({bool withCovers = false}) async =>
      List.of(groups);

  @override
  Future<GroupDefinition> createGroup(CreateGroupInput input) async {
    if (input.unitId == null) {
      throw Exception('unitId is required for non-machine hierarchical groups.');
    }
    final parent = input.parentGroupId ??
        groups.firstWhere((g) => g.name == 'Primary Group').id;
    created.add(input);
    final made = _group(_next++, input.name, parent: parent, unitId: input.unitId);
    groups.add(made);
    return made;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Items implements ItemRepository {
  final List<CreateItemInput> created = [];
  int _next = 700;

  @override
  Future<void> init() async {}

  @override
  Future<List<ItemDefinition>> getItems() async => const [];

  @override
  Future<ItemDefinition> createItem(CreateItemInput input) async {
    created.add(input);
    return ItemDefinition(
      id: _next++,
      name: input.name,
      alias: '',
      displayName: input.name,
      quantity: 0,
      groupId: input.groupId,
      unitId: input.unitId,
      developedFor: DevelopedFor.empty,
      variationTree: const [],
      isArchived: false,
      usageCount: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SheetDraft _row(String group, String type, String name) =>
    SheetDraft(sheetKey: 'item', values: {
      1: CellValue(columnId: 1, optionLabel: group, isNew: true),
      2: CellValue(columnId: 2, optionLabel: type, isNew: true),
      3: CellValue(columnId: 3, optionLabel: name, isNew: true),
    });

void main() {
  late _ServerLikeGroups groupRepo;
  late _Items itemRepo;

  Future<ItemSheetBinding> binding({required int? primaryUnit}) async {
    groupRepo = _ServerLikeGroups([_group(1, 'Primary Group', unitId: primaryUnit)]);
    final groups = GroupsProvider(repository: groupRepo);
    await groups.refresh();
    itemRepo = _Items();
    final items = ItemsProvider(repository: itemRepo);
    await items.refresh();
    return ItemSheetBinding(
      items: items,
      groups: groups,
      itemSheet: SheetDef(id: 1, key: 'item', title: 'Item', columns: itemSheetColumns),
    );
  }

  test('a new Group and Type are created with a unit, and the part saves', () async {
    final b = await binding(primaryUnit: 7);
    final saved = await b.saveRow(_row('action', 'dolly', 'patti'));

    expect(saved, isNotNull, reason: b.lastError);
    expect(groupRepo.created.map((g) => g.name), ['action', 'dolly']);
    expect(groupRepo.created.map((g) => g.unitId), [7, 7]);
    expect(itemRepo.created.single.unitId, 7);
  });

  test('the second part under the same new Group reuses it', () async {
    final b = await binding(primaryUnit: 7);
    await b.saveRow(_row('action', 'dolly', 'patti'));
    final second = await b.saveRow(_row('Action', 'Dolly', 'dabbi'));

    expect(second, isNotNull, reason: b.lastError);
    expect(groupRepo.created, hasLength(2),
        reason: 'action now lives under Primary Group and must still be found');
  });

  test('a group saved earlier is offered again after a restart', () async {
    // The server filed "action" under Primary Group. The Group column listed
    // only parentless groups, so after a restart "action" was nowhere.
    final b = await binding(primaryUnit: 7);
    final saved = await b.saveRow(_row('action', 'dolly', 'patti'));

    final data = await b.referenceData();
    final groupOptions = [
      for (final o in data.options)
        if (o.columnId == 1) o.label,
    ];
    final typeOptions = [
      for (final o in data.options)
        if (o.columnId == 2) o.label,
    ];
    expect(groupOptions, contains('action'));
    expect(typeOptions, contains('dolly'));
    expect(typeOptions, isNot(contains('action')),
        reason: 'promoted to a Group, not offered as a Type of Primary Group');

    // Opening the part reads action › dolly, not Primary Group › action.
    final draft = b.toDrafts([saved!]).single;
    expect(draft.get(1)?.optionLabel, 'action');
    expect(draft.get(2)?.optionLabel, 'dolly');
  });

  test('a refused group shows the server\'s reason, not a shrug', () async {
    // No unit anywhere on the system: the server's refusal goes through.
    final b = await binding(primaryUnit: null);
    final saved = await b.saveRow(_row('action', 'dolly', 'patti'));

    expect(saved, isNull);
    expect(b.lastError, contains('unitId is required'));
  });
}

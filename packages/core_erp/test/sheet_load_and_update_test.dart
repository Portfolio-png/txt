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

// Opening an existing part on the sheet, and saving it back.
//
// Phase 2 could only create. A sheet that can load has three ways to go wrong
// that a sheet that cannot does not have, and each of these guards one:
//
//  * the loaded part reads as colliding with itself, because its own code is
//    in `existingCodes`;
//  * saving it files a SECOND part, because a row had nothing to say it was an
//    edit;
//  * saving it wipes the photo, the attachments and the pipeline, because
//    `UpdateItemInput` is a full replace.

class _FakeGroupRepository implements GroupRepository {
  _FakeGroupRepository(this.groups);
  final List<GroupDefinition> groups;

  @override
  Future<void> init() async {}

  @override
  Future<List<GroupDefinition>> getGroups({bool withCovers = false}) async =>
      List.of(groups);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeItemRepository implements ItemRepository {
  _FakeItemRepository(this.stored);

  final List<ItemDefinition> stored;
  final List<CreateItemInput> created = [];
  final List<UpdateItemInput> updated = [];

  /// Refuse every create with this message.
  String? refuseWith;

  /// Refuse a create whose part name is in here — one bad row among good ones.
  final Set<String> refuseRowsNamed = {};
  int _nextId = 700;

  @override
  Future<void> init() async {}

  @override
  Future<List<ItemDefinition>> getItems() async => List.of(stored);

  @override
  Future<ItemDefinition> createItem(CreateItemInput input) async {
    if (refuseWith != null) throw Exception(refuseWith);
    if (refuseRowsNamed.contains(input.name)) {
      throw Exception('"${input.name}" already exists in this group.');
    }
    created.add(input);
    final id = _nextId++;
    final item = _item(
      id: id,
      name: input.name,
      groupId: input.groupId,
      partCode: input.partCode ?? 'AUTO$id',
    );
    stored.add(item);
    return item;
  }

  @override
  Future<ItemDefinition> updateItem(UpdateItemInput input) async {
    updated.add(input);
    return _item(
      id: input.id,
      name: input.name,
      groupId: input.groupId,
      partCode: input.partCode ?? 'KEPT',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ItemDefinition _item({
  required int id,
  required String name,
  required int groupId,
  String partCode = 'SADP48',
  int? partNo = 48,
  String photoUrl = '',
  String cadFileKey = '',
  String? defaultPipelineId,
  List<ItemAttachmentDefinition> attachments = const [],
  List<ItemVariationNodeDefinition> variationTree = const [],
  DevelopedFor? developedFor,
}) {
  return ItemDefinition(
    id: id,
    name: name,
    alias: '',
    displayName: name,
    partNo: partNo,
    partCode: partCode,
    quantity: 0,
    groupId: groupId,
    unitId: 7,
    developedFor: developedFor ?? DevelopedFor.empty,
    isArchived: false,
    usageCount: 0,
    createdAt: DateTime(2026, 5, 15, 10, 5),
    updatedAt: DateTime(2026, 5, 15, 10, 5),
    variationTree: variationTree,
    photoUrl: photoUrl,
    cadFileKey: cadFileKey,
    defaultPipelineId: defaultPipelineId,
    attachments: attachments,
  );
}

GroupDefinition _group({
  required int id,
  required String name,
  int? parentGroupId,
  int? unitId = 7,
}) {
  return GroupDefinition(
    id: id,
    name: name,
    groupType: 'item',
    groupStructure: 'Standard',
    parentGroupId: parentGroupId,
    unitId: unitId,
    isArchived: false,
    usageCount: 0,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

SheetDef _itemSheet() => SheetDef(
      id: 1,
      key: 'item',
      title: 'Item Master 1',
      columns: itemSheetColumns,
    );

void main() {
  group('the production sheet declares its bindings', () {
    test('every column that feeds something says what', () {
      // The gap this guards: these ten columns carried NO `bindsTo` at all
      // while the binding and its tests were written against a parallel copy
      // that did. Wired together as they were, a save would have mapped
      // nothing.
      final bound = {
        for (final column in itemSheetColumns)
          if (column.bindsTo != null) column.bindsTo!,
      };
      expect(bound, contains(SheetBindsTo.group));
      expect(bound, contains(SheetBindsTo.set));
      expect(bound, contains(SheetBindsTo.name));
      expect(bound, contains(SheetBindsTo.partNo));
      expect(bound, contains(SheetBindsTo.partCode));
      expect(bound, contains(SheetBindsTo.createdDate));
      expect(bound, contains(SheetBindsTo.createdTime));
      expect(
        bound.where(SheetBindsTo.isVariation).length,
        2,
        reason: 'Alloy and Thickness are the recipe columns the sheet ships '
            'with; the + adds more',
      );
      expect(
        itemSheetColumns.every((c) => c.bindsTo != null),
        isTrue,
        reason: 'a column with no binding is a cell that goes nowhere',
      );
    });

    test('the recipe columns mirror the item model’s own input types', () {
      final sheet = _itemSheet();
      expect(
        sheet.columnBoundTo('${SheetBindsTo.variationPrefix}Alloy')!.kind,
        ColumnKind.material,
      );
      expect(
        sheet.columnBoundTo('${SheetBindsTo.variationPrefix}Thickness')!.kind,
        ColumnKind.gauge,
        reason: 'a gauge is not a quantity: Units.parse rejects the suffix',
      );
    });

    test('the party sheet writes only the writable fields', () {
      final writable = {
        SheetBindsTo.developedForParty,
        SheetBindsTo.developedForQuotation,
      };
      final readOnly = {
        SheetBindsTo.developedForContact,
        SheetBindsTo.developedForDesignation,
        SheetBindsTo.developedForPhone,
        SheetBindsTo.developedForEmail,
      };
      final bound = {
        for (final c in partySheetColumns)
          if (c.bindsTo != null) c.bindsTo!,
      };
      expect(bound.intersection(writable), writable);
      expect(
        bound.intersection(readOnly),
        readOnly,
        reason: 'shown as projections of the party, never written',
      );
    });

    test('the sheet collects the quotation but not the development cost', () {
      final sheet = SheetDef(
        id: 2,
        key: 'item_party',
        title: 'Party',
        columns: partySheetColumns,
      );
      expect(sheet.columnBoundTo(SheetBindsTo.developedForQuotation), isNotNull);
      expect(
        sheet.columnBoundTo(SheetBindsTo.developedForCost),
        isNull,
        reason: 'the cost column was removed from this sheet; the field and '
            'its binding stay, so a null cost must keep reading as "not '
            'known" rather than as zero',
      );
    });
  });

  group('columnBoundTo', () {
    test('finds a column by what it feeds, not by its id', () {
      final sheet = _itemSheet();
      expect(sheet.columnBoundTo(SheetBindsTo.name)!.label, 'Part Name');
      expect(sheet.columnBoundTo(SheetBindsTo.partCode)!.label, 'Part Code');
      expect(sheet.columnBoundTo('variation:Nothing'), isNull);
    });

    test('variationColumns are the recipe, in sheet order', () {
      expect(
        _itemSheet().variationColumns.map((c) => c.label),
        ['Alloy', 'Thickness'],
      );
    });
  });

  group('loading a record', () {
    test('a loaded part does not collide with itself', () async {
      // `existingCodes` and `existingPaths` come from the live table, so the
      // part being edited is in both. Loaded through `replaceRows` the sheet
      // flags a code the user never touched.
      final controller = SheetController(
        sheetDef: _itemSheet(),
        // 47 used, so the auto code derives SADP48 — the same code the live
        // table already holds for this very part.
        counters: {'Switch Action › Dolly › Patti': 47},
        existingCodes: {'SADP48'},
        existingPaths: {'switch action › dolly › patti'},
        options: const [
          ColumnOption(id: 10, columnId: 1, label: 'Switch Action'),
          ColumnOption(id: 11, columnId: 2, parentOptionId: 10, label: 'Dolly'),
          ColumnOption(id: 12, columnId: 3, parentOptionId: 11, label: 'Patti'),
        ],
      );
      addTearDown(controller.dispose);

      final row = SheetDraft(sheetKey: 'item', entityId: 500, values: {
        1: const CellValue(columnId: 1, optionId: 10, optionLabel: 'Switch Action'),
        2: const CellValue(columnId: 2, optionId: 11, optionLabel: 'Dolly'),
        3: const CellValue(columnId: 3, optionId: 12, optionLabel: 'Patti'),
        5: const CellValue(
          columnId: 5,
          textValue: 'SADP48',
          mode: ValueMode.edit,
        ),
      });

      controller.replaceRows([row.clone()]);
      expect(
        controller.errors[3]?.code,
        'duplicate_item',
        reason: 'replaceRows is for new rows — this is the trap being guarded',
      );
      expect(
        controller.errors[5]?.code,
        'code_used',
        reason: 'a TYPED code is a claim, so it collides',
      );

      controller.loadRecords([row.clone()]);
      expect(
        controller.errors[3]?.code,
        isNot('duplicate_item'),
        reason: 'a part does not already exist under its own group path',
      );
      expect(
        controller.errors[5],
        isNull,
        reason: 'nor is its own code taken by somebody else',
      );
    });

    test('loadRecords keeps the row’s record id', () {
      final controller = SheetController(sheetDef: _itemSheet());
      addTearDown(controller.dispose);
      controller.loadRecords([
        SheetDraft(sheetKey: 'item', entityId: 77),
      ]);
      expect(controller.draft.entityId, 77);
    });

    test('a cloned draft carries its record id', () {
      final draft = SheetDraft(sheetKey: 'item', entityId: 42);
      expect(draft.clone().entityId, 42);
    });

    test('toDrafts stamps the record id onto the row', () async {
      final groups = GroupsProvider(
        repository: _FakeGroupRepository([
          _group(id: 10, name: 'Switch Action'),
          _group(id: 11, name: 'Dolly', parentGroupId: 10),
        ]),
      );
      await groups.refresh();
      final items = ItemsProvider(repository: _FakeItemRepository([]));

      final binding = ItemSheetBinding(
        items: items,
        groups: groups,
        itemSheet: _itemSheet(),
      );

      final rows = binding.toDrafts([
        _item(id: 321, name: 'Patti', groupId: 11),
      ]);
      expect(rows.single.entityId, 321);
    });
  });

  group('what a save may demand', () {
    test('the server-set stamps are never required', () {
      // Date and Time are filled by the server on save, so a sheet can never
      // satisfy them beforehand. Requiring them made every new part
      // permanently unsaveable — and the prototype hid it by seeding the
      // literal string "Set on save" into those cells.
      final controller = SheetController(
        sheetDef: _itemSheet(),
        options: const [
          ColumnOption(id: 10, columnId: 1, label: 'Primary Group'),
        ],
        initialDraft: SheetDraft(sheetKey: 'item', values: {
          1: const CellValue(
            columnId: 1,
            optionId: 10,
            optionLabel: 'Primary Group',
          ),
          3: const CellValue(
            columnId: 3,
            optionLabel: 'E2E Sheet Part',
            isNew: true,
          ),
        }),
      );
      addTearDown(controller.dispose);

      final sheet = controller.sheetDef;
      final date = sheet.columnBoundTo(SheetBindsTo.createdDate)!;
      final time = sheet.columnBoundTo(SheetBindsTo.createdTime)!;

      expect(controller.draft.get(date.id), isNull, reason: 'nothing stamped yet');
      expect(controller.validateAll(), isTrue);
      expect(controller.errors[date.id], isNull);
      expect(controller.errors[time.id], isNull);
    });

    test('a level with nothing to pick does not block the one below it', () {
      // Flat item groups — no Types at all — so "Pick Type first" on Part Name
      // would be a demand nobody could meet, and the part unsaveable.
      final controller = SheetController(
        sheetDef: _itemSheet(),
        options: const [
          ColumnOption(id: 10, columnId: 1, label: 'Primary Group'),
        ],
        initialDraft: SheetDraft(sheetKey: 'item', values: {
          1: const CellValue(
            columnId: 1,
            optionId: 10,
            optionLabel: 'Primary Group',
          ),
          3: const CellValue(
            columnId: 3,
            optionLabel: 'E2E Sheet Part',
            isNew: true,
          ),
        }),
      );
      addTearDown(controller.dispose);

      final nameId = controller.sheetDef.columnBoundTo(SheetBindsTo.name)!.id;
      expect(controller.errors[nameId], isNull);
    });

    test('a level WITH something to pick still blocks the one below it', () {
      final controller = SheetController(
        sheetDef: _itemSheet(),
        options: const [
          ColumnOption(id: 10, columnId: 1, label: 'Switch Action'),
          ColumnOption(id: 11, columnId: 2, parentOptionId: 10, label: 'Dolly'),
        ],
        initialDraft: SheetDraft(sheetKey: 'item', values: {
          1: const CellValue(
            columnId: 1,
            optionId: 10,
            optionLabel: 'Switch Action',
          ),
          3: const CellValue(columnId: 3, optionLabel: 'Patti', isNew: true),
        }),
      );
      addTearDown(controller.dispose);

      final nameId = controller.sheetDef.columnBoundTo(SheetBindsTo.name)!.id;
      expect(controller.errors[nameId]?.code, 'parent_first');
    });

    test('a part still needs its group and its name', () {
      final controller = SheetController(
        sheetDef: _itemSheet(),
        initialDraft: SheetDraft(sheetKey: 'item'),
      );
      addTearDown(controller.dispose);

      expect(controller.validateAll(), isFalse);
      final sheet = controller.sheetDef;
      expect(
        controller.errors[sheet.columnBoundTo(SheetBindsTo.group)!.id]?.code,
        'required',
      );
      expect(
        controller.errors[sheet.columnBoundTo(SheetBindsTo.name)!.id]?.code,
        'required',
      );
    });
  });

  group('the identity the sheet sends', () {
    test('a derived code is never sent — the server stamps it', () async {
      // The sheet derives a running number and a code into those cells as soon
      // as a group is picked. Sending that suppressed the server's stamp and
      // handed it a guess.
      final groups = GroupsProvider(
        repository: _FakeGroupRepository([
          _group(id: 10, name: 'Primary Group'),
        ]),
      );
      await groups.refresh();
      final repo = _FakeItemRepository([]);
      final items = ItemsProvider(repository: repo);
      await items.refresh();
      final binding = ItemSheetBinding(
        items: items,
        groups: groups,
        itemSheet: _itemSheet(),
      );

      final controller = SheetController(
        sheetDef: _itemSheet(),
        options: const [
          ColumnOption(id: 10, columnId: 1, label: 'Primary Group'),
        ],
        initialDraft: SheetDraft(sheetKey: 'item', values: {
          1: const CellValue(
            columnId: 1,
            optionId: 10,
            optionLabel: 'Primary Group',
          ),
          3: const CellValue(columnId: 3, optionLabel: 'Patti', isNew: true),
        }),
      );
      addTearDown(controller.dispose);

      expect(
        controller.draft.get(5)?.textValue,
        isNotEmpty,
        reason: 'a code IS derived, as a preview',
      );

      await binding.saveRow(controller.draft);
      expect(
        repo.created.single.partCode,
        isNull,
        reason: 'neither key sent, so the server stamps both',
      );
      expect(repo.created.single.partNo, isNull);
    });

    test('a TYPED code is sent, and the server stamp is turned off', () async {
      final groups = GroupsProvider(
        repository: _FakeGroupRepository([
          _group(id: 10, name: 'Primary Group'),
        ]),
      );
      await groups.refresh();
      final repo = _FakeItemRepository([]);
      final items = ItemsProvider(repository: repo);
      await items.refresh();
      final binding = ItemSheetBinding(
        items: items,
        groups: groups,
        itemSheet: _itemSheet(),
      );

      final row = SheetDraft(sheetKey: 'item', values: {
        1: const CellValue(
          columnId: 1,
          optionId: 10,
          optionLabel: 'Primary Group',
        ),
        3: const CellValue(columnId: 3, optionLabel: 'Patti', isNew: true),
        4: const CellValue(columnId: 4, intValue: 48, mode: ValueMode.edit),
        5: const CellValue(
          columnId: 5,
          textValue: 'SADP48',
          mode: ValueMode.edit,
        ),
      });

      await binding.saveRow(row);
      expect(repo.created.single.partCode, 'SADP48');
      expect(repo.created.single.partNo, 48);
    });

    test('two names under one group do not collide on a derived code', () {
      // "Patti" and "Plate" under Primary Group both derive PGP1, because the
      // preview scopes the number by a path that includes the part name while
      // the server counts over the group. Both rows were flagged for a value
      // nobody typed.
      final controller = SheetController(
        sheetDef: _itemSheet(),
        options: const [
          ColumnOption(id: 10, columnId: 1, label: 'Primary Group'),
        ],
        initialDrafts: [
          SheetDraft(sheetKey: 'item', values: {
            1: const CellValue(
              columnId: 1,
              optionId: 10,
              optionLabel: 'Primary Group',
            ),
            3: const CellValue(columnId: 3, optionLabel: 'Patti', isNew: true),
          }),
          SheetDraft(sheetKey: 'item', values: {
            1: const CellValue(
              columnId: 1,
              optionId: 10,
              optionLabel: 'Primary Group',
            ),
            3: const CellValue(columnId: 3, optionLabel: 'Plate', isNew: true),
          }),
        ],
      );
      addTearDown(controller.dispose);

      expect(
        controller.draftAt(0).get(5)?.textValue,
        controller.draftAt(1).get(5)?.textValue,
        reason: 'the previews really are identical',
      );
      expect(controller.validateAll(), isTrue,
          reason: 'but a preview is not a claim, so neither row is refused');
    });
  });

  group('committing one row at a time', () {
    late _FakeItemRepository repo;
    late ItemMasterController controller;

    Future<ItemMasterController> sheetWith({
      List<ItemDefinition> stored = const [],
      List<GroupDefinition>? groups,
    }) async {
      final groupsProvider = GroupsProvider(
        repository: _FakeGroupRepository(
          groups == null ? [_group(id: 10, name: 'Primary Group')] : [...groups],
        ),
      );
      await groupsProvider.refresh();
      repo = _FakeItemRepository([...stored]);
      final items = ItemsProvider(repository: repo);
      await items.refresh();

      final binding = ItemSheetBinding(
        items: items,
        groups: groupsProvider,
        itemSheet: _itemSheet(),
      );
      controller = ItemMasterController(binding: binding);
      addTearDown(controller.dispose);
      await controller.loadReferenceData();
      return controller;
    }

    void fill(
      ItemMasterController c,
      int row, {
      required String name,
      String group = 'Primary Group',
    }) {
      final sheet = c.groupItemController.sheetDef;
      c.groupItemController.updateValue(
        sheet.columnBoundTo(SheetBindsTo.group)!.id,
        CellValue(
          columnId: sheet.columnBoundTo(SheetBindsTo.group)!.id,
          optionId: 10,
          optionLabel: group,
        ),
        row: row,
      );
      c.groupItemController.updateValue(
        sheet.columnBoundTo(SheetBindsTo.name)!.id,
        CellValue(
          columnId: sheet.columnBoundTo(SheetBindsTo.name)!.id,
          optionLabel: name,
          isNew: true,
        ),
        row: row,
      );
    }

    test('a committed row carries its id, and a second commit updates', () async {
      final c = await sheetWith();
      fill(c, 0, name: 'Patti');

      expect(await c.commitRow(0), isTrue);
      expect(repo.created, hasLength(1));
      final id = c.groupItemController.draftAt(0).entityId;
      expect(id, isNotNull);

      // Editing a committed row and committing again must UPDATE, not file a
      // second part.
      fill(c, 0, name: 'Patti Mk2');
      expect(await c.commitRow(0), isTrue);
      expect(repo.created, hasLength(1), reason: 'still only one create');
      expect(repo.updated, hasLength(1));
      expect(repo.updated.single.id, id);
    });

    // --- picking an existing part ------------------------------------------

    ColumnOption nameOption(ItemMasterController c, int id) {
      final column = c.groupItemController.sheetDef.columnBoundTo(
        SheetBindsTo.name,
      )!;
      return c.groupItemController.options.firstWhere(
        (o) => o.columnId == column.id && o.id == id,
      );
    }

    int nameColumn(ItemMasterController c) =>
        c.groupItemController.sheetDef.columnBoundTo(SheetBindsTo.name)!.id;

    test('picking an existing part loads it into the row, as an edit', () async {
      final patti = _item(id: 500, name: 'Patti', groupId: 10);
      final c = await sheetWith(stored: [patti]);
      final sheet = c.groupItemController;

      sheet.setOption(nameColumn(c), nameOption(c, 500), row: 0);
      expect(sheet.draftAt(0).entityId, 500, reason: 'that part, not a new one');
      expect(sheet.isRowLocked(0), isFalse, reason: 'open to edit right away');
      expect(c.savedItemId, 500, reason: 'the sections below follow it');
      expect(sheet.validateRow(0), isTrue, reason: 'not "already exists"');

      fill(c, 0, name: 'Patti Mk2');
      expect(await c.commitRow(0), isTrue);
      expect(repo.created, isEmpty);
      expect(repo.updated.single.id, 500);
    });

    test('a part already on another row is gone to, not loaded twice', () async {
      final patti = _item(id: 500, name: 'Patti', groupId: 10);
      final c = await sheetWith(stored: [patti]);
      final sheet = c.groupItemController;
      c.loadItems(<ItemDefinition>[patti]);
      sheet.addRow();
      expect(sheet.row, 1);

      sheet.setOption(nameColumn(c), nameOption(c, 500), row: 1);
      expect(sheet.row, 0);
      expect(sheet.rowCount, 1, reason: 'the row that only held the pick goes');
    });

    test('two parts with one name are both offered, told apart by code', () async {
      final c = await sheetWith(
        stored: [
          _item(id: 500, name: 'Patti', groupId: 10, partCode: 'SADP48'),
          _item(id: 501, name: 'Patti', groupId: 10, partCode: 'SADP49'),
        ],
      );
      final offered = c.groupItemController.options
          .where((o) => o.columnId == nameColumn(c))
          .toList();
      expect(offered.map((o) => o.id), [500, 501]);
      expect(offered.map((o) => o.detail), ['SADP48', 'SADP49']);

      c.groupItemController.setOption(nameColumn(c), offered[1], row: 0);
      expect(c.groupItemController.draftAt(0).entityId, 501);
    });

    test('a blank row is not a failure and is not written', () async {
      final c = await sheetWith();
      expect(await c.commitRow(0), isFalse);
      expect(c.rowError(0), isNull, reason: 'blank is not an error');
      expect(repo.created, isEmpty);
    });

    test('a refused row keeps what was typed and writes nothing', () async {
      final c = await sheetWith();
      fill(c, 0, name: 'Patti');
      repo.refuseWith = 'Name already used in this group.';

      expect(await c.commitRow(0), isFalse);
      expect(c.rowError(0), contains('already used'));
      expect(
        c.groupItemController.draftAt(0).get(3)?.optionLabel,
        'Patti',
        reason: 'clearing on failure throws away the typing',
      );
      expect(c.groupItemController.draftAt(0).entityId, isNull);
    });

    test('ONE bad row does not cost the good ones', () async {
      // The defect this model replaces: the batching save created rows 1-2 on
      // the server, hit row 3, and returned null discarding both — so the sheet
      // said nothing saved while two parts were already stored, and a retry
      // collided with them.
      final c = await sheetWith();
      fill(c, 0, name: 'Patti');
      c.groupItemController.addRow();
      fill(c, 1, name: 'Dabbi');
      c.groupItemController.addRow();
      fill(c, 2, name: 'Threading Patti');

      repo.refuseRowsNamed.add('Dabbi');
      final written = await c.commitAllRows();

      expect(written, 2);
      expect(repo.created.map((i) => i.name), ['Patti', 'Threading Patti']);
      expect(c.savedRows, {0, 2});
      expect(c.rowError(1), isNotNull);
      expect(c.rowError(0), isNull);
      expect(c.rowError(2), isNull);
      expect(c.statusBarMessage, contains('2 saved, 1 need'));
    });

    test('committing again does not re-create the rows that landed', () async {
      final c = await sheetWith();
      fill(c, 0, name: 'Patti');
      c.groupItemController.addRow();
      fill(c, 1, name: 'Dabbi');

      repo.refuseRowsNamed.add('Dabbi');
      await c.commitAllRows();
      expect(repo.created, hasLength(1));

      // The user fixes the bad row and presses Save again.
      repo.refuseRowsNamed.clear();
      fill(c, 1, name: 'Dabbi Two');
      await c.commitAllRows();

      expect(
        repo.created.map((i) => i.name),
        ['Patti', 'Dabbi Two'],
        reason: 'the row that already landed is not filed a second time',
      );
      expect(
        repo.updated,
        isEmpty,
        reason: 'row 0 was untouched since it saved, so it is not rewritten '
            'either — an update is a full replace and costs information',
      );
    });

    test('a committed row is never re-derived', () async {
      // Committing row 1 moves the counters. Row 1 is in the database, so its
      // code must not move with them; row 2 is not, so its must.
      final c = await sheetWith();
      fill(c, 0, name: 'Patti');
      c.groupItemController.addRow();
      fill(c, 1, name: 'Dabbi');

      final codeColumn =
          c.groupItemController.sheetDef.columnBoundTo(SheetBindsTo.partCode)!;
      expect(await c.commitRow(0), isTrue);
      final savedCode =
          c.groupItemController.draftAt(0).get(codeColumn.id)?.textValue;

      c.groupItemController.applyReferenceData(const SheetReferenceData(
        counters: {'Primary Group': 500},
      ));

      expect(
        c.groupItemController.draftAt(0).get(codeColumn.id)?.textValue,
        savedCode,
        reason: 'a stored code is the server\'s answer, not a suggestion',
      );
    });
  });

  group('reference data arriving late', () {
    test('a reload reaches the pickers after the masters fill in', () async {
      // What the e2e caught: the screen opened before GroupsProvider had
      // finished its first fetch, loaded reference data once in a post-frame
      // callback, and the Group picker then offered NOTHING — on a workspace
      // with three groups in it. A single load has no way to recover.
      final groupRepo = _FakeGroupRepository([]);
      final groups = GroupsProvider(repository: groupRepo);
      await groups.refresh();

      final items = ItemsProvider(repository: _FakeItemRepository([]));
      final binding = ItemSheetBinding(
        items: items,
        groups: groups,
        itemSheet: _itemSheet(),
      );
      final controller = ItemMasterController(binding: binding);
      addTearDown(controller.dispose);

      final groupColumn = _itemSheet().columnBoundTo(SheetBindsTo.group)!;
      await controller.loadReferenceData();
      expect(
        controller.groupItemController.options
            .where((o) => o.columnId == groupColumn.id),
        isEmpty,
        reason: 'no groups had loaded yet (the gauge column still offers the '
            'SWG table, which comes from a constant)',
      );

      // The masters arrive.
      groupRepo.groups.add(_group(id: 10, name: 'Primary Group'));
      await groups.refresh();
      await controller.loadReferenceData();

      expect(
        controller.groupItemController.options
            .where((o) => o.label == 'Primary Group'),
        hasLength(1),
        reason: 'a second load should pick the groups up',
      );
    });

    test('a reload keeps options the user minted here', () async {
      final groups = GroupsProvider(
        repository: _FakeGroupRepository([
          _group(id: 10, name: 'Primary Group'),
        ]),
      );
      await groups.refresh();
      final items = ItemsProvider(repository: _FakeItemRepository([]));
      final binding = ItemSheetBinding(
        items: items,
        groups: groups,
        itemSheet: _itemSheet(),
      );
      final controller = ItemMasterController(binding: binding);
      addTearDown(controller.dispose);

      await controller.loadReferenceData();

      // A part name typed into the picker, not yet saved.
      final nameColumn = _itemSheet().columnBoundTo(SheetBindsTo.name)!;
      controller.groupItemController
          .addNewOption(nameColumn.id, 'E2E Sheet Part');
      expect(
        controller.groupItemController.draft.get(nameColumn.id)?.optionLabel,
        'E2E Sheet Part',
      );

      // Reference data arrives again — an item save notifies the provider, so
      // this happens on the save that is about to use the typed value.
      await controller.loadReferenceData();

      expect(
        controller.groupItemController.options
            .where((o) => o.label == 'E2E Sheet Part'),
        hasLength(1),
        reason: 'unsaved work is not the server’s list to replace',
      );
      expect(
        controller.groupItemController.errors[nameColumn.id]?.code,
        isNot('not_in_list'),
      );
    });
  });

  group('saving a loaded record', () {
    late _FakeItemRepository repo;
    late ItemsProvider items;
    late GroupsProvider groups;

    Future<ItemSheetBinding> bindingFor(List<ItemDefinition> stored) async {
      groups = GroupsProvider(
        repository: _FakeGroupRepository([
          _group(id: 10, name: 'Switch Action'),
          _group(id: 11, name: 'Dolly', parentGroupId: 10),
        ]),
      );
      await groups.refresh();
      repo = _FakeItemRepository(stored);
      items = ItemsProvider(repository: repo);
      await items.refresh();
      return ItemSheetBinding(
        items: items,
        groups: groups,
        itemSheet: _itemSheet(),
      );
    }

    SheetDraft row({int? entityId, String name = 'Patti'}) =>
        SheetDraft(sheetKey: 'item', entityId: entityId, values: {
          1: const CellValue(columnId: 1, optionLabel: 'Switch Action'),
          2: const CellValue(columnId: 2, optionLabel: 'Dolly'),
          3: CellValue(columnId: 3, optionLabel: name),
          4: const CellValue(columnId: 4, intValue: 48),
          5: const CellValue(columnId: 5, textValue: 'SADP48'),
        });

    test('a row with no record id creates', () async {
      final binding = await bindingFor([]);
      final saved = await binding.save([row()]);
      expect(saved, isNotNull);
      expect(repo.created, hasLength(1));
      expect(repo.updated, isEmpty);
    });

    test('a row with a record id updates, and files no second part', () async {
      final existing = _item(id: 500, name: 'Patti', groupId: 11);
      final binding = await bindingFor([existing]);

      final saved = await binding.save([row(entityId: 500, name: 'Patti Mk2')]);
      expect(saved, isNotNull);
      expect(
        repo.created,
        isEmpty,
        reason: 'editing a part must not file a second one',
      );
      expect(repo.updated, hasLength(1));
      expect(repo.updated.single.id, 500);
      expect(repo.updated.single.name, 'Patti Mk2');
    });

    test('an update carries forward everything the sheet does not own', () async {
      // `UpdateItemInput` is a full replace: a field it does not carry takes
      // its default. An update built from the sheet alone wipes the part's
      // photo, CAD file, attachments and pipeline.
      final existing = _item(
        id: 500,
        name: 'Patti',
        groupId: 11,
        photoUrl: 'https://cdn/patti.png',
        cadFileKey: 'cad/patti.step',
        defaultPipelineId: 'pipe-7',
        attachments: const [
          ItemAttachmentDefinition(
            label: 'Drawing',
            objectKey: 'att/patti.pdf',
            fileName: 'patti.pdf',
          ),
        ],
      );
      final binding = await bindingFor([existing]);

      await binding.save([row(entityId: 500)]);
      final update = repo.updated.single;

      expect(update.photoUrl, 'https://cdn/patti.png');
      expect(update.cadFileKey, 'cad/patti.step');
      expect(update.defaultPipelineId, 'pipe-7');
      expect(update.attachments, hasLength(1));
      expect(update.attachments.single.objectKey, 'att/patti.pdf');
    });

    test('an update with both identity keys declares them', () async {
      // `partIdentitySpecified` exists on update and not on create. False with
      // both keys present would drop a typed code silently. Typed is the
      // operative word: a derived preview is not sent at all.
      final binding = await bindingFor([
        _item(id: 500, name: 'Patti', groupId: 11),
      ]);
      final typed = row(entityId: 500);
      typed.set(
        4,
        const CellValue(columnId: 4, intValue: 48, mode: ValueMode.edit),
      );
      typed.set(
        5,
        const CellValue(
          columnId: 5,
          textValue: 'SADP48',
          mode: ValueMode.edit,
        ),
      );
      await binding.save([typed]);
      expect(repo.updated.single.partIdentitySpecified, isTrue);
      expect(repo.updated.single.partCode, 'SADP48');
    });

    test('an update with no typed identity leaves the stamp alone', () async {
      final binding = await bindingFor([
        _item(id: 500, name: 'Patti', groupId: 11),
      ]);
      final bare = SheetDraft(sheetKey: 'item', entityId: 500, values: {
        1: const CellValue(columnId: 1, optionLabel: 'Switch Action'),
        2: const CellValue(columnId: 2, optionLabel: 'Dolly'),
        3: const CellValue(columnId: 3, optionLabel: 'Patti'),
      });
      await binding.save([bare]);
      expect(
        repo.updated.single.partIdentitySpecified,
        isFalse,
        reason: 'the server keeps the code it already stamped',
      );
    });

    test('an empty recipe keeps the variation tree rather than clearing it', () async {
      final existing = _item(
        id: 500,
        name: 'Patti',
        groupId: 11,
        variationTree: [
          ItemVariationNodeDefinition(
            id: 1,
            itemId: 500,
            parentNodeId: null,
            kind: ItemVariationNodeKind.property,
            name: 'Thickness',
            displayName: 'Thickness',
            inputType: 'Gauge',
            position: 0,
            children: const [],
            isArchived: false,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
        ],
      );
      final binding = await bindingFor([existing]);
      await binding.save([row(entityId: 500)]);

      final tree = repo.updated.single.variationTree;
      expect(tree, hasLength(1));
      expect(tree.single.name, 'Thickness');
      expect(
        tree.single.inputType,
        'Gauge',
        reason: 'ItemsProvider’s own converter drops inputType, so a Gauge '
            'property would come back as Text',
      );
    });

    test('a record that vanished is refused, not silently created', () async {
      final binding = await bindingFor([]);
      final saved = await binding.save([row(entityId: 500)]);
      expect(saved, isNull);
      expect(repo.created, isEmpty);
      expect(binding.lastError, contains('no longer in the catalogue'));
    });
  });
}

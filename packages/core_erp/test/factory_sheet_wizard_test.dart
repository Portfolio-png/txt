import 'package:core_erp/features/groups/data/repositories/group_repository.dart';
import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/groups/domain/group_inputs.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/groups/presentation/widgets/factory_sheet_wizard.dart';
import 'package:core_erp/features/items/data/repositories/item_repository.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/domain/item_inputs.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/features/units/data/repositories/unit_repository.dart';
import 'package:core_erp/features/units/domain/unit_definition.dart';
import 'package:core_erp/features/units/presentation/providers/units_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _FakeGroupRepository implements GroupRepository {
  final List<GroupDefinition> groups = [
    GroupDefinition(
      id: 1,
      name: 'Switch Action',
      groupStructure: 'hierarchical',
      parentGroupId: null,
      unitId: 1,
      isArchived: false,
      usageCount: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
  ];

  @override
  Future<void> init() async {}

  @override
  Future<List<GroupDefinition>> getGroups({bool withCovers = false}) async => List.of(groups);

  @override
  Future<GroupDefinition> createGroup(CreateGroupInput input) async {
    final g = GroupDefinition(
      id: groups.length + 1,
      name: input.name,
      groupStructure: 'hierarchical',
      parentGroupId: null,
      unitId: 1,
      isArchived: false,
      usageCount: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    groups.add(g);
    return g;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeItemRepository implements ItemRepository {
  final List<ItemDefinition> items = [];

  @override
  Future<void> init() async {}

  @override
  Future<List<ItemDefinition>> getItems() async => List.of(items);

  @override
  Future<ItemDefinition> createItem(CreateItemInput input) async {
    final it = ItemDefinition(
      id: items.length + 1,
      name: input.name,
      alias: '',
      displayName: input.displayName,
      quantity: 0,
      partCode: input.partCode ?? '',
      groupId: input.groupId,
      unitId: input.unitId,
      isArchived: false,
      usageCount: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      variationTree: const [],
    );
    items.add(it);
    return it;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUnitRepository implements UnitRepository {
  final List<UnitDefinition> units = [
    UnitDefinition(
      id: 1,
      name: 'Piece',
      symbol: 'pcs',
      notes: '',
      unitGroupId: null,
      unitGroupName: null,
      conversionFactor: 1,
      conversionBaseUnitId: null,
      conversionBaseUnitName: null,
      conversionType: 'linear',
      precision: 0,
      unitGroupDimension: null,
      unitGroupBaseUnitId: null,
      isArchived: false,
      usageCount: 1,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
  ];

  @override
  Future<void> init() async {}

  @override
  Future<List<UnitDefinition>> getUnits() async => List.of(units);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('FactorySheetWizard renders 7-page blueprint fields, calculates codes, yield and scrap', (tester) async {
    final groupRepo = _FakeGroupRepository();
    final itemRepo = _FakeItemRepository();
    final unitRepo = _FakeUnitRepository();

    final groupsProvider = GroupsProvider(repository: groupRepo);
    final itemsProvider = ItemsProvider(repository: itemRepo);
    final unitsProvider = UnitsProvider(repository: unitRepo);

    await tester.binding.setSurfaceSize(const Size(1400, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GroupsProvider>.value(value: groupsProvider),
          ChangeNotifierProvider<ItemsProvider>.value(value: itemsProvider),
          ChangeNotifierProvider<UnitsProvider>.value(value: unitsProvider),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: FactorySheetWizard(
              onSwitchToBench: () {},
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Assert Blueprint Title & Badges
    expect(find.text('Factory Sheet Wizard'), findsWidgets);
    expect(find.text('Page 1'), findsNWidgets(2));
    expect(find.text('Page 2'), findsOneWidget);
    expect(find.text('Pages 4 & 5'), findsOneWidget);
    expect(find.text('Page 4 Bottom'), findsOneWidget);
    expect(find.text('Pages 6 & 7'), findsOneWidget);

    // 2. Trunk Stamped Code (SADP48)
    expect(find.text('SADP48'), findsWidgets);

    // 3. Developed For Commercial card
    expect(find.textContaining('Gold Madel'), findsWidgets);
    expect(find.textContaining('Kissan Jain'), findsWidgets);
    expect(find.textContaining('Director'), findsWidgets);
    expect(find.text('85000'), findsWidgets);

    // 4. Material Variant: Initially Brass (SADPB2248)
    expect(find.text('SADPB2248'), findsWidgets);

    // 5. Test 1-Click Clone for Another Material (Page 5: Mild Steel -> SADPMS2248)
    final cloneBtn = find.text('📋 Clone for Another Material');
    expect(cloneBtn, findsOneWidget);
    await tester.tap(cloneBtn);
    await tester.pumpAndSettle();

    final msOption = find.textContaining('Mild Steel (MS)');
    expect(msOption, findsOneWidget);
    await tester.tap(msOption);
    await tester.pumpAndSettle();

    expect(find.text('SADPMS2248'), findsWidgets);

    // 5. Units Yield Ladder (1 Gross + 7 Dozen + 0 Pcs = 228 pcs)
    expect(find.text('228 Items / Sheet'), findsOneWidget);

    // 6. Live Scrap Calculation (2.080 - 0.842 = 1.238 kg)
    expect(find.text('1.238 kg'), findsOneWidget);

    // 7. Tooling Suite (CDSADP48, RSADP48, ASADP48) with Rack 23-4
    expect(find.text('CDSADP48'), findsWidgets);
    expect(find.text('RSADP48'), findsWidgets);
    expect(find.text('ASADP48'), findsWidgets);
    expect(find.textContaining('F206'), findsWidgets);
    expect(find.textContaining('23-4'), findsWidgets);

    // 8. 9-Stage Routing Ribbon
    expect(find.text('Stage 1'), findsOneWidget);
    expect(find.text('Die'), findsWidgets);
    expect(find.text('Stage 2'), findsOneWidget);
    expect(find.text('Shearing'), findsWidgets);
    expect(find.text('Stage 3'), findsOneWidget);
    expect(find.text('Cutting'), findsWidgets);
    expect(find.text('Stage 4'), findsOneWidget);
    expect(find.text('Riveting'), findsWidgets);
    expect(find.text('Stage 5'), findsOneWidget);
    expect(find.text('Assembly'), findsWidgets);
    expect(find.text('Stage 6'), findsOneWidget);
    expect(find.text('Packing'), findsWidgets);
    expect(find.text('Stage 7'), findsOneWidget);
    expect(find.text('Barcode'), findsWidgets);
    expect(find.text('Stage 8'), findsOneWidget);
    expect(find.text('Billing'), findsWidgets);
    expect(find.text('Stage 9'), findsOneWidget);
    expect(find.text('Delivery'), findsWidgets);

    // 9. Machine Assignment
    expect(find.text('Mayank 35T Power Press (PP-4)'), findsWidgets);

    // 10. Sibling Tray & Sibling Adding / Switching
    expect(find.textContaining('SET COMPONENTS IN "Dolly"'), findsOneWidget);
    expect(find.text('+ Add Part to Set'), findsOneWidget);
    await tester.tap(find.text('+ Add Part to Set'));
    await tester.pumpAndSettle();

    // With 2 siblings existing (Brass Patti + MS Patti clone), next added part is Threading Patti
    expect(find.textContaining('Threading Patti'), findsWidgets);
    expect(find.text('SADTP48'), findsWidgets);

    // Switch back to 1. Patti
    final pattiTab = find.textContaining('1. Patti');
    expect(pattiTab, findsWidgets);
    await tester.tap(pattiTab.first);
    await tester.pumpAndSettle();
    expect(find.text('SADP48'), findsWidgets);

    // 11. Click Save Complete Manufacturing Recipe
    final saveBtn = find.text('Save Complete Manufacturing Recipe');
    expect(saveBtn, findsOneWidget);
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();

    // Verify item created in itemRepo
    expect(itemRepo.items.length, 1);
    expect(itemRepo.items.first.partCode, 'SADP48');
    expect(itemRepo.items.first.name, 'Patti');
    expect(itemRepo.items.first.displayName, 'Dolly Patti');
  });

  testWidgets('FactorySheetWizard supports in-dropdown creation for missing Group', (tester) async {
    final groupRepo = _FakeGroupRepository();
    final itemRepo = _FakeItemRepository();
    final unitRepo = _FakeUnitRepository();

    final groupsProvider = GroupsProvider(repository: groupRepo);
    final itemsProvider = ItemsProvider(repository: itemRepo);
    final unitsProvider = UnitsProvider(repository: unitRepo);

    await tester.binding.setSurfaceSize(const Size(1400, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GroupsProvider>.value(value: groupsProvider),
          ChangeNotifierProvider<ItemsProvider>.value(value: itemsProvider),
          ChangeNotifierProvider<UnitsProvider>.value(value: unitsProvider),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: FactorySheetWizard(
              onSwitchToBench: () {},
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Tap on Group Dropdown
    final groupDropdown = find.byKey(const ValueKey('wizard_group_select'));
    expect(groupDropdown, findsOneWidget);
    await tester.tap(groupDropdown);
    await tester.pumpAndSettle();

    // Type new group name in Search field of the opened picker dialog
    final dialogSearch = find.byType(TextField).last;
    await tester.enterText(dialogSearch, 'Power Socket');
    await tester.pumpAndSettle();

    // Tap "+ Add \"Power Socket\" as new Group" creation option
    final createOption = find.text('+ Add "Power Socket" as new Group');
    expect(createOption, findsOneWidget);
    await tester.tap(createOption);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Dialog appears with Title "Add New Item Group"
    expect(find.text('Add New Item Group'), findsOneWidget);
    expect(find.text('Power Socket'), findsWidgets);

    // Save dialog via "Save & Select"
    final saveDialogBtn = find.text('Save & Select');
    expect(saveDialogBtn, findsOneWidget);
    await tester.tap(saveDialogBtn);
    await tester.pumpAndSettle();

    // Assert new group is selected and trunk starts with PS (Power Socket)
    expect(find.text('Power Socket'), findsWidgets);
    expect(find.text('PSDP48'), findsWidgets);
    expect(groupRepo.groups.any((g) => g.name == 'Power Socket'), isTrue);
  });
}

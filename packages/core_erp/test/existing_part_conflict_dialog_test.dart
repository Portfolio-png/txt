import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/presentation/widgets/existing_part_conflict_dialog.dart';
import 'package:core_erp/sheet/sheet.dart';

void main() {
  final testSheetDef = SheetDef(
    id: 1,
    key: 'item',
    title: 'Item Master',
    columns: [
      const ColumnDef(
        id: 1,
        sheetId: 1,
        position: 0,
        label: 'Part Name',
        kind: ColumnKind.text,
        bindsTo: SheetBindsTo.name,
      ),
      const ColumnDef(
        id: 2,
        sheetId: 1,
        position: 1,
        label: 'Part Code',
        kind: ColumnKind.code,
        bindsTo: SheetBindsTo.partCode,
      ),
      const ColumnDef(
        id: 3,
        sheetId: 1,
        position: 2,
        label: 'Part No',
        kind: ColumnKind.seq,
      ),
      const ColumnDef(
        id: 4,
        sheetId: 1,
        position: 3,
        label: 'Alloy',
        kind: ColumnKind.text,
        bindsTo: 'variation.alloy',
        identity: true,
      ),
      const ColumnDef(
        id: 5,
        sheetId: 1,
        position: 4,
        label: 'Thickness',
        kind: ColumnKind.text,
        bindsTo: 'variation.thickness',
        identity: true,
      ),
    ],
  );

  final testItem = ItemDefinition(
    id: 101,
    name: 'fd',
    alias: '',
    displayName: 'fd',
    quantity: 0,
    groupId: 10,
    unitId: 1,
    isArchived: false,
    usageCount: 0,
    createdAt: DateTime(2026, 11, 23, 3, 30),
    updatedAt: DateTime(2026, 11, 23, 3, 30),
    partCode: 'ADFA23G2N2',
    partNo: 2,
    variationTree: [
      ItemVariationNodeDefinition(
        id: 1,
        itemId: 101,
        parentNodeId: null,
        kind: ItemVariationNodeKind.property,
        name: 'Alloy',
        displayName: 'Alloy',
        position: 0,
        isArchived: false,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        children: [
          ItemVariationNodeDefinition(
            id: 2,
            itemId: 101,
            parentNodeId: 1,
            kind: ItemVariationNodeKind.value,
            name: 'Aluminium',
            displayName: 'Aluminium',
            position: 0,
            children: const [],
            isArchived: false,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
        ],
      ),
      ItemVariationNodeDefinition(
        id: 3,
        itemId: 101,
        parentNodeId: null,
        kind: ItemVariationNodeKind.property,
        name: 'Thickness',
        displayName: 'Thickness',
        position: 1,
        isArchived: false,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        children: [
          ItemVariationNodeDefinition(
            id: 4,
            itemId: 101,
            parentNodeId: 3,
            kind: ItemVariationNodeKind.value,
            name: '23 Gauge',
            displayName: '23 Gauge',
            position: 0,
            children: const [],
            isArchived: false,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
        ],
      ),
    ],
    dies: const [
      ItemDieLink(
        id: 'die_1',
        toolCode: 'D-01',
        dieType: 'cutting',
        dieTypeLabel: 'Cutting',
        madeBy: 'Apex Tools',
        storeArea: 'Store A',
        rackNo: '12',
      ),
    ],
    machines: const [
      ItemMachineLink(
        id: 'mach_1',
        name: 'Power Press 50T',
        assetId: 'PP-4',
        machineType: 'Power Press',
        machineMake: 'Amada',
        capacityKgf: 50000,
        strokesPerMinute: 60,
      ),
    ],
  );

  testWidgets('ExistingPartConflictDialog displays full Item Master, Die & Machine details with Creator info', (tester) async {
    final controller = SheetController(sheetDef: testSheetDef);
    final draft = controller.draft;

    ExistingPartConflictAction? chosenAction;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              chosenAction = await showDialog<ExistingPartConflictAction>(
                context: context,
                builder: (dialogCtx) => ExistingPartConflictDialog(
                  part: testItem,
                  draft: draft,
                  sheet: controller,
                  nextPartNo: 3,
                  creatorName: 'Rutuparn',
                  creatorRole: 'admin',
                  groupPath: 'action › dolly',
                  conflictMessage: 'Part No 2 is already used within action › dolly › fd. The last one is 2.',
                ),
              );
            },
            child: const Text('Open Dialog'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    // Verify Header & Conflict message
    expect(find.text('PART ALREADY EXISTS'), findsOneWidget);
    expect(find.text('Part already exists in Item Master'), findsOneWidget);
    expect(
      find.text('Part No 2 is already used within action › dolly › fd. The last one is 2.'),
      findsOneWidget,
    );

    // Verify Item Master details
    expect(find.text('fd'), findsOneWidget);
    expect(find.text('ADFA23G2N2'), findsOneWidget);
    expect(find.text('Part #2'), findsOneWidget);
    expect(find.text('action › dolly'), findsOneWidget);
    expect(find.textContaining('Created by: Rutuparn (admin)'), findsOneWidget);

    // Verify Material Specs
    expect(find.textContaining('Alloy: Aluminium'), findsOneWidget);
    expect(find.textContaining('Thickness: 23 Gauge'), findsOneWidget);

    // Verify Die Process Master details
    expect(find.text('Die Process Master Details'), findsOneWidget);
    expect(find.text('D-01'), findsOneWidget);
    expect(find.textContaining('Type: Cutting · Maker: Apex Tools'), findsOneWidget);
    expect(find.textContaining('Location: Store A · Rack 12'), findsOneWidget);

    // Verify Machine Master details
    expect(find.text('Machine Master Details'), findsOneWidget);
    expect(find.text('PP-4'), findsOneWidget);
    expect(find.textContaining('Power Press 50T · Amada'), findsOneWidget);
    expect(find.textContaining('Capacity: 50.0 T'), findsOneWidget);

    // Verify Use Next Part No button
    final nextBtn = find.byKey(const ValueKey('conflict_use_next_no_btn'));
    expect(nextBtn, findsOneWidget);
    expect(find.text('Use Next Part No (3)'), findsOneWidget);

    // Tap Use Next Part No
    await tester.tap(nextBtn);
    await tester.pumpAndSettle();

    expect(chosenAction, equals(ExistingPartConflictAction.useNextPartNo));
  });

  testWidgets('ExistingPartConflictDialog handles open in another tab conflict', (tester) async {
    final draft1 = SheetDraft(sheetKey: 'item');
    final draft2 = SheetDraft(sheetKey: 'item');
    final controller = SheetController(
      sheetDef: testSheetDef,
      initialDrafts: [draft1, draft2],
    );

    ExistingPartConflictAction? chosenAction;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              chosenAction = await showDialog<ExistingPartConflictAction>(
                context: context,
                builder: (dialogCtx) => ExistingPartConflictDialog(
                  part: testItem,
                  draft: draft1,
                  sheet: controller,
                  openInTabRow: 1, // Open in Tab 2
                  creatorName: 'Rutuparn',
                  groupPath: 'action › dolly',
                  conflictMessage: 'This part is already open in Tab 2',
                ),
              );
            },
            child: const Text('Open Dialog'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('TAB ALREADY OPEN'), findsOneWidget);
    expect(find.text('This part is already open in Tab 2'), findsOneWidget);
    expect(find.textContaining('Tab 2 holds this exact part'), findsOneWidget);

    // Tap Switch to Tab button
    final switchBtn = find.byKey(const ValueKey('conflict_switch_tab_btn'));
    expect(switchBtn, findsOneWidget);
    await tester.tap(switchBtn);
    await tester.pumpAndSettle();

    expect(chosenAction, equals(ExistingPartConflictAction.switchToTab));
  });

  testWidgets('ExistingPartConflictDialog cancels cleanly', (tester) async {
    final controller = SheetController(sheetDef: testSheetDef);
    ExistingPartConflictAction? chosenAction;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              chosenAction = await showDialog<ExistingPartConflictAction>(
                context: context,
                builder: (dialogCtx) => ExistingPartConflictDialog(
                  part: testItem,
                  draft: controller.draft,
                  sheet: controller,
                ),
              );
            },
            child: const Text('Open Dialog'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    final cancelBtn = find.byKey(const ValueKey('conflict_cancel_btn'));
    expect(cancelBtn, findsOneWidget);
    await tester.tap(cancelBtn);
    await tester.pumpAndSettle();

    expect(chosenAction, equals(ExistingPartConflictAction.cancel));
  });
}

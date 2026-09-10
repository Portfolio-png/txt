import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_prototype/features/sheet_planning/domain/sheet_plan.dart';
import 'package:flutter_prototype/main.dart';

void main() {
  test('Physics math: 1 Sheet converts to 8 Strips and 72 Blanks with 91.7% Yield', () {
    final cuttingPlan = SheetPlan.empty().copyWith(
      sheetWidthInches: 48,
      sheetHeightInches: 96,
      sheetThicknessMm: 1.2,
      edgeTrimMm: 10,
      kerfMm: 2,
      materialName: 'Steel / MS',
      bands: [const Band(sizeMm: 145, count: 8)],
      subCuts: {
        0: [const SubCut(sizeMm: 260, count: 9)],
      },
      plannedPartName: 'Enclosure Blank 145×260',
    );

    final totalParts = pieceCount(cuttingPlan);
    expect(totalParts, equals(72));

    final weight = calculateWeight(cuttingPlan);
    expect(weight.sheetKg, closeTo(28.00, 0.1));
    expect(weight.partsKg, closeTo(25.57, 0.1));
    expect(weight.scrapKg, closeTo(2.43, 0.1));
    expect(weight.yieldPercent, closeTo(91.3, 0.2));
  });

  testWidgets('Full Prototype Interaction: Pipeline -> CAD Planner -> Transformation Simulator -> Global Library', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const PaperPrototypeApp());
    await tester.pumpAndSettle();

    // 1. Verify Pipeline Designer Screen initial state
    expect(find.text('2D Pipeline Designer'), findsOneWidget);
    expect(find.text('Precision Enclosure — 5 Stage Transformation Line'), findsOneWidget);
    expect(find.text('Slating (8 Strips)'), findsWidgets);
    expect(find.text('Cutting (72 Blanks)'), findsWidgets);

    // 2. Open Global Node Library from Toolbar (Notch Slider Drawer)
    final nodeLibraryBtn = find.widgetWithText(OutlinedButton, 'Node Library');
    expect(nodeLibraryBtn, findsOneWidget);
    await tester.tap(nodeLibraryBtn);
    await tester.pumpAndSettle();

    expect(find.text('Rotary Slitting (8 Strips)'), findsWidgets);
    expect(find.text('Guillotine Blanking (72 Blanks)'), findsWidgets);

    // Close / Collapse slider
    final collapseBtn = find.byTooltip('Collapse Library Slider');
    expect(collapseBtn, findsOneWidget);
    await tester.tap(collapseBtn);
    await tester.pumpAndSettle();

    // Also test opening via the floating notch handle
    expect(find.text('Search or insert process nodes...'), findsOneWidget);
    await tester.tap(find.text('Search or insert process nodes...'));
    await tester.pumpAndSettle();

    expect(find.text('Rotary Slitting (8 Strips)'), findsWidgets);
    await tester.tap(find.byTooltip('Collapse Library Slider'));
    await tester.pumpAndSettle();

    // 3. Navigate to CAD Sheet Planner tab
    await tester.tap(find.text('CAD Sheet Planner'));
    await tester.pumpAndSettle();

    expect(find.text('CAD Sheet Planning & 2D Nesting Engine'), findsOneWidget);
    expect(find.text('72 Blanks'), findsOneWidget);
    expect(find.textContaining('Material Yield'), findsWidgets);

    // 4. Navigate to Flow Transformation Simulator
    await tester.tap(find.text('Flow Transformation'));
    await tester.pumpAndSettle();

    expect(find.text('Physical Sheet Transformation Simulator'), findsOneWidget);
    expect(find.text('Stage 1: Raw Stock Inward'), findsOneWidget);

    // Click Next Step
    final nextBtn = find.byTooltip('Next Step');
    expect(nextBtn, findsOneWidget);
    await tester.tap(nextBtn);
    await tester.pumpAndSettle();

    expect(find.text('Stage 2: Rotary Slitting (8 Strips)'), findsOneWidget);
    expect(find.text('Rotary Slitter RS-1250'), findsOneWidget);

    await tester.tap(nextBtn);
    await tester.pumpAndSettle();

    expect(find.text('Stage 3: Guillotine Blanking (72 Blanks)'), findsOneWidget);
    expect(find.text('Hydraulic Guillotine G-300'), findsOneWidget);
  });
}

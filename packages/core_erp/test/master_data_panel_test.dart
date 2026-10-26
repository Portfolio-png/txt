import 'package:core_erp/features/materials/domain/material_definition.dart';
import 'package:core_erp/features/production_pipelines/domain/pen_paper_baseline.dart';
import 'package:core_erp/features/production_pipelines/domain/sheet_part.dart';
import 'package:core_erp/features/production_pipelines/presentation/widgets/master_data_dialog.dart';
import 'package:core_erp/features/production_pipelines/presentation/widgets/sheet_dimension_figure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Master Data editor without a dialog around it: the same panel the
/// dialog shows, set into a narrow side panel. It has to lay out in the room it
/// is given, report through its callbacks rather than popping a route, and —
/// while read only — follow the record when it is saved somewhere else.
void main() {
  const materials = <MaterialDefinition>[
    MaterialDefinition(id: 1, name: 'Steel / MS', densityGCm3: 7.85),
  ];
  const parts = <SheetPart>[
    SheetPart(id: 7, name: 'Bracket blank', widthMm: 60, heightMm: 40),
  ];

  // A 4' x 8' sheet at 1.6 mm, sheared into four 300 mm strips, the first one
  // blanked — enough of a plan to fill every block of the controls column.
  const planned = PenPaperBaseline(
    sheetWidthInches: 48,
    sheetHeightInches: 96,
    sheetThicknessMm: 1.6,
    bands: [SheetCutGroup(sizeMm: 300, count: 4)],
    subCuts: {
      0: [SheetCutGroup(sizeMm: 40, count: 10)],
    },
    kerfMm: 3,
    edgeTrimMm: 5,
    materialName: 'Steel / MS',
  );

  Future<void> mount(
    WidgetTester tester, {
    PenPaperBaseline baseline = planned,
    bool readOnly = false,
    ValueChanged<PenPaperBaseline>? onSave,
    VoidCallback? onCancel,
    bool showHeader = true,
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              const Expanded(child: SizedBox()),
              SizedBox(
                width: 520,
                child: MasterDataPanel(
                  key: const ValueKey<String>('panel'),
                  baseline: baseline,
                  itemName: 'Alloy - 16A - MS Sheet',
                  pipelineName: 'Cut → Punch',
                  parts: parts,
                  materials: materials,
                  readOnly: readOnly,
                  embedded: true,
                  showHeader: showHeader,
                  onSave: onSave ?? (_) {},
                  onCancel: onCancel,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lays out in a 520 x 900 side panel on every step', (
    tester,
  ) async {
    await mount(tester, onCancel: () {});
    expect(tester.takeException(), isNull);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(SheetDimensionFigure), findsOneWidget);
    expect(find.text('THE SHEET'), findsOneWidget);

    // The controls stack under the drawing, and scroll rather than overflow.
    await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Material data'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('WHAT IT PRODUCED'), findsOneWidget);

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('without a header or a cancel it is only the editor and Save', (
    tester,
  ) async {
    await mount(tester, showHeader: false);
    expect(tester.takeException(), isNull);
    expect(find.text('Master Data'), findsNothing);
    expect(find.byTooltip('Close'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('Save Master Data'), findsOneWidget);
  });

  testWidgets('Save and Cancel report instead of popping a route', (
    tester,
  ) async {
    PenPaperBaseline? saved;
    var cancelled = 0;
    await mount(
      tester,
      onSave: (value) => saved = value,
      onCancel: () => cancelled++,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(cancelled, 1);
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    expect(cancelled, 2);

    await tester.enterText(find.byType(TextField).at(0), '50');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Master Data'));
    await tester.pump();

    expect(saved, isNotNull);
    expect(saved!.sheetWidthInches, 50);
    expect(saved!.sheetHeightInches, 96);
    // The blank typing rows are not part of the record.
    expect(saved!.bands.every((group) => group.isComplete), isTrue);
    // The panel is still there — nothing was popped.
    expect(find.byKey(const ValueKey<String>('panel')), findsOneWidget);
  });

  testWidgets('read only, it follows the record when it is saved elsewhere', (
    tester,
  ) async {
    await mount(tester, readOnly: true);
    expect(find.text('48'), findsOneWidget);

    await mount(
      tester,
      readOnly: true,
      baseline: planned.copyWith(sheetWidthInches: 60),
    );
    expect(find.text('60'), findsOneWidget);
    expect(find.text('48'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('while editing, the working copy is kept', (tester) async {
    await mount(tester);
    await tester.enterText(find.byType(TextField).at(0), '50');
    await tester.pumpAndSettle();

    await mount(tester, baseline: planned.copyWith(sheetHeightInches: 120));
    // What was typed survives; the incoming record does not overwrite it.
    expect(find.text('50'), findsOneWidget);
    expect(find.text('120'), findsNothing);
  });
}

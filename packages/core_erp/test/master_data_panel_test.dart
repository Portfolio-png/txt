import 'package:core_erp/features/materials/domain/material_definition.dart';
import 'package:core_erp/features/production_pipelines/domain/pen_paper_baseline.dart';
import 'package:core_erp/features/production_pipelines/domain/sheet_part.dart';
import 'package:core_erp/features/production_pipelines/presentation/widgets/master_data_dialog.dart';
import 'package:core_erp/features/production_pipelines/presentation/widgets/raw_sheet_review.dart';
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
    VoidCallback? onEdit,
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
                  onEdit: onEdit,
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

    // The step bar scrolls in a side panel; Review sits past its edge.
    await tester.ensureVisible(find.text('Review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('AS IT WILL BE RECORDED'), findsOneWidget);
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

  // --- Material data follows the sheet plan ---------------------------------

  final following = planned.copyWith(materialFromPlan: true);

  Future<void> openStep(WidgetTester tester, String title) async {
    await tester.ensureVisible(find.text(title));
    await tester.pumpAndSettle();
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  String text(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey<String>(key))).data ?? '';

  testWidgets('the input is the sheet, the output the part — not a guess', (
    tester,
  ) async {
    await mount(tester, baseline: following);
    await openStep(tester, 'Material data');

    expect(text(tester, 'material-input-name'), contains('Steel / MS'));
    expect(text(tester, 'material-input-name'), contains('48 × 96 in'));
    expect(text(tester, 'material-output-name'), 'Alloy - 16A - MS Sheet');
    expect(find.text('TYPE'), findsNothing);
    expect(find.text('Sheet'), findsNothing, reason: 'the old noun guess');

    final sheets = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('material-input-sheets')),
        matching: find.byType(TextField),
      ),
    );
    expect(sheets.controller!.text, '1');
    final pieces = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('material-output-pieces')),
    );
    expect(pieces.controller!.text, '${planned.pieceCount}');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Save from the first step records the plan, not 100 kg in', (
    tester,
  ) async {
    PenPaperBaseline? saved;
    await mount(tester, baseline: following, onSave: (b) => saved = b);
    await tester.tap(find.text('Save Master Data'));
    await tester.pump();

    final row = saved!.stageReconciliations.single;
    final weights = planned.weighAt(7.85);
    expect(row.inputSheets, 1);
    expect(row.outputPieces, planned.pieceCount);
    expect(row.inputKg, closeTo(weights.sheetKg, 0.001));
    expect(row.scrapKg, closeTo(weights.offcutKg, 0.001));
    expect(row.outputLabel, 'Alloy - 16A - MS Sheet');
    expect(saved!.bands, isNotEmpty);
  });

  testWidgets('typed pieces are saved; Refill brings the plan back', (
    tester,
  ) async {
    PenPaperBaseline? saved;
    await mount(tester, baseline: following, onSave: (b) => saved = b);
    await openStep(tester, 'Material data');

    await tester.enterText(
      find.byKey(const ValueKey<String>('material-output-pieces')),
      '2900',
    );
    await tester.pumpAndSettle();
    expect(find.text('= 2900 Pc'), findsNothing);
    await tester.tap(find.text('Save Master Data'));
    await tester.pump();
    expect(saved!.stageReconciliations.single.outputPieces, 2900);
    expect(saved!.materialFromPlan, isFalse);

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('material-refill')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('material-refill')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Master Data'));
    await tester.pump();
    expect(saved!.stageReconciliations.single.outputPieces, planned.pieceCount);
    expect(saved!.materialFromPlan, isTrue);
  });

  testWidgets('Stage by Stage is kept, and keeps the sheet plan', (
    tester,
  ) async {
    PenPaperBaseline? saved;
    await mount(tester, baseline: following, onSave: (b) => saved = b);
    await openStep(tester, 'Material data');
    await tester.tap(find.text('Stage by Stage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Master Data'));
    await tester.pump();

    expect(saved!.isGranular, isTrue);
    expect(saved!.sheetWidthInches, 48);
    expect(saved!.bands, isNotEmpty, reason: 'used to be wiped to defaults');
  });

  testWidgets('read only, the footer offers Edit and the notes are shut', (
    tester,
  ) async {
    var edits = 0;
    await mount(
      tester,
      baseline: following,
      readOnly: true,
      onEdit: () {
        edits++;
      },
    );
    expect(find.text('Save Master Data'), findsNothing);
    await tester.tap(find.byKey(const ValueKey<String>('master-data-edit')));
    expect(edits, 1);

    await openStep(tester, 'Material data');
    final notes = tester.widget<TextField>(
      find.descendant(
        of: find
            .byWidgetPredicate((w) => w is TextFormField, description: 'notes')
            .last,
        matching: find.byType(TextField),
      ),
    );
    expect(notes.enabled, isFalse);
  });

  testWidgets('Review states the plan and prints the same page', (
    tester,
  ) async {
    await mount(tester, baseline: following);
    await openStep(tester, 'Review');
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey<String>('raw-review-card')),
      findsOneWidget,
    );
    expect(find.text('Alloy - 16A - MS Sheet'), findsOneWidget);
    expect(find.text('${planned.pieceCount} pcs'), findsWidgets);
    expect(find.textContaining('Steel / MS · 7.85'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('raw-review-print')),
      findsOneWidget,
    );
  });

  test('the printed review builds a PDF', () async {
    final sections = rawSheetReviewSections(
      baseline: following,
      partName: 'Dolly Patti',
      sheetLabel: 'Steel / MS · 48 × 96 in · 1.6 mm',
      material: materials.single,
    );
    expect(sections.map((s) => s.title), contains('Weights per sheet'));
    final bytes = await buildRawSheetReviewPdf(
      baseline: following,
      sections: sections,
      partName: 'Dolly Patti',
    );
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}

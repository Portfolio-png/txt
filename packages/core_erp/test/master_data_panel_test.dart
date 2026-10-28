import 'package:core_erp/features/materials/domain/material_definition.dart';
import 'package:core_erp/features/production_pipelines/domain/pen_paper_baseline.dart';
import 'package:core_erp/features/production_pipelines/domain/raw_stock_form.dart';
import 'package:core_erp/features/production_pipelines/domain/sheet_part.dart';
import 'package:core_erp/features/production_pipelines/presentation/widgets/band_form_animation.dart';
import 'package:core_erp/features/production_pipelines/presentation/widgets/master_data_dialog.dart';
import 'package:core_erp/features/production_pipelines/presentation/widgets/pen_paper_baseline_widget.dart';
import 'package:core_erp/features/production_pipelines/presentation/widgets/raw_sheet_review.dart';
import 'package:core_erp/features/production_pipelines/presentation/widgets/sheet_dimension_figure.dart';
import 'package:core_erp/features/vendors/data/repositories/vendor_repository.dart';
import 'package:core_erp/features/vendors/domain/vendor_definition.dart';
import 'package:core_erp/features/vendors/domain/vendor_inputs.dart';
import 'package:core_erp/features/vendors/presentation/providers/vendors_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

VendorDefinition _vendor(int id, String name) => VendorDefinition(
  id: id,
  name: name,
  alias: '',
  gstNumber: '',
  address: '',
  contactName: '',
  phone: '',
  email: '',
  isArchived: false,
  usageCount: 0,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

/// The Vendors master, in memory.
class _Vendors implements VendorRepository {
  final List<VendorDefinition> rows = [_vendor(1, 'Tata Steel')];

  @override
  Future<void> init() async {}

  @override
  Future<List<VendorDefinition>> getVendors() async => List.of(rows);

  @override
  Future<VendorDefinition?> getVendor(int id) async =>
      rows.where((v) => v.id == id).firstOrNull;

  @override
  Future<VendorDefinition> createVendor(CreateVendorInput input) async {
    final created = _vendor(rows.length + 1, input.name);
    rows.add(created);
    return created;
  }

  @override
  Future<VendorDefinition> updateVendor(UpdateVendorInput input) =>
      throw UnimplementedError();

  @override
  Future<void> deleteVendor(int id) async {}
}

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
    String? alloy,
    String? grade,
    String? thickness,
    ValueChanged<String>? onThicknessChanged,
    VendorsProvider? vendors,
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget app(Widget child) => vendors == null
        ? child
        : ChangeNotifierProvider<VendorsProvider>.value(
            value: vendors,
            child: child,
          );
    await tester.pumpWidget(
      app(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                const Expanded(child: SizedBox()),
                SizedBox(
                  width: 520,
                  child: MasterDataPanel(
                    key: const ValueKey<String>('panel'),
                    alloy: alloy,
                    grade: grade,
                    thickness: thickness,
                    onThicknessChanged: onThicknessChanged,
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

    // Width is the first field, length the second.
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
    await tester.enterText(find.byType(TextField).at(0), '50'); // the width
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
    // Length × width, as the fields are typed.
    expect(text(tester, 'material-input-name'), contains('48 × 96 in'));
    expect(text(tester, 'material-output-name'), 'Alloy - 16A - MS Sheet');
    expect(find.text('TYPE'), findsNothing);
    // Inside Material data: the form switcher above has a "Sheet" tile.
    expect(
      find.descendant(
        of: find.byType(PenPaperBaselineWidget),
        matching: find.text('Sheet'),
      ),
      findsNothing,
      reason: 'the old noun guess',
    );

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
    expect(row.inputSheets, 1);
    expect(row.outputPieces, planned.pieceCount);
    // Nothing weighed, nothing claimed: no density makes up a weight.
    expect(row.inputKg, 0);
    expect(row.scrapKg, 0);
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
    expect(find.text('Steel / MS'), findsOneWidget, reason: 'the Alloy row');
    expect(find.text('Weights per sheet'.toUpperCase()), findsNothing);
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
    );
    expect(sections.map((s) => s.title), isNot(contains('Weights per sheet')));
    final sheet = sections.firstWhere((s) => s.title == 'Sheet');
    expect(
      sheet.rows.map((r) => r.$1),
      containsAll(['Alloy', 'Grade', 'Vendor']),
    );
    final bytes = await buildRawSheetReviewPdf(
      baseline: following,
      sections: sections,
      partName: 'Dolly Patti',
    );
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  // --- alloy from the part, scrap from the balance, vendor -----------------

  testWidgets('the alloy is the part\'s: shown, not picked, and stamped', (
    tester,
  ) async {
    PenPaperBaseline? saved;
    await mount(tester, alloy: 'Brass', onSave: (b) => saved = b);
    expect(find.byKey(const ValueKey<String>('sheet-material')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('sheet-alloy')),
        matching: find.text('Brass'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Save Master Data'));
    await tester.pump();
    expect(saved!.materialName, 'Brass', reason: 'over the old Steel / MS');
  });

  testWidgets('scrap follows the balance, and offers it back once typed over', (
    tester,
  ) async {
    PenPaperBaseline? saved;
    await mount(tester, baseline: following, onSave: (b) => saved = b);
    await openStep(tester, 'Material data');

    Finder field(String key) => find.descendant(
      of: find.byKey(ValueKey<String>(key)),
      matching: find.byType(TextField),
    );
    String scrap() =>
        tester.widget<TextField>(field('material-scrap-kg')).controller!.text;

    await tester.enterText(field('material-input-kg'), '4');
    await tester.pump();
    await tester.enterText(field('material-output-kg'), '3');
    await tester.pump();
    expect(scrap(), '1.0', reason: '4 in − 3 out');

    await tester.ensureVisible(field('material-scrap-kg'));
    await tester.enterText(field('material-scrap-kg'), '0.5');
    await tester.pump();
    final use = find.byKey(
      const ValueKey<String>('material-scrap-use-balance'),
    );
    expect(use, findsOneWidget);
    expect(find.text('Use 1.0 kg'), findsOneWidget);

    // Typed over, a new weight leaves it alone…
    await tester.enterText(field('material-output-kg'), '2');
    await tester.pump();
    expect(scrap(), '0.5');

    // …until the balance is taken back.
    await tester.tap(use);
    await tester.pump();
    expect(scrap(), '2.0');
    expect(use, findsNothing);

    await tester.tap(find.text('Save Master Data'));
    await tester.pump();
    final row = saved!.stageReconciliations.single;
    expect(row.scrapKg, 2);
    expect(saved!.materialFromPlan, isTrue, reason: 'a weight is not a count');
  });

  testWidgets('a vendor is picked from the master, or added to it', (
    tester,
  ) async {
    final repo = _Vendors();
    final vendors = VendorsProvider(repository: repo);
    await vendors.refresh();
    PenPaperBaseline? saved;
    await mount(tester, vendors: vendors, onSave: (b) => saved = b);

    await tester.tap(find.byKey(const ValueKey<String>('sheet-vendor')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tata Steel').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Master Data'));
    await tester.pump();
    expect(saved!.vendorId, 1);
    expect(saved!.vendorName, 'Tata Steel');

    await tester.tap(find.byKey(const ValueKey<String>('sheet-vendor')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Jindal');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add vendor "Jindal"'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Master Data'));
    await tester.pump();
    expect(saved!.vendorName, 'Jindal');
    expect(repo.rows.map((v) => v.name), contains('Jindal'));
  });

  testWidgets('an unloaded vendor list is fetched after the first frame', (
    tester,
  ) async {
    // Fetched from initState, the refresh notified mid-build and threw —
    // found by the end-to-end run, where the list starts empty.
    final vendors = VendorsProvider(repository: _Vendors());
    await mount(tester, vendors: vendors);
    expect(tester.takeException(), isNull);
    expect(vendors.vendors.map((v) => v.name), ['Tata Steel']);
  });

  group('the four forms', () {
    testWidgets('Sheet, Strip, Coil and Roll sit side by side, the sheet dotted',
        (tester) async {
      await mount(tester);
      for (final form in RawForm.values) {
        expect(find.byKey(ValueKey<String>('raw-form-${form.name}')), findsOneWidget);
      }
      // The plan above has a sheet and nothing else.
      expect(find.byKey(const ValueKey<String>('raw-form-dot-sheet')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('raw-form-dot-coil')), findsNothing);
      expect(find.text('Sheet planning'), findsOneWidget);
    });

    testWidgets('the sheet is quoted Width, then Length — and has no pitch', (
      tester,
    ) async {
      await mount(tester);
      // The labels are drawn in capitals.
      expect(find.text('HEIGHT'), findsNothing);
      final width = tester.getTopLeft(find.text('WIDTH').first).dx;
      final length = tester.getTopLeft(find.text('LENGTH').first).dx;
      expect(width, lessThan(length), reason: 'Width sits first again');
      expect(find.text('PITCH'), findsNothing);
      expect(find.byKey(const ValueKey<String>('sheet-kerf')), findsNothing);
      expect(find.text('EDGE TRIM'), findsOneWidget);
    });

    testWidgets('a strip, coil or roll is its own stock, animated once — '
        'never shown as cut from the sheet', (tester) async {
      await mount(tester);
      for (final form in [RawForm.strip, RawForm.coil, RawForm.roll]) {
        await tester.tap(find.byKey(ValueKey<String>('raw-form-${form.name}')));
        await tester.pump();
        expect(
          find.byKey(ValueKey<String>('band-animation-${form.name}')),
          findsOneWidget,
        );
        // Mid-way, then to rest: it plays once and stops.
        await tester.pump(const Duration(milliseconds: 700));
        expect(tester.hasRunningAnimations, isTrue);
        await tester.pumpAndSettle();
        expect(find.textContaining('From the sheet'), findsNothing);
        expect(find.byType(SheetDimensionFigure), findsNothing);
      }
      await tester.tap(find.byKey(const ValueKey<String>('band-animation-replay')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.hasRunningAnimations, isTrue, reason: 'replay plays it again');
      await tester.pumpAndSettle();
    });

    /// Scrolls the step until [key] is built and on screen: in a side panel
    /// the step is one tall list, and a list builds only what it shows.
    Future<void> reveal(WidgetTester tester, String key) async {
      await tester.scrollUntilVisible(
        find.byKey(ValueKey<String>(key)),
        150,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a coil is laid out like the sheet: width, an undefined '
        'length, the thickness, and an operation', (tester) async {
      PenPaperBaseline? saved;
      await mount(
        tester,
        baseline: planned.copyWith(plannedPartId: 7),
        onSave: (b) => saved = b,
        alloy: 'Brass',
      );
      await tester.tap(find.byKey(const ValueKey<String>('raw-form-coil')));
      await tester.pumpAndSettle();
      expect(find.text('Coil planning'), findsOneWidget);

      await reveal(tester, 'coil-width');
      expect(find.byKey(const ValueKey<String>('coil-length-undefined')), findsOneWidget);
      expect(find.text('Undefined'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('raw-thickness')), findsOneWidget);
      // No edge trim and no parts across on a band.
      expect(find.text('EDGE TRIM'), findsNothing);
      expect(find.text('ACROSS'), findsNothing);
      expect(find.byKey(const ValueKey<String>('coil-trim')), findsNothing);
      expect(find.byKey(const ValueKey<String>('coil-lanes')), findsNothing);

      await tester.enterText(find.byKey(const ValueKey<String>('coil-width')), '250');
      await reveal(tester, 'coil-pitch');
      expect(find.text('OPERATION'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey<String>('coil-pitch')), '3');
      await reveal(tester, 'coil-yield');
      expect(find.text('One part every 3 mm of coil.'), findsOneWidget);

      // The day the length is known, it is a count.
      await reveal(tester, 'coil-length');
      await tester.tap(find.byKey(const ValueKey<String>('coil-length')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Known length'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('coil-length-value')),
        '2000',
      );
      await reveal(tester, 'coil-yield');
      expect(
        find.text('≈ 666 parts from 2000 mm of coil — one every 3 mm.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Save Master Data'));
      await tester.pump();
      final coil = saved!.formOf(RawForm.coil);
      expect(coil.widthNm, 250 * 1000000);
      expect(coil.lengthNm, 2000 * 1000000);
      expect(coil.pitchNm, 3 * 1000000);
      expect(coil.thicknessNm, 1600000, reason: 'the part’s, stamped on');
      expect(saved!.lastForm, RawForm.coil);
      // The sheet is untouched, and has no pitch any more.
      expect(saved!.sheetWidthInches, 48);
      expect(saved!.kerfMm, 0);
    });

    testWidgets('back to Undefined clears the length', (tester) async {
      PenPaperBaseline? saved;
      await mount(
        tester,
        baseline: planned.withForm(
          RawForm.strip,
          const RawStockForm(widthNm: 40 * 1000000, lengthNm: 900 * 1000000),
        ).copyWith(lastForm: RawForm.strip),
        onSave: (b) => saved = b,
      );
      await reveal(tester, 'strip-length');
      expect(find.byKey(const ValueKey<String>('strip-length-value')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('strip-length')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Undefined').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('strip-length-undefined')), findsOneWidget);
      await tester.tap(find.text('Save Master Data'));
      await tester.pump();
      expect(saved!.formOf(RawForm.strip).lengthNm, isNull);
    });

    testWidgets('the animation carries the measures as typed', (tester) async {
      await mount(
        tester,
        thickness: '1.6 mm',
        baseline: planned.withForm(
          RawForm.coil,
          const RawStockForm(widthNm: 250 * 1000000, pitchNm: 45 * 1000000),
        ).copyWith(lastForm: RawForm.coil),
      );
      BandFormPainter painter() => tester
          .widget<CustomPaint>(
            find
                .descendant(
                  of: find.byKey(const ValueKey<String>('band-animation-coil')),
                  matching: find.byType(CustomPaint),
                )
                .last,
          )
          .painter! as BandFormPainter;
      expect(painter().widthLabel, '250 mm');
      expect(painter().thicknessLabel, '1.6 mm');
      expect(painter().pitchLabel, '45 mm');
      expect(painter().lengthMm, isNull, reason: 'undefined');

      await reveal(tester, 'coil-width');
      await tester.enterText(find.byKey(const ValueKey<String>('coil-width')), '300');
      await tester.pump();
      expect(painter().widthLabel, '300 mm', reason: 'follows the typing');
      expect(painter().t, 1, reason: 'without playing again');
    });

    testWidgets('every form has the operation, with the part’s alloy and '
        'grade read-only', (tester) async {
      PenPaperBaseline? saved;
      await mount(
        tester,
        alloy: 'Brass',
        grade: 'A',
        onSave: (b) => saved = b,
        baseline: planned.withForm(
          RawForm.roll,
          const RawStockForm(widthNm: 100 * 1000000, grade: 'Old'),
        ),
      );
      for (final form in RawForm.values) {
        await tester.tap(find.byKey(ValueKey<String>('raw-form-${form.name}')));
        await tester.pumpAndSettle();
        await reveal(tester, 'part-grade');
        expect(find.text('OPERATION'), findsOneWidget, reason: form.label);
        expect(find.byKey(const ValueKey<String>('sheet-part')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('sheet-alloy')),
            matching: find.text('Brass'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('part-grade')),
            matching: find.text('A'),
          ),
          findsOneWidget,
        );
        // Read-only: no grade picker of the panel's own.
        expect(find.byKey(ValueKey<String>('${form.name}-grade')), findsNothing);
      }
      await tester.tap(find.text('Save Master Data'));
      await tester.pump();
      expect(saved!.materialGrade, 'A');
      expect(saved!.formOf(RawForm.roll).grade, 'A');
    });

    testWidgets('a part with no grade says where to give it one', (tester) async {
      await mount(tester, alloy: 'Brass', grade: '');
      await reveal(tester, 'part-grade');
      expect(find.text('Not set — add a Grade column in Properties'), findsOneWidget);
    });

    testWidgets('the thickness is the part’s: it opens on it, follows it, '
        'and sends back what is typed', (tester) async {
      final sent = <String>[];
      await mount(tester, thickness: '1.2 mm', onThicknessChanged: sent.add);
      final field = find.descendant(
        of: find.byKey(const ValueKey<String>('raw-thickness')),
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(field).controller!.text, '1.2');

      // Changed in the Thickness column: the panel follows.
      await mount(tester, thickness: '18 Gauge', onThicknessChanged: sent.add);
      expect(tester.widget<TextField>(field).controller!.text, '18');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('raw-thickness')),
          matching: find.text('ga'),
        ),
        findsOneWidget,
      );

      // Typed here: the Thickness column is told, in its own words.
      await tester.enterText(field, '20');
      await tester.pump();
      expect(sent.last, '20 Gauge');

      await mount(tester, thickness: 'thick', onThicknessChanged: sent.add);
      expect(
        find.text('“thick” in the Thickness column is not a measurement.'),
        findsNothing,
        reason: 'not while the field is being typed in',
      );
    });

    testWidgets('a Thickness cell that is not a measurement says so', (tester) async {
      await mount(tester, thickness: 'thick');
      expect(
        find.text('“thick” in the Thickness column is not a measurement.'),
        findsOneWidget,
      );
    });

    testWidgets('a vendor and grade on the coil are the coil\'s, not the sheet\'s',
        (tester) async {
      final vendors = VendorsProvider(repository: _Vendors());
      await vendors.refresh();
      PenPaperBaseline? saved;
      await mount(
        tester,
        vendors: vendors,
        baseline: planned.copyWith(materialGrade: 'First'),
        onSave: (b) => saved = b,
      );
      await tester.tap(find.byKey(const ValueKey<String>('raw-form-coil')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('coil-vendor')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tata Steel').last);
      await tester.pumpAndSettle();
      // Below the sheet-to-coil picture, so scrolled to first.
      await tester.ensureVisible(find.byKey(const ValueKey<String>('coil-grade')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('coil-grade')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Third grade').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save Master Data'));
      await tester.pump();
      expect(saved!.formOf(RawForm.coil).vendorName, 'Tata Steel');
      expect(saved!.formOf(RawForm.coil).grade, 'Third');
      expect(saved!.vendorId, isNull, reason: 'the sheet has no vendor yet');
      expect(saved!.materialGrade, 'First');
    });

    testWidgets('it reopens on the form last worked on, and Review lists it',
        (tester) async {
      await mount(
        tester,
        baseline: planned
            .withForm(
              RawForm.roll,
              const RawStockForm(widthNm: 100 * 1000000, grade: 'Second'),
            )
            .copyWith(lastForm: RawForm.roll),
      );
      expect(find.text('Roll planning'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('roll-width')), findsOneWidget);

      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      expect(find.text('Roll'), findsWidgets);
      expect(find.text('Second grade'), findsOneWidget);
    });

    testWidgets('a coil\'s Material data is its own, counted in coils',
        (tester) async {
      PenPaperBaseline? saved;
      await mount(tester, onSave: (b) => saved = b);
      await tester.tap(find.byKey(const ValueKey<String>('raw-form-coil')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Material data'));
      await tester.pumpAndSettle();

      expect(find.text('coils'), findsOneWidget);
      expect(find.text('Stage by Stage'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey<String>('material-input-kg')),
        '120',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Master Data'));
      await tester.pump();
      expect(saved!.formOf(RawForm.coil).reconciliation.inputKg, 120);
      expect(saved!.totalInputKg, isNot(120), reason: 'the sheet row is apart');
    });
  });
}

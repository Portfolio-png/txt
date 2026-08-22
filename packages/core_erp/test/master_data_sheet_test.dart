import 'package:core_erp/features/production_pipelines/domain/pen_paper_baseline.dart';
import 'package:core_erp/features/production_pipelines/presentation/widgets/master_data_dialog.dart';
import 'package:core_erp/features/production_pipelines/domain/sheet_part.dart';
import 'package:core_erp/features/production_pipelines/presentation/widgets/sheet_dimension_figure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The Master Data window draws the sheet from what is typed. Two things have to
// hold: the arithmetic that turns inches and millimetres into an area and a
// volume, and the drawing actually answering to the fields rather than sitting
// there as decoration.

void main() {
  cutTests();

  group('sheet dimensions on the baseline', () {
    test('area is the face in square inches, once both sides are given', () {
      const half = PenPaperBaseline(sheetWidthInches: 48);
      expect(half.sheetAreaSqInches, 0, reason: 'one side is not an area');

      const full = PenPaperBaseline(
        sheetWidthInches: 48,
        sheetHeightInches: 96,
      );
      expect(full.sheetAreaSqInches, 4608);
    });

    test('volume converts the inch face and the mm gauge into cm³', () {
      const sheet = PenPaperBaseline(
        sheetWidthInches: 48,
        sheetHeightInches: 96,
        sheetThicknessMm: 1,
      );
      // 4608 in² × 6.4516 cm²/in² × 0.1 cm.
      expect(sheet.sheetVolumeCc, closeTo(2972.9, 0.1));
    });

    test('volume stays at zero until there is a gauge to multiply by', () {
      const noGauge = PenPaperBaseline(
        sheetWidthInches: 48,
        sheetHeightInches: 96,
      );
      expect(noGauge.sheetVolumeCc, 0);
    });

    test('a thickness on its own still counts as something recorded', () {
      const gaugeOnly = PenPaperBaseline(sheetThicknessMm: 1.6);
      expect(gaugeOnly.hasSheetDimensions, isTrue);
      expect(const PenPaperBaseline().hasSheetDimensions, isFalse);
    });

    test('the dimensions survive a JSON round trip', () {
      const original = PenPaperBaseline(
        sheetWidthInches: 48,
        sheetHeightInches: 96.5,
        sheetThicknessMm: 1.6,
      );
      final restored = PenPaperBaseline.fromJson(original.toJson());

      expect(restored.sheetWidthInches, 48);
      expect(restored.sheetHeightInches, 96.5);
      expect(restored.sheetThicknessMm, 1.6);
    });

    test('a record written before dimensions existed reads as unmeasured', () {
      final legacy = PenPaperBaseline.fromJson(<String, dynamic>{
        'isGranular': false,
        'notes': 'from an older release',
      });

      expect(legacy.hasSheetDimensions, isFalse);
      expect(legacy.sheetVolumeCc, 0);
    });

    test('copyWith changes one dimension without disturbing the others', () {
      const original = PenPaperBaseline(
        sheetWidthInches: 48,
        sheetHeightInches: 96,
        sheetThicknessMm: 1,
      );
      final thicker = original.copyWith(sheetThicknessMm: 2);

      expect(thicker.sheetWidthInches, 48);
      expect(thicker.sheetHeightInches, 96);
      expect(thicker.sheetThicknessMm, 2);
    });
  });

  group('SheetDimensionFigure', () {
    Widget host(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 320, height: 240, child: child)),
      ),
    );

    testWidgets('draws an unmeasured sheet without values', (tester) async {
      await tester.pumpWidget(
        host(
          const SheetDimensionFigure(
            widthInches: 0,
            heightInches: 0,
            thicknessMm: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(SheetDimensionFigure), findsOneWidget);
    });

    testWidgets('repaints when a dimension changes', (tester) async {
      await tester.pumpWidget(
        host(
          const SheetDimensionFigure(
            widthInches: 48,
            heightInches: 96,
            thicknessMm: 1,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        host(
          const SheetDimensionFigure(
            widthInches: 96,
            heightInches: 48,
            thicknessMm: 3,
          ),
        ),
      );
      // Mid-animation: the shape is travelling between the two proportions.
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives an area too small to dimension', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 30,
                height: 20,
                child: const SheetDimensionFigure(
                  widthInches: 48,
                  heightInches: 96,
                  thicknessMm: 1,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('a zero height does not divide the aspect ratio by zero', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const SheetDimensionFigure(
            widthInches: 48,
            heightInches: 0,
            thicknessMm: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('the Master Data window', () {
    Future<PenPaperBaseline?> open(
      WidgetTester tester, {
      PenPaperBaseline baseline = const PenPaperBaseline(),
    }) async {
      PenPaperBaseline? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showMasterDataDialog(
                      context,
                      baseline: baseline,
                      pipelineName: 'Cut → Punch',
                      itemName: 'Alloy - 16A - MS Sheet',
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('opens with the sheet, the fields and the figures', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await open(tester);

      expect(find.text('Master Data'), findsOneWidget);
      expect(find.text('THE SHEET'), findsOneWidget);
      // Step one is sheet planning; the material tables are a step along.
      expect(find.text('Sheet planning'), findsOneWidget);
      await tester.tap(find.text('Material data'));
      await tester.pumpAndSettle();
      expect(find.text('WHAT IT PRODUCED'), findsOneWidget);
      await tester.tap(find.text('Sheet planning'));
      await tester.pumpAndSettle();
      expect(find.byType(SheetDimensionFigure), findsOneWidget);
      expect(find.text('WIDTH'), findsOneWidget);
      expect(find.text('HEIGHT'), findsOneWidget);
      expect(find.text('THICKNESS'), findsOneWidget);
      // Nothing typed yet, so the panel asks rather than printing zeros.
      expect(
        find.text('Enter width and height to draw the sheet.'),
        findsOneWidget,
      );
    });

    testWidgets('typing the dimensions reads back live', (tester) async {
      tester.view.physicalSize = const Size(1600, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await open(tester);

      await tester.enterText(find.byType(TextField).at(0), '48');
      await tester.pump();
      // One side is not an area, so it still asks for the other.
      expect(
        find.text('Enter width and height to draw the sheet.'),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField).at(1), '96');
      await tester.pump();
      expect(
        find.text('4608 in² · add a thickness for volume'),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField).at(2), '1');
      await tester.pumpAndSettle();
      expect(find.textContaining('4608 in² ·'), findsOneWidget);
      expect(find.textContaining('cm³ per sheet'), findsOneWidget);
    });

    testWidgets('saving returns the dimensions on the baseline', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      PenPaperBaseline? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    saved = await showMasterDataDialog(
                      context,
                      baseline: const PenPaperBaseline(),
                      pipelineName: 'Cut → Punch',
                      itemName: 'Alloy - 16A - MS Sheet',
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), '48');
      await tester.enterText(find.byType(TextField).at(1), '96');
      await tester.enterText(find.byType(TextField).at(2), '1.6');
      await tester.pump();

      await tester.tap(find.text('Save Master Data'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.sheetWidthInches, 48);
      expect(saved!.sheetHeightInches, 96);
      expect(saved!.sheetThicknessMm, 1.6);
    });

    testWidgets('cancelling returns nothing, so the card is left alone', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      PenPaperBaseline? saved = const PenPaperBaseline(notes: 'untouched');
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    saved = await showMasterDataDialog(
                      context,
                      baseline: const PenPaperBaseline(),
                      itemName: 'Alloy Sheet',
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), '48');
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(saved, isNull);
    });

    testWidgets('read only offers no save', (tester) async {
      tester.view.physicalSize = const Size(1600, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showMasterDataDialog(
                    context,
                    baseline: const PenPaperBaseline(
                      sheetWidthInches: 48,
                      sheetHeightInches: 96,
                    ),
                    itemName: 'Alloy Sheet',
                    readOnly: true,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Read only.'), findsOneWidget);
      final save = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('Save Master Data'),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(save.onPressed, isNull);
    });
  });
}

// --- the cutting operation --------------------------------------------------
//
// The sheet is sheared into strips along one axis, and then each strip can be
// blanked its own way. Two levels, because that is what a shear and a press do:
// one strip goes to one die and the next may go to a different one.
//
// The lie this replaced was a cross product — "129 columns × 23 rows = 2967
// pieces" adds 12 mm parts to 89 mm parts. So most of what follows is about the
// yield being a list of sizes, never a single number.

void cutTests() {
  const sheet = PenPaperBaseline(sheetWidthInches: 48, sheetHeightInches: 96);

  group('shearing the sheet into strips', () {
    test('bands claim size times count along the primary axis', () {
      final plan = sheet.copyWith(
        bands: const <SheetCutGroup>[SheetCutGroup(sizeMm: 40, count: 12)],
      );
      expect(plan.plannedSpanMm(SheetCutAxis.columns), 480);
      expect(plan.plannedPieces(SheetCutAxis.columns), 12);
      expect(plan.remainderMm(SheetCutAxis.columns), closeTo(739.2, 0.01));
    });

    test('the secondary axis has no sheet-wide split any more', () {
      final plan = sheet.copyWith(
        bands: const <SheetCutGroup>[SheetCutGroup(sizeMm: 40, count: 12)],
      );
      // Each strip is blanked its own way, so asking the sheet is meaningless.
      expect(plan.cutsFor(SheetCutAxis.rows), isEmpty);
    });

    test('shearing along rows makes the height the primary axis', () {
      final plan = sheet.copyWith(
        primaryAxis: SheetCutAxis.rows,
        bands: const <SheetCutGroup>[SheetCutGroup(sizeMm: 100, count: 4)],
      );
      expect(plan.plannedSpanMm(SheetCutAxis.rows), 400);
      expect(plan.secondaryAxis, SheetCutAxis.columns);
    });

    test('a plan wider than the sheet reports the overrun, not a remainder', () {
      final plan = sheet.copyWith(
        bands: const <SheetCutGroup>[SheetCutGroup(sizeMm: 40, count: 40)],
      );
      expect(plan.overruns(SheetCutAxis.columns), isTrue);
      expect(plan.remainderMm(SheetCutAxis.columns), 0);
    });
  });

  group('the regions a cut can land in', () {
    final plan = sheet.copyWith(
      bands: const <SheetCutGroup>[
        SheetCutGroup(sizeMm: 400, count: 2),
        SheetCutGroup(sizeMm: 200, count: 1),
      ],
    );

    test('every strip is a region, and so is what is left', () {
      final regions = plan.regions;
      expect(regions.length, 3);
      expect(regions[0].index, 0);
      expect(regions[0].copies, 2, reason: 'the first band made two strips');
      expect(regions[1].index, 1);
      expect(regions.last.isOffcut, isTrue);
      expect(regions.last.label, 'Leftover');
    });

    test('a strip is its band wide and the full sheet long', () {
      final strip = plan.regions.first;
      expect(strip.widthMm, 400);
      expect(strip.heightMm, closeTo(2438.4, 0.01));
    });

    test('the leftover is what the shear did not claim', () {
      // 1219.2 less 800 less 200.
      expect(plan.regions.last.widthMm, closeTo(219.2, 0.01));
    });

    test('no leftover region when the shear used the sheet up', () {
      final exact = sheet.copyWith(
        bands: <SheetCutGroup>[SheetCutGroup(sizeMm: 48 * 25.4, count: 1)],
      );
      expect(exact.regions.length, 1);
      expect(exact.regions.single.isOffcut, isFalse);
    });

    test('a region is as long as the sheet along the blanking axis', () {
      expect(
        plan.regionExtentMm(0, SheetCutAxis.rows),
        closeTo(2438.4, 0.01),
      );
      expect(plan.regionExtentMm(0, SheetCutAxis.columns), 400);
    });
  });

  group('blanking one strip', () {
    final plan = sheet.copyWith(
      bands: const <SheetCutGroup>[SheetCutGroup(sizeMm: 400, count: 2)],
      subCuts: const <int, List<SheetCutGroup>>{
        0: <SheetCutGroup>[SheetCutGroup(sizeMm: 300, count: 5)],
      },
    );

    test('what fits is asked of the strip, not of the sheet', () {
      // 2438.4 long, 300 blanks — eight, and the strip is 400 wide either way.
      expect(plan.fitsRemaining(SheetCutAxis.rows, 300, region: 0), 3);
      expect(
        plan.fitsRemaining(SheetCutAxis.rows, 300, region: 0, ignoreIndex: 0),
        8,
      );
    });

    test('the blanks are counted once per strip in the band', () {
      final blanks = plan.yields.firstWhere((entry) => !entry.isOffcut);
      // Five blanks down each of two strips.
      expect(blanks.count, 10);
      expect(blanks.widthMm, 400);
      expect(blanks.heightMm, 300);
    });

    test('the tail of a blanked strip is offcut, not a part', () {
      final tail = plan.yields.firstWhere(
        (entry) => entry.isOffcut && entry.label.contains('tail'),
      );
      // 2438.4 less 5 × 300.
      expect(tail.heightMm, closeTo(938.4, 0.01));
      expect(tail.count, 2, reason: 'one tail per strip');
    });

    test('an uncut strip leaves as a strip', () {
      final uncut = sheet.copyWith(
        bands: const <SheetCutGroup>[SheetCutGroup(sizeMm: 400, count: 2)],
      );
      final strip = uncut.yields.first;
      expect(strip.count, 2);
      expect(strip.widthMm, 400);
      expect(strip.heightMm, closeTo(2438.4, 0.01));
      expect(strip.isOffcut, isFalse);
    });

    test('the leftover region can be blanked like any other', () {
      final withLeftover = sheet.copyWith(
        bands: const <SheetCutGroup>[SheetCutGroup(sizeMm: 400, count: 2)],
        subCuts: const <int, List<SheetCutGroup>>{
          PenPaperBaseline.offcutRegion: <SheetCutGroup>[
            SheetCutGroup(sizeMm: 200, count: 3),
          ],
        },
      );
      final fromLeftover = withLeftover.yields.where(
        (entry) => entry.label.startsWith('Leftover') && !entry.isOffcut,
      );
      expect(fromLeftover.single.count, 3);
    });

    test('two strips can be blanked differently — the whole point', () {
      final mixed = sheet.copyWith(
        bands: const <SheetCutGroup>[
          SheetCutGroup(sizeMm: 400, count: 1),
          SheetCutGroup(sizeMm: 300, count: 1),
        ],
        subCuts: const <int, List<SheetCutGroup>>{
          0: <SheetCutGroup>[SheetCutGroup(sizeMm: 500, count: 4)],
          1: <SheetCutGroup>[SheetCutGroup(sizeMm: 200, count: 10)],
        },
      );
      final parts = mixed.yields.where((entry) => !entry.isOffcut).toList();
      expect(parts.length, 2);
      expect(parts[0].heightMm, 500);
      expect(parts[1].heightMm, 200);
      expect(parts[0].count, 4);
      expect(parts[1].count, 10);
    });
  });

  group('what the sheet yields', () {
    test('different sizes are listed, never summed into one figure', () {
      final plan = sheet.copyWith(
        bands: const <SheetCutGroup>[
          SheetCutGroup(sizeMm: 12, count: 20),
          SheetCutGroup(sizeMm: 89, count: 5),
        ],
      );
      final parts = plan.yields.where((entry) => !entry.isOffcut).toList();

      expect(parts.length, 2, reason: '12 mm and 89 mm are different parts');
      expect(parts[0].widthMm, 12);
      expect(parts[0].count, 20);
      expect(parts[1].widthMm, 89);
      expect(parts[1].count, 5);
    });

    test('the piece count excludes offcut', () {
      final plan = sheet.copyWith(
        bands: const <SheetCutGroup>[SheetCutGroup(sizeMm: 400, count: 2)],
        subCuts: const <int, List<SheetCutGroup>>{
          0: <SheetCutGroup>[SheetCutGroup(sizeMm: 300, count: 5)],
        },
      );
      expect(plan.pieceCount, 10);
      expect(plan.yields.any((entry) => entry.isOffcut), isTrue);
    });

    test('an unplanned sheet yields nothing', () {
      expect(sheet.hasCutPlan, isFalse);
      expect(sheet.pieceCount, 0);
    });

    test('a sub-cut alone counts as a plan', () {
      final plan = sheet.copyWith(
        bands: const <SheetCutGroup>[SheetCutGroup(sizeMm: 400, count: 1)],
        subCuts: const <int, List<SheetCutGroup>>{
          0: <SheetCutGroup>[SheetCutGroup(sizeMm: 300, count: 2)],
        },
      );
      expect(plan.hasCutPlan, isTrue);
    });
  });

  group('reading the yield', () {
    test('two bands of one size in one strip are one kind of part', () {
      final plan = sheet.copyWith(
        bands: const <SheetCutGroup>[SheetCutGroup(sizeMm: 400, count: 2)],
        subCuts: const <int, List<SheetCutGroup>>{
          0: <SheetCutGroup>[
            SheetCutGroup(sizeMm: 300, count: 3),
            SheetCutGroup(sizeMm: 300, count: 4),
          ],
        },
      );
      final parts = plan.yields.where((entry) => !entry.isOffcut).toList();

      // Seven blanks down each of two strips, listed once.
      expect(parts.length, 1);
      expect(parts.single.count, 14);
      expect(parts.single.heightMm, 300);
    });

    test('the same size off different strips stays apart', () {
      final plan = sheet.copyWith(
        bands: const <SheetCutGroup>[
          SheetCutGroup(sizeMm: 400, count: 1),
          SheetCutGroup(sizeMm: 300, count: 1),
        ],
        subCuts: const <int, List<SheetCutGroup>>{
          0: <SheetCutGroup>[SheetCutGroup(sizeMm: 500, count: 2)],
          1: <SheetCutGroup>[SheetCutGroup(sizeMm: 500, count: 2)],
        },
      );
      final parts = plan.yields.where((entry) => !entry.isOffcut).toList();

      // 400 × 500 and 300 × 500 are different parts, however alike the cut.
      expect(parts.length, 2);
      expect(parts[0].widthMm, 400);
      expect(parts[1].widthMm, 300);
    });

    test('merging does not disturb the piece count', () {
      final plan = sheet.copyWith(
        bands: const <SheetCutGroup>[SheetCutGroup(sizeMm: 400, count: 2)],
        subCuts: const <int, List<SheetCutGroup>>{
          0: <SheetCutGroup>[
            SheetCutGroup(sizeMm: 300, count: 3),
            SheetCutGroup(sizeMm: 300, count: 4),
          ],
        },
      );
      expect(plan.pieceCount, 14);
    });
  });

  group('the gap and the trim', () {
    test('n pieces cost n-1 gaps, not n', () {
      final plan = sheet.copyWith(kerfMm: 3);
      expect(plan.consumedMm(400, 1), 400, reason: 'one piece needs no cut');
      expect(plan.consumedMm(400, 10), 427, reason: '400 + 9 × 3');
    });

    test('the gap takes strips off the count paper gives', () {
      expect(sheet.fitsRemaining(SheetCutAxis.columns, 40), 30);
      expect(
        sheet.copyWith(kerfMm: 3).fitsRemaining(SheetCutAxis.columns, 40),
        28,
      );
    });

    test('trim comes off both edges before anything is planned', () {
      final trimmed = sheet.copyWith(edgeTrimMm: 10);
      expect(trimmed.usableSpanMm(SheetCutAxis.columns), closeTo(1199.2, 0.01));
      expect(trimmed.fitsRemaining(SheetCutAxis.columns, 40), 29);
    });

    test('the gap applies inside a strip too', () {
      final plan = sheet.copyWith(
        kerfMm: 5,
        bands: const <SheetCutGroup>[SheetCutGroup(sizeMm: 400, count: 1)],
        subCuts: const <int, List<SheetCutGroup>>{
          0: <SheetCutGroup>[SheetCutGroup(sizeMm: 1000, count: 3)],
        },
      );
      // 2438.4 long: 1000 + 5 + 1000 fits, a third would need 3010.
      final blanks = plan.yields.firstWhere((entry) => !entry.isOffcut);
      expect(blanks.count, 2);
    });

    test('a band that divides exactly leaves no offcut', () {
      final plan = sheet.copyWith(
        bands: <SheetCutGroup>[
          SheetCutGroup(sizeMm: (48 * 25.4) / 8, count: 8),
        ],
      );
      expect(plan.remainderMm(SheetCutAxis.columns), closeTo(0, 0.001));
      expect(plan.overruns(SheetCutAxis.columns), isFalse);
    });
  });

  group('where the bands sit on the sheet', () {
    test('bands run end to end, each knowing its own stretch', () {
      final plan = sheet.copyWith(
        bands: const <SheetCutGroup>[
          SheetCutGroup(sizeMm: 100, count: 3),
          SheetCutGroup(sizeMm: 50, count: 2),
        ],
      );
      final spans = plan.bandSpansMm(SheetCutAxis.columns);

      expect(spans.length, 2);
      expect(spans[0].endMm, 300);
      expect(spans[1].startMm, 300);
      expect(spans[1].endMm, 400);
      expect(spans[0].index, 0);
    });

    test('a band is clipped to what fits, not to what was asked for', () {
      final plan = sheet.copyWith(
        bands: const <SheetCutGroup>[SheetCutGroup(sizeMm: 500, count: 10)],
      );
      expect(plan.bandSpansMm(SheetCutAxis.columns).single.count, 2);
    });

    test('a half-typed band keeps its index so colours do not shuffle', () {
      final plan = sheet.copyWith(
        bands: const <SheetCutGroup>[
          SheetCutGroup(sizeMm: 100),
          SheetCutGroup(sizeMm: 50, count: 2),
        ],
      );
      expect(plan.bandSpansMm(SheetCutAxis.columns).single.index, 1);
    });
  });

  group('planning a part off the catalogue', () {
    const bracket = SheetPart(
      id: 7,
      name: 'Bracket blank',
      widthMm: 60,
      heightMm: 40,
    );

    test('strips one blank wide, then blanked down each strip', () {
      final plan = sheet.planFor(bracket);

      expect(plan.bands.single.sizeMm, 60);
      expect(plan.bands.single.count, 20);
      expect(plan.subCutsFor(0).single.sizeMm, 40);
      expect(plan.subCutsFor(0).single.count, 60);
      expect(plan.pieceCount, 1200);
    });

    test('the gap and the trim come off both levels', () {
      final plan = sheet.copyWith(kerfMm: 3, edgeTrimMm: 10).planFor(bracket);
      expect(plan.bands.single.count, 19);
      expect(plan.subCutsFor(0).single.count, 56);
      expect(plan.pieceCount, 1064, reason: 'against 1200 on paper');
    });

    test('the plan is stamped with what it is cutting', () {
      final plan = sheet.planFor(bracket);
      expect(plan.plannedPartId, 7);
      expect(plan.plannedPartName, 'Bracket blank');
    });

    test('planning a part replaces the old plan rather than adding to it', () {
      final second = sheet.planFor(bracket).planFor(
        const SheetPart(id: 8, name: 'Cover', widthMm: 120, heightMm: 90),
      );
      expect(second.bands.length, 1);
      expect(second.bands.single.sizeMm, 120);
      expect(second.subCutsFor(0).single.sizeMm, 90);
      expect(second.plannedPartId, 8);
    });

    test('a part wider than the sheet plans nothing at all', () {
      final plan = sheet.planFor(
        const SheetPart(id: 9, name: 'Slab', widthMm: 5000, heightMm: 40),
      );
      expect(plan.bands, isEmpty);
      expect(plan.pieceCount, 0);
    });

    test('an unmeasured part leaves the plan alone', () {
      final existing = sheet.copyWith(
        bands: const <SheetCutGroup>[SheetCutGroup(sizeMm: 40, count: 5)],
      );
      expect(
        existing
            .planFor(
              const SheetPart(id: 10, name: 'Coil', widthMm: 0, heightMm: 0),
            )
            .bands
            .single
            .count,
        5,
      );
    });
  });

  group('storage', () {
    test('a two-level plan survives a JSON round trip', () {
      final plan = sheet.copyWith(
        primaryAxis: SheetCutAxis.rows,
        bands: const <SheetCutGroup>[SheetCutGroup(sizeMm: 400, count: 2)],
        subCuts: const <int, List<SheetCutGroup>>{
          0: <SheetCutGroup>[SheetCutGroup(sizeMm: 300, count: 5)],
          PenPaperBaseline.offcutRegion: <SheetCutGroup>[
            SheetCutGroup(sizeMm: 100, count: 2),
          ],
        },
      );
      final restored = PenPaperBaseline.fromJson(plan.toJson());

      expect(restored.primaryAxis, SheetCutAxis.rows);
      expect(restored.bands.single.count, 2);
      expect(restored.subCutsFor(0).single.sizeMm, 300);
      expect(
        restored.subCutsFor(PenPaperBaseline.offcutRegion).single.count,
        2,
      );
    });

    test('a two-list record keeps meaning what it meant', () {
      // The old release applied its rows across every column, so they are read
      // back as each strip's blanking — the same pieces, not a new claim.
      final legacy = PenPaperBaseline.fromJson(<String, dynamic>{
        'sheetWidthInches': 48,
        'sheetHeightInches': 96,
        'columnCuts': <Map<String, dynamic>>[
          <String, dynamic>{'sizeMm': 400, 'count': 2},
        ],
        'rowCuts': <Map<String, dynamic>>[
          <String, dynamic>{'sizeMm': 300, 'count': 5},
        ],
      });

      expect(legacy.primaryAxis, SheetCutAxis.columns);
      // One band making two strips — not two bands. The old list held groups,
      // and a group's count is how many strips it makes.
      expect(legacy.bands.single.sizeMm, 400);
      expect(legacy.bands.single.count, 2);
      expect(legacy.subCutsFor(0).single.sizeMm, 300);
      expect(legacy.subCutsFor(1), isEmpty, reason: 'there is no second band');
      // 5 blanks down each of 2 strips, as the cross product used to give.
      expect(legacy.pieceCount, 10);
    });

    test('a single-band legacy plan reads as one band, no sub-cuts', () {
      final legacy = PenPaperBaseline.fromJson(<String, dynamic>{
        'sheetWidthInches': 48,
        'cutAxis': 'vertical',
        'cutSizeMm': 40,
        'cutCount': 12,
      });
      expect(legacy.bands.single.count, 12);
      expect(legacy.subCuts, isEmpty);
    });

    test('a legacy horizontal plan shears along rows', () {
      final legacy = PenPaperBaseline.fromJson(<String, dynamic>{
        'sheetHeightInches': 96,
        'cutAxis': 'horizontal',
        'cutSizeMm': 50,
        'cutCount': 9,
      });
      expect(legacy.primaryAxis, SheetCutAxis.rows);
      expect(legacy.bands.single.count, 9);
    });

    test('a record with no plan reads as no plan', () {
      final none = PenPaperBaseline.fromJson(<String, dynamic>{'notes': 'old'});
      expect(none.bands, isEmpty);
      expect(none.subCuts, isEmpty);
      expect(none.hasCutPlan, isFalse);
    });
  });

  group('units', () {
    test('the sheet remembers the units it was written in', () {
      const plan = PenPaperBaseline(
        sheetWidthInches: 48,
        faceUnit: 'mm',
        gaugeUnit: 'ga',
      );
      final restored = PenPaperBaseline.fromJson(plan.toJson());

      expect(restored.faceUnit, 'mm');
      expect(restored.gaugeUnit, 'ga');
      // The size itself is unchanged — a unit is how a number is read.
      expect(restored.sheetWidthInches, 48);
    });

    test('a record from before units were chosen reads as inches and mm', () {
      final legacy = PenPaperBaseline.fromJson(<String, dynamic>{
        'sheetWidthInches': 48,
      });
      expect(legacy.faceUnit, 'in');
      expect(legacy.gaugeUnit, 'mm');
    });

    test('an unknown unit falls back rather than throwing', () {
      final odd = PenPaperBaseline.fromJson(<String, dynamic>{
        'faceUnit': 'furlongs',
        'gaugeUnit': 'furlongs',
      });
      expect(odd.faceUnit, 'in');
      expect(odd.gaugeUnit, 'mm');
    });
  });

  group('the operation panel', () {
    Future<void> open(
      WidgetTester tester, {
      PenPaperBaseline baseline = const PenPaperBaseline(
        sheetWidthInches: 48,
        sheetHeightInches: 96,
        sheetThicknessMm: 1.6,
      ),
    }) async {
      tester.view.physicalSize = const Size(1700, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showMasterDataDialog(
                    context,
                    baseline: baseline,
                    pipelineName: 'Cut → Punch',
                    itemName: 'Alloy - 16A - MS Sheet',
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Finder band(int region, int index, {required bool size}) => find.byKey(
      ValueKey<String>('band-${size ? 'size' : 'count'}-$region-$index'),
    );

    /// A region's own row, by key — its label also names the yield it makes,
    /// so finding it by text picks up two widgets.
    Finder regionRow(int index) =>
        find.byKey(ValueKey<String>('region-$index'));

    /// Opens a region, scrolling to it first: the controls column is a list,
    /// and a plan with a few bands pushes the regions below the fold.
    Future<void> openRegion(WidgetTester tester, int index) async {
      await tester.ensureVisible(regionRow(index));
      await tester.pumpAndSettle();
      await tester.tap(regionRow(index));
      await tester.pumpAndSettle();
    }

    testWidgets('opens asking how to shear, with the sheet whole', (
      tester,
    ) async {
      await open(tester);

      expect(find.text('SHEAR INTO'), findsOneWidget);
      // A blank row waits to be typed into, rather than a + to press first.
      expect(band(-2, 0, size: true), findsOneWidget);
      // No regions until the shear makes some.
      expect(find.text('THEN CUT A REGION'), findsNothing);
    });

    testWidgets('shearing makes regions a cut can land in', (tester) async {
      await open(tester);
      await tester.enterText(band(-2, 0, size: true), '400');
      await tester.enterText(band(-2, 0, size: false), '2');
      await tester.pumpAndSettle();

      expect(find.text('THEN CUT A REGION'), findsOneWidget);
      // Named on its region row and again on the yield it produces.
      expect(find.text('Strip 1'), findsWidgets);
      expect(find.text('Leftover'), findsWidgets);
    });

    testWidgets('a strip opens to be cut its own way', (tester) async {
      await open(tester);
      await tester.enterText(band(-2, 0, size: true), '400');
      await tester.enterText(band(-2, 0, size: false), '2');
      await tester.pumpAndSettle();

      await openRegion(tester, 0);

      // No + to press: opening the strip leaves a blank row waiting.
      await tester.enterText(band(0, 0, size: true), '300');
      await tester.enterText(band(0, 0, size: false), '5');
      await tester.pumpAndSettle();

      // Ten blanks: five down each of two strips.
      expect(find.textContaining('10×'), findsOneWidget);
    });

    testWidgets('the yield is a list of sizes, not one number', (tester) async {
      await open(
        tester,
        baseline: sheet.copyWith(
          bands: const <SheetCutGroup>[
            SheetCutGroup(sizeMm: 12, count: 20),
            SheetCutGroup(sizeMm: 89, count: 5),
          ],
        ),
      );

      expect(find.text('THIS SHEET YIELDS'), findsOneWidget);
      expect(find.text('20×'), findsOneWidget);
      expect(find.text('5×'), findsOneWidget);
      // Never the sum: 12 mm and 89 mm parts are not 25 of anything.
      expect(find.textContaining('25 pieces'), findsNothing);
    });

    testWidgets('asking for more strips than fit is called out', (tester) async {
      await open(tester);
      await tester.enterText(band(-2, 0, size: true), '40');
      await tester.enterText(band(-2, 0, size: false), '40');
      await tester.pumpAndSettle();

      expect(find.text('≤30'), findsOneWidget);
      expect(find.textContaining('more than the sheet has'), findsOneWidget);
    });

    testWidgets('changing the shear direction clears the sub-cuts', (
      tester,
    ) async {
      await open(
        tester,
        baseline: sheet.copyWith(
          bands: const <SheetCutGroup>[SheetCutGroup(sizeMm: 400, count: 2)],
          subCuts: const <int, List<SheetCutGroup>>{
            0: <SheetCutGroup>[SheetCutGroup(sizeMm: 300, count: 5)],
          },
        ),
      );
      expect(find.text('Strip 1'), findsWidgets);

      // A strip that ran one way is not the strip that runs the other.
      await tester.tap(find.text('rows'));
      await tester.pumpAndSettle();
      await openRegion(tester, 0);
      expect(band(0, 0, size: true), findsOneWidget);
    });

    testWidgets('the plan saves with both levels', (tester) async {
      tester.view.physicalSize = const Size(1700, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      PenPaperBaseline? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    saved = await showMasterDataDialog(
                      context,
                      baseline: sheet,
                      itemName: 'Alloy Sheet',
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(band(-2, 0, size: true), '400');
      await tester.enterText(band(-2, 0, size: false), '2');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Master Data'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.bands.single.sizeMm, 400);
      expect(saved!.bands.single.count, 2);
    });
  });
}

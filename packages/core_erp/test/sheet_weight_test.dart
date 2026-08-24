import 'package:core_erp/features/production_pipelines/domain/pen_paper_baseline.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sheet planning knows the volume; the material master knows the density.
/// Together they answer the question the client actually asked — what does this
/// cost — without anyone weighing anything.
void main() {
  // A 4' x 8' sheet at 1.6 mm, the shop default.
  PenPaperBaseline sheet({
    double thicknessMm = 1.6,
    SheetCutAxis axis = SheetCutAxis.columns,
    List<SheetCutGroup> bands = const [],
    Map<int, List<SheetCutGroup>> subCuts = const {},
    double kerfMm = 0,
    double edgeTrimMm = 0,
  }) {
    return PenPaperBaseline(
      sheetWidthInches: 48,
      sheetHeightInches: 96,
      sheetThicknessMm: thicknessMm,
      primaryAxis: axis,
      bands: bands,
      subCuts: subCuts,
      kerfMm: kerfMm,
      edgeTrimMm: edgeTrimMm,
    );
  }

  test('an unplanned sheet weighs what the material says', () {
    final weights = sheet().weighAt(7.85);
    // 121.92 x 243.84 x 0.16 cm = 4756 cm3, at 7.85 g/cm3 = 37.3 kg. Two people
    // lifting a sheet of mild steel would tell you the same.
    expect(weights.sheetKg, closeTo(37.3, 0.1));
    // Nothing is cut yet, so the whole sheet is still one uncut piece.
    expect(weights.partsKg + weights.offcutKg, closeTo(weights.sheetKg, 0.1));
  });

  test('aluminium weighs a third of steel for the same plan', () {
    final steel = sheet().weighAt(7.85).sheetKg;
    final aluminium = sheet().weighAt(2.70).sheetKg;
    expect(aluminium / steel, closeTo(2.70 / 7.85, 0.001));
  });

  test('no density means no guess', () {
    expect(sheet().weighAt(0).isEmpty, isTrue);
    expect(sheet().weighAt(-1).isEmpty, isTrue);
    // And no sheet means no weight, however well known the material is.
    expect(sheet(thicknessMm: 0).weighAt(7.85).isEmpty, isTrue);
  });

  test('the blade eats weight that lands in neither parts nor offcut', () {
    // Four 300 mm strips down a 1219 mm sheet, with a 3 mm blade.
    final plan = sheet(
      bands: const [SheetCutGroup(sizeMm: 300, count: 4)],
      kerfMm: 3,
    );
    final weights = plan.weighAt(7.85);

    expect(weights.sheetKg, greaterThan(0));
    // Everything accounted for is at most the sheet, never more.
    expect(
      weights.partsKg + weights.offcutKg,
      lessThanOrEqualTo(weights.sheetKg + 0.001),
    );
    // Three cuts at 3 mm across a 2438 mm sheet is real material gone to dust:
    // 9 mm x 2438 mm x 1.6 mm at 7.85 g/cm3 is a bit over a quarter kilo.
    expect(weights.lostKg, greaterThan(0.2));
    expect(weights.lostKg, lessThan(0.5));
  });

  test('loss never reads negative while a plan is being typed', () {
    // More strips than the sheet can hold — a half-typed plan.
    final overcommitted = sheet(
      bands: const [SheetCutGroup(sizeMm: 900, count: 6)],
    );
    expect(overcommitted.weighAt(7.85).lostKg, greaterThanOrEqualTo(0));
  });

  test('yield is the share that leaves as parts', () {
    final plan = sheet(
      bands: const [SheetCutGroup(sizeMm: 600, count: 2)],
      subCuts: const {
        0: [SheetCutGroup(sizeMm: 1200, count: 2)],
      },
    );
    final weights = plan.weighAt(7.85);
    expect(weights.yieldPercent, greaterThan(0));
    expect(weights.yieldPercent, lessThanOrEqualTo(100));
    // The parts share and the offcut share cannot together exceed the sheet.
    final accounted =
        (weights.partsKg + weights.offcutKg) / weights.sheetKg * 100;
    expect(accounted, lessThanOrEqualTo(100.01));
  });

  test('the material name survives a round trip', () {
    final plan = sheet().copyWith(materialName: 'Steel / MS');
    final reread = PenPaperBaseline.fromJson(plan.toJson());
    expect(reread.materialName, 'Steel / MS');
    // And an old record without one reads as empty, not as null.
    final legacy = Map<String, dynamic>.from(plan.toJson())
      ..remove('materialName');
    expect(PenPaperBaseline.fromJson(legacy).materialName, '');
  });
}

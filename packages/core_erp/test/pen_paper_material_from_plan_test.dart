import 'package:core_erp/features/production_pipelines/domain/pen_paper_baseline.dart';
import 'package:flutter_test/flutter_test.dart';

// Material data filled from the sheet plan: one sheet in, the planned pieces
// out, offcut as scrap and blade-and-trim as weight loss, so it balances. It
// used to start from hard-coded 100 kg in / 90 kg out and nought pieces.

void main() {
  // A 4' x 8' sheet at 1.6 mm, sheared into four 300 mm strips.
  const planned = PenPaperBaseline(
    sheetWidthInches: 48,
    sheetHeightInches: 96,
    sheetThicknessMm: 1.6,
    bands: [SheetCutGroup(sizeMm: 300, count: 4)],
    kerfMm: 3,
  );

  test('one sheet in, the planned pieces out, and it balances', () {
    final row = planned.reconciliationFromPlan(
      densityGCm3: 7.85,
      sheetLabel: 'MS sheet',
      partName: 'Dolly Patti',
    );
    final weights = planned.weighAt(7.85);

    expect(row.sheetsIn, 1);
    expect(row.piecesOut, planned.pieceCount);
    expect(row.inputKg, closeTo(weights.sheetKg, 0.001));
    expect(row.outputKg, closeTo(weights.partsKg, 0.001));
    expect(row.scrapKg, closeTo(weights.offcutKg, 0.001));
    expect(row.weightLossKg, closeTo(weights.lostKg, 0.001));
    expect(row.rejectionKg, 0);
    expect(row.balanceDeltaKg.abs(), lessThan(0.01));
    expect(row.inputName, 'MS sheet');
    expect(row.outputName, 'Dolly Patti');
  });

  test('with no material the counts fill and the weights wait', () {
    final row = planned.reconciliationFromPlan(
      densityGCm3: null,
      sheetLabel: 'Sheet',
      partName: 'Dolly Patti',
    );
    expect(row.sheetsIn, 1);
    expect(row.piecesOut, planned.pieceCount);
    expect(row.inputKg, 0);
  });

  test('pieces and labels survive a round trip; old records still read', () {
    const row = PenPaperStageReconciliation(
      stageId: 'whole_pipeline',
      stageName: 'Entire Pipeline',
      inputSheets: 1,
      outputPieces: 2900,
      outputUnitId: 3,
      inputLabel: 'MS sheet',
      outputLabel: 'Dolly Patti',
    );
    final back = PenPaperStageReconciliation.fromJson(row.toJson());
    expect(back.piecesOut, 2900);
    expect(back.outputUnitId, 3);
    expect(back.inputName, 'MS sheet');

    // Saved before pieces were whole and labels were named.
    final old = PenPaperStageReconciliation.fromJson({
      'stageId': 's',
      'stageName': 'S',
      'inputQty': 2,
      'outputQty': 40.0,
      'materialType': 'Sheet',
    });
    expect(old.sheetsIn, 2);
    expect(old.piecesOut, 40);
    expect(old.inputName, 'Sheet');
    expect(old.outputName, 'Sheet');
  });

  test('a fresh record follows the plan; one saved earlier does not', () {
    expect(PenPaperBaseline.createDefault().materialFromPlan, isTrue);
    final saved = PenPaperBaseline.fromJson(
      PenPaperBaseline.createDefault().toJson()..remove('materialFromPlan'),
    );
    expect(saved.materialFromPlan, isFalse);
  });
}

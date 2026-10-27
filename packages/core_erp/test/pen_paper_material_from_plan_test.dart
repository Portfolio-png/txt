import 'package:core_erp/features/production_pipelines/domain/pen_paper_baseline.dart';
import 'package:flutter_test/flutter_test.dart';

// Material data filled from the sheet plan: the counts — one sheet in, the
// planned pieces out — and the names. Never a weight: what an alloy weighs
// depends on its grade, so the weights are what was put on the scale.

void main() {
  // A 4' x 8' sheet at 1.6 mm, sheared into four 300 mm strips.
  const planned = PenPaperBaseline(
    sheetWidthInches: 48,
    sheetHeightInches: 96,
    sheetThicknessMm: 1.6,
    bands: [SheetCutGroup(sizeMm: 300, count: 4)],
    kerfMm: 3,
  );

  test('one sheet in, the planned pieces out, and no weight made up', () {
    final row = planned.reconciliationFromPlan(
      sheetLabel: 'MS · First grade',
      partName: 'Dolly Patti',
    );
    expect(row.sheetsIn, 1);
    expect(row.piecesOut, planned.pieceCount);
    expect(row.inputKg, 0);
    expect(row.outputKg, 0);
    expect(row.scrapKg, 0);
    expect(row.inputName, 'MS · First grade');
    expect(row.outputName, 'Dolly Patti');
  });

  test('weights typed earlier are kept; the stage defaults never leak in', () {
    const typed = PenPaperStageReconciliation(
      stageId: 'whole_pipeline',
      stageName: 'Entire Pipeline',
      inputKg: 4,
      outputKg: 3,
      scrapKg: 1,
      outputPieces: 10,
    );
    final kept = planned.reconciliationFromPlan(
      sheetLabel: 'Sheet',
      partName: 'Dolly Patti',
      keepFrom: typed,
    );
    expect(kept.inputKg, 4);
    expect(kept.scrapKg, 1);
    expect(
      kept.piecesOut,
      planned.pieceCount,
      reason: 'counts follow the plan',
    );

    // createDefault's per-stage rows carry 100 kg nobody weighed.
    final stage = PenPaperBaseline.createDefault().stageReconciliations.first;
    final fresh = planned.reconciliationFromPlan(
      sheetLabel: 'Sheet',
      partName: 'Dolly Patti',
      keepFrom: stage,
    );
    expect(fresh.inputKg, 0);
  });

  test(
    'alloy, grade and vendor survive a round trip; old records read empty',
    () {
      final back = PenPaperBaseline.fromJson(
        planned
            .copyWith(
              materialName: 'MS',
              materialGrade: 'Second',
              vendorId: 7,
              vendorName: 'Tata Steel',
            )
            .toJson(),
      );
      expect(back.materialName, 'MS');
      expect(back.materialGrade, 'Second');
      expect(back.vendorId, 7);
      expect(back.vendorName, 'Tata Steel');
      expect(back.copyWith(vendorId: null).vendorId, isNull);

      final old = PenPaperBaseline.fromJson(
        planned.toJson()
          ..remove('materialGrade')
          ..remove('vendorId')
          ..remove('vendorName'),
      );
      expect(old.materialGrade, '');
      expect(old.vendorId, isNull);
      expect(old.vendorName, '');
    },
  );

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

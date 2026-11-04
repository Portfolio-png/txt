import 'package:core_erp/features/production_pipelines/domain/pen_paper_baseline.dart';
import 'package:core_erp/features/production_pipelines/presentation/widgets/pen_paper_baseline_widget.dart';
import 'package:core_erp/features/units/data/unit_family_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Material data at the sheet's side-panel width, with the Count family: the
// output Qty's breakdown ("= 848 gro · 9 doz · 2 Pc") sits under its box.
// The two cards were made one height by IntrinsicHeight, which measured that
// line at the column's width while it was laid out in the narrow box — and
// the card came up 19px short.

void main() {
  testWidgets('a big count under the output Qty never overflows its card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(470, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final count = await tester.runAsync(
      () => UnitFamilyService(baseUrl: '', useMockResponses: true).byCode('count'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PenPaperBaselineWidget(
              baseline: PenPaperBaseline(
                stageReconciliations: [
                  PenPaperStageReconciliation(
                    stageId: 'whole',
                    stageName: 'Whole pipeline',
                    inputKg: 22,
                    outputKg: 12,
                    outputPieces: 122222,
                  ),
                ],
              ),
              countFamily: count,
              showChrome: false,
              allowStageByStage: false,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'no overflow');
    final box = tester.getRect(
      find.byKey(const ValueKey<String>('material-output-pieces')),
    );
    expect(box.width, lessThanOrEqualTo(150.5), reason: 'the box a number wide');
    expect(find.textContaining('= 848 gro'), findsOneWidget,
        reason: 'the breakdown shows, under it');
  });
}

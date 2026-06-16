import 'package:flutter_test/flutter_test.dart';
import 'package:paper/features/production/providers/batch_flow_provider.dart';
import 'package:paper/features/production_pipelines/domain/material_batch.dart';

void main() {
  const runId = 'RUN-1';

  BatchFlowProvider seeded() {
    final p = BatchFlowProvider();
    p.seedRun(runId, [
      const MaterialBatch(
        id: 'b1',
        barcode: 'BC-1',
        materialName: 'Brass',
        quantity: 100,
        currentNodeId: 'input',
      ),
    ]);
    return p;
  }

  double totalAt(BatchFlowProvider p, String node) => p
      .batchesAtNode(runId, node)
      .fold<double>(0, (s, b) => s + b.quantity);

  test('split move then revert restores the source exactly', () {
    final p = seeded();
    final resultId = p.moveBatch(
      runId: runId,
      batchId: 'b1',
      toNodeId: 'stage1',
      quantity: 30,
    )!;
    final rec = BatchMoveRecord(
      resultBatchId: resultId,
      fromNodeId: 'input',
      toNodeId: 'stage1',
      qty: 30,
      wasSplit: true,
      parentBatchId: 'b1',
    );
    p.recordMove(runId, rec);

    expect(totalAt(p, 'input'), 70);
    expect(totalAt(p, 'stage1'), 30);

    expect(p.revertChip(runId, rec), isTrue);
    expect(totalAt(p, 'input'), 100);
    expect(totalAt(p, 'stage1'), 0);
    expect(p.lastRecordForBatch(runId, resultId), isNull);
  });

  test('split revert also restores reconcile loss to the source', () {
    final p = seeded();
    final resultId = p.moveBatch(
      runId: runId,
      batchId: 'b1',
      toNodeId: 'stage1',
      quantity: 30,
    )!;
    // Reconcile declared 5 lost from the source pool.
    p.reduceBatch(runId: runId, batchId: 'b1', amount: 5);
    final rec = BatchMoveRecord(
      resultBatchId: resultId,
      fromNodeId: 'input',
      toNodeId: 'stage1',
      qty: 30,
      wasSplit: true,
      parentBatchId: 'b1',
    )..lossQty = 5;

    expect(totalAt(p, 'input'), 65); // 100 - 30 - 5

    p.revertChip(runId, rec);
    expect(totalAt(p, 'input'), 100); // 65 + 30 + 5
    expect(totalAt(p, 'stage1'), 0);
  });

  test('full move then revert relocates the batch back', () {
    final p = seeded();
    final resultId = p.moveBatch(
      runId: runId,
      batchId: 'b1',
      toNodeId: 'stage1',
      quantity: 100,
    )!;
    expect(resultId, 'b1'); // same id on a full move
    final rec = BatchMoveRecord(
      resultBatchId: resultId,
      fromNodeId: 'input',
      toNodeId: 'stage1',
      qty: 100,
      wasSplit: false,
    );
    p.recordMove(runId, rec);

    expect(totalAt(p, 'stage1'), 100);
    p.revertChip(runId, rec);
    expect(totalAt(p, 'input'), 100);
    expect(totalAt(p, 'stage1'), 0);
  });
}

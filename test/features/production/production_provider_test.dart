import 'package:flutter_test/flutter_test.dart';
import 'package:paper/features/production/providers/production_provider.dart';

void main() {
  group('ProductionProvider setup validation', () {
    test('matching machine and die setup succeeds', () {
      final provider = ProductionProvider.seeded();
      final stage = provider.selectedStage!;

      provider.verifyAssetSetup(
        'MACHINE:${stage.machineId}',
        'DIE:${stage.dieId}',
      );

      expect(provider.phase, ProductionRunPhase.setupVerified);
      expect(provider.currentMachineId, stage.machineId);
      expect(provider.currentDieId, stage.dieId);
      expect(provider.validationErrorMessage, isNull);
      provider.dispose();
    });

    test('machine mismatch throws and prevents running', () {
      final provider = ProductionProvider.seeded();
      final stage = provider.selectedStage!;

      expect(
        () => provider.verifyAssetSetup('MACHINE:WRONG', stage.dieId),
        throwsA(isA<ProductionSetupException>()),
      );

      expect(provider.isIdle, isTrue);
      expect(provider.currentMachineId, isNull);
      expect(
        provider.validationErrorMessage,
        contains('Machine lock-key mismatch'),
      );
      provider.startRun();
      expect(provider.isRunning, isFalse);
      provider.dispose();
    });

    test('die mismatch throws and prevents running', () {
      final provider = ProductionProvider.seeded();
      final stage = provider.selectedStage!;

      expect(
        () => provider.verifyAssetSetup(stage.machineId, 'DIE:WRONG'),
        throwsA(isA<ProductionSetupException>()),
      );

      expect(provider.isIdle, isTrue);
      expect(provider.currentDieId, isNull);
      expect(
        provider.validationErrorMessage,
        contains('Die lock-key mismatch'),
      );
      provider.startRun();
      expect(provider.isRunning, isFalse);
      provider.dispose();
    });
  });

  group('ProductionProvider run lifecycle', () {
    test('start, pause, resume, and closure update phase booleans', () {
      final provider = ProductionProvider.seeded();
      final stage = provider.selectedStage!;

      provider.verifyAssetSetup(stage.machineId, stage.dieId);
      provider.startRun();
      expect(provider.isRunning, isTrue);

      provider.pauseRun();
      expect(provider.isPaused, isTrue);

      provider.resumeRun();
      expect(provider.isRunning, isTrue);

      provider.beginClosure();
      expect(provider.isLoggingClosure, isTrue);

      provider.commitClosure();
      expect(provider.phase, ProductionRunPhase.closed);
      provider.dispose();
    });

    test('closure preview formats kg and unit deltas precisely', () {
      final provider = ProductionProvider.seeded();

      provider.updateClosureValues(
        parentReelConsumedKg: 510,
        goodYieldCount: 4850,
        scrapWeightKg: 20.7,
      );

      expect(provider.ledgerPreview.lines, [
        'Parent Reel Stock: -510.00 Kg',
        'WIP Board Lot: +4,850 Units',
        'Core Shredding Scrap: +20.70 Kg',
      ]);
      provider.dispose();
    });

    test('switching stages clears stale verified setup before start', () {
      final provider = ProductionProvider.seeded();
      final firstStage = provider.selectedStage!;
      final secondStage = provider.blueprint.stages[1];

      provider.verifyAssetSetup(firstStage.machineId, firstStage.dieId);
      provider.selectStage(secondStage.id);
      provider.startRun();

      expect(provider.isRunning, isFalse);
      expect(provider.isIdle, isTrue);
      expect(provider.validationErrorMessage, contains('Verify the machine'));
      provider.dispose();
    });

    test('canceling closure returns the active run to paused', () {
      final provider = ProductionProvider.seeded();
      final stage = provider.selectedStage!;

      provider.verifyAssetSetup(stage.machineId, stage.dieId);
      provider.startRun();
      provider.beginClosure();
      provider.cancelClosure();

      expect(provider.isPaused, isTrue);
      provider.dispose();
    });
  });

  group('ProductionProvider stage reordering', () {
    test('reordering stages updates template.stages order correctly', () {
      final provider = ProductionProvider.seeded();
      final stages = provider.blueprint.stages;
      final originalFirst = stages[0];
      final originalSecond = stages[1];

      provider.reorderStages(0, 2); // drag first item past second item

      expect(provider.template.stages[0].id, originalSecond.id);
      expect(provider.template.stages[1].id, originalFirst.id);
      provider.dispose();
    });
  });
}

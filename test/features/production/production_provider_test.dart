import 'package:flutter_test/flutter_test.dart';
import 'package:paper/features/production/providers/production_provider.dart';

void main() {
  group('ProductionProvider run lifecycle', () {
    test('start, pause, resume, and closure update phase booleans', () {
      final provider = ProductionProvider.seeded();

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

    test('canceling closure returns the active run to paused', () {
      final provider = ProductionProvider.seeded();

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

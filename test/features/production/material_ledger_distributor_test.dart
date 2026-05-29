import 'package:flutter_test/flutter_test.dart';
import 'package:paper/features/production/domain/utils/material_ledger_distributor.dart';

void main() {
  group('MaterialLedgerDistributor Tests', () {
    test('initialDistribution - typical case where good yield is <= parent', () {
      final weights = MaterialLedgerDistributor.initialDistribution(
        parentKg: 100.0,
        initialYieldCount: 500, // 500 * 0.1 = 50.0 kg good
        initialScrapWeightKg: 20.0, // 20.0 kg scrap
      );

      expect(weights.parentKg, 100.0);
      expect(weights.goodKg, 50.0);
      expect(weights.scrapKg, 20.0);
      expect(weights.setupKg, closeTo(12.0, 0.001)); // 20 * 0.6
      expect(weights.processKg, closeTo(8.0, 0.001)); // 20 * 0.4
      expect(weights.yieldUnits, 500);
    });

    test('initialDistribution - good yield exceeds parent', () {
      final weights = MaterialLedgerDistributor.initialDistribution(
        parentKg: 50.0,
        initialYieldCount: 600, // 600 * 0.1 = 60.0 kg (exceeds parent)
        initialScrapWeightKg: 10.0,
      );

      expect(weights.parentKg, 50.0);
      expect(weights.goodKg, 40.0); // (50.0 - 10.0)
      expect(weights.scrapKg, 10.0);
      expect(weights.setupKg, 6.0); // 10 * 0.6
      expect(weights.processKg, 4.0); // 10 * 0.4
      expect(weights.yieldUnits, 400); // 40.0 / 0.1
    });

    test('updateParent - scales weights and yields proportionally', () {
      final initial = MaterialLedgerDistributor.initialDistribution(
        parentKg: 100.0,
        initialYieldCount: 500,
        initialScrapWeightKg: 20.0,
      );

      // Scale parent to 200.0
      final updated = MaterialLedgerDistributor.updateParent(initial, 200.0);

      expect(updated.parentKg, 200.0);
      expect(updated.goodKg, 100.0); // 50.0 * 2
      expect(updated.scrapKg, 40.0); // 20.0 * 2
      expect(updated.setupKg, 24.0); // 12.0 * 2
      expect(updated.processKg, 16.0); // 8.0 * 2
      expect(updated.yieldUnits, 1000);
    });

    test('updateYield - adjusts good yield and distributes remaining to scrap', () {
      final initial = MaterialLedgerDistributor.initialDistribution(
        parentKg: 100.0,
        initialYieldCount: 500, // 50.0 kg good
        initialScrapWeightKg: 20.0, // 20.0 kg scrap
      );

      // Increase yield to 600 units (60 kg)
      final updated = MaterialLedgerDistributor.updateYield(initial, 600);

      expect(updated.parentKg, 100.0);
      expect(updated.goodKg, 60.0);
      expect(updated.scrapKg, 40.0); // 100.0 - 60.0
      expect(updated.setupKg, closeTo(24.0, 0.001)); // 40 * 0.6
      expect(updated.processKg, closeTo(16.0, 0.001)); // 40 * 0.4
      expect(updated.yieldUnits, 600);
    });

    test('updateScrap - adjusts scrap and distributes remaining to good yield', () {
      final initial = MaterialLedgerDistributor.initialDistribution(
        parentKg: 100.0,
        initialYieldCount: 500,
        initialScrapWeightKg: 20.0,
      );

      // Increase scrap to 40 kg
      final updated = MaterialLedgerDistributor.updateScrap(initial, 40.0);

      expect(updated.parentKg, 100.0);
      expect(updated.scrapKg, 40.0);
      expect(updated.goodKg, 60.0); // 100 - 40
      expect(updated.yieldUnits, 600);
    });

    test('adjustWeights - adjusts good yield directly', () {
      final initial = MaterialLedgerDistributor.initialDistribution(
        parentKg: 100.0,
        initialYieldCount: 500,
        initialScrapWeightKg: 20.0,
      );

      // Adjust good yield directly to 70 kg
      final adjusted = MaterialLedgerDistributor.adjustWeights(initial, goodKg: 70.0);

      expect(adjusted.parentKg, 100.0);
      expect(adjusted.goodKg, 70.0);
      expect(adjusted.scrapKg, 30.0);
      expect(adjusted.yieldUnits, 700);
    });

    test('adjustWeights - adjusts setup scrap directly', () {
      final initial = MaterialLedgerDistributor.initialDistribution(
        parentKg: 100.0,
        initialYieldCount: 500, // 50 kg good
        initialScrapWeightKg: 20.0, // 12 kg setup, 8 kg process
      );

      // Adjust setup scrap to 30 kg directly
      final adjusted = MaterialLedgerDistributor.adjustWeights(initial, setupKg: 30.0);

      expect(adjusted.parentKg, 100.0);
      expect(adjusted.setupKg, 30.0);
      // Good and process weights are scaled proportionally to remaining (100 - 30 = 70 kg)
      // Good (50) to Process (8) ratio = 50 / 58 vs 8 / 58
      expect(adjusted.goodKg, closeTo(70.0 * (50.0 / 58.0), 0.001));
      expect(adjusted.processKg, closeTo(70.0 * (8.0 / 58.0), 0.001));
    });
  });
}

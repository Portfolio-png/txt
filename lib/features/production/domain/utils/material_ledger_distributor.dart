class LedgerWeights {
  final double parentKg;
  final double goodKg;
  final double setupKg;
  final double processKg;
  final int yieldUnits;
  final double scrapKg;

  const LedgerWeights({
    required this.parentKg,
    required this.goodKg,
    required this.setupKg,
    required this.processKg,
    required this.yieldUnits,
    required this.scrapKg,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LedgerWeights &&
          runtimeType == other.runtimeType &&
          parentKg == other.parentKg &&
          goodKg == other.goodKg &&
          setupKg == other.setupKg &&
          processKg == other.processKg &&
          yieldUnits == other.yieldUnits &&
          scrapKg == other.scrapKg;

  @override
  int get hashCode =>
      parentKg.hashCode ^
      goodKg.hashCode ^
      setupKg.hashCode ^
      processKg.hashCode ^
      yieldUnits.hashCode ^
      scrapKg.hashCode;

  @override
  String toString() {
    return 'LedgerWeights(parentKg: $parentKg, goodKg: $goodKg, setupKg: $setupKg, processKg: $processKg, yieldUnits: $yieldUnits, scrapKg: $scrapKg)';
  }
}

class MaterialLedgerDistributor {
  static LedgerWeights initialDistribution({
    required double parentKg,
    required int initialYieldCount,
    required double initialScrapWeightKg,
  }) {
    double goodKg;
    double setupKg;
    double processKg;
    double scrapKg = initialScrapWeightKg;
    int yieldUnits = initialYieldCount;

    final calculatedGoodKg = yieldUnits * 0.1;
    if (calculatedGoodKg > 0 && calculatedGoodKg <= parentKg) {
      goodKg = calculatedGoodKg;
      final remaining = parentKg - goodKg;
      if (scrapKg > 0) {
        setupKg = scrapKg * 0.6;
        processKg = scrapKg * 0.4;
      } else {
        setupKg = remaining * 0.6;
        processKg = remaining * 0.4;
        scrapKg = setupKg + processKg;
      }
    } else {
      goodKg = (parentKg - scrapKg).clamp(0.0, parentKg);
      setupKg = scrapKg * 0.6;
      processKg = scrapKg * 0.4;
      yieldUnits = (goodKg / 0.1).round();
    }
    return LedgerWeights(
      parentKg: parentKg,
      goodKg: goodKg,
      setupKg: setupKg,
      processKg: processKg,
      yieldUnits: yieldUnits,
      scrapKg: scrapKg,
    );
  }

  static LedgerWeights updateParent(LedgerWeights current, double newParentKg) {
    final oldParent = current.parentKg;
    final parentKg = newParentKg.clamp(1.0, double.infinity);
    final ratio = oldParent > 0 ? (parentKg / oldParent) : 0.0;
    final goodKg = (current.goodKg * ratio).clamp(0.0, parentKg);
    final setupKg = (current.setupKg * ratio).clamp(0.0, parentKg);
    final processKg = (current.processKg * ratio).clamp(0.0, parentKg);
    final yieldUnits = (goodKg / 0.1).round();
    final scrapKg = setupKg + processKg;

    return LedgerWeights(
      parentKg: parentKg,
      goodKg: goodKg,
      setupKg: setupKg,
      processKg: processKg,
      yieldUnits: yieldUnits,
      scrapKg: scrapKg,
    );
  }

  static LedgerWeights updateYield(LedgerWeights current, int newYieldUnits) {
    final parentKg = current.parentKg;
    final yieldUnits = newYieldUnits.clamp(0, 99999999);
    final goodKg = (yieldUnits * 0.1).clamp(0.0, parentKg);
    final remaining = parentKg - goodKg;
    final currentScrapTotal = current.setupKg + current.processKg;

    double setupKg;
    double processKg;
    if (currentScrapTotal > 0) {
      setupKg = remaining * (current.setupKg / currentScrapTotal);
      processKg = remaining * (current.processKg / currentScrapTotal);
    } else {
      setupKg = remaining * 0.6;
      processKg = remaining * 0.4;
    }
    final scrapKg = setupKg + processKg;

    return LedgerWeights(
      parentKg: parentKg,
      goodKg: goodKg,
      setupKg: setupKg,
      processKg: processKg,
      yieldUnits: yieldUnits,
      scrapKg: scrapKg,
    );
  }

  static LedgerWeights updateScrap(LedgerWeights current, double newScrapKg) {
    final parentKg = current.parentKg;
    final scrapKg = newScrapKg.clamp(0.0, parentKg);
    final goodKg = parentKg - scrapKg;
    final yieldUnits = (goodKg / 0.1).round();
    final currentScrapTotal = current.setupKg + current.processKg;

    double setupKg;
    double processKg;
    if (currentScrapTotal > 0) {
      setupKg = scrapKg * (current.setupKg / currentScrapTotal);
      processKg = scrapKg * (current.processKg / currentScrapTotal);
    } else {
      setupKg = scrapKg * 0.6;
      processKg = scrapKg * 0.4;
    }

    return LedgerWeights(
      parentKg: parentKg,
      goodKg: goodKg,
      setupKg: setupKg,
      processKg: processKg,
      yieldUnits: yieldUnits,
      scrapKg: scrapKg,
    );
  }

  static LedgerWeights adjustWeights(
    LedgerWeights current, {
    double? goodKg,
    double? setupKg,
    double? processKg,
  }) {
    final total = current.parentKg;
    double newGoodKg = current.goodKg;
    double newSetupKg = current.setupKg;
    double newProcessKg = current.processKg;

    if (goodKg != null) {
      final newGood = goodKg.clamp(0.0, total);
      final remaining = total - newGood;
      final currentScrapTotal = current.setupKg + current.processKg;
      if (currentScrapTotal > 0) {
        newSetupKg = remaining * (current.setupKg / currentScrapTotal);
        newProcessKg = remaining * (current.processKg / currentScrapTotal);
      } else {
        newSetupKg = remaining * 0.6;
        newProcessKg = remaining * 0.4;
      }
      newGoodKg = newGood;
    } else if (setupKg != null) {
      final newSetup = setupKg.clamp(0.0, total);
      final remaining = total - newSetup;
      final currentOtherTotal = current.goodKg + current.processKg;
      if (currentOtherTotal > 0) {
        newGoodKg = remaining * (current.goodKg / currentOtherTotal);
        newProcessKg = remaining * (current.processKg / currentOtherTotal);
      } else {
        newGoodKg = remaining * 0.9;
        newProcessKg = remaining * 0.1;
      }
      newSetupKg = newSetup;
    } else if (processKg != null) {
      final newProcess = processKg.clamp(0.0, total);
      final remaining = total - newProcess;
      final currentOtherTotal = current.goodKg + current.setupKg;
      if (currentOtherTotal > 0) {
        newGoodKg = remaining * (current.goodKg / currentOtherTotal);
        newSetupKg = remaining * (current.setupKg / currentOtherTotal);
      } else {
        newGoodKg = remaining * 0.9;
        newSetupKg = remaining * 0.1;
      }
      newProcessKg = newProcess;
    }

    final yieldUnits = (newGoodKg / 0.1).round();
    final scrapKg = newSetupKg + newProcessKg;

    return LedgerWeights(
      parentKg: total,
      goodKg: newGoodKg,
      setupKg: newSetupKg,
      processKg: newProcessKg,
      yieldUnits: yieldUnits,
      scrapKg: scrapKg,
    );
  }
}

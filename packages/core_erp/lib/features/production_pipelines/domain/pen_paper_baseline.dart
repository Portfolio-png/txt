import 'package:flutter/foundation.dart';

/// Single stage or whole-pipeline reconciliation entry recorded from historical paper/sample logs.
/// All quantities are measured in kilograms (kg).
@immutable
class PenPaperStageReconciliation {
  const PenPaperStageReconciliation({
    required this.stageId,
    required this.stageName,
    this.recordScrap = true,
    this.recordRejection = true,
    this.recordWeightLoss = true,
    this.inputKg = 100.0,
    this.outputKg = 90.0,
    this.scrapKg = 5.0,
    this.rejectionKg = 3.0,
    this.weightLossKg = 2.0,
    this.inputQty = 0,
    this.outputQty = 0,
    this.materialType = '',
    this.rejectionPercent = 0.0,
    this.notes = '',
  });

  final String stageId;
  final String stageName;
  final bool recordScrap;
  final bool recordRejection;
  final bool recordWeightLoss;
  final double inputKg;
  final double outputKg;
  final double scrapKg;
  final double rejectionKg;
  final double weightLossKg;

  /// Pieces in and out. Weight is the sum across the lot, so a piece count is
  /// what makes a per-piece average possible — the same pairing the mobile app
  /// records against a reception challan.
  final double inputQty;
  final double outputQty;

  /// What the material is, read off the variant's own name (a variant of a
  /// sheet is a sheet). Stamped so the record still says what was weighed.
  final String materialType;

  /// Rejection is booked as a percentage of input weight rather than an
  /// absolute, because that is how the floor quotes it.
  final double rejectionPercent;
  final String notes;

  /// Average weight of one piece, which is what the pieces/weight pair is for.
  double get inputKgPerPiece => inputQty > 0 ? inputKg / inputQty : 0.0;
  double get outputKgPerPiece => outputQty > 0 ? outputKg / outputQty : 0.0;

  /// Rejection resolved to kg from its percentage of input.
  double get rejectionFromPercentKg =>
      recordRejection ? inputKg * (rejectionPercent / 100.0) : 0.0;

  double get effectiveScrapKg => recordScrap ? scrapKg : 0.0;
  double get effectiveRejectionKg => recordRejection ? rejectionKg : 0.0;
  double get effectiveWeightLossKg => recordWeightLoss ? weightLossKg : 0.0;

  /// Total material accounted for (Good Output + Scrap + Rejection + Process Loss).
  double get totalAccountedKg =>
      outputKg + effectiveScrapKg + effectiveRejectionKg + effectiveWeightLossKg;

  /// Material yield percentage = (Good Output Kg / Input Kg) * 100%.
  double get yieldPercentage =>
      inputKg > 0 ? ((outputKg / inputKg) * 100.0).clamp(0.0, 100.0) : 0.0;

  /// Difference between Input and Accounted Output (Unexplained Mass Variance).
  double get balanceDeltaKg => inputKg - totalAccountedKg;

  PenPaperStageReconciliation copyWith({
    String? stageId,
    String? stageName,
    bool? recordScrap,
    bool? recordRejection,
    bool? recordWeightLoss,
    double? inputKg,
    double? outputKg,
    double? scrapKg,
    double? rejectionKg,
    double? weightLossKg,
    double? inputQty,
    double? outputQty,
    String? materialType,
    double? rejectionPercent,
    String? notes,
  }) {
    return PenPaperStageReconciliation(
      stageId: stageId ?? this.stageId,
      stageName: stageName ?? this.stageName,
      recordScrap: recordScrap ?? this.recordScrap,
      recordRejection: recordRejection ?? this.recordRejection,
      recordWeightLoss: recordWeightLoss ?? this.recordWeightLoss,
      inputKg: inputKg ?? this.inputKg,
      outputKg: outputKg ?? this.outputKg,
      scrapKg: scrapKg ?? this.scrapKg,
      rejectionKg: rejectionKg ?? this.rejectionKg,
      weightLossKg: weightLossKg ?? this.weightLossKg,
      inputQty: inputQty ?? this.inputQty,
      outputQty: outputQty ?? this.outputQty,
      materialType: materialType ?? this.materialType,
      rejectionPercent: rejectionPercent ?? this.rejectionPercent,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'stageId': stageId,
      'stageName': stageName,
      'recordScrap': recordScrap,
      'recordRejection': recordRejection,
      'recordWeightLoss': recordWeightLoss,
      'inputKg': inputKg,
      'outputKg': outputKg,
      'scrapKg': scrapKg,
      'rejectionKg': rejectionKg,
      'weightLossKg': weightLossKg,
      'inputQty': inputQty,
      'outputQty': outputQty,
      'materialType': materialType,
      'rejectionPercent': rejectionPercent,
      'notes': notes,
    };
  }

  factory PenPaperStageReconciliation.fromJson(Map<String, dynamic> json) {
    return PenPaperStageReconciliation(
      stageId: json['stageId'] as String? ?? '',
      stageName: json['stageName'] as String? ?? 'Process Stage',
      recordScrap: json['recordScrap'] as bool? ?? true,
      recordRejection: json['recordRejection'] as bool? ?? true,
      recordWeightLoss: json['recordWeightLoss'] as bool? ?? true,
      inputKg: (json['inputKg'] as num?)?.toDouble() ?? 100.0,
      outputKg: (json['outputKg'] as num?)?.toDouble() ?? 90.0,
      scrapKg: (json['scrapKg'] as num?)?.toDouble() ?? 5.0,
      rejectionKg: (json['rejectionKg'] as num?)?.toDouble() ?? 3.0,
      weightLossKg: (json['weightLossKg'] as num?)?.toDouble() ?? 2.0,
      inputQty: (json['inputQty'] as num?)?.toDouble() ?? 0,
      outputQty: (json['outputQty'] as num?)?.toDouble() ?? 0,
      materialType: json['materialType'] as String? ?? '',
      rejectionPercent: (json['rejectionPercent'] as num?)?.toDouble() ?? 0.0,
      notes: json['notes'] as String? ?? '',
    );
  }
}

/// Baseline paper record model containing stage-by-stage or whole-pipeline reconciliation logs.
@immutable
class PenPaperBaseline {
  const PenPaperBaseline({
    this.isGranular = false,
    this.keyEfficiencyBenchmark = 75.0,
    this.baselineOutputRate = 12.0,
    this.baselineScrapRate = 4.0,
    this.stageReconciliations = const [],
    this.notes = 'Recorded from sample production logs.',
    this.pipelineId,
    this.pipelineName = '',
  });

  /// The production pipeline this sample was measured on. A baseline only means
  /// something in the context of a route, so it is stamped at capture time —
  /// if the item's default pipeline later changes, the record still says which
  /// pipeline the weights came from.
  final String? pipelineId;
  final String pipelineName;

  final bool isGranular;
  final double keyEfficiencyBenchmark;
  final double baselineOutputRate;
  final double baselineScrapRate;
  final List<PenPaperStageReconciliation> stageReconciliations;
  final String notes;

  /// Overall pipeline input kg (input to Stage 1 or whole pipeline).
  double get totalInputKg =>
      stageReconciliations.isNotEmpty ? stageReconciliations.first.inputKg : 0.0;

  /// Overall pipeline final output kg (good output of final stage or whole pipeline).
  double get totalFinalOutputKg => stageReconciliations.isNotEmpty
      ? stageReconciliations.last.outputKg
      : 0.0;

  /// Overall pipeline material recovery yield %.
  double get overallYieldPercentage =>
      totalInputKg > 0 ? ((totalFinalOutputKg / totalInputKg) * 100.0).clamp(0.0, 100.0) : 0.0;

  /// Creates default baseline for given pipeline stage labels.
  static PenPaperBaseline createDefaultForStages([List<String>? stageNames]) {
    final stages = (stageNames != null && stageNames.isNotEmpty)
        ? stageNames
        : const ['Raw Preparation', 'Material Shaping', 'Final Polish'];

    double currentInput = 100.0;
    final list = <PenPaperStageReconciliation>[];

    for (int i = 0; i < stages.length; i++) {
      final name = stages[i];
      final output = (currentInput * 0.90).roundToDouble();
      final scrap = (currentInput * 0.05).roundToDouble();
      final rejection = (currentInput * 0.03).roundToDouble();
      final loss = (currentInput * 0.02).roundToDouble();

      list.add(
        PenPaperStageReconciliation(
          stageId: 'stage-${i + 1}',
          stageName: name,
          recordScrap: true,
          recordRejection: true,
          recordWeightLoss: true,
          inputKg: currentInput,
          outputKg: output,
          scrapKg: scrap,
          rejectionKg: rejection,
          weightLossKg: loss,
          notes: 'Log for $name',
        ),
      );

      currentInput = output;
    }

    return PenPaperBaseline(
      isGranular: false,
      keyEfficiencyBenchmark: 88.0,
      baselineOutputRate: 12.5,
      baselineScrapRate: 4.2,
      stageReconciliations: list,
    );
  }

  static PenPaperBaseline createDefault() => createDefaultForStages();

  PenPaperBaseline copyWith({
    bool? isGranular,
    double? keyEfficiencyBenchmark,
    double? baselineOutputRate,
    double? baselineScrapRate,
    List<PenPaperStageReconciliation>? stageReconciliations,
    String? notes,
    String? pipelineId,
    String? pipelineName,
  }) {
    return PenPaperBaseline(
      isGranular: isGranular ?? this.isGranular,
      keyEfficiencyBenchmark:
          keyEfficiencyBenchmark ?? this.keyEfficiencyBenchmark,
      baselineOutputRate: baselineOutputRate ?? this.baselineOutputRate,
      baselineScrapRate: baselineScrapRate ?? this.baselineScrapRate,
      stageReconciliations: stageReconciliations ?? this.stageReconciliations,
      notes: notes ?? this.notes,
      pipelineId: pipelineId ?? this.pipelineId,
      pipelineName: pipelineName ?? this.pipelineName,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'isGranular': isGranular,
      'keyEfficiencyBenchmark': keyEfficiencyBenchmark,
      'baselineOutputRate': baselineOutputRate,
      'baselineScrapRate': baselineScrapRate,
      'stageReconciliations': stageReconciliations.map((e) => e.toJson()).toList(),
      'notes': notes,
      'pipelineId': pipelineId,
      'pipelineName': pipelineName,
    };
  }

  factory PenPaperBaseline.fromJson(Map<String, dynamic> json) {
    final stages = (json['stageReconciliations'] as List<dynamic>? ?? const [])
        .map((e) => PenPaperStageReconciliation.fromJson(e as Map<String, dynamic>))
        .toList();

    return PenPaperBaseline(
      isGranular: json['isGranular'] as bool? ?? false,
      keyEfficiencyBenchmark:
          (json['keyEfficiencyBenchmark'] as num?)?.toDouble() ?? 88.0,
      baselineOutputRate:
          (json['baselineOutputRate'] as num?)?.toDouble() ?? 12.0,
      baselineScrapRate:
          (json['baselineScrapRate'] as num?)?.toDouble() ?? 4.0,
      stageReconciliations:
          stages.isNotEmpty ? stages : createDefaultForStages().stageReconciliations,
      notes: json['notes'] as String? ?? '',
      pipelineId: json['pipelineId'] as String?,
      pipelineName: json['pipelineName'] as String? ?? '',
    );
  }
}

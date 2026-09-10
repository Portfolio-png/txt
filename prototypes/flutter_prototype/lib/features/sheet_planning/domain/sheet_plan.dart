import 'dart:math' as math;

class Band {
  final double sizeMm;
  final int count;

  const Band({required this.sizeMm, required this.count});

  Band copyWith({double? sizeMm, int? count}) =>
      Band(sizeMm: sizeMm ?? this.sizeMm, count: count ?? this.count);
}

class SubCut {
  final double sizeMm;
  final int count;

  const SubCut({required this.sizeMm, required this.count});

  SubCut copyWith({double? sizeMm, int? count}) =>
      SubCut(sizeMm: sizeMm ?? this.sizeMm, count: count ?? this.count);
}

class YieldPart {
  final double widthMm;
  final double heightMm;
  final int count;
  final bool isOffcut;

  const YieldPart({
    required this.widthMm,
    required this.heightMm,
    required this.count,
    this.isOffcut = false,
  });
}

class SheetPlanWeight {
  final double sheetKg;
  final double partsKg;
  final double scrapKg;
  final double yieldPercent;

  const SheetPlanWeight({
    required this.sheetKg,
    required this.partsKg,
    required this.scrapKg,
    required this.yieldPercent,
  });
}

class SheetPlan {
  final double sheetWidthInches;
  final double sheetHeightInches;
  final double sheetThicknessMm;
  final double kerfMm;
  final double edgeTrimMm;
  final String materialName;
  final List<Band> bands;
  final Map<int, List<SubCut>> subCuts;
  final String plannedPartName;

  const SheetPlan({
    required this.sheetWidthInches,
    required this.sheetHeightInches,
    required this.sheetThicknessMm,
    required this.kerfMm,
    required this.edgeTrimMm,
    required this.materialName,
    required this.bands,
    required this.subCuts,
    this.plannedPartName = '',
  });

  static SheetPlan empty() => const SheetPlan(
        sheetWidthInches: 48,
        sheetHeightInches: 96,
        sheetThicknessMm: 1.2,
        kerfMm: 2,
        edgeTrimMm: 10,
        materialName: 'Steel / MS',
        bands: [],
        subCuts: {},
        plannedPartName: '',
      );

  double get widthMm => sheetWidthInches * 25.4;
  double get heightMm => sheetHeightInches * 25.4;
  double get usableWidthMm => math.max(0, widthMm - 2 * edgeTrimMm);
  double get usableHeightMm => math.max(0, heightMm - 2 * edgeTrimMm);

  SheetPlan copyWith({
    double? sheetWidthInches,
    double? sheetHeightInches,
    double? sheetThicknessMm,
    double? kerfMm,
    double? edgeTrimMm,
    String? materialName,
    List<Band>? bands,
    Map<int, List<SubCut>>? subCuts,
    String? plannedPartName,
  }) {
    return SheetPlan(
      sheetWidthInches: sheetWidthInches ?? this.sheetWidthInches,
      sheetHeightInches: sheetHeightInches ?? this.sheetHeightInches,
      sheetThicknessMm: sheetThicknessMm ?? this.sheetThicknessMm,
      kerfMm: kerfMm ?? this.kerfMm,
      edgeTrimMm: edgeTrimMm ?? this.edgeTrimMm,
      materialName: materialName ?? this.materialName,
      bands: bands ?? this.bands,
      subCuts: subCuts ?? this.subCuts,
      plannedPartName: plannedPartName ?? this.plannedPartName,
    );
  }
}

const Map<String, double> materialDensities = {
  'Steel / MS': 7.85,
  'Stainless Steel': 7.90,
  'Aluminium': 2.70,
  'Brass': 8.50,
  'Copper': 8.96,
};

double densityForMaterial(String materialName) =>
    materialDensities[materialName] ?? 7.85;

int pieceCount(SheetPlan plan) {
  int total = 0;
  for (int b = 0; b < plan.bands.length; b++) {
    final band = plan.bands[b];
    final cuts = plan.subCuts[b] ?? [];
    if (cuts.isEmpty) {
      total += band.count;
    } else {
      final perStrip = cuts.fold<int>(0, (sum, c) => sum + c.count);
      total += band.count * perStrip;
    }
  }
  return total;
}

SheetPlanWeight calculateWeight(SheetPlan plan, [double? density]) {
  final d = density ?? densityForMaterial(plan.materialName);
  final sheetVolCc = (plan.widthMm * plan.heightMm * plan.sheetThicknessMm) / 1000.0;
  final sheetKg = (sheetVolCc * d) / 1000.0;

  double partsAreaMm2 = 0;
  for (int b = 0; b < plan.bands.length; b++) {
    final band = plan.bands[b];
    final cuts = plan.subCuts[b] ?? [];
    if (cuts.isEmpty) {
      partsAreaMm2 += band.sizeMm * plan.usableHeightMm * band.count;
    } else {
      for (final cut in cuts) {
        partsAreaMm2 += band.sizeMm * cut.sizeMm * cut.count * band.count;
      }
    }
  }

  final partsVolCc = (partsAreaMm2 * plan.sheetThicknessMm) / 1000.0;
  final partsKg = (partsVolCc * d) / 1000.0;
  final scrapKg = math.max(0.0, sheetKg - partsKg);
  final yieldPct = sheetKg > 0 ? (partsKg / sheetKg) * 100.0 : 0.0;

  return SheetPlanWeight(
    sheetKg: sheetKg,
    partsKg: partsKg,
    scrapKg: scrapKg,
    yieldPercent: yieldPct,
  );
}

List<YieldPart> calculateYields(SheetPlan plan) {
  final List<YieldPart> result = [];
  for (int b = 0; b < plan.bands.length; b++) {
    final band = plan.bands[b];
    final cuts = plan.subCuts[b] ?? [];
    if (cuts.isEmpty) {
      result.add(YieldPart(
        widthMm: band.sizeMm,
        heightMm: plan.usableHeightMm,
        count: band.count,
      ));
    } else {
      for (final cut in cuts) {
        result.add(YieldPart(
          widthMm: band.sizeMm,
          heightMm: cut.sizeMm,
          count: cut.count * band.count,
        ));
      }
    }
  }
  return result;
}

SheetPlan createPlanForPart({
  required SheetPlan basePlan,
  required String partName,
  required double partWidthMm,
  required double partHeightMm,
}) {
  final usableW = basePlan.usableWidthMm;
  final usableH = basePlan.usableHeightMm;

  final bandCount = math.max(1, ((usableW + basePlan.kerfMm) / (partWidthMm + basePlan.kerfMm)).floor());
  final subCutCount = math.max(1, ((usableH + basePlan.kerfMm) / (partHeightMm + basePlan.kerfMm)).floor());

  return basePlan.copyWith(
    plannedPartName: partName,
    bands: [Band(sizeMm: partWidthMm, count: bandCount)],
    subCuts: {
      0: [SubCut(sizeMm: partHeightMm, count: subCutCount)],
    },
  );
}

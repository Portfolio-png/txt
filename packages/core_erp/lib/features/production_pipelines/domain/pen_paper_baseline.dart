import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'pipeline_stage_node.dart';
import '../../units/domain/global_length_units.dart';
import 'sheet_part.dart';

/// One band of cuts: how big each piece is along an axis, and how many of them.
///
/// The sheet is not divided into one repeated strip. A plan is a list of these
/// — twelve at 40 mm, then thirteen at 35 — because that is how stock is
/// actually broken down when several parts come off one sheet.
@immutable
class SheetCutGroup {
  const SheetCutGroup({this.sizeMm = 0, this.count = 0});

  factory SheetCutGroup.fromJson(Map<String, dynamic> json) => SheetCutGroup(
    sizeMm: (json['sizeMm'] as num?)?.toDouble() ?? 0,
    count: (json['count'] as num?)?.toInt() ?? 0,
  );

  final double sizeMm;
  final int count;

  /// How much of the axis this band eats.
  double get spanMm => sizeMm <= 0 || count <= 0 ? 0 : sizeMm * count;

  /// A band with a size but no count, or the reverse, is half-typed rather than
  /// wrong — it just contributes nothing yet.
  bool get isComplete => sizeMm > 0 && count > 0;

  SheetCutGroup copyWith({double? sizeMm, int? count}) =>
      SheetCutGroup(sizeMm: sizeMm ?? this.sizeMm, count: count ?? this.count);

  Map<String, dynamic> toJson() => {'sizeMm': sizeMm, 'count': count};

  static List<SheetCutGroup> listFromJson(dynamic raw) {
    if (raw is! List) return const <SheetCutGroup>[];
    return raw
        .whereType<Map>()
        .map((entry) => SheetCutGroup.fromJson(entry.cast<String, dynamic>()))
        .toList(growable: false);
  }
}

/// Where one band sits along an axis, in millimetres from the sheet's own edge.
///
/// A band is a run of same-size pieces. Knowing where it starts and stops is
/// what lets the drawing colour it as a region rather than draw a line per
/// piece — which at any real count is an unreadable smear.
@immutable
class SheetBandSpan {
  const SheetBandSpan({
    required this.index,
    required this.startMm,
    required this.endMm,
    required this.sizeMm,
    required this.count,
  });

  /// Which band on its axis, so the drawing and the panel colour it the same.
  final int index;
  final double startMm;
  final double endMm;
  final double sizeMm;

  /// Pieces that actually fit. Fewer than asked for when the sheet ran out.
  final int count;

  double get spanMm => endMm - startMm;
}

/// A stretch of sheet a cut can act on: one strip, or the leftover.
///
/// Regions are what make "where does this cut go?" answerable. Without them a
/// second cut has nowhere to land but across the whole sheet, which is the
/// machine nobody owns.
@immutable
class SheetRegion {
  const SheetRegion({
    required this.index,
    required this.copies,
    required this.widthMm,
    required this.heightMm,
  });

  /// The band this region came from, or [PenPaperBaseline.offcutRegion].
  final int index;

  /// How many identical regions of this shape the band produced. Cutting one
  /// strip a certain way cuts every strip in that band the same way.
  final int copies;

  final double widthMm;
  final double heightMm;

  bool get isOffcut => index == PenPaperBaseline.offcutRegion;

  String get label => isOffcut ? 'Leftover' : 'Strip ${index + 1}';

  /// How long this region runs along [axis].
  double extentAlong(SheetCutAxis axis) =>
      axis == SheetCutAxis.columns ? widthMm : heightMm;
}

/// One kind of piece the plan produces, and how many of it.
///
/// The bottom line of a plan is a *list* of these, never a single number. Bands
/// of different sizes make different parts: 99 strips at 12 mm and 5 strips at
/// 89 mm are not 104 of anything. Adding them up was the lie the two-list model
/// told, and it is the reason a plan has to be read as regions.
@immutable
class SheetYield {
  const SheetYield({
    required this.label,
    required this.widthMm,
    required this.heightMm,
    required this.count,
    required this.colourIndex,
    required this.isOffcut,
  });

  final String label;
  final double widthMm;
  final double heightMm;
  final int count;
  final int colourIndex;

  /// Whether this is material that leaves as waste rather than as a part.
  final bool isOffcut;

  double get areaMm2 => widthMm * heightMm * count;

  String get sizeLabel => '${_dim(widthMm)} × ${_dim(heightMm)} mm';

  static String _dim(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
}

/// The two axes a sheet is divided along, named for what they yield.
enum SheetCutAxis {
  /// Cuts running down the sheet, dividing its width into columns. The x axis.
  columns('columns', 'x'),

  /// Cuts running across, dividing its height into rows. The y axis.
  rows('rows', 'y');

  const SheetCutAxis(this.yields, this.letter);

  /// What a cut on this axis produces.
  final String yields;

  /// The axis letter, so the drawing and the operation panel agree.
  final String letter;
}

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
      outputKg +
      effectiveScrapKg +
      effectiveRejectionKg +
      effectiveWeightLossKg;

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
    this.sheetWidthInches = 0,
    this.sheetHeightInches = 0,
    this.sheetThicknessMm = 0,
    this.primaryAxis = SheetCutAxis.columns,
    this.bands = const <SheetCutGroup>[],
    this.subCuts = const <int, List<SheetCutGroup>>{},
    this.kerfMm = 0,
    this.edgeTrimMm = 0,
    this.plannedPartId,
    this.plannedPartName = '',
    this.faceUnit = 'in',
    this.gaugeUnit = 'mm',
  });

  /// The units the sheet's own measurements are read in, by symbol.
  ///
  /// Kept on the record so reopening it shows the numbers the way they were
  /// entered — a sheet typed in millimetres coming back as inches reads like
  /// someone changed it. Symbols rather than an enum of our own, so the record
  /// names a unit the whole system knows rather than one this screen invented.
  final String faceUnit;
  final String gaugeUnit;

  /// The part this plan is cutting, when it came from the catalogue rather than
  /// from typed sizes. Stamped so the record says what it was planning, and so
  /// a plan can be read back months later without guessing from the numbers.
  final int? plannedPartId;
  final String plannedPartName;

  /// What the blade itself eats on every cut.
  ///
  /// The reason a paper plan fails at the machine: thirty 40 mm strips fit
  /// across 1219 mm on paper, but a 3 mm shear turns twenty-nine of the gaps
  /// into swarf and you get twenty-eight. Zero means nobody has said yet, and
  /// the plan is arithmetic rather than a promise.
  final double kerfMm;

  /// Trim taken off every edge before anything is planned — the clamped strip,
  /// the mill edge, whatever the operator will not cut into. The sheet that was
  /// bought is not the sheet that can be used.
  final double edgeTrimMm;

  /// How the sheet is broken down, in the two levels a shear and a press work
  /// in: the sheet is sheared into strips along [primaryAxis], and then each
  /// strip can be taken to the press and blanked at its own pitch.
  ///
  /// The second level is per strip, not across the sheet, because that is what
  /// actually happens — one strip goes to one die, and the next strip may go to
  /// a different die entirely. Applying one row cut across every strip at once
  /// would describe a machine nobody owns.
  ///
  /// Sizes are millimetres whatever unit they were typed in: the sheet is
  /// bought in inches and cut in millimetres, and storing one unit is what keeps
  /// the arithmetic from drifting.
  final SheetCutAxis primaryAxis;
  final List<SheetCutGroup> bands;

  /// Sub-cuts keyed by the band they act on. [offcutRegion] keys the material
  /// left over after the last band, which is a region like any other and can be
  /// cut like one.
  final Map<int, List<SheetCutGroup>> subCuts;

  /// The key under which the leftover region's own cuts live.
  static const int offcutRegion = -1;

  /// The axis a strip is blanked along — the one the sheet was not sheared on.
  SheetCutAxis get secondaryAxis => primaryAxis == SheetCutAxis.columns
      ? SheetCutAxis.rows
      : SheetCutAxis.columns;

  /// Kept so callers that still think in two lists keep working. Columns and
  /// rows are now the primary split and its sub-cuts, not two peers.
  List<SheetCutGroup> get columnCuts =>
      primaryAxis == SheetCutAxis.columns ? bands : const <SheetCutGroup>[];
  List<SheetCutGroup> get rowCuts =>
      primaryAxis == SheetCutAxis.rows ? bands : const <SheetCutGroup>[];

  /// The sheet this record was measured off, as it comes in: width and height
  /// in inches because that is how stock is bought and quoted, thickness in
  /// millimetres because that is how it is gauged. Zero means not recorded —
  /// the weights stand on their own, the dimensions describe what they were
  /// weighed from.
  final double sheetWidthInches;
  final double sheetHeightInches;
  final double sheetThicknessMm;

  static const double _mmPerInch = 25.4;

  /// Which way the sheet is sheared first. Older records named two peer lists
  /// instead; whichever of them carried the plan becomes the primary split.
  static SheetCutAxis _readPrimaryAxis(Map<String, dynamic> json) {
    final named = json['primaryAxis']?.toString();
    if (named == 'rows') return SheetCutAxis.rows;
    if (named == 'columns') return SheetCutAxis.columns;
    final columns = _readLegacyCuts(json, 'columnCuts', 'vertical');
    if (columns.isNotEmpty) return SheetCutAxis.columns;
    final rows = _readLegacyCuts(json, 'rowCuts', 'horizontal');
    return rows.isNotEmpty ? SheetCutAxis.rows : SheetCutAxis.columns;
  }

  static List<SheetCutGroup> _readBands(Map<String, dynamic> json) {
    final bands = SheetCutGroup.listFromJson(json['bands']);
    if (bands.isNotEmpty) return bands;
    final columns = _readLegacyCuts(json, 'columnCuts', 'vertical');
    if (columns.isNotEmpty) return columns;
    return _readLegacyCuts(json, 'rowCuts', 'horizontal');
  }

  /// A record from the two-list release meant its row cuts to apply across
  /// every column. Read back as the sub-cut of each strip, which produces the
  /// same pieces it always did rather than quietly changing what it said.
  static Map<int, List<SheetCutGroup>> _readSubCuts(Map<String, dynamic> json) {
    final raw = json['subCuts'];
    if (raw is Map) {
      final out = <int, List<SheetCutGroup>>{};
      raw.forEach((key, value) {
        final region = int.tryParse('$key');
        if (region == null) return;
        final groups = SheetCutGroup.listFromJson(value);
        if (groups.isNotEmpty) out[region] = groups;
      });
      if (out.isNotEmpty) return out;
    }
    final columns = _readLegacyCuts(json, 'columnCuts', 'vertical');
    final rows = _readLegacyCuts(json, 'rowCuts', 'horizontal');
    if (columns.isEmpty || rows.isEmpty) {
      return const <int, List<SheetCutGroup>>{};
    }
    return <int, List<SheetCutGroup>>{
      for (var i = 0; i < columns.length; i++) i: rows,
    };
  }

  /// Reads a cut list, falling back to the single-band plan an earlier release
  /// stored. A record written then named one axis, one size and one count; that
  /// is simply a plan with one band, so it is read as one rather than dropped.
  static List<SheetCutGroup> _readLegacyCuts(
    Map<String, dynamic> json,
    String key,
    String legacyAxis,
  ) {
    final groups = SheetCutGroup.listFromJson(json[key]);
    if (groups.isNotEmpty) return groups;
    if (json['cutAxis']?.toString() != legacyAxis) {
      return const <SheetCutGroup>[];
    }
    final size = (json['cutSizeMm'] as num?)?.toDouble() ?? 0;
    final count = (json['cutCount'] as num?)?.toInt() ?? 0;
    if (size <= 0 || count <= 0) return const <SheetCutGroup>[];
    return <SheetCutGroup>[SheetCutGroup(sizeMm: size, count: count)];
  }

  double get sheetWidthMm => sheetWidthInches * _mmPerInch;
  double get sheetHeightMm => sheetHeightInches * _mmPerInch;

  /// The edge each axis divides, as bought.
  double axisSpanMm(SheetCutAxis axis) => switch (axis) {
    SheetCutAxis.columns => sheetWidthMm,
    SheetCutAxis.rows => sheetHeightMm,
  };

  /// The edge that can actually be planned on, once both trims are off it.
  double usableSpanMm(SheetCutAxis axis) {
    final span = axisSpanMm(axis);
    if (span <= 0) return 0;
    return math.max(0, span - edgeTrimMm * 2);
  }

  /// The cuts acting along one axis at the top level. The secondary axis has no
  /// single answer any more — each strip is blanked its own way — so this
  /// returns the sheet-wide split only.
  List<SheetCutGroup> cutsFor(SheetCutAxis axis) =>
      axis == primaryAxis ? bands : const <SheetCutGroup>[];

  /// The sub-cuts on one region: a band index, or [offcutRegion].
  List<SheetCutGroup> subCutsFor(int region) =>
      subCuts[region] ?? const <SheetCutGroup>[];

  /// Material the top-level split turns into strips.
  double plannedSpanMm(SheetCutAxis axis) =>
      cutsFor(axis).fold<double>(0, (total, group) => total + group.spanMm);

  /// How many strips the top-level split takes off this axis.
  int plannedPieces(SheetCutAxis axis) => cutsFor(
    axis,
  ).fold<int>(0, (total, group) => total + math.max(0, group.count));

  /// What [pieces] pieces of [materialMm] actually take out of the edge.
  ///
  /// Pieces in a row are separated by one fewer cuts than there are pieces —
  /// the outer two edges are the trim's business, not the blade's.
  double consumedMm(double materialMm, int pieces) =>
      pieces <= 0 ? 0 : materialMm + (pieces - 1) * math.max(0, kerfMm);

  double plannedConsumedMm(SheetCutAxis axis) =>
      consumedMm(plannedSpanMm(axis), plannedPieces(axis));

  double kerfLossMm(SheetCutAxis axis) =>
      plannedConsumedMm(axis) - plannedSpanMm(axis);

  double remainderMm(SheetCutAxis axis) {
    final usable = usableSpanMm(axis);
    if (usable <= 0) return 0;
    return math.max(0, usable - plannedConsumedMm(axis));
  }

  double overrunMm(SheetCutAxis axis) {
    final usable = usableSpanMm(axis);
    if (usable <= 0) return 0;
    // A hair over is not an overrun: 96 in is 2438.3999999999996 mm, and eight
    // bands of exactly one eighth of it must still read as fitting.
    final over = plannedConsumedMm(axis) - usable;
    return over > 0.001 ? over : 0;
  }

  bool overruns(SheetCutAxis axis) => overrunMm(axis) > 0;

  /// How many more pieces of [sizeMm] a region could still take.
  ///
  /// [region] is a band index or [offcutRegion] to ask about a strip's own
  /// sub-cuts; omit it to ask about the sheet-wide split. Solves
  /// `otherMaterial + n·size + (otherPieces + n − 1)·kerf ≤ free`, which also
  /// covers an empty region: the first piece costs no cut of its own.
  int fitsRemaining(
    SheetCutAxis axis,
    double sizeMm, {
    int ignoreIndex = -1,
    int? region,
  }) {
    if (sizeMm <= 0) return 0;
    final free = region == null
        ? usableSpanMm(axis)
        : regionExtentMm(region, axis);
    if (free <= 0) return 0;
    final kerf = math.max(0, kerfMm);
    final groups = region == null ? cutsFor(axis) : subCutsFor(region);
    var otherMaterial = 0.0;
    var otherPieces = 0;
    for (var i = 0; i < groups.length; i++) {
      if (i == ignoreIndex) continue;
      otherMaterial += groups[i].spanMm;
      otherPieces += math.max(0, groups[i].count);
    }
    final room = free - otherMaterial - (otherPieces - 1) * kerf;
    if (room <= 0) return 0;
    final exact = room / (sizeMm + kerf);
    final whole = exact.roundToDouble();
    if ((exact - whole).abs() < 1e-6) return math.max(0, whole.toInt());
    return math.max(0, exact.floor());
  }

  /// How long a region is along [axis].
  ///
  /// Along the primary axis a strip is as wide as its own band; along the
  /// secondary it runs the full usable length, because shearing a strip off the
  /// sheet does not shorten it.
  double regionExtentMm(int region, SheetCutAxis axis) {
    if (axis == secondaryAxis) return usableSpanMm(secondaryAxis);
    if (region == offcutRegion) return remainderMm(primaryAxis);
    final spans = bandSpansMm(primaryAxis);
    for (final span in spans) {
      if (span.index == region) return span.sizeMm;
    }
    return 0;
  }

  /// Every region a cut could act on: each strip, then what is left over.
  ///
  /// This is the list the panel has to ask from — "where does this cut go?" is
  /// only answerable if the regions have names.
  List<SheetRegion> get regions {
    final out = <SheetRegion>[];
    for (final span in bandSpansMm(primaryAxis)) {
      out.add(
        SheetRegion(
          index: span.index,
          copies: span.count,
          widthMm: primaryAxis == SheetCutAxis.columns
              ? span.sizeMm
              : usableSpanMm(SheetCutAxis.columns),
          heightMm: primaryAxis == SheetCutAxis.columns
              ? usableSpanMm(SheetCutAxis.rows)
              : span.sizeMm,
        ),
      );
    }
    final left = remainderMm(primaryAxis);
    if (left > 0.05) {
      out.add(
        SheetRegion(
          index: offcutRegion,
          copies: 1,
          widthMm: primaryAxis == SheetCutAxis.columns
              ? left
              : usableSpanMm(SheetCutAxis.columns),
          heightMm: primaryAxis == SheetCutAxis.columns
              ? usableSpanMm(SheetCutAxis.rows)
              : left,
        ),
      );
    }
    return out;
  }

  /// What the plan actually produces: one entry per distinct piece size.
  ///
  /// A strip with no cuts of its own leaves as a strip. A strip that is blanked
  /// leaves as its blanks, plus whatever tail no blank reached. Never a single
  /// total, because bands of different sizes are different parts and adding
  /// them together says nothing.
  List<SheetYield> get yields {
    final out = <SheetYield>[];
    final gap = math.max(0, kerfMm);
    for (final region in regions) {
      final full = region.extentAlong(secondaryAxis);
      final subs = subCutsFor(
        region.index,
      ).where((group) => group.isComplete).toList();

      if (subs.isEmpty || full <= 0) {
        out.add(
          SheetYield(
            label: region.label,
            widthMm: region.widthMm,
            heightMm: region.heightMm,
            count: region.copies,
            colourIndex: region.isOffcut ? -1 : region.index,
            isOffcut: region.isOffcut,
          ),
        );
        continue;
      }

      // The same walk the bands take, inside one region: each piece, then the
      // gap before the next.
      var at = 0.0;
      var first = true;
      for (final group in subs) {
        var placed = 0;
        for (var i = 0; i < group.count; i++) {
          final step = (first ? 0.0 : gap) + group.sizeMm;
          if (at + step > full + 0.001) break;
          at += step;
          first = false;
          placed++;
        }
        if (placed <= 0) continue;
        out.add(
          SheetYield(
            label: '${region.label} blank',
            widthMm: primaryAxis == SheetCutAxis.columns
                ? region.widthMm
                : group.sizeMm,
            heightMm: primaryAxis == SheetCutAxis.columns
                ? group.sizeMm
                : region.heightMm,
            count: placed * region.copies,
            colourIndex: region.isOffcut ? -1 : region.index,
            isOffcut: false,
          ),
        );
      }

      final tail = full - at;
      if (tail > 0.05) {
        out.add(
          SheetYield(
            label: '${region.label} tail',
            widthMm: primaryAxis == SheetCutAxis.columns
                ? region.widthMm
                : tail,
            heightMm: primaryAxis == SheetCutAxis.columns
                ? tail
                : region.heightMm,
            count: region.copies,
            colourIndex: -1,
            isOffcut: true,
          ),
        );
      }
    }
    return _merged(out);
  }

  /// Folds together entries that are the same piece from the same region.
  ///
  /// Two bands in one strip cut at the same size make one part, not two kinds
  /// of part — listing them twice reads as a mistake and makes the reader add
  /// up rows that were never separate. Only within a region: a 12 mm piece off
  /// Strip 1 and one off Strip 2 stay apart, because their strips do.
  static List<SheetYield> _merged(List<SheetYield> entries) {
    final out = <SheetYield>[];
    for (final entry in entries) {
      final at = out.indexWhere(
        (kept) =>
            kept.label == entry.label &&
            kept.isOffcut == entry.isOffcut &&
            (kept.widthMm - entry.widthMm).abs() < 0.01 &&
            (kept.heightMm - entry.heightMm).abs() < 0.01,
      );
      if (at == -1) {
        out.add(entry);
        continue;
      }
      final kept = out[at];
      out[at] = SheetYield(
        label: kept.label,
        widthMm: kept.widthMm,
        heightMm: kept.heightMm,
        count: kept.count + entry.count,
        colourIndex: kept.colourIndex,
        isOffcut: kept.isOffcut,
      );
    }
    return out;
  }

  /// Whether either axis carries a plan worth drawing.  /// Whether either axis carries a plan worth drawing.  /// Whether either axis carries a plan worth drawing.
  bool get hasCutPlan =>
      bands.any((group) => group.isComplete) ||
      subCuts.values.any((list) => list.any((group) => group.isComplete));

  /// Parts the plan makes, offcut excluded. Not a product of two axes — that
  /// arithmetic only ever held when there was one band each way.
  int get pieceCount => yields
      .where((entry) => !entry.isOffcut)
      .fold<int>(0, (total, entry) => total + entry.count);

  /// Where every score line falls along an axis, measured from the sheet's own
  /// edge in millimetres — the trim first, then each piece and the blade after
  /// it. What the drawing draws and what the operator's cut list reads.
  List<double> cutPositionsMm(SheetCutAxis axis) {
    final usable = usableSpanMm(axis);
    if (usable <= 0) return const <double>[];
    final kerf = math.max(0, kerfMm);
    final limit = edgeTrimMm + usable;
    final positions = <double>[];
    var at = edgeTrimMm;
    var first = true;
    for (final group in cutsFor(axis)) {
      if (!group.isComplete) continue;
      for (var i = 0; i < group.count; i++) {
        if (!first) at += kerf;
        first = false;
        at += group.sizeMm;
        if (at > limit + 0.001) return positions;
        positions.add(at);
      }
    }
    return positions;
  }

  /// Where each band sits along an axis, in order, clipped to what fits.
  ///
  /// The same walk [cutPositionsMm] makes, kept as regions rather than points:
  /// the drawing needs to know which stretch of the sheet belongs to which
  /// band, because that is the only way two bands can be told apart on it.
  List<SheetBandSpan> bandSpansMm(SheetCutAxis axis) {
    final usable = usableSpanMm(axis);
    if (usable <= 0) return const <SheetBandSpan>[];
    final gap = math.max(0, kerfMm);
    final limit = edgeTrimMm + usable;
    final spans = <SheetBandSpan>[];
    var at = edgeTrimMm;
    var first = true;
    var index = -1;
    for (final group in cutsFor(axis)) {
      index++;
      if (!group.isComplete) continue;
      final start = at;
      var placed = 0;
      for (var i = 0; i < group.count; i++) {
        final step = (first ? 0.0 : gap) + group.sizeMm;
        if (at + step > limit + 0.001) break;
        at += step;
        first = false;
        placed++;
      }
      if (placed > 0) {
        spans.add(
          SheetBandSpan(
            index: index,
            startMm: start,
            endMm: at,
            sizeMm: group.sizeMm,
            count: placed,
          ),
        );
      }
      if (at >= limit - 0.001) break;
    }
    return spans;
  }

  /// Where the plan stops along an axis, from the sheet's edge. Everything from
  /// here to the far trim is offcut.
  double planEndMm(SheetCutAxis axis) {
    final positions = cutPositionsMm(axis);
    return positions.isEmpty ? edgeTrimMm : positions.last;
  }

  /// The share of the usable edge that leaves as parts rather than as swarf or
  /// offcut. The number the floor is actually judged on.
  double yieldPercent(SheetCutAxis axis) {
    final usable = usableSpanMm(axis);
    if (usable <= 0) return 0;
    return (plannedSpanMm(axis) / usable * 100).clamp(0, 100);
  }

  /// Yield over the whole sheet, both axes and the trim included. A plan can
  /// look tidy on each edge and still waste a third of what was bought.
  double get sheetYieldPercent {
    final bought = sheetWidthMm * sheetHeightMm;
    if (bought <= 0) return 0;
    final across = plannedSpanMm(SheetCutAxis.columns);
    final down = plannedSpanMm(SheetCutAxis.rows);
    final parts =
        (across > 0 ? across : usableSpanMm(SheetCutAxis.columns)) *
        (down > 0 ? down : usableSpanMm(SheetCutAxis.rows));
    return (parts / bought * 100).clamp(0, 100);
  }

  /// The plan this sheet yields for [part]: strips the width of the blank, and
  /// blanks down each strip the height of it, as many of each as fit.
  ///
  /// This is the whole of guillotine nesting for one part — shear the sheet into
  /// strips of the blank's width, then punch down the strip at the blank's
  /// pitch. Replaces both axes rather than adding to them, because a plan for a
  /// part is a different plan, not an extra band on the old one.
  PenPaperBaseline planFor(SheetPart part) {
    if (!part.isPlannable) return this;
    // Against an empty plan: what already sat on the sheet belonged to whatever
    // was being cut before.
    final cleared = copyWith(
      primaryAxis: SheetCutAxis.columns,
      bands: const <SheetCutGroup>[],
      subCuts: const <int, List<SheetCutGroup>>{},
    );
    final across = cleared.fitsRemaining(SheetCutAxis.columns, part.widthMm);
    if (across <= 0) {
      return cleared.copyWith(
        plannedPartId: part.id,
        plannedPartName: part.name,
      );
    }
    // Shear into strips one blank wide, then blank down each strip at the
    // blank's own pitch — the two levels, for one part.
    final withStrips = cleared.copyWith(
      plannedPartId: part.id,
      plannedPartName: part.name,
      bands: <SheetCutGroup>[
        SheetCutGroup(sizeMm: part.widthMm, count: across),
      ],
    );
    final down = withStrips.fitsRemaining(
      SheetCutAxis.rows,
      part.heightMm,
      region: 0,
    );
    if (down <= 0) return withStrips;
    return withStrips.copyWith(
      subCuts: <int, List<SheetCutGroup>>{
        0: <SheetCutGroup>[SheetCutGroup(sizeMm: part.heightMm, count: down)],
      },
    );
  }

  /// The plan without the empty bands the editor keeps around.
  ///
  /// A blank row waits at the end of every region so that typing is what adds a
  /// band, and while editing that row has to stay in step with the model or the
  /// rows would renumber under the cursor. It has no business being saved
  /// though: an empty band is not a cut, and left in it would accumulate one
  /// per edit.
  PenPaperBaseline get withoutEmptyBands {
    bool real(SheetCutGroup group) => group.sizeMm > 0 || group.count > 0;
    final cleanedSubs = <int, List<SheetCutGroup>>{};
    for (final entry in subCuts.entries) {
      final kept = entry.value.where(real).toList(growable: false);
      if (kept.isNotEmpty) cleanedSubs[entry.key] = kept;
    }
    return copyWith(
      bands: bands.where(real).toList(growable: false),
      subCuts: cleanedSubs,
    );
  }

  /// A band's size in inches, which is the unit the sheet itself is drawn in.
  double sizeInInches(double sizeMm) => sizeMm / _mmPerInch;

  /// Whether a sheet has been described at all.
  bool get hasSheetDimensions =>
      sheetWidthInches > 0 || sheetHeightInches > 0 || sheetThicknessMm > 0;

  /// Face area of one sheet in square inches, zero until both sides are given.
  double get sheetAreaSqInches => sheetWidthInches > 0 && sheetHeightInches > 0
      ? sheetWidthInches * sheetHeightInches
      : 0;

  /// Volume of one sheet in cubic centimetres. Thickness is in mm and the face
  /// in inches, so the conversion happens here rather than at each call site.
  double get sheetVolumeCc {
    if (sheetAreaSqInches <= 0 || sheetThicknessMm <= 0) return 0;
    const sqInchToSqCm = 6.4516;
    return sheetAreaSqInches * sqInchToSqCm * (sheetThicknessMm / 10.0);
  }

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
  double get totalInputKg => stageReconciliations.isNotEmpty
      ? stageReconciliations.first.inputKg
      : 0.0;

  /// Overall pipeline final output kg (good output of final stage or whole pipeline).
  double get totalFinalOutputKg => stageReconciliations.isNotEmpty
      ? stageReconciliations.last.outputKg
      : 0.0;

  /// Overall pipeline material recovery yield %.
  double get overallYieldPercentage => totalInputKg > 0
      ? ((totalFinalOutputKg / totalInputKg) * 100.0).clamp(0.0, 100.0)
      : 0.0;

  /// One reconciliation row per pipeline stage node, named and keyed from the
  /// node itself so a renamed stage carries its recorded weights with it.
  /// Falls back to generic names only when the pipeline has no nodes to read.
  static PenPaperBaseline createDefaultForStages([
    List<PipelineStageNode>? stageNodes,
  ]) {
    final nodes = (stageNodes != null && stageNodes.isNotEmpty)
        ? stageNodes
        : const <PipelineStageNode>[
            PipelineStageNode(id: 'stage-1', name: 'Raw Preparation'),
            PipelineStageNode(id: 'stage-2', name: 'Material Shaping'),
            PipelineStageNode(id: 'stage-3', name: 'Final Polish'),
          ];
    final stages = nodes;

    double currentInput = 100.0;
    final list = <PenPaperStageReconciliation>[];

    for (int i = 0; i < stages.length; i++) {
      final name = stages[i].name;
      final output = (currentInput * 0.90).roundToDouble();
      final scrap = (currentInput * 0.05).roundToDouble();
      final rejection = (currentInput * 0.03).roundToDouble();
      final loss = (currentInput * 0.02).roundToDouble();

      list.add(
        PenPaperStageReconciliation(
          // The node's own id, so the row survives a rename on the board.
          stageId: stages[i].id,
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
    double? sheetWidthInches,
    double? sheetHeightInches,
    double? sheetThicknessMm,
    SheetCutAxis? primaryAxis,
    List<SheetCutGroup>? bands,
    Map<int, List<SheetCutGroup>>? subCuts,
    double? kerfMm,
    double? edgeTrimMm,
    int? plannedPartId,
    String? plannedPartName,
    String? faceUnit,
    String? gaugeUnit,
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
      sheetWidthInches: sheetWidthInches ?? this.sheetWidthInches,
      sheetHeightInches: sheetHeightInches ?? this.sheetHeightInches,
      sheetThicknessMm: sheetThicknessMm ?? this.sheetThicknessMm,
      primaryAxis: primaryAxis ?? this.primaryAxis,
      bands: bands ?? this.bands,
      subCuts: subCuts ?? this.subCuts,
      kerfMm: kerfMm ?? this.kerfMm,
      edgeTrimMm: edgeTrimMm ?? this.edgeTrimMm,
      plannedPartId: plannedPartId ?? this.plannedPartId,
      plannedPartName: plannedPartName ?? this.plannedPartName,
      faceUnit: faceUnit ?? this.faceUnit,
      gaugeUnit: gaugeUnit ?? this.gaugeUnit,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'isGranular': isGranular,
      'keyEfficiencyBenchmark': keyEfficiencyBenchmark,
      'baselineOutputRate': baselineOutputRate,
      'baselineScrapRate': baselineScrapRate,
      'stageReconciliations': stageReconciliations
          .map((e) => e.toJson())
          .toList(),
      'notes': notes,
      'pipelineId': pipelineId,
      'pipelineName': pipelineName,
      'sheetWidthInches': sheetWidthInches,
      'sheetHeightInches': sheetHeightInches,
      'sheetThicknessMm': sheetThicknessMm,
      'primaryAxis': primaryAxis.name,
      'bands': bands.map((group) => group.toJson()).toList(),
      'subCuts': subCuts.map(
        (region, groups) =>
            MapEntry('$region', groups.map((group) => group.toJson()).toList()),
      ),
      'kerfMm': kerfMm,
      'edgeTrimMm': edgeTrimMm,
      'plannedPartId': plannedPartId,
      'plannedPartName': plannedPartName,
      'faceUnit': faceUnit,
      'gaugeUnit': gaugeUnit,
    };
  }

  factory PenPaperBaseline.fromJson(Map<String, dynamic> json) {
    final stages = (json['stageReconciliations'] as List<dynamic>? ?? const [])
        .map(
          (e) =>
              PenPaperStageReconciliation.fromJson(e as Map<String, dynamic>),
        )
        .toList();

    return PenPaperBaseline(
      isGranular: json['isGranular'] as bool? ?? false,
      keyEfficiencyBenchmark:
          (json['keyEfficiencyBenchmark'] as num?)?.toDouble() ?? 88.0,
      baselineOutputRate:
          (json['baselineOutputRate'] as num?)?.toDouble() ?? 12.0,
      baselineScrapRate: (json['baselineScrapRate'] as num?)?.toDouble() ?? 4.0,
      stageReconciliations: stages.isNotEmpty
          ? stages
          : createDefaultForStages().stageReconciliations,
      notes: json['notes'] as String? ?? '',
      pipelineId: json['pipelineId'] as String?,
      pipelineName: json['pipelineName'] as String? ?? '',
      sheetWidthInches: (json['sheetWidthInches'] as num?)?.toDouble() ?? 0,
      sheetHeightInches: (json['sheetHeightInches'] as num?)?.toDouble() ?? 0,
      sheetThicknessMm: (json['sheetThicknessMm'] as num?)?.toDouble() ?? 0,
      primaryAxis: _readPrimaryAxis(json),
      bands: _readBands(json),
      subCuts: _readSubCuts(json),
      kerfMm: (json['kerfMm'] as num?)?.toDouble() ?? 0,
      edgeTrimMm: (json['edgeTrimMm'] as num?)?.toDouble() ?? 0,
      plannedPartId: (json['plannedPartId'] as num?)?.toInt(),
      plannedPartName: json['plannedPartName']?.toString() ?? '',
      faceUnit: lengthUnitBySymbol(
        json['faceUnit']?.toString(),
        fallback: 'in',
      ).symbol,
      gaugeUnit: lengthUnitBySymbol(json['gaugeUnit']?.toString()).symbol,
    );
  }
}

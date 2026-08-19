import 'package:flutter/foundation.dart';

import '../../production_pipelines/domain/pen_paper_baseline.dart';

/// Which step of the resolution answered for a (variant, pipeline) pair.
///
/// A pipeline is shared, so it carries as many Master Data records as there are
/// variants running through it. Asking "what is the baseline for this variant on
/// this pipeline?" walks four steps, and which one answered is what the user
/// needs to see — a measured record and an inherited one are not the same claim.
enum MasterDataSource {
  /// Recorded against this exact variant-and-pipeline pair.
  pair,

  /// The variant's own record, applied to this pipeline.
  item,

  /// The record on the pipeline that makes this variant as output.
  pipeline,

  /// Nothing matched, so this data is new.
  fresh,
}

/// How the stored record came to be, which outlives the lookup that produced it.
enum MasterDataOrigin { manual, item, pipeline, fresh }

MasterDataSource _sourceFrom(String? raw) {
  switch (raw) {
    case 'pair':
      return MasterDataSource.pair;
    case 'item':
      return MasterDataSource.item;
    case 'pipeline':
      return MasterDataSource.pipeline;
    default:
      return MasterDataSource.fresh;
  }
}

MasterDataOrigin _originFrom(String? raw) {
  switch (raw) {
    case 'item':
      return MasterDataOrigin.item;
    case 'pipeline':
      return MasterDataOrigin.pipeline;
    case 'new':
      return MasterDataOrigin.fresh;
    default:
      return MasterDataOrigin.manual;
  }
}

String originToWire(MasterDataOrigin origin) {
  switch (origin) {
    case MasterDataOrigin.item:
      return 'item';
    case MasterDataOrigin.pipeline:
      return 'pipeline';
    case MasterDataOrigin.fresh:
      return 'new';
    case MasterDataOrigin.manual:
      return 'manual';
  }
}

/// The answer to "what is the baseline for this variant on this pipeline?"
@immutable
class MasterDataResolution {
  const MasterDataResolution({
    required this.itemId,
    required this.pipelineId,
    required this.matched,
    required this.source,
    required this.origin,
    required this.baseline,
    this.persisted = false,
  });

  factory MasterDataResolution.fromJson(Map<String, dynamic> json) {
    return MasterDataResolution(
      itemId: (json['itemId'] as num?)?.toInt() ?? 0,
      pipelineId: json['pipelineId']?.toString() ?? '',
      matched: json['matched'] == true,
      source: _sourceFrom(json['source']?.toString()),
      origin: _originFrom(json['origin']?.toString()),
      baseline: PenPaperBaseline.fromJson(
        (json['baseline'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      persisted: json['persisted'] == true,
    );
  }

  final int itemId;
  final String pipelineId;

  /// False only for the fourth step, where new data is created.
  final bool matched;
  final MasterDataSource source;
  final MasterDataOrigin origin;
  final PenPaperBaseline baseline;

  /// Whether the resolution was written onto the pair, so the next lookup is an
  /// exact hit rather than another inheritance.
  final bool persisted;

  /// One line saying which step answered — the distinction, in the user's words.
  String describe({String pipelineName = ''}) {
    final on = pipelineName.trim().isEmpty ? 'this pipeline' : pipelineName;
    switch (source) {
      case MasterDataSource.pair:
        return 'Measured against $on';
      case MasterDataSource.item:
        return 'Matched from this variant\'s own record';
      case MasterDataSource.pipeline:
        return 'Matched from $on';
      case MasterDataSource.fresh:
        return 'New data for this variant on $on';
    }
  }
}

/// One stored Master Data record: a baseline pinned to a (variant, pipeline).
@immutable
class ItemMasterDataRecord {
  const ItemMasterDataRecord({
    required this.id,
    required this.itemId,
    required this.pipelineId,
    required this.baseline,
    this.pipelineName = '',
    this.itemDisplayName = '',
    this.origin = MasterDataOrigin.manual,
    this.isVariant = false,
    this.inputKg = 0,
    this.outputKg = 0,
    this.inputQty = 0,
    this.outputQty = 0,
    this.yieldPercent = 0,
    this.updatedAt,
  });

  factory ItemMasterDataRecord.fromJson(Map<String, dynamic> json) {
    return ItemMasterDataRecord(
      id: (json['id'] as num?)?.toInt() ?? 0,
      itemId: (json['itemId'] as num?)?.toInt() ?? 0,
      pipelineId: json['pipelineId']?.toString() ?? '',
      pipelineName: json['pipelineName']?.toString() ?? '',
      itemDisplayName:
          json['itemDisplayName']?.toString() ??
          json['itemName']?.toString() ??
          '',
      baseline: PenPaperBaseline.fromJson(
        (json['baseline'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      origin: _originFrom(json['origin']?.toString()),
      isVariant: json['isVariant'] == true,
      inputKg: (json['inputKg'] as num?)?.toDouble() ?? 0,
      outputKg: (json['outputKg'] as num?)?.toDouble() ?? 0,
      inputQty: (json['inputQty'] as num?)?.toDouble() ?? 0,
      outputQty: (json['outputQty'] as num?)?.toDouble() ?? 0,
      yieldPercent: (json['yieldPercent'] as num?)?.toDouble() ?? 0,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }

  final int id;
  final int itemId;
  final String pipelineId;
  final String pipelineName;
  final String itemDisplayName;
  final PenPaperBaseline baseline;
  final MasterDataOrigin origin;
  final bool isVariant;

  /// The four numbers the roster compares on, totalled by the server so every
  /// caller reads a stage-by-stage record the same way.
  final double inputKg;
  final double outputKg;
  final double inputQty;
  final double outputQty;
  final double yieldPercent;
  final DateTime? updatedAt;

  bool get isMeasured => origin == MasterDataOrigin.manual;
  bool get isInherited =>
      origin == MasterDataOrigin.item || origin == MasterDataOrigin.pipeline;
  bool get isBlank => origin == MasterDataOrigin.fresh;
}

/// Every variant's Master Data on one pipeline — the insight view. A pipeline
/// with twenty variants has twenty records, and the counts say how many were
/// actually measured against it rather than inherited or left blank.
@immutable
class PipelineMasterDataRoster {
  const PipelineMasterDataRoster({
    required this.pipelineId,
    required this.entries,
    this.measuredCount = 0,
    this.inheritedCount = 0,
    this.blankCount = 0,
  });

  factory PipelineMasterDataRoster.fromJson(Map<String, dynamic> json) {
    return PipelineMasterDataRoster(
      pipelineId: json['pipelineId']?.toString() ?? '',
      entries:
          (json['entries'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map>()
              .map(
                (entry) =>
                    ItemMasterDataRecord.fromJson(entry.cast<String, dynamic>()),
              )
              .toList(growable: false),
      measuredCount: (json['measuredCount'] as num?)?.toInt() ?? 0,
      inheritedCount: (json['inheritedCount'] as num?)?.toInt() ?? 0,
      blankCount: (json['blankCount'] as num?)?.toInt() ?? 0,
    );
  }

  final String pipelineId;
  final List<ItemMasterDataRecord> entries;
  final int measuredCount;
  final int inheritedCount;
  final int blankCount;

  int get count => entries.length;

  /// Average yield across the records that were actually measured. Inherited and
  /// blank records are excluded: averaging in a baseline copied from somewhere
  /// else would quote the same numbers twice.
  double get measuredYieldPercent {
    final measured = entries.where((entry) => entry.isMeasured).toList();
    if (measured.isEmpty) return 0;
    final total = measured.fold<double>(
      0,
      (sum, entry) => sum + entry.yieldPercent,
    );
    return total / measured.length;
  }
}

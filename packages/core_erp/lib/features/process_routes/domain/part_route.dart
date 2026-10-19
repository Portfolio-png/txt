import 'process_stage.dart';

/// Where a route stands. The three words are the schema's CHECK constraint.
enum RouteStatus {
  draft,
  active,
  retired;

  static RouteStatus parse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'active':
        return RouteStatus.active;
      case 'retired':
        return RouteStatus.retired;
      default:
        return RouteStatus.draft;
    }
  }

  String get wire => name;
}

/// One step of a route: a stage, at a position, optionally naming its tooling.
///
/// `seq` is assigned by the server from list order, so it is read-only here —
/// a view reorders the LIST and the numbering follows, which is what keeps it
/// contiguous by construction.
class RouteStep {
  const RouteStep({
    required this.stageId,
    this.seq = 0,
    this.stageCode = '',
    this.stageName = '',
    this.notes = '',
    this.machineId,
    this.dieId,
  });

  final int stageId;
  final int seq;
  final String stageCode;
  final String stageName;
  final String notes;
  final int? machineId;
  final int? dieId;

  RouteStep copyWith({
    String? notes,
    int? machineId,
    int? dieId,
    bool clearMachine = false,
    bool clearDie = false,
  }) {
    return RouteStep(
      stageId: stageId,
      seq: seq,
      stageCode: stageCode,
      stageName: stageName,
      notes: notes ?? this.notes,
      machineId: clearMachine ? null : (machineId ?? this.machineId),
      dieId: clearDie ? null : (dieId ?? this.dieId),
    );
  }

  static RouteStep? fromJson(Map<String, dynamic> json) {
    final stageId = (json['stage_id'] ?? json['stageId']) as Object?;
    final id = stageId is num ? stageId.toInt() : int.tryParse('$stageId');
    if (id == null) return null;
    return RouteStep(
      stageId: id,
      seq: (json['seq'] as num?)?.toInt() ?? 0,
      stageCode: (json['stage_code'] ?? json['stageCode']) as String? ?? '',
      stageName: (json['stage_name'] ?? json['stageName']) as String? ?? '',
      notes: (json['notes'] as String?) ?? '',
      machineId: _id(json['machine_id'] ?? json['machineId']),
      dieId: _id(json['die_id'] ?? json['dieId']),
    );
  }

  static int? _id(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  /// The payload the doc specifies: a stage id, plus what this step adds to it.
  /// `seq` is deliberately NOT sent — the server numbers from list order, so
  /// two sources of ordering truth never arise.
  Map<String, dynamic> toJson() => {
        'stageId': stageId,
        if (notes.trim().isNotEmpty) 'notes': notes.trim(),
        if (machineId != null) 'machineId': machineId,
        if (dieId != null) 'dieId': dieId,
      };

  /// What to call this step when the stage master was not loaded alongside it.
  String labelWith(List<ProcessStage> stages) {
    if (stageName.trim().isNotEmpty) return stageName.trim();
    for (final stage in stages) {
      if (stage.id == stageId) return stage.name;
    }
    return 'Stage $stageId';
  }
}

/// One version of one part's route.
class PartRoute {
  const PartRoute({
    required this.id,
    required this.partId,
    required this.version,
    required this.status,
    this.note = '',
    this.steps = const [],
  });

  final int id;
  final int partId;
  final int version;
  final RouteStatus status;
  final String note;
  final List<RouteStep> steps;

  bool get isActive => status == RouteStatus.active;

  /// Whether a change to this route needs a new version declared rather than
  /// a plain save. Mirrors the backend rule; the server still decides.
  bool get isLocked => status == RouteStatus.active;

  static PartRoute? fromJson(Map<String, dynamic> json) {
    final id = (json['id'] as num?)?.toInt();
    if (id == null) return null;
    final rawSteps = (json['steps'] as List?) ?? const [];
    return PartRoute(
      id: id,
      partId: ((json['part_id'] ?? json['partId']) as num?)?.toInt() ?? 0,
      version: (json['version'] as num?)?.toInt() ?? 1,
      status: RouteStatus.parse(json['status'] as String?),
      note: (json['note'] as String?) ?? '',
      steps: [
        for (final entry in rawSteps)
          if (entry is Map<String, dynamic>) ?RouteStep.fromJson(entry),
      ],
    );
  }

  @override
  String toString() => 'PartRoute(#$id v$version ${status.wire})';
}

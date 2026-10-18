import 'machine_capability.dart';

enum MachineStatus { active, maintenance, decommissioned }

enum CustomPropertyType { text, numeric, dropdown }

class CustomProperty {
  const CustomProperty({
    required this.key,
    required this.value,
    this.type = CustomPropertyType.text,
    this.unitId,
    this.options = const [],
  });

  final String key;
  final String value;
  final CustomPropertyType type;
  final int? unitId;
  final List<String> options;

  CustomProperty copyWith({
    String? key,
    String? value,
    CustomPropertyType? type,
    int? unitId,
    List<String>? options,
  }) {
    return CustomProperty(
      key: key ?? this.key,
      value: value ?? this.value,
      type: type ?? this.type,
      unitId: unitId ?? this.unitId,
      options: options ?? this.options,
    );
  }
}

const Object _absent = Object();

class Machine {
  const Machine({
    required this.id,
    required this.name,
    required this.assetId,
    this.barcode = '',
    required this.primaryPhotoUrl,
    required this.groupId,
    required this.makeModel,
    required this.serialNumber,
    this.location,
    this.installationDate,
    required this.status,
    this.reportOutputPerHour,
    this.setupMinutes,
    this.laborCount,
    this.powerKw,
    this.machineMake = '',
    this.manufacturedYear,
    this.feederMake = '',
    this.runningHours,
    this.strokesPerMinute,
    this.capacityKind = '',
    this.capacityKgf,
    this.dieFeedType = '',
    this.reportNotes = '',
    this.customProperties = const [],
    this.capabilities = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String assetId;

  /// Unique system-generated scan code for the machine (falls back to [assetId]
  /// server-side when unset).
  final String barcode;
  final String primaryPhotoUrl;
  final int? groupId;
  final String makeModel;
  final String serialNumber;
  final String? location;
  final DateTime? installationDate;
  final MachineStatus status;
  final double? reportOutputPerHour;
  final double? setupMinutes;
  final double? laborCount;
  final double? powerKw;
  // --- the machine sheet (migrations/049) ------------------------------------

  /// Who built it. Its own column rather than [makeModel], which the editor
  /// treats as legacy and blanks on every save.
  final String machineMake;

  /// The year it was built — a year, not a date, because that is all anyone
  /// records. Distinct from [installationDate], which is when it arrived here.
  final int? manufacturedYear;

  /// The make of the feeder attached to it. NOT the pipeline sense of the
  /// word, which is an upstream node in a graph.
  final String feederMake;

  /// The latest meter reading, and the rated strokes per minute.
  final int? runningHours;
  final int? strokesPerMinute;

  /// `''` | `rated` | `free_hand`. Stored rather than inferred: a bench with
  /// no rated tonnage is a fact, and a blank is the absence of one.
  final String capacityKind;

  /// An integer count of kilograms-force, per the units contract.
  final int? capacityKgf;

  /// What tooling it takes — Manual, Semi Prog, Progressive. NOT a die's own
  /// type, which is Cutting or Bending.
  final String dieFeedType;

  final String reportNotes;
  final List<CustomProperty> customProperties;
  final List<MachineCapability> capabilities;
  final DateTime createdAt;
  final DateTime updatedAt;

  Machine copyWith({
    String? id,
    String? name,
    String? assetId,
    String? barcode,
    String? primaryPhotoUrl,
    int? groupId,
    String? makeModel,
    String? serialNumber,
    Object? location = _absent,
    DateTime? installationDate,
    MachineStatus? status,
    Object? reportOutputPerHour = _absent,
    Object? setupMinutes = _absent,
    Object? laborCount = _absent,
    Object? powerKw = _absent,
    String? machineMake,
    Object? manufacturedYear = _absent,
    String? feederMake,
    Object? runningHours = _absent,
    Object? strokesPerMinute = _absent,
    String? capacityKind,
    Object? capacityKgf = _absent,
    String? dieFeedType,
    String? reportNotes,
    List<CustomProperty>? customProperties,
    List<MachineCapability>? capabilities,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Machine(
      id: id ?? this.id,
      name: name ?? this.name,
      assetId: assetId ?? this.assetId,
      barcode: barcode ?? this.barcode,
      primaryPhotoUrl: primaryPhotoUrl ?? this.primaryPhotoUrl,
      groupId: groupId ?? this.groupId,
      makeModel: makeModel ?? this.makeModel,
      serialNumber: serialNumber ?? this.serialNumber,
      location: location == _absent ? this.location : location as String?,
      installationDate: installationDate ?? this.installationDate,
      status: status ?? this.status,
      reportOutputPerHour: reportOutputPerHour == _absent
          ? this.reportOutputPerHour
          : reportOutputPerHour as double?,
      setupMinutes: setupMinutes == _absent
          ? this.setupMinutes
          : setupMinutes as double?,
      laborCount: laborCount == _absent
          ? this.laborCount
          : laborCount as double?,
      powerKw: powerKw == _absent ? this.powerKw : powerKw as double?,
      machineMake: machineMake ?? this.machineMake,
      manufacturedYear: manufacturedYear == _absent
          ? this.manufacturedYear
          : manufacturedYear as int?,
      feederMake: feederMake ?? this.feederMake,
      runningHours: runningHours == _absent
          ? this.runningHours
          : runningHours as int?,
      strokesPerMinute: strokesPerMinute == _absent
          ? this.strokesPerMinute
          : strokesPerMinute as int?,
      capacityKind: capacityKind ?? this.capacityKind,
      capacityKgf: capacityKgf == _absent
          ? this.capacityKgf
          : capacityKgf as int?,
      dieFeedType: dieFeedType ?? this.dieFeedType,
      reportNotes: reportNotes ?? this.reportNotes,
      customProperties: customProperties ?? this.customProperties,
      capabilities: capabilities ?? this.capabilities,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// One pending production run in a machine's queue (machine queue popup).
class MachineQueueItem {
  const MachineQueueItem({
    required this.runId,
    required this.runName,
    this.createdBy,
    this.clientName = '',
    this.orderNo = '',
    this.weightKg = 0,
    this.status = '',
  });

  final String runId;
  final String runName;
  final String? createdBy;
  final String clientName;
  final String orderNo;
  final double weightKg;
  final String status;

  factory MachineQueueItem.fromJson(Map<String, dynamic> json) {
    return MachineQueueItem(
      runId: '${json['runId'] ?? ''}',
      runName: '${json['runName'] ?? ''}',
      createdBy: json['createdBy'] as String?,
      clientName: (json['clientName'] as String?) ?? '',
      orderNo: (json['orderNo'] as String?) ?? '',
      weightKg: (json['weightKg'] as num?)?.toDouble() ?? 0,
      status: (json['status'] as String?) ?? '',
    );
  }
}

class MachineAssetUploadIntentInput {
  const MachineAssetUploadIntentInput({
    required this.machineId,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    required this.sha256,
    this.isPrimary = true,
  });

  final String machineId;
  final String fileName;
  final String contentType;
  final int sizeBytes;
  final String sha256;
  final bool isPrimary;
}

class MachineAssetUploadIntent {
  const MachineAssetUploadIntent({
    required this.alreadyUploaded,
    this.photoUrl,
    this.upload,
  });

  final bool alreadyUploaded;
  final String? photoUrl; // the final url if already uploaded
  final MachineAssetUploadTarget? upload;
}

class MachineAssetUploadTarget {
  const MachineAssetUploadTarget({
    required this.uploadSessionId,
    required this.objectKey,
    required this.uploadUrl,
    required this.headers,
    this.expiresAt,
  });

  final String uploadSessionId;
  final String objectKey;
  final Uri uploadUrl;
  final Map<String, String> headers;
  final DateTime? expiresAt;
}

class CompleteMachineAssetUploadInput {
  const CompleteMachineAssetUploadInput({
    required this.uploadSessionId,
    required this.objectKey,
    required this.machineId,
  });

  final String uploadSessionId;
  final String objectKey;
  final String machineId;
}

/// A refused machine save, with what the server said about it.
///
/// `machine_asset_id_duplicate` is the one worth keying off: asset ids are
/// unique across the whole plant while the number series is per type, so a
/// suggestion can collide with a machine of another type or one numbered by
/// hand years ago. The server offers the next free number rather than refusing
/// flatly.
class MachineSaveException implements Exception {
  const MachineSaveException(this.message, {this.code, this.suggestedAssetId});

  final String message;
  final String? code;
  final String? suggestedAssetId;

  @override
  String toString() => message;
}

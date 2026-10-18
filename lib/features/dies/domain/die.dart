import 'package:paper/features/machines/domain/machine.dart';

enum DieStatus { ready, inProduction, needsRepair, obsolete }

enum DieOwnership { inHouse, customerOwned }

const Object _dieAbsent = Object();

class Die {
  const Die({
    required this.id,
    required this.name,
    required this.toolCode,
    required this.photoUrls,
    required this.operationalNotes,
    required this.compatibleMachineGroupIds,
    this.clientId,
    this.storageLocation,
    this.numberOfCavities,
    this.strokeCount,
    this.maxStrokes,
    this.strokesPerPiece,
    this.setupMinutes,
    this.reportNotes = '',
    this.physicalSpecs = const [],
    this.dieType = '',
    this.madeBy = '',
    this.poAt,
    this.dateInAt,
    this.linerSizeNm,
    this.linerSizeUnit = 'mm',
    this.noOfSet,
    this.storeArea = '',
    this.rackNo = '',
    required this.status,
    required this.ownership,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String toolCode;
  final List<String> photoUrls;
  final String operationalNotes;
  final List<int> compatibleMachineGroupIds;
  final int? clientId;
  final String? storageLocation;
  final int? numberOfCavities;
  final int? strokeCount;
  final int? maxStrokes;
  final double? strokesPerPiece;
  final double? setupMinutes;
  final String reportNotes;
  final List<CustomProperty> physicalSpecs;

  // --- the die sheet (migrations/048) ---------------------------------------

  /// '' | 'cutting' | 'bending'. What the code's initials come from.
  final String dieType;

  /// Whoever cut it — a fitter here, or an outside toolroom. Free text.
  final String madeBy;

  /// UTC instants: ordered, and came into store. Render with .toLocal().
  final DateTime? poAt;
  final DateTime? dateInAt;

  /// An integer count of nanometres, per the units contract: no floats in a
  /// quantity, and a base small enough that thou and SWG land on it exactly.
  final int? linerSizeNm;

  /// How that size was read. Display only; never used in arithmetic.
  final String linerSizeUnit;
  final int? noOfSet;

  /// Where it is kept. These replace the free-text [storageLocation], which is
  /// kept only so dies that predate them still say where they are.
  final String storeArea;
  final String rackNo;

  final DieStatus status;
  final DieOwnership ownership;
  final DateTime createdAt;
  final DateTime updatedAt;

  Die copyWith({
    String? id,
    String? name,
    String? toolCode,
    List<String>? photoUrls,
    String? operationalNotes,
    List<int>? compatibleMachineGroupIds,
    int? clientId,
    Object? storageLocation = _dieAbsent,
    int? numberOfCavities,
    int? strokeCount,
    int? maxStrokes,
    Object? strokesPerPiece = _dieAbsent,
    Object? setupMinutes = _dieAbsent,
    String? reportNotes,
    List<CustomProperty>? physicalSpecs,
    String? dieType,
    String? madeBy,
    Object? poAt = _dieAbsent,
    Object? dateInAt = _dieAbsent,
    Object? linerSizeNm = _dieAbsent,
    String? linerSizeUnit,
    Object? noOfSet = _dieAbsent,
    String? storeArea,
    String? rackNo,
    DieStatus? status,
    DieOwnership? ownership,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Die(
      id: id ?? this.id,
      name: name ?? this.name,
      toolCode: toolCode ?? this.toolCode,
      photoUrls: photoUrls ?? this.photoUrls,
      operationalNotes: operationalNotes ?? this.operationalNotes,
      compatibleMachineGroupIds:
          compatibleMachineGroupIds ?? this.compatibleMachineGroupIds,
      clientId: clientId ?? this.clientId,
      storageLocation: storageLocation == _dieAbsent
          ? this.storageLocation
          : storageLocation as String?,
      numberOfCavities: numberOfCavities ?? this.numberOfCavities,
      strokeCount: strokeCount ?? this.strokeCount,
      maxStrokes: maxStrokes ?? this.maxStrokes,
      strokesPerPiece: strokesPerPiece == _dieAbsent
          ? this.strokesPerPiece
          : strokesPerPiece as double?,
      setupMinutes: setupMinutes == _dieAbsent
          ? this.setupMinutes
          : setupMinutes as double?,
      reportNotes: reportNotes ?? this.reportNotes,
      physicalSpecs: physicalSpecs ?? this.physicalSpecs,
      dieType: dieType ?? this.dieType,
      madeBy: madeBy ?? this.madeBy,
      poAt: poAt == _dieAbsent ? this.poAt : poAt as DateTime?,
      dateInAt: dateInAt == _dieAbsent ? this.dateInAt : dateInAt as DateTime?,
      linerSizeNm: linerSizeNm == _dieAbsent
          ? this.linerSizeNm
          : linerSizeNm as int?,
      linerSizeUnit: linerSizeUnit ?? this.linerSizeUnit,
      noOfSet: noOfSet == _dieAbsent ? this.noOfSet : noOfSet as int?,
      storeArea: storeArea ?? this.storeArea,
      rackNo: rackNo ?? this.rackNo,
      status: status ?? this.status,
      ownership: ownership ?? this.ownership,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class DieAssetUploadIntentInput {
  const DieAssetUploadIntentInput({
    required this.dieId,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    required this.sha256,
    this.isPrimary = false,
  });

  final String dieId;
  final String fileName;
  final String contentType;
  final int sizeBytes;
  final String sha256;
  final bool isPrimary;
}

class DieAssetUploadIntent {
  const DieAssetUploadIntent({
    required this.alreadyUploaded,
    this.photoUrl,
    this.upload,
  });

  final bool alreadyUploaded;
  final String? photoUrl; // the final url if already uploaded
  final DieAssetUploadTarget? upload;
}

class DieAssetUploadTarget {
  const DieAssetUploadTarget({
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

class CompleteDieAssetUploadInput {
  const CompleteDieAssetUploadInput({
    required this.uploadSessionId,
    required this.objectKey,
    required this.dieId,
  });

  final String uploadSessionId;
  final String objectKey;
  final String dieId;
}

/// A refused die save, with what the server said about it.
///
/// `die_tool_code_duplicate` is the one worth keying off: tool codes are
/// unique across the factory while part codes are unique only within a group,
/// so two groups holding the same part code derive the same die code. The
/// server offers the first free one in the series rather than refusing flatly.
class DieSaveException implements Exception {
  const DieSaveException(this.message, {this.code, this.suggestedToolCode});

  final String message;
  final String? code;
  final String? suggestedToolCode;

  @override
  String toString() => message;
}

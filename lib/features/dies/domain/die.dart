enum DieStatus { ready, inProduction, needsRepair, obsolete }
enum DieOwnership { inHouse, customerOwned }

const Object _dieAbsent = Object();

class Die {
  const Die({
    required this.id,
    required this.toolCode,
    required this.producedPartNumbers,
    required this.photoUrls,
    required this.operationalNotes,
    required this.compatibleMachineGroupIds,
    this.storageLocation,
    this.numberOfCavities,
    this.strokeCount,
    this.maxStrokes,
    this.physicalSpecs = const {},
    required this.status,
    required this.ownership,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String toolCode;
  final List<String> producedPartNumbers;
  final List<String> photoUrls;
  final String operationalNotes;
  final List<int> compatibleMachineGroupIds;
  final String? storageLocation;
  final int? numberOfCavities;
  final int? strokeCount;
  final int? maxStrokes;
  final Map<String, String> physicalSpecs;
  final DieStatus status;
  final DieOwnership ownership;
  final DateTime createdAt;
  final DateTime updatedAt;

  Die copyWith({
    String? id,
    String? toolCode,
    List<String>? producedPartNumbers,
    List<String>? photoUrls,
    String? operationalNotes,
    List<int>? compatibleMachineGroupIds,
    Object? storageLocation = _dieAbsent,
    int? numberOfCavities,
    int? strokeCount,
    int? maxStrokes,
    Map<String, String>? physicalSpecs,
    DieStatus? status,
    DieOwnership? ownership,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Die(
      id: id ?? this.id,
      toolCode: toolCode ?? this.toolCode,
      producedPartNumbers: producedPartNumbers ?? this.producedPartNumbers,
      photoUrls: photoUrls ?? this.photoUrls,
      operationalNotes: operationalNotes ?? this.operationalNotes,
      compatibleMachineGroupIds: compatibleMachineGroupIds ?? this.compatibleMachineGroupIds,
      storageLocation: storageLocation == _dieAbsent ? this.storageLocation : storageLocation as String?,
      numberOfCavities: numberOfCavities ?? this.numberOfCavities,
      strokeCount: strokeCount ?? this.strokeCount,
      maxStrokes: maxStrokes ?? this.maxStrokes,
      physicalSpecs: physicalSpecs ?? this.physicalSpecs,
      status: status ?? this.status,
      ownership: ownership ?? this.ownership,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

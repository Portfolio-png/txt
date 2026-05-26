enum MachineStatus { active, maintenance, decommissioned }

enum CustomPropertyType { text, numeric }

class CustomProperty {
  const CustomProperty({
    required this.key,
    required this.value,
    this.type = CustomPropertyType.text,
    this.unitId,
  });

  final String key;
  final String value;
  final CustomPropertyType type;
  final int? unitId;
  
  CustomProperty copyWith({
    String? key,
    String? value,
    CustomPropertyType? type,
    int? unitId,
  }) {
    return CustomProperty(
      key: key ?? this.key,
      value: value ?? this.value,
      type: type ?? this.type,
      unitId: unitId ?? this.unitId,
    );
  }
}

const Object _absent = Object();

class Machine {
  const Machine({
    required this.id,
    required this.name,
    required this.assetId,
    required this.primaryPhotoUrl,
    required this.groupId,
    required this.makeModel,
    required this.serialNumber,
    this.location,
    this.installationDate,
    required this.status,
    this.customProperties = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String assetId;
  final String primaryPhotoUrl;
  final int? groupId;
  final String makeModel;
  final String serialNumber;
  final String? location;
  final DateTime? installationDate;
  final MachineStatus status;
  final List<CustomProperty> customProperties;
  final DateTime createdAt;
  final DateTime updatedAt;

  Machine copyWith({
    String? id,
    String? name,
    String? assetId,
    String? primaryPhotoUrl,
    int? groupId,
    String? makeModel,
    String? serialNumber,
    Object? location = _absent,
    DateTime? installationDate,
    MachineStatus? status,
    List<CustomProperty>? customProperties,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Machine(
      id: id ?? this.id,
      name: name ?? this.name,
      assetId: assetId ?? this.assetId,
      primaryPhotoUrl: primaryPhotoUrl ?? this.primaryPhotoUrl,
      groupId: groupId ?? this.groupId,
      makeModel: makeModel ?? this.makeModel,
      serialNumber: serialNumber ?? this.serialNumber,
      location: location == _absent ? this.location : location as String?,
      installationDate: installationDate ?? this.installationDate,
      status: status ?? this.status,
      customProperties: customProperties ?? this.customProperties,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

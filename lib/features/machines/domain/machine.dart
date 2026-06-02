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
    required this.primaryPhotoUrl,
    required this.groupId,
    required this.makeModel,
    required this.serialNumber,
    this.location,
    this.installationDate,
    required this.status,
    this.customProperties = const [],
    this.capabilities = const [],
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
  final List<MachineCapability> capabilities;
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
    List<MachineCapability>? capabilities,
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
      capabilities: capabilities ?? this.capabilities,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
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

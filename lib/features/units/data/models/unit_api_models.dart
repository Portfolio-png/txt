import '../../domain/unit_definition.dart';
import '../../domain/unit_inputs.dart';

class UnitDto {
  const UnitDto({
    required this.id,
    required this.name,
    required this.symbol,
    required this.notes,
    required this.isArchived,
    required this.usageCount,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final String symbol;
  final String notes;
  final bool isArchived;
  final int usageCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory UnitDto.fromJson(Map<String, dynamic> json) {
    return UnitDto(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      symbol: json['symbol'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      isArchived: json['isArchived'] as bool? ?? false,
      usageCount: json['usageCount'] as int? ?? 0,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  UnitDefinition toDomain() {
    return UnitDefinition(
      id: id,
      name: name,
      symbol: symbol,
      notes: notes,
      isArchived: isArchived,
      usageCount: usageCount,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

class UnitResponse {
  const UnitResponse({required this.success, this.unit, this.error});

  final bool success;
  final UnitDto? unit;
  final String? error;

  factory UnitResponse.fromJson(Map<String, dynamic> json) {
    return UnitResponse(
      success: json['success'] as bool? ?? false,
      unit: json['unit'] == null
          ? null
          : UnitDto.fromJson(json['unit'] as Map<String, dynamic>),
      error: json['error'] as String?,
    );
  }
}

class UnitsListResponse {
  const UnitsListResponse({required this.success, required this.units});

  final bool success;
  final List<UnitDto> units;

  factory UnitsListResponse.fromJson(Map<String, dynamic> json) {
    return UnitsListResponse(
      success: json['success'] as bool? ?? false,
      units: (json['units'] as List<dynamic>? ?? const [])
          .map((item) => UnitDto.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

class CreateUnitRequest {
  const CreateUnitRequest({
    required this.name,
    required this.symbol,
    required this.notes,
  });

  final String name;
  final String symbol;
  final String notes;

  factory CreateUnitRequest.fromInput(CreateUnitInput input) {
    return CreateUnitRequest(
      name: input.name,
      symbol: input.symbol,
      notes: input.notes,
    );
  }

  Map<String, dynamic> toJson() {
    return {'name': name, 'symbol': symbol, 'notes': notes};
  }
}

class UpdateUnitRequest {
  const UpdateUnitRequest({
    required this.name,
    required this.symbol,
    required this.notes,
  });

  final String name;
  final String symbol;
  final String notes;

  factory UpdateUnitRequest.fromInput(UpdateUnitInput input) {
    return UpdateUnitRequest(
      name: input.name,
      symbol: input.symbol,
      notes: input.notes,
    );
  }

  Map<String, dynamic> toJson() {
    return {'name': name, 'symbol': symbol, 'notes': notes};
  }
}

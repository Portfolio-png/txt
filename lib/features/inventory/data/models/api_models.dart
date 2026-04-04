import 'dart:convert';

import '../../domain/create_parent_material_input.dart';
import '../../domain/material_record.dart';

class MaterialDto {
  const MaterialDto({
    required this.id,
    required this.barcode,
    required this.name,
    required this.type,
    required this.grade,
    required this.thickness,
    required this.supplier,
    required this.unitId,
    required this.unit,
    required this.notes,
    required this.isParent,
    required this.parentBarcode,
    required this.numberOfChildren,
    required this.linkedChildBarcodes,
    required this.scanCount,
    required this.createdAt,
  });

  final int? id;
  final String barcode;
  final String name;
  final String type;
  final String grade;
  final String thickness;
  final String supplier;
  final int? unitId;
  final String unit;
  final String notes;
  final bool isParent;
  final String? parentBarcode;
  final int numberOfChildren;
  final List<String> linkedChildBarcodes;
  final int scanCount;
  final DateTime createdAt;

  factory MaterialDto.fromJson(Map<String, dynamic> json) {
    final rawChildren = json['linkedChildBarcodes'];
    final parsedChildren = rawChildren is String
        ? List<String>.from(jsonDecode(rawChildren) as List<dynamic>)
        : List<String>.from((rawChildren as List<dynamic>? ?? const []));

    return MaterialDto(
      id: json['id'] as int?,
      barcode: json['barcode'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      grade: json['grade'] as String? ?? '',
      thickness: json['thickness'] as String? ?? '',
      supplier: json['supplier'] as String? ?? '',
      unitId: json['unitId'] as int?,
      unit: json['unit'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      isParent: json['isParent'] as bool? ?? false,
      parentBarcode: json['parentBarcode'] as String?,
      numberOfChildren: json['numberOfChildren'] as int? ?? 0,
      linkedChildBarcodes: parsedChildren,
      scanCount: json['scanCount'] as int? ?? 0,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'barcode': barcode,
      'name': name,
      'type': type,
      'grade': grade,
      'thickness': thickness,
      'supplier': supplier,
      'unitId': unitId,
      'unit': unit,
      'notes': notes,
      'isParent': isParent,
      'parentBarcode': parentBarcode,
      'numberOfChildren': numberOfChildren,
      'linkedChildBarcodes': linkedChildBarcodes,
      'scanCount': scanCount,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  MaterialRecord toRecord() {
    return MaterialRecord(
      id: id,
      barcode: barcode,
      name: name,
      type: type,
      grade: grade,
      thickness: thickness,
      supplier: supplier,
      unitId: unitId,
      unit: unit,
      notes: notes,
      createdAt: createdAt,
      kind: isParent ? 'parent' : 'child',
      parentBarcode: parentBarcode,
      numberOfChildren: numberOfChildren,
      linkedChildBarcodes: linkedChildBarcodes,
      scanCount: scanCount,
    );
  }

  factory MaterialDto.fromRecord(MaterialRecord record) {
    return MaterialDto(
      id: record.id,
      barcode: record.barcode,
      name: record.name,
      type: record.type,
      grade: record.grade,
      thickness: record.thickness,
      supplier: record.supplier,
      unitId: record.unitId,
      unit: record.unit,
      notes: record.notes,
      isParent: record.isParent,
      parentBarcode: record.parentBarcode,
      numberOfChildren: record.numberOfChildren,
      linkedChildBarcodes: record.linkedChildBarcodes,
      scanCount: record.scanCount,
      createdAt: record.createdAt,
    );
  }
}

class CreateParentRequest {
  const CreateParentRequest({
    required this.name,
    required this.type,
    required this.grade,
    required this.thickness,
    required this.supplier,
    required this.unitId,
    required this.unit,
    required this.notes,
    required this.numberOfChildren,
  });

  final String name;
  final String type;
  final String grade;
  final String thickness;
  final String supplier;
  final int? unitId;
  final String unit;
  final String notes;
  final int numberOfChildren;

  factory CreateParentRequest.fromInput(CreateParentMaterialInput input) {
    return CreateParentRequest(
      name: input.name,
      type: input.type,
      grade: input.grade,
      thickness: input.thickness,
      supplier: input.supplier,
      unitId: input.unitId,
      unit: input.unit,
      notes: input.notes,
      numberOfChildren: input.numberOfChildren,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type,
      'grade': grade,
      'thickness': thickness,
      'supplier': supplier,
      'unitId': unitId,
      'unit': unit,
      'notes': notes,
      'numberOfChildren': numberOfChildren,
    };
  }
}

class MaterialResponse {
  const MaterialResponse({required this.success, this.material, this.error});

  final bool success;
  final MaterialDto? material;
  final String? error;

  factory MaterialResponse.fromJson(Map<String, dynamic> json) {
    return MaterialResponse(
      success: json['success'] as bool? ?? false,
      material: json['material'] == null
          ? null
          : MaterialDto.fromJson(json['material'] as Map<String, dynamic>),
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {'success': success, 'material': material?.toJson(), 'error': error};
  }
}

class MaterialsListResponse {
  const MaterialsListResponse({required this.success, required this.materials});

  final bool success;
  final List<MaterialDto> materials;

  factory MaterialsListResponse.fromJson(Map<String, dynamic> json) {
    return MaterialsListResponse(
      success: json['success'] as bool? ?? false,
      materials: (json['materials'] as List<dynamic>? ?? const [])
          .map((item) => MaterialDto.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'materials': materials.map((material) => material.toJson()).toList(),
    };
  }
}

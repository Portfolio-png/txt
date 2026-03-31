import 'dart:convert';

import '../../domain/material_record.dart';

class InventoryMaterialModel {
  const InventoryMaterialModel({
    required this.id,
    required this.barcode,
    required this.name,
    required this.type,
    required this.grade,
    required this.thickness,
    required this.supplier,
    required this.unit,
    required this.notes,
    required this.createdAt,
    required this.kind,
    required this.parentBarcode,
    required this.numberOfChildren,
    required this.linkedChildBarcodes,
    required this.scanCount,
  });

  final int? id;
  final String barcode;
  final String name;
  final String type;
  final String grade;
  final String thickness;
  final String supplier;
  final String unit;
  final String notes;
  final DateTime createdAt;
  final String kind;
  final String? parentBarcode;
  final int numberOfChildren;
  final List<String> linkedChildBarcodes;
  final int scanCount;

  factory InventoryMaterialModel.fromMap(Map<String, Object?> map) {
    final rawLinked = map['linked_child_barcodes'] as String?;
    return InventoryMaterialModel(
      id: map['id'] as int?,
      barcode: map['barcode'] as String,
      name: map['name'] as String,
      type: map['type'] as String,
      grade: map['grade'] as String? ?? '',
      thickness: map['thickness'] as String? ?? '',
      supplier: map['supplier'] as String? ?? '',
      unit: map['unit'] as String? ?? '',
      notes: map['notes'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String),
      kind: map['kind'] as String,
      parentBarcode: map['parent_barcode'] as String?,
      numberOfChildren: (map['number_of_children'] as int?) ?? 0,
      linkedChildBarcodes: rawLinked == null || rawLinked.isEmpty
          ? const []
          : List<String>.from(jsonDecode(rawLinked) as List<dynamic>),
      scanCount: (map['scan_count'] as int?) ?? 0,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'barcode': barcode,
      'name': name,
      'type': type,
      'grade': grade,
      'thickness': thickness,
      'supplier': supplier,
      'unit': unit,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'kind': kind,
      'parent_barcode': parentBarcode,
      'number_of_children': numberOfChildren,
      'linked_child_barcodes': jsonEncode(linkedChildBarcodes),
      'scan_count': scanCount,
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
      unit: unit,
      notes: notes,
      createdAt: createdAt,
      kind: kind,
      parentBarcode: parentBarcode,
      numberOfChildren: numberOfChildren,
      linkedChildBarcodes: linkedChildBarcodes,
      scanCount: scanCount,
    );
  }
}

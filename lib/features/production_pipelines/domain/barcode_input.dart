import 'package:core_erp/features/inventory/domain/material_record.dart';

class BarcodeInput {
  const BarcodeInput({
    required this.barcode,
    required this.materialName,
    required this.materialType,
    required this.scanCount,
    this.quantity,
    this.unit,
  });

  final String barcode;
  final String materialName;
  final String materialType;
  final int scanCount;
  final double? quantity;
  final String? unit;

  factory BarcodeInput.fromJson(Map<String, dynamic> json) {
    return BarcodeInput(
      barcode: json['barcode'] as String? ?? '',
      materialName: json['materialName'] as String? ?? '',
      materialType: json['materialType'] as String? ?? '',
      scanCount: json['scanCount'] as int? ?? 0,
      quantity: (json['quantity'] as num?)?.toDouble(),
      unit: json['unit'] as String?,
    );
  }

  factory BarcodeInput.fromMaterialRecord(MaterialRecord record, {double? quantity}) {
    return BarcodeInput(
      barcode: record.barcode,
      materialName: record.name,
      materialType: record.type,
      scanCount: record.scanCount,
      quantity: quantity,
      unit: record.unit,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'barcode': barcode,
      'materialName': materialName,
      'materialType': materialType,
      'scanCount': scanCount,
      if (quantity != null) 'quantity': quantity,
      if (unit != null) 'unit': unit,
    };
  }
}


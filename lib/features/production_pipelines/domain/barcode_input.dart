import '../../inventory/domain/material_record.dart';

class BarcodeInput {
  const BarcodeInput({
    required this.barcode,
    required this.materialName,
    required this.materialType,
    required this.scanCount,
  });

  final String barcode;
  final String materialName;
  final String materialType;
  final int scanCount;

  factory BarcodeInput.fromJson(Map<String, dynamic> json) {
    return BarcodeInput(
      barcode: json['barcode'] as String? ?? '',
      materialName: json['materialName'] as String? ?? '',
      materialType: json['materialType'] as String? ?? '',
      scanCount: json['scanCount'] as int? ?? 0,
    );
  }

  factory BarcodeInput.fromMaterialRecord(MaterialRecord record) {
    return BarcodeInput(
      barcode: record.barcode,
      materialName: record.name,
      materialType: record.type,
      scanCount: record.scanCount,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'barcode': barcode,
      'materialName': materialName,
      'materialType': materialType,
      'scanCount': scanCount,
    };
  }
}

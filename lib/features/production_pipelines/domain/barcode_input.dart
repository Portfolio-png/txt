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

  factory BarcodeInput.fromMaterialRecord(MaterialRecord record) {
    return BarcodeInput(
      barcode: record.barcode,
      materialName: record.name,
      materialType: record.type,
      scanCount: record.scanCount,
    );
  }
}

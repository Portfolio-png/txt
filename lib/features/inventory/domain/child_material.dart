import 'material_base.dart';

class ChildMaterial extends MaterialBase {
  const ChildMaterial({
    required super.id,
    required super.barcode,
    required super.name,
    required super.type,
    required super.grade,
    required super.thickness,
    required super.supplier,
    required super.createdAt,
    required this.parentBarcode,
    this.scanCount = 0,
  });

  final String parentBarcode;
  final int scanCount;
}

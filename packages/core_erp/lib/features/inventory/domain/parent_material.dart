import 'material_base.dart';

class ParentMaterial extends MaterialBase {
  const ParentMaterial({
    required super.id,
    required super.barcode,
    required super.name,
    required super.type,
    required super.grade,
    required super.thickness,
    required super.supplier,
    required super.createdAt,
    required this.numberOfChildren,
    required this.linkedChildBarcodes,
    this.scanCount = 0,
  });

  final int numberOfChildren;
  final List<String> linkedChildBarcodes;
  final int scanCount;
}

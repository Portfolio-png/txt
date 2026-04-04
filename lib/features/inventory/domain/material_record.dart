class MaterialRecord {
  const MaterialRecord({
    required this.id,
    required this.barcode,
    required this.name,
    required this.type,
    required this.grade,
    required this.thickness,
    required this.supplier,
    this.unitId,
    this.unit = '',
    this.notes = '',
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
  final int? unitId;
  final String unit;
  final String notes;
  final DateTime createdAt;
  final String kind;
  final String? parentBarcode;
  final int numberOfChildren;
  final List<String> linkedChildBarcodes;
  final int scanCount;

  bool get isParent => kind == 'parent';
  bool get isChild => kind == 'child';
}

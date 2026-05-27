class CreateChildMaterialInput {
  const CreateChildMaterialInput({
    required this.parentBarcode,
    required this.name,
    this.notes = '',
  });

  final String parentBarcode;
  final String name;
  final String notes;
}

class UpdateMaterialInput {
  const UpdateMaterialInput({
    required this.barcode,
    required this.name,
    required this.type,
    required this.grade,
    required this.thickness,
    required this.supplier,
    this.unitId,
    this.unit = '',
    this.location = '',
    this.notes = '',
  });

  final String barcode;
  final String name;
  final String type;
  final String grade;
  final String thickness;
  final String supplier;
  final int? unitId;
  final String unit;
  final String location;
  final String notes;
}

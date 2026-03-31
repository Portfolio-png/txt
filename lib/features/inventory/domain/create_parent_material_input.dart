class CreateParentMaterialInput {
  const CreateParentMaterialInput({
    required this.name,
    required this.type,
    required this.grade,
    required this.thickness,
    required this.supplier,
    required this.numberOfChildren,
    this.unit = '',
    this.notes = '',
  });

  final String name;
  final String type;
  final String grade;
  final String thickness;
  final String supplier;
  final int numberOfChildren;
  final String unit;
  final String notes;
}

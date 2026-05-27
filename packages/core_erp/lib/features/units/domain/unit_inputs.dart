class CreateUnitInput {
  const CreateUnitInput({
    required this.name,
    required this.symbol,
    this.notes = '',
    this.unitGroupName = '',
    this.conversionFactor = 1,
  });

  final String name;
  final String symbol;
  final String notes;
  final String unitGroupName;
  final double conversionFactor;
}

class UpdateUnitInput {
  const UpdateUnitInput({
    required this.id,
    required this.name,
    required this.symbol,
    this.notes = '',
    this.unitGroupName = '',
    this.conversionFactor = 1,
  });

  final int id;
  final String name;
  final String symbol;
  final String notes;
  final String unitGroupName;
  final double conversionFactor;
}

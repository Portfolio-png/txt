class CreateUnitInput {
  const CreateUnitInput({
    required this.name,
    required this.symbol,
    this.notes = '',
  });

  final String name;
  final String symbol;
  final String notes;
}

class UpdateUnitInput {
  const UpdateUnitInput({
    required this.id,
    required this.name,
    required this.symbol,
    this.notes = '',
  });

  final int id;
  final String name;
  final String symbol;
  final String notes;
}

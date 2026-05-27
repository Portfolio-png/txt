class MaterialActivityEvent {
  const MaterialActivityEvent({
    this.id,
    required this.barcode,
    required this.type,
    required this.label,
    this.description = '',
    this.actor = '',
    required this.createdAt,
  });

  final int? id;
  final String barcode;
  final String type;
  final String label;
  final String description;
  final String actor;
  final DateTime createdAt;
}

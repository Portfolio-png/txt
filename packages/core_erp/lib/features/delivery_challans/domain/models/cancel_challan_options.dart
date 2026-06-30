class CancelChallanOptions {
  final int challanId;
  final List<dynamic> linkedInvoices;
  final List<CancelActionOption> availableActions;

  CancelChallanOptions({
    required this.challanId,
    required this.linkedInvoices,
    required this.availableActions,
  });

  factory CancelChallanOptions.fromJson(Map<String, dynamic> json) {
    return CancelChallanOptions(
      challanId: json['challanId'] as int,
      linkedInvoices: json['linkedInvoices'] as List<dynamic>? ?? [],
      availableActions: (json['availableActions'] as List<dynamic>? ?? [])
          .map((e) => CancelActionOption.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class CancelActionOption {
  final String key;
  final String label;
  final String description;
  final bool requiresConfirmation;

  CancelActionOption({
    required this.key,
    required this.label,
    required this.description,
    required this.requiresConfirmation,
  });

  factory CancelActionOption.fromJson(Map<String, dynamic> json) {
    return CancelActionOption(
      key: json['key'] as String,
      label: json['label'] as String,
      description: json['description'] as String,
      requiresConfirmation: json['requiresConfirmation'] as bool? ?? false,
    );
  }
}

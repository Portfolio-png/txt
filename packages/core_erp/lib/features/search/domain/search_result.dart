class SearchResult {
  const SearchResult({
    required this.type,
    required this.id,
    required this.label,
    required this.subLabel,
    this.metadata = const {},
  });

  final String type;
  final String id;
  final String label;
  final String subLabel;
  final Map<String, dynamic> metadata;

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      type: json['type'] as String? ?? 'item',
      id: json['id']?.toString() ?? '',
      label: json['label'] as String? ?? '',
      subLabel: json['subLabel'] as String? ?? '',
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
    );
  }
}

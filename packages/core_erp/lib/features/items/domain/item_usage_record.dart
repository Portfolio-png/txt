class ItemUsageRecord {
  const ItemUsageRecord({
    required this.type,
    required this.id,
    required this.title,
    required this.subtitle,
    this.status,
    this.date,
  });

  final String type;
  final String id;
  final String title;
  final String subtitle;
  final String? status;
  final String? date;

  factory ItemUsageRecord.fromJson(Map<String, dynamic> json) {
    return ItemUsageRecord(
      type: json['type'] as String? ?? 'unknown',
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      status: json['status'] as String?,
      date: json['date'] as String?,
    );
  }
}

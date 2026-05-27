class OrderActivityEntry {
  const OrderActivityEntry({
    required this.id,
    required this.orderId,
    required this.activityType,
    required this.createdAt,
    this.actorUserId,
    this.actorName,
    this.actorRole,
    this.source,
    this.details,
  });

  final int id;
  final int orderId;
  final String activityType;
  final int? actorUserId;
  final String? actorName;
  final String? actorRole;
  final String? source;
  final Map<String, dynamic>? details;
  final DateTime createdAt;
}

class OrderStatusHistoryEntry {
  const OrderStatusHistoryEntry({
    required this.id,
    required this.orderId,
    required this.newStatus,
    required this.changedAt,
    this.previousStatus,
    this.changedByUserId,
  });

  final int id;
  final int orderId;
  final String? previousStatus;
  final String newStatus;
  final int? changedByUserId;
  final DateTime changedAt;
}

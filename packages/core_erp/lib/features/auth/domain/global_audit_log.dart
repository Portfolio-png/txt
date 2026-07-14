class GlobalAuditLog {
  final int id;
  final int actorUserId;
  final String actorName;
  final String actorRole;
  final String action;
  final String entityType;
  final String entityId;
  final Map<String, dynamic> details;
  final String ipAddress;
  final DateTime createdAt;

  const GlobalAuditLog({
    required this.id,
    required this.actorUserId,
    required this.actorName,
    required this.actorRole,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.details,
    required this.ipAddress,
    required this.createdAt,
  });

  factory GlobalAuditLog.fromJson(Map<String, dynamic> json) {
    return GlobalAuditLog(
      id: json['id'] as int? ?? 0,
      actorUserId: json['actorUserId'] as int? ?? 0,
      actorName: json['actorName'] as String? ?? '',
      actorRole: json['actorRole'] as String? ?? '',
      action: json['action'] as String? ?? '',
      entityType: json['entityType'] as String? ?? '',
      entityId: json['entityId'] as String? ?? '',
      details: json['details'] as Map<String, dynamic>? ?? {},
      ipAddress: json['ipAddress'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
    );
  }
}

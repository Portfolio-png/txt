class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.permissions,
    required this.isActive,
  });

  final int id;
  final String name;
  final String email;
  final String role;
  final List<String> permissions;
  final bool isActive;

  bool get isSuperAdmin => role == 'super_admin';
  bool get isAdmin => role == 'admin' || role == 'super_admin';
  bool get isRegularUser => role == 'user';
  bool can(String permissionKey) =>
      isSuperAdmin || permissions.contains(permissionKey);

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role: json['role'] as String? ?? 'user',
      permissions: (json['permissions'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      isActive: json['isActive'] as bool? ?? false,
    );
  }
}

class PermissionDescriptor {
  const PermissionDescriptor({
    required this.key,
    required this.label,
    required this.description,
  });

  final String key;
  final String label;
  final String description;

  factory PermissionDescriptor.fromJson(Map<String, dynamic> json) {
    return PermissionDescriptor(
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      description: json['description'] as String? ?? '',
    );
  }
}

class UserPermissionState {
  const UserPermissionState({
    required this.key,
    required this.allowed,
    required this.source,
  });

  final String key;
  final bool allowed;
  final String source;

  factory UserPermissionState.fromJson(Map<String, dynamic> json) {
    return UserPermissionState(
      key: json['key'] as String? ?? '',
      allowed: json['allowed'] as bool? ?? false,
      source: json['source'] as String? ?? 'role',
    );
  }
}

class DeleteRequest {
  const DeleteRequest({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.entityLabel,
    required this.reason,
    required this.status,
    required this.requestedByName,
    required this.createdAt,
  });

  final int id;
  final String entityType;
  final String entityId;
  final String entityLabel;
  final String reason;
  final String status;
  final String requestedByName;
  final DateTime createdAt;

  factory DeleteRequest.fromJson(Map<String, dynamic> json) {
    return DeleteRequest(
      id: json['id'] as int? ?? 0,
      entityType: json['entityType'] as String? ?? '',
      entityId: json['entityId'] as String? ?? '',
      entityLabel: json['entityLabel'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      requestedByName: json['requestedByName'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class AuthSession {
  const AuthSession({
    required this.id,
    required this.userId,
    required this.createdAt,
    required this.lastUsedAt,
    required this.expiresAt,
    required this.revokedAt,
    required this.revokedReason,
    required this.ipAddress,
    required this.userAgent,
  });

  final String id;
  final int userId;
  final DateTime createdAt;
  final DateTime lastUsedAt;
  final DateTime expiresAt;
  final DateTime? revokedAt;
  final String revokedReason;
  final String ipAddress;
  final String userAgent;

  bool get isActive => revokedAt == null && expiresAt.isAfter(DateTime.now());

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as int? ?? 0,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      lastUsedAt:
          DateTime.tryParse(json['lastUsedAt'] as String? ?? '') ??
          DateTime.now(),
      expiresAt:
          DateTime.tryParse(json['expiresAt'] as String? ?? '') ??
          DateTime.now(),
      revokedAt: DateTime.tryParse(json['revokedAt'] as String? ?? ''),
      revokedReason: json['revokedReason'] as String? ?? '',
      ipAddress: json['ipAddress'] as String? ?? '',
      userAgent: json['userAgent'] as String? ?? '',
    );
  }
}

class AuthEvent {
  const AuthEvent({
    required this.id,
    required this.eventType,
    required this.actorUserName,
    required this.targetUserName,
    required this.ipAddress,
    required this.userAgent,
    required this.createdAt,
  });

  final int id;
  final String eventType;
  final String actorUserName;
  final String targetUserName;
  final String ipAddress;
  final String userAgent;
  final DateTime createdAt;

  factory AuthEvent.fromJson(Map<String, dynamic> json) {
    return AuthEvent(
      id: json['id'] as int? ?? 0,
      eventType: json['eventType'] as String? ?? '',
      actorUserName: json['actorUserName'] as String? ?? '',
      targetUserName: json['targetUserName'] as String? ?? '',
      ipAddress: json['ipAddress'] as String? ?? '',
      userAgent: json['userAgent'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

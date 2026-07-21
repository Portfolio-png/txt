/// One field-level change captured in a Track event's diff.
class TrackChange {
  const TrackChange({required this.field, required this.from, required this.to});

  final String field;
  final String from;
  final String to;

  factory TrackChange.fromJson(Map<String, dynamic> json) {
    return TrackChange(
      field: json['field'] as String? ?? '',
      from: (json['from'] ?? '').toString(),
      to: (json['to'] ?? '').toString(),
    );
  }
}

/// A single entry in a "Track" feed — a create/update/delete recorded against
/// a master record (item, vendor, client, …) or attributed to a person.
class TrackEvent {
  const TrackEvent({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.actorName,
    required this.actorRole,
    required this.changes,
    required this.label,
    required this.createdAt,
  });

  final int id;
  final String entityType;
  final String entityId;
  final String action; // 'created' | 'updated' | 'deleted'
  final String actorName;
  final String actorRole;
  final List<TrackChange> changes;
  final String label; // human name of the record at the time
  final DateTime? createdAt;

  factory TrackEvent.fromJson(Map<String, dynamic> json) {
    final details =
        (json['details'] as Map?)?.cast<String, dynamic>() ?? const {};
    return TrackEvent(
      id: json['id'] as int? ?? 0,
      entityType: json['entityType'] as String? ?? '',
      entityId: (json['entityId'] ?? '').toString(),
      action: json['action'] as String? ?? '',
      actorName: json['actorName'] as String? ?? '',
      actorRole: json['actorRole'] as String? ?? '',
      changes: (json['changes'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(TrackChange.fromJson)
          .toList(growable: false),
      label: details['label'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    );
  }

  /// Singular noun for the entity type ('items' → 'Item').
  String get entityNoun {
    const map = {
      'items': 'Item',
      'clients': 'Client',
      'vendors': 'Vendor',
      'units': 'Unit',
      'machines': 'Machine',
      'dies': 'Die',
      'pipeline_templates': 'Pipeline',
      'employees': 'Person',
    };
    return map[entityType] ?? entityType;
  }
}

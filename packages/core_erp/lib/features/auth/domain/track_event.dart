/// One field-level change captured in a Track event's diff.
class TrackChange {
  const TrackChange({
    required this.field,
    required this.from,
    required this.to,
  });

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
    this.sittingId,
    this.otherType,
    this.otherLabel,
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

  /// Which opening of a window this change belongs to, or null for a change
  /// made outside one. The server has sent this since migration 050; it was
  /// simply being dropped here, because `fromJson` reads named keys.
  final String? sittingId;

  /// For a `linked` / `unlinked` event, the record at the other end.
  ///
  /// Snapshotted server-side at the moment of the link, so the line still
  /// reads after that record is deleted — which is exactly when somebody goes
  /// looking for it.
  final String? otherType;
  final String? otherLabel;

  /// Whether this event is about a link rather than a record of its own.
  bool get isLink => action == 'linked' || action == 'unlinked';

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
      // All three stay nullable so a payload from a server older than
      // migration 050 still decodes rather than throwing.
      sittingId: json['sittingId'] as String?,
      otherType: details['otherType'] as String?,
      otherLabel: details['otherLabel'] as String?,
    );
  }

  /// Singular noun for the entity type ('items' → 'Item').
  String get entityNoun => trackEntityNoun(entityType);

  /// The noun for the record at the other end of a link.
  String get otherNoun => otherType == null || otherType!.isEmpty
      ? 'record'
      : trackEntityNoun(otherType!);
}

/// Entity type to the word a person would say.
///
/// Kept in step with `TRACK_ENTITY_LABELS` on the server, so both sides call a
/// thing by the same name. The last five were added when those masters started
/// logging: without them a sitting read `inventory_sets` and `sub_contractors`
/// out loud, because an unknown type falls back to the raw column value.
const Map<String, String> _trackEntityNouns = {
  'items': 'Item',
  'clients': 'Client',
  'vendors': 'Vendor',
  'units': 'Unit',
  'machines': 'Machine',
  'dies': 'Die',
  'pipeline_templates': 'Pipeline',
  'employees': 'Person',
  'departments': 'Department',
  'sub_contractors': 'Sub-contractor',
  'groups': 'Group',
  'inventory_sets': 'Set',
  'materials': 'Material',
};

/// The word for [entityType], or the type itself when it is one nobody has
/// taught this yet.
String trackEntityNoun(String entityType) =>
    _trackEntityNouns[entityType] ?? entityType;

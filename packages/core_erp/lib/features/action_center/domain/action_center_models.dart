/// A dangling foreign-key reference surfaced by the Action Center scanner.
///
/// `ownerTable`/`ownerId` identify the record that still holds the reference
/// (drives the "Resolve" action → open that module). `brokenTable`/`brokenId`
/// identify the missing target row (drives the "Revert" action → restore it
/// from the trash).
class ActionCenterIssue {
  const ActionCenterIssue({
    required this.type,
    required this.severity,
    required this.ownerTable,
    required this.ownerId,
    required this.ownerLabel,
    required this.brokenTable,
    required this.brokenField,
    required this.brokenId,
    required this.brokenLabel,
  });

  final String type;
  final String severity; // 'error' | 'warning'
  final String ownerTable;
  final int ownerId;
  final String ownerLabel;
  final String brokenTable;
  final String brokenField;
  final int brokenId;
  final String brokenLabel;

  bool get isError => severity == 'error';

  factory ActionCenterIssue.fromJson(Map<String, dynamic> json) {
    return ActionCenterIssue(
      type: (json['type'] as String?) ?? 'broken_reference',
      severity: (json['severity'] as String?) ?? 'error',
      ownerTable: (json['ownerTable'] as String?) ?? '',
      ownerId: (json['ownerId'] as num?)?.toInt() ?? 0,
      ownerLabel: (json['ownerLabel'] as String?) ?? '',
      brokenTable: (json['brokenTable'] as String?) ?? '',
      brokenField: (json['brokenField'] as String?) ?? '',
      brokenId: (json['brokenId'] as num?)?.toInt() ?? 0,
      brokenLabel: (json['brokenLabel'] as String?) ?? '',
    );
  }
}

/// A row currently held in the trash (`deleted_records`), recoverable via restore.
class TrashedRecord {
  const TrashedRecord({
    required this.id,
    required this.tableName,
    required this.recordId,
    required this.deletedAt,
    required this.deletedBy,
    required this.label,
  });

  final int id;
  final String tableName;
  final int recordId;
  final String deletedAt;
  final String deletedBy;
  final String label;

  factory TrashedRecord.fromJson(Map<String, dynamic> json) {
    return TrashedRecord(
      id: (json['id'] as num?)?.toInt() ?? 0,
      tableName: (json['tableName'] as String?) ?? '',
      recordId: (json['recordId'] as num?)?.toInt() ?? 0,
      deletedAt: (json['deletedAt'] as String?) ?? '',
      deletedBy: (json['deletedBy'] as String?) ?? '',
      label: (json['label'] as String?) ?? '',
    );
  }
}

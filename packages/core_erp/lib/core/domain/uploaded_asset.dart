class UploadedAsset {
  const UploadedAsset({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    required this.sha256,
    required this.objectKey,
    required this.status,
    required this.isPrimary,
    this.createdAt,
    this.uploadedAt,
    this.readUrl,
    this.readUrlExpiresAt,
  });

  final int id;
  final String entityType;
  final int entityId;
  final String fileName;
  final String contentType;
  final int sizeBytes;
  final String sha256;
  final String objectKey;
  final String status;
  final bool isPrimary;
  final DateTime? createdAt;
  final DateTime? uploadedAt;
  final Uri? readUrl;
  final DateTime? readUrlExpiresAt;

  factory UploadedAsset.fromJson(Map<String, dynamic> json) {
    return UploadedAsset(
      id: json['id'] as int? ?? 0,
      entityType:
          json['entityType'] as String? ?? json['entity_type'] as String? ?? '',
      entityId: json['entityId'] as int? ?? json['entity_id'] as int? ?? 0,
      fileName:
          json['fileName'] as String? ?? json['file_name'] as String? ?? '',
      contentType:
          json['contentType'] as String? ??
          json['content_type'] as String? ??
          '',
      sizeBytes: json['sizeBytes'] as int? ?? json['size_bytes'] as int? ?? 0,
      sha256: json['sha256'] as String? ?? '',
      objectKey:
          json['objectKey'] as String? ?? json['object_key'] as String? ?? '',
      status: json['status'] as String? ?? '',
      isPrimary:
          (json['isPrimary'] as bool?) ??
          (json['is_primary'] as bool?) ??
          false,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : (json['created_at'] != null
                ? DateTime.tryParse(json['created_at'] as String)
                : null),
      uploadedAt: json['uploadedAt'] != null
          ? DateTime.tryParse(json['uploadedAt'] as String)
          : (json['uploaded_at'] != null
                ? DateTime.tryParse(json['uploaded_at'] as String)
                : null),
      readUrl: json['readUrl'] != null
          ? Uri.tryParse(json['readUrl'] as String)
          : null,
      readUrlExpiresAt: json['readUrlExpiresAt'] != null
          ? DateTime.tryParse(json['readUrlExpiresAt'] as String)
          : null,
    );
  }
}

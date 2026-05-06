class ItemAsset {
  const ItemAsset({
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
}

class ItemAssetUploadIntentInput {
  const ItemAssetUploadIntentInput({
    required this.itemId,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    required this.sha256,
    this.isPrimary = true,
  });

  final int itemId;
  final String fileName;
  final String contentType;
  final int sizeBytes;
  final String sha256;
  final bool isPrimary;
}

class ItemAssetUploadIntent {
  const ItemAssetUploadIntent({
    required this.alreadyUploaded,
    this.asset,
    this.upload,
  });

  final bool alreadyUploaded;
  final ItemAsset? asset;
  final ItemAssetUploadTarget? upload;
}

class ItemAssetUploadTarget {
  const ItemAssetUploadTarget({
    required this.uploadSessionId,
    required this.objectKey,
    required this.uploadUrl,
    required this.headers,
    this.expiresAt,
  });

  final String uploadSessionId;
  final String objectKey;
  final Uri uploadUrl;
  final Map<String, String> headers;
  final DateTime? expiresAt;
}

class CompleteItemAssetUploadInput {
  const CompleteItemAssetUploadInput({
    required this.uploadSessionId,
    required this.objectKey,
  });

  final String uploadSessionId;
  final String objectKey;
}

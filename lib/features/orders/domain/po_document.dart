enum PoUploadStatus { pending, uploading, uploaded, failed }

class PoDocumentEntry {
  const PoDocumentEntry({
    required this.id,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    required this.sha256,
    required this.objectKey,
    required this.status,
    this.createdAt,
    this.uploadedAt,
    this.linkedAt,
  });

  final int id;
  final String fileName;
  final String contentType;
  final int sizeBytes;
  final String sha256;
  final String objectKey;
  final String status;
  final DateTime? createdAt;
  final DateTime? uploadedAt;
  final DateTime? linkedAt;
}

class PoUploadIntentInput {
  const PoUploadIntentInput({
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    required this.sha256,
  });

  final String fileName;
  final String contentType;
  final int sizeBytes;
  final String sha256;
}

class PoUploadIntent {
  const PoUploadIntent({
    required this.alreadyUploaded,
    this.document,
    this.upload,
  });

  final bool alreadyUploaded;
  final PoDocumentEntry? document;
  final PoUploadTarget? upload;
}

class PoUploadTarget {
  const PoUploadTarget({
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

class CompletePoUploadInput {
  const CompletePoUploadInput({
    required this.uploadSessionId,
    required this.objectKey,
  });

  final String uploadSessionId;
  final String objectKey;
}

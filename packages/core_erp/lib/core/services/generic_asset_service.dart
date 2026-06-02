import 'dart:convert';
import 'package:http/http.dart' as http;

class GenericAssetUploadIntentInput {
  const GenericAssetUploadIntentInput({
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

class GenericAssetUploadTarget {
  const GenericAssetUploadTarget({
    required this.uploadUrl,
    required this.headers,
    required this.objectKey,
    this.readUrl,
  });

  final Uri uploadUrl;
  final Map<String, String> headers;
  final String objectKey;
  final String? readUrl;
}

class GenericAssetService {
  GenericAssetService({
    http.Client? client,
    this.baseUrl = 'http://localhost:8080',
    this.useMockResponses = true,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final bool useMockResponses;

  Future<GenericAssetUploadTarget> createUploadIntent(GenericAssetUploadIntentInput input) async {
    if (useMockResponses) {
      await Future.delayed(const Duration(milliseconds: 300));
      return GenericAssetUploadTarget(
        uploadUrl: Uri.parse('http://mock.local/upload'),
        headers: {},
        objectKey: 'mock-key-${DateTime.now().millisecondsSinceEpoch}',
        readUrl: 'https://images.unsplash.com/photo-1550439062-609e1531270e?auto=format&fit=crop&q=80',
      );
    }

    final uri = Uri.parse('$baseUrl/api/upload/generic');
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'fileName': input.fileName,
        'contentType': input.contentType,
        'sizeBytes': input.sizeBytes,
        'sha256': input.sha256,
      }),
    );

    final payload = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300 || payload['success'] != true) {
      throw Exception(payload['error'] as String? ?? 'Failed to create generic upload intent');
    }

    final data = payload['intent'] as Map<String, dynamic>;
    final uploadMap = data['upload'] as Map<String, dynamic>;
    final headersMap = uploadMap['headers'] as Map<String, dynamic>? ?? {};
    
    // In the generic asset flow, readUrl is returned immediately or constructed since there's no completion callback
    // (Wait, the backend returns readUrl inside intent if it's already generated, or we might need to construct it).
    // Let's assume readUrl is returned in the intent or upload map.
    final readUrl = data['readUrl'] as String? ?? uploadMap['readUrl'] as String?;

    return GenericAssetUploadTarget(
      uploadUrl: Uri.parse(uploadMap['uploadUrl'] as String? ?? ''),
      headers: headersMap.map((k, v) => MapEntry(k, v.toString())),
      objectKey: uploadMap['objectKey'] as String? ?? '',
      readUrl: readUrl,
    );
  }
}

import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

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

  /// The app's own service: signed in, and real outside demo mode.
  ///
  /// Editors used to build `GenericAssetService(baseUrl: …)` themselves, which
  /// is unauthenticated and defaults to mock mode — so their logo and photo
  /// "uploads" stored a stock picture and sent nothing. Only a host with no
  /// provider at all (a bare test) gets the mock.
  static GenericAssetService resolve(BuildContext context) {
    try {
      return Provider.of<GenericAssetService>(context, listen: false);
    } on ProviderNotFoundException {
      return GenericAssetService(
        baseUrl: const String.fromEnvironment(
          'PAPER_API_BASE_URL',
          defaultValue: 'http://localhost:8080',
        ),
      );
    }
  }

  Future<GenericAssetUploadTarget> createUploadIntent(
    GenericAssetUploadIntentInput input,
  ) async {
    if (useMockResponses) {
      await Future.delayed(const Duration(milliseconds: 300));
      return GenericAssetUploadTarget(
        uploadUrl: Uri.parse('http://mock.local/upload'),
        headers: {},
        objectKey: 'mock-key-${DateTime.now().millisecondsSinceEpoch}',
        readUrl:
            'https://images.unsplash.com/photo-1550439062-609e1531270e?auto=format&fit=crop&q=80',
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
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw Exception(
        payload['error'] as String? ?? 'Failed to create generic upload intent',
      );
    }

    final data = payload['intent'] as Map<String, dynamic>;
    final uploadMap = data['upload'] as Map<String, dynamic>;
    final headersMap = uploadMap['headers'] as Map<String, dynamic>? ?? {};

    // What gets saved on the record. `viewUrl` is a link that never expires;
    // the presigned `readUrl` stops working in seven days, which is how saved
    // logos and photos used to go blank on their own.
    final readUrl =
        uploadMap['viewUrl'] as String? ??
        data['readUrl'] as String? ??
        uploadMap['readUrl'] as String?;

    return GenericAssetUploadTarget(
      uploadUrl: Uri.parse(uploadMap['uploadUrl'] as String? ?? ''),
      headers: headersMap.map((k, v) => MapEntry(k, v.toString())),
      objectKey: uploadMap['objectKey'] as String? ?? '',
      readUrl: readUrl,
    );
  }
}

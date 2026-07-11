import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/action_center_models.dart';

class ActionCenterApiException implements Exception {
  ActionCenterApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Talks to the Action Center + Trash backend endpoints
/// (`/api/action-center/issues`, `/api/trash`, `/api/trash/restore`).
class ActionCenterRepository {
  ActionCenterRepository({
    http.Client? client,
    this.baseUrl = 'http://localhost:8080',
    this.useMockResponses = true,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final bool useMockResponses;

  Map<String, dynamic> _decode(String body) {
    if (body.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    return <String, dynamic>{};
  }

  /// Broken foreign-key references caused by hard deletes.
  Future<List<ActionCenterIssue>> getIssues() async {
    if (useMockResponses) return const <ActionCenterIssue>[];

    final response = await _client.get(Uri.parse('$baseUrl/api/action-center/issues'));
    final payload = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300 || payload['success'] != true) {
      throw ActionCenterApiException(
        (payload['error'] as String?) ?? 'Failed to load action-center issues.',
      );
    }
    final raw = (payload['issues'] as List<dynamic>? ?? const <dynamic>[]);
    return raw
        .whereType<Map<String, dynamic>>()
        .map(ActionCenterIssue.fromJson)
        .toList(growable: false);
  }

  /// Everything currently in the trash, most-recent first.
  Future<List<TrashedRecord>> listTrash() async {
    if (useMockResponses) return const <TrashedRecord>[];

    final response = await _client.get(Uri.parse('$baseUrl/api/trash'));
    final payload = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300 || payload['success'] != true) {
      throw ActionCenterApiException(
        (payload['error'] as String?) ?? 'Failed to load the trash bin.',
      );
    }
    final raw = (payload['records'] as List<dynamic>? ?? const <dynamic>[]);
    return raw
        .whereType<Map<String, dynamic>>()
        .map(TrashedRecord.fromJson)
        .toList(growable: false);
  }

  /// Restore a trashed row back into its table (original id preserved).
  Future<void> restore(String tableName, int recordId) async {
    if (useMockResponses) return;

    final response = await _client.post(
      Uri.parse('$baseUrl/api/trash/restore'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'tableName': tableName, 'recordId': recordId}),
    );
    final payload = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300 || payload['success'] != true) {
      throw ActionCenterApiException(
        (payload['error'] as String?) ?? 'Failed to restore the record.',
      );
    }
  }
}

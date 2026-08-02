import 'dart:convert';

import 'package:http/http.dart' as http;

/// Reads and writes the signed-in user's own UI preferences.
///
/// Backed by `GET/PUT /api/user-preferences/:key`, which is scoped server-side
/// to the caller — there is no way to read or write another user's values.
class UserPreferencesService {
  UserPreferencesService({
    http.Client? client,
    required this.baseUrl,
    this.useMockResponses = false,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final bool useMockResponses;

  /// In-memory stand-in so demo mode still round-trips within a session.
  final Map<String, Map<String, dynamic>> _mockValues =
      <String, Map<String, dynamic>>{};

  /// Returns null when the user has never saved this preference, so callers can
  /// tell "not set" apart from "explicitly empty".
  Future<Map<String, dynamic>?> read(String key) async {
    if (useMockResponses) {
      return _mockValues[key];
    }

    final response = await _client.get(
      Uri.parse('$baseUrl/api/user-preferences/$key'),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load preference "$key".');
    }
    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic> || payload['success'] != true) {
      throw Exception('Failed to load preference "$key".');
    }
    final value = payload['value'];
    return value is Map<String, dynamic> ? value : null;
  }

  Future<void> write(String key, Map<String, dynamic> value) async {
    if (useMockResponses) {
      _mockValues[key] = value;
      return;
    }

    final response = await _client.put(
      Uri.parse('$baseUrl/api/user-preferences/$key'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{'value': value}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to save preference "$key".');
    }
  }
}

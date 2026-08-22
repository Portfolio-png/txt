import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../domain/search_result.dart';
import 'search_repository.dart';

class ApiSearchRepository implements SearchRepository {
  ApiSearchRepository({
    http.Client? client,
    this.baseUrl = 'http://localhost:8080',
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  @override
  Future<List<SearchResult>> search(String query) async {
    if (query.trim().isEmpty) return const [];
    final uri = Uri.parse(
      '$baseUrl/api/search?q=${Uri.encodeQueryComponent(query)}',
    );
    final response = await _client.get(uri);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        payload['success'] == true) {
      final results = payload['results'] as List? ?? [];
      return results
          .map((e) => SearchResult.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception(payload['error'] ?? 'Failed to search');
  }

  @override
  Future<Map<String, dynamic>?> lookupBarcode(String code) async {
    final uri = Uri.parse(
      '$baseUrl/api/barcode/lookup?code=${Uri.encodeQueryComponent(code)}',
    );
    final response = await _client.get(uri);
    if (response.statusCode == 404) return null;

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        payload['success'] == true) {
      return payload['result'] as Map<String, dynamic>;
    }
    throw Exception(payload['error'] ?? 'Failed to lookup barcode');
  }

  @override
  Future<List<String>> getSearchHistory() async {
    final uri = Uri.parse('$baseUrl/api/search/history');
    final response = await _client.get(uri);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        payload['success'] == true) {
      final history = payload['history'] as List? ?? [];
      return history.map((e) => e.toString()).toList();
    }
    return const [];
  }

  @override
  Future<void> logSearchQuery(String query) async {
    final uri = Uri.parse('$baseUrl/api/search/history');
    await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'query': query}),
    );
  }

  @override
  Future<void> logSearchClick(String query, SearchResult result) async {
    final uri = Uri.parse('$baseUrl/api/search/clicks');
    await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'query': query,
        'entityType': result.type,
        'entityId': result.id,
        'entityLabel': result.label,
      }),
    );
  }
}

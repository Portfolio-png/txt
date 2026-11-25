import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/spring.dart';

/// What the server refused, in its own words. [existing] is set when the
/// refusal is "this spring (or this code) already exists" — the form offers
/// to open that one instead.
class SpringApiException implements Exception {
  const SpringApiException(this.message, {this.code, this.existing});

  final String message;
  final String? code;
  final SpringDefinition? existing;

  @override
  String toString() => message;
}

abstract class SpringRepository {
  Future<List<SpringDefinition>> list();

  /// One spring by its item's id; null when the item has no spring spec.
  Future<SpringDefinition?> get(int itemId);
  Future<SpringDefinition> create(SpringInput input);
  Future<SpringDefinition> update(int itemId, SpringInput input);
}

/// /api/raw-materials/springs (backend modules/items/springs.js).
class ApiSpringRepository implements SpringRepository {
  ApiSpringRepository({
    http.Client? client,
    this.baseUrl = 'http://localhost:8080',
    this.useMockResponses = false,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final bool useMockResponses;

  static final List<SpringDefinition> _mock = <SpringDefinition>[];
  static int _mockNextId = 1;

  Uri _uri(String path) => Uri.parse('$baseUrl/api/raw-materials/springs$path');

  Map<String, dynamic> _decode(http.Response response) {
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const SpringApiException(
        'The server answered something unexpected.',
      );
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded['success'] != true) {
      final existing = decoded['spring'];
      throw SpringApiException(
        decoded['error'] as String? ?? 'The spring could not be saved.',
        code: decoded['code'] as String?,
        existing: existing is Map<String, dynamic>
            ? SpringDefinition.fromJson(existing)
            : null,
      );
    }
    return decoded;
  }

  @override
  Future<List<SpringDefinition>> list() async {
    if (useMockResponses) return List<SpringDefinition>.of(_mock);
    final payload = _decode(await _client.get(_uri('')));
    return (payload['springs'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(SpringDefinition.fromJson)
        .toList(growable: false);
  }

  @override
  Future<SpringDefinition?> get(int itemId) async {
    if (useMockResponses) {
      for (final spring in _mock) {
        if (spring.itemId == itemId) return spring;
      }
      return null;
    }
    final response = await _client.get(_uri('/$itemId'));
    if (response.statusCode == 404) return null;
    final payload = _decode(response);
    return SpringDefinition.fromJson(payload['spring'] as Map<String, dynamic>);
  }

  @override
  Future<SpringDefinition> create(SpringInput input) async {
    if (useMockResponses) return _mockSave(null, input);
    final payload = _decode(
      await _client.post(
        _uri(''),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(input.toJson()),
      ),
    );
    return SpringDefinition.fromJson(payload['spring'] as Map<String, dynamic>);
  }

  @override
  Future<SpringDefinition> update(int itemId, SpringInput input) async {
    if (useMockResponses) return _mockSave(itemId, input);
    final payload = _decode(
      await _client.put(
        _uri('/$itemId'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(input.toJson()),
      ),
    );
    return SpringDefinition.fromJson(payload['spring'] as Map<String, dynamic>);
  }

  SpringDefinition _mockSave(int? itemId, SpringInput input) {
    final saved = SpringDefinition(
      itemId: itemId ?? _mockNextId++,
      name: springName(
        kind: input.kind,
        springType: input.springType,
        sizes: input.sizes,
        wireGauge: input.wireGauge,
        wireGrade: input.wireGrade,
        format: input.nameFormat,
      ),
      code: input.code.trim(),
      kind: input.kind,
      springType: input.springType.trim(),
      sizes: Map.of(input.sizes),
      wireGauge: input.wireGauge.trim(),
      wireGrade: input.wireGrade.trim(),
      nameFormat: input.nameFormat,
      vendors: input.vendors,
    );
    _mock.removeWhere((s) => s.itemId == saved.itemId);
    _mock.add(saved);
    return saved;
  }
}

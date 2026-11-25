import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/rivet.dart';

/// What the server refused, in its own words. [existing] is set when the
/// refusal is "this rivet (or this code) already exists" — the form offers
/// to open that one instead.
class RivetApiException implements Exception {
  const RivetApiException(this.message, {this.code, this.existing});

  final String message;
  final String? code;
  final RivetDefinition? existing;

  @override
  String toString() => message;
}

abstract class RivetRepository {
  Future<List<RivetDefinition>> list();

  /// One rivet by its item's id; null when the item has no rivet spec.
  Future<RivetDefinition?> get(int itemId);
  Future<RivetDefinition> create(RivetInput input);
  Future<RivetDefinition> update(int itemId, RivetInput input);
}

/// /api/raw-materials/rivets (backend modules/items/rivets.js).
class ApiRivetRepository implements RivetRepository {
  ApiRivetRepository({
    http.Client? client,
    this.baseUrl = 'http://localhost:8080',
    this.useMockResponses = false,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final bool useMockResponses;

  static final List<RivetDefinition> _mock = <RivetDefinition>[];
  static int _mockNextId = 1;

  static void debugResetMockStore() {
    _mock.clear();
    _mockNextId = 1;
  }

  Uri _uri(String path) => Uri.parse('$baseUrl/api/raw-materials/rivets$path');

  Map<String, dynamic> _decode(http.Response response) {
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const RivetApiException(
        'The server answered something unexpected.',
      );
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded['success'] != true) {
      final existing = decoded['rivet'];
      throw RivetApiException(
        decoded['error'] as String? ?? 'The rivet could not be saved.',
        code: decoded['code'] as String?,
        existing: existing is Map<String, dynamic>
            ? RivetDefinition.fromJson(existing)
            : null,
      );
    }
    return decoded;
  }

  @override
  Future<List<RivetDefinition>> list() async {
    if (useMockResponses) return List<RivetDefinition>.of(_mock);
    final payload = _decode(await _client.get(_uri('')));
    return (payload['rivets'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(RivetDefinition.fromJson)
        .toList(growable: false);
  }

  @override
  Future<RivetDefinition?> get(int itemId) async {
    if (useMockResponses) {
      for (final rivet in _mock) {
        if (rivet.itemId == itemId) return rivet;
      }
      return null;
    }
    final response = await _client.get(_uri('/$itemId'));
    if (response.statusCode == 404) return null;
    final payload = _decode(response);
    return RivetDefinition.fromJson(payload['rivet'] as Map<String, dynamic>);
  }

  @override
  Future<RivetDefinition> create(RivetInput input) async {
    if (useMockResponses) return _mockSave(null, input);
    final payload = _decode(
      await _client.post(
        _uri(''),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(input.toJson()),
      ),
    );
    return RivetDefinition.fromJson(payload['rivet'] as Map<String, dynamic>);
  }

  @override
  Future<RivetDefinition> update(int itemId, RivetInput input) async {
    if (useMockResponses) return _mockSave(itemId, input);
    final payload = _decode(
      await _client.put(
        _uri('/$itemId'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(input.toJson()),
      ),
    );
    return RivetDefinition.fromJson(payload['rivet'] as Map<String, dynamic>);
  }

  RivetDefinition _mockSave(int? itemId, RivetInput input) {
    final saved = RivetDefinition(
      itemId: itemId ?? _mockNextId++,
      name: rivetName(
        rivetType: input.rivetType,
        headType: input.headType,
        dimensions: input.dimensions,
      ),
      code: input.code.trim(),
      rivetType: input.rivetType.trim(),
      headType: input.headType,
      dimensions: <RivetDimension, RivetLength?>{
        for (final dim in RivetDimension.values)
          dim: (input.dimensions[dim] ?? '').trim().isEmpty
              ? null
              : RivetLength(mm: input.dimensions[dim]!.trim(), nm: 0),
      },
      vendors: input.vendors,
    );
    _mock.removeWhere((r) => r.itemId == saved.itemId);
    _mock.add(saved);
    return saved;
  }
}

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/material_definition.dart';

class MaterialApiException implements Exception {
  const MaterialApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads and writes the material master.
///
/// The catalogue ships seeded, so the common case is reading it and editing one
/// density — a shop's brass is whatever its supplier ships, not whatever a
/// handbook says.
class MaterialRepository {
  MaterialRepository({
    http.Client? client,
    this.baseUrl = 'http://localhost:8080',
    this.useMockResponses = false,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final bool useMockResponses;

  /// Enough of the catalogue to render a screen in demo mode without a server.
  static const List<MaterialDefinition> _mock = <MaterialDefinition>[
    MaterialDefinition(id: 1, name: 'Steel / MS', densityGCm3: 7.85),
    MaterialDefinition(id: 2, name: 'Aluminium', densityGCm3: 2.70),
    MaterialDefinition(id: 3, name: 'Brass', densityGCm3: 8.50),
    MaterialDefinition(id: 4, name: 'Copper', densityGCm3: 8.96),
    MaterialDefinition(
      id: 5,
      name: 'Nylon',
      densityGCm3: 1.15,
      category: 'plastic',
    ),
  ];

  /// Where this material's swatch is served from.
  ///
  /// The generator writes `backend/public/materials/<slug>.png`, and the server
  /// mounts that folder at `/public`. Building the URL here keeps the one place
  /// that knows the host as the one place that knows the path.
  String imageUrl(MaterialDefinition material) =>
      '$baseUrl/public/${material.imagePath}';

  Map<String, dynamic> _decode(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Never _fail(http.Response response, String fallback) {
    throw MaterialApiException(
      _decode(response)['error']?.toString() ?? fallback,
    );
  }

  Future<List<MaterialDefinition>> list({bool includeArchived = false}) async {
    if (useMockResponses) return _mock;
    final uri = Uri.parse(
      '$baseUrl/api/material-types${includeArchived ? '?includeArchived=1' : ''}',
    );
    final response = await _client.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _fail(response, 'Could not load the material master.');
    }
    return (_decode(response)['materialTypes'] as List<dynamic>? ??
            const <dynamic>[])
        .whereType<Map>()
        .map((row) => MaterialDefinition.fromJson(row.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<MaterialDefinition> create(MaterialDefinition material) async {
    if (useMockResponses) return material;
    final response = await _client.post(
      Uri.parse('$baseUrl/api/material-types'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(material.toJson()),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _fail(response, 'Could not add the material.');
    }
    return MaterialDefinition.fromJson(
      (_decode(response)['materialType'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{},
    );
  }

  Future<MaterialDefinition> update(MaterialDefinition material) async {
    if (useMockResponses) return material;
    final response = await _client.patch(
      Uri.parse('$baseUrl/api/material-types/${material.id}'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(material.toJson()),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _fail(response, 'Could not save the material.');
    }
    return MaterialDefinition.fromJson(
      (_decode(response)['materialType'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{},
    );
  }

  /// Archives rather than deletes: a plan recorded last year names the material
  /// it was cut from, and that name has to keep resolving.
  Future<void> archive(int id) async {
    if (useMockResponses) return;
    final response = await _client.delete(
      Uri.parse('$baseUrl/api/material-types/$id'),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _fail(response, 'Could not archive the material.');
    }
  }
}

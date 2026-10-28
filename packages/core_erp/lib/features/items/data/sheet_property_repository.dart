import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/sheet_property.dart';

/// The item sheet's property columns, on the server.
abstract class SheetPropertyRepository {
  Future<List<SheetProperty>> list();

  /// Throws [SheetPropertyException] with `code == 'property_exists'` and the
  /// existing column when the name is already on the sheet.
  Future<SheetProperty> create({
    required String name,
    required String kind,
    List<String> options = const [],
  });

  Future<SheetProperty> update(int id, {String? name, List<String>? options});

  /// Adds one option unless it is already listed (ignoring case).
  Future<SheetProperty> addOption(int id, String label);

  /// Takes one option off the list (matched ignoring case). Parts carrying
  /// the value keep it.
  Future<SheetProperty> removeOption(int id, String label);

  Future<void> remove(int id);
}

class ApiSheetPropertyRepository implements SheetPropertyRepository {
  ApiSheetPropertyRepository({
    http.Client? client,
    this.baseUrl = 'http://localhost:8080',
    this.useMockResponses = false,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final bool useMockResponses;

  static final List<SheetProperty> _mock = <SheetProperty>[];
  static int _mockNextId = 1;

  static void debugResetMockStore() {
    _mock.clear();
    _mockNextId = 1;
  }

  Uri _uri(String path) => Uri.parse('$baseUrl/api/item-sheet-properties$path');

  SheetProperty _read(http.Response response) {
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const SheetPropertyException('The server answered something unexpected.');
    }
    final property = decoded['property'];
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded['success'] != true) {
      throw SheetPropertyException(
        decoded['error'] as String? ?? 'That did not save.',
        code: decoded['code'] as String?,
        existing: property is Map<String, dynamic>
            ? SheetProperty.fromJson(property)
            : null,
      );
    }
    return SheetProperty.fromJson(property as Map<String, dynamic>);
  }

  static List<String> _clean(Iterable<String> options) {
    final seen = <String>{};
    return [
      for (final raw in options)
        if (raw.trim().isNotEmpty && seen.add(raw.trim().toLowerCase()))
          raw.trim(),
    ];
  }

  @override
  Future<List<SheetProperty>> list() async {
    if (useMockResponses) return List.of(_mock);
    final response = await _client.get(_uri(''));
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> ||
        response.statusCode != 200 ||
        decoded['success'] != true) {
      throw SheetPropertyException(
        decoded is Map<String, dynamic>
            ? (decoded['error'] as String? ?? 'Could not load the sheet columns.')
            : 'Could not load the sheet columns.',
      );
    }
    return [
      for (final row in (decoded['properties'] as List? ?? const []))
        SheetProperty.fromJson(row as Map<String, dynamic>),
    ];
  }

  @override
  Future<SheetProperty> create({
    required String name,
    required String kind,
    List<String> options = const [],
  }) async {
    if (useMockResponses) {
      final key = name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
      final existing = _mock.where((p) => p.key == key).firstOrNull;
      if (existing != null) {
        throw SheetPropertyException(
          '"${existing.name}" is already a column on the sheet.',
          code: 'property_exists',
          existing: existing,
        );
      }
      final made = SheetProperty(
        id: _mockNextId++,
        key: key,
        propertyName: name.trim(),
        name: name.trim(),
        kind: kind,
        position: _mock.length + 1,
        options: _clean(options),
      );
      _mock.add(made);
      return made;
    }
    return _read(await _client.post(
      _uri(''),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name, 'kind': kind, 'options': options}),
    ));
  }

  @override
  Future<SheetProperty> update(int id, {String? name, List<String>? options}) async {
    if (useMockResponses) {
      final at = _mock.indexWhere((p) => p.id == id);
      if (at < 0) throw const SheetPropertyException('No such property column.');
      _mock[at] = _mock[at].copyWith(
        name: name?.trim(),
        options: options == null ? null : _clean(options),
      );
      return _mock[at];
    }
    return _read(await _client.patch(
      _uri('/$id'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        if (name != null) 'displayName': name,
        if (options != null) 'options': options,
      }),
    ));
  }

  @override
  Future<SheetProperty> addOption(int id, String label) async {
    if (useMockResponses) {
      final at = _mock.indexWhere((p) => p.id == id);
      if (at < 0) throw const SheetPropertyException('No such property column.');
      _mock[at] = _mock[at].copyWith(options: _clean([..._mock[at].options, label]));
      return _mock[at];
    }
    return _read(await _client.post(
      _uri('/$id/options'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'label': label}),
    ));
  }

  @override
  Future<SheetProperty> removeOption(int id, String label) async {
    if (useMockResponses) {
      final at = _mock.indexWhere((p) => p.id == id);
      if (at < 0) throw const SheetPropertyException('No such property column.');
      final drop = label.trim().toLowerCase();
      _mock[at] = _mock[at].copyWith(options: [
        for (final option in _mock[at].options)
          if (option.toLowerCase() != drop) option,
      ]);
      return _mock[at];
    }
    return _read(await _client.delete(
      _uri('/$id/options').replace(queryParameters: {'label': label}),
    ));
  }

  @override
  Future<void> remove(int id) async {
    if (useMockResponses) {
      _mock.removeWhere((p) => p.id == id);
      return;
    }
    final response = await _client.delete(_uri('/$id'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final decoded = jsonDecode(response.body);
      throw SheetPropertyException(
        decoded is Map<String, dynamic>
            ? (decoded['error'] as String? ?? 'The column was not removed.')
            : 'The column was not removed.',
      );
    }
  }
}

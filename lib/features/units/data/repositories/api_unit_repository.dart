import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/unit_definition.dart';
import '../../domain/unit_inputs.dart';
import '../models/unit_api_models.dart';
import 'unit_repository.dart';

class ApiUnitRepository implements UnitRepository {
  ApiUnitRepository({
    http.Client? client,
    this.baseUrl = 'http://localhost:8080',
    this.useMockResponses = true,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final bool useMockResponses;

  static final List<UnitDefinition> _mockUnits = <UnitDefinition>[];
  static int _mockNextId = 1;
  static bool _mockSeeded = false;

  @override
  Future<void> init() async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
    }
  }

  @override
  Future<List<UnitDefinition>> getUnits() async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      return List<UnitDefinition>.from(_mockUnits);
    }

    final uri = Uri.parse('$baseUrl/api/units');
    final response = await _client.get(uri);
    final payload = _decodeJsonObject(response.body);
    final parsed = UnitsListResponse.fromJson(payload);
    if (response.statusCode < 200 || response.statusCode >= 300 || !parsed.success) {
      throw UnitApiException(
        payload['error'] as String? ?? 'Failed to fetch units.',
      );
    }
    return parsed.units.map((unit) => unit.toDomain()).toList(growable: false);
  }

  @override
  Future<UnitDefinition> createUnit(CreateUnitInput input) async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      final unit = UnitDefinition(
        id: _mockNextId++,
        name: input.name.trim(),
        symbol: input.symbol.trim(),
        notes: input.notes.trim(),
        isArchived: false,
        usageCount: 0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      _mockUnits.add(unit);
      return unit;
    }

    final uri = Uri.parse('$baseUrl/api/units');
    final request = CreateUnitRequest.fromInput(input);
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );
    final payload = _decodeJsonObject(response.body);
    final parsed = UnitResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success ||
        parsed.unit == null) {
      throw UnitApiException(parsed.error ?? 'Failed to create unit.');
    }
    return parsed.unit!.toDomain();
  }

  @override
  Future<UnitDefinition> updateUnit(UpdateUnitInput input) async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      final index = _mockUnits.indexWhere((unit) => unit.id == input.id);
      if (index == -1) {
        throw UnitApiException('Unit not found.');
      }
      final current = _mockUnits[index];
      if (current.isUsed) {
        throw UnitApiException('Used units cannot be edited.');
      }
      final updated = UnitDefinition(
        id: current.id,
        name: input.name.trim(),
        symbol: input.symbol.trim(),
        notes: input.notes.trim(),
        isArchived: current.isArchived,
        usageCount: current.usageCount,
        createdAt: current.createdAt,
        updatedAt: DateTime.now(),
      );
      _mockUnits[index] = updated;
      return updated;
    }

    final uri = Uri.parse('$baseUrl/api/units/${input.id}');
    final request = UpdateUnitRequest.fromInput(input);
    final response = await _client.patch(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );
    final payload = _decodeJsonObject(response.body);
    final parsed = UnitResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success ||
        parsed.unit == null) {
      throw UnitApiException(parsed.error ?? 'Failed to update unit.');
    }
    return parsed.unit!.toDomain();
  }

  @override
  Future<UnitDefinition> archiveUnit(int id) async {
    return _updateArchiveState(id, archive: true);
  }

  @override
  Future<UnitDefinition> restoreUnit(int id) async {
    return _updateArchiveState(id, archive: false);
  }

  Future<UnitDefinition> _updateArchiveState(int id, {required bool archive}) async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      final index = _mockUnits.indexWhere((unit) => unit.id == id);
      if (index == -1) {
        throw UnitApiException('Unit not found.');
      }
      final current = _mockUnits[index];
      final updated = UnitDefinition(
        id: current.id,
        name: current.name,
        symbol: current.symbol,
        notes: current.notes,
        isArchived: archive,
        usageCount: current.usageCount,
        createdAt: current.createdAt,
        updatedAt: DateTime.now(),
      );
      _mockUnits[index] = updated;
      return updated;
    }

    final path = archive ? 'archive' : 'restore';
    final uri = Uri.parse('$baseUrl/api/units/$id/$path');
    final response = await _client.patch(uri);
    final payload = _decodeJsonObject(response.body);
    final parsed = UnitResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success ||
        parsed.unit == null) {
      throw UnitApiException(parsed.error ?? 'Failed to update unit status.');
    }
    return parsed.unit!.toDomain();
  }

  void _seedMockStoreIfNeeded() {
    if (_mockSeeded) {
      return;
    }
    _mockSeeded = true;
    final now = DateTime.now();
    _mockUnits
      ..clear()
      ..addAll([
        UnitDefinition(
          id: _mockNextId++,
          name: 'Kilogram',
          symbol: 'Kg',
          notes: 'Seeded unit',
          isArchived: false,
          usageCount: 3,
          createdAt: now,
          updatedAt: now,
        ),
        UnitDefinition(
          id: _mockNextId++,
          name: 'Sheet',
          symbol: 'Sheet',
          notes: 'Seeded unit',
          isArchived: false,
          usageCount: 2,
          createdAt: now,
          updatedAt: now,
        ),
      ]);
  }

  Map<String, dynamic> _decodeJsonObject(String body) {
    if (body.isEmpty) {
      return const {'success': false, 'error': 'Empty response from server.'};
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return {
        'success': false,
        'error': 'Unexpected response format from server.',
      };
    } on FormatException {
      return {
        'success': false,
        'error': body.trim().isEmpty
            ? 'Unexpected response from server.'
            : body.trim(),
      };
    }
  }
}

class UnitApiException implements Exception {
  const UnitApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

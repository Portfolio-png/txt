import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/client_definition.dart';
import '../../domain/client_inputs.dart';
import '../models/client_api_models.dart';
import 'client_repository.dart';

class ApiClientRepository implements ClientRepository {
  ApiClientRepository({
    http.Client? client,
    this.baseUrl = 'http://localhost:8080',
    this.useMockResponses = true,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final bool useMockResponses;

  static final List<ClientDefinition> _mockClients = <ClientDefinition>[];
  static int _mockNextId = 1;
  static bool _mockSeeded = false;

  static void debugResetMockStore() {
    _mockClients.clear();
    _mockNextId = 1;
    _mockSeeded = false;
  }

  @override
  Future<void> init() async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
    }
  }

  @override
  Future<List<ClientDefinition>> getClients() async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      return List<ClientDefinition>.from(_mockClients);
    }

    final uri = Uri.parse('$baseUrl/api/clients');
    final response = await _client.get(uri);
    final payload = _decodeJsonObject(response.body);
    final parsed = ClientsListResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success) {
      throw ClientApiException(
        payload['error'] as String? ?? 'Failed to fetch clients.',
      );
    }
    return parsed.clients
        .map((client) => client.toDomain())
        .toList(growable: false);
  }

  @override
  Future<ClientDefinition> createClient(CreateClientInput input) async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      _assertNoDuplicate(name: input.name, gstNumber: input.gstNumber);
      final now = DateTime.now();
      final created = ClientDefinition(
        id: _mockNextId++,
        name: input.name.trim(),
        alias: input.alias.trim(),
        gstNumber: _normalizeGstNumber(input.gstNumber),
        address: input.address.trim(),
        isArchived: false,
        usageCount: 0,
        createdAt: now,
        updatedAt: now,
      );
      _mockClients.add(created);
      return created;
    }

    final uri = Uri.parse('$baseUrl/api/clients');
    final request = CreateClientRequest.fromInput(input);
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );
    final payload = _decodeJsonObject(response.body);
    final parsed = ClientResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success ||
        parsed.client == null) {
      throw ClientApiException(parsed.error ?? 'Failed to create client.');
    }
    return parsed.client!.toDomain();
  }

  @override
  Future<ClientDefinition> updateClient(UpdateClientInput input) async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      final index = _mockClients.indexWhere((client) => client.id == input.id);
      if (index == -1) {
        throw ClientApiException('Client not found.');
      }
      _assertNoDuplicate(
        name: input.name,
        gstNumber: input.gstNumber,
        excludeId: input.id,
      );
      final current = _mockClients[index];
      final updated = ClientDefinition(
        id: current.id,
        name: input.name.trim(),
        alias: input.alias.trim(),
        gstNumber: _normalizeGstNumber(input.gstNumber),
        address: input.address.trim(),
        isArchived: current.isArchived,
        usageCount: current.usageCount,
        createdAt: current.createdAt,
        updatedAt: DateTime.now(),
      );
      _mockClients[index] = updated;
      return updated;
    }

    final uri = Uri.parse('$baseUrl/api/clients/${input.id}');
    final request = UpdateClientRequest.fromInput(input);
    final response = await _client.patch(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );
    final payload = _decodeJsonObject(response.body);
    final parsed = ClientResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success ||
        parsed.client == null) {
      throw ClientApiException(parsed.error ?? 'Failed to update client.');
    }
    return parsed.client!.toDomain();
  }

  @override
  Future<ClientDefinition> archiveClient(int id) async {
    return _updateArchiveState(id, archive: true);
  }

  @override
  Future<ClientDefinition> restoreClient(int id) async {
    return _updateArchiveState(id, archive: false);
  }

  Future<ClientDefinition> _updateArchiveState(
    int id, {
    required bool archive,
  }) async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      final index = _mockClients.indexWhere((client) => client.id == id);
      if (index == -1) {
        throw ClientApiException('Client not found.');
      }
      final current = _mockClients[index];
      final updated = ClientDefinition(
        id: current.id,
        name: current.name,
        alias: current.alias,
        gstNumber: current.gstNumber,
        address: current.address,
        isArchived: archive,
        usageCount: current.usageCount,
        createdAt: current.createdAt,
        updatedAt: DateTime.now(),
      );
      _mockClients[index] = updated;
      return updated;
    }

    final path = archive ? 'archive' : 'restore';
    final uri = Uri.parse('$baseUrl/api/clients/$id/$path');
    final response = await _client.patch(uri);
    final payload = _decodeJsonObject(response.body);
    final parsed = ClientResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success ||
        parsed.client == null) {
      throw ClientApiException(
        parsed.error ?? 'Failed to update client status.',
      );
    }
    return parsed.client!.toDomain();
  }

  void _assertNoDuplicate({
    required String name,
    required String gstNumber,
    int? excludeId,
  }) {
    final normalizedName = _normalize(name);
    final normalizedGstNumber = _normalizeGstNumber(gstNumber);

    for (final client in _mockClients) {
      if (excludeId != null && client.id == excludeId) {
        continue;
      }
      if (_normalize(client.name) == normalizedName) {
        throw const ClientApiException(
          'A client with the same name already exists.',
        );
      }
      if (normalizedGstNumber.isNotEmpty &&
          _normalizeGstNumber(client.gstNumber) == normalizedGstNumber) {
        throw const ClientApiException(
          'A client with the same GST number already exists.',
        );
      }
    }
  }

  void _seedMockStoreIfNeeded() {
    if (_mockSeeded) {
      return;
    }
    _mockSeeded = true;
    final now = DateTime.now();
    _mockClients
      ..clear()
      ..addAll([
        ClientDefinition(
          id: _mockNextId++,
          name: 'Acme Packaging Pvt. Ltd.',
          alias: 'Acme',
          gstNumber: '27ABCDE1234F1Z5',
          address: 'MIDC Industrial Area, Pune, Maharashtra 411019',
          isArchived: false,
          usageCount: 0,
          createdAt: now,
          updatedAt: now,
        ),
        ClientDefinition(
          id: _mockNextId++,
          name: 'Sunrise Retail LLP',
          alias: 'Sunrise',
          gstNumber: '24AAKCS9988M1Z2',
          address: 'Satellite Road, Ahmedabad, Gujarat 380015',
          isArchived: false,
          usageCount: 0,
          createdAt: now,
          updatedAt: now,
        ),
        ClientDefinition(
          id: _mockNextId++,
          name: 'Legacy Trading Co.',
          alias: 'Legacy',
          gstNumber: '',
          address: 'Old Market Road, Indore, Madhya Pradesh 452001',
          isArchived: true,
          usageCount: 0,
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

  static String _normalize(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  static String _normalizeGstNumber(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), '').toUpperCase();
  }
}

class ClientApiException implements Exception {
  const ClientApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

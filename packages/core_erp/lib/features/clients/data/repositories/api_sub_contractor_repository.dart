import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/sub_contractor_definition.dart';
import '../../domain/sub_contractor_inputs.dart';
import 'sub_contractor_repository.dart';

class SubContractorApiException implements Exception {
  const SubContractorApiException(this.message);
  final String message;
  @override
  String toString() => 'SubContractorApiException: $message';
}

class ApiSubContractorRepository implements SubContractorRepository {
  ApiSubContractorRepository({
    http.Client? client,
    this.baseUrl = 'http://localhost:8080',
    this.useMockResponses = true,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final bool useMockResponses;

  static final List<SubContractorDefinition> _mockSubContractors = <SubContractorDefinition>[];
  static int _mockNextId = 1;

  @override
  Future<void> init() async {}

  Map<String, dynamic> _decodeJsonObject(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  @override
  Future<List<SubContractorDefinition>> getSubContractors(int clientId) async {
    if (useMockResponses) {
      return _mockSubContractors.where((s) => s.clientId == clientId).toList();
    }

    final uri = Uri.parse('$baseUrl/api/clients/$clientId/sub-contractors');
    final response = await _client.get(uri);
    final payload = _decodeJsonObject(response.body);
    
    if (response.statusCode < 200 || response.statusCode >= 300 || payload['success'] == false) {
      throw SubContractorApiException(payload['error'] as String? ?? 'Failed to fetch sub-contractors.');
    }
    
    final list = payload['subContractors'] as List<dynamic>? ?? [];
    return list.map((e) => SubContractorDefinition.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<SubContractorDefinition>> getAllSubContractors() async {
    if (useMockResponses) {
      return _mockSubContractors.toList();
    }

    final uri = Uri.parse('$baseUrl/api/sub-contractors');
    final response = await _client.get(uri);
    final payload = _decodeJsonObject(response.body);
    
    if (response.statusCode < 200 || response.statusCode >= 300 || payload['success'] == false) {
      throw SubContractorApiException(payload['error'] as String? ?? 'Failed to fetch sub-contractors.');
    }
    
    final list = payload['subContractors'] as List<dynamic>? ?? [];
    return list.map((e) => SubContractorDefinition.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<SubContractorDefinition> createSubContractor(int clientId, CreateSubContractorInput input) async {
    if (useMockResponses) {
      final created = SubContractorDefinition(
        id: _mockNextId++,
        clientId: clientId,
        name: input.name,
        phone: input.phone,
        email: input.email,
        notes: input.notes,
        gstNumber: input.gstNumber,
        address: input.address,
        photoUrl: input.photoUrl,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      _mockSubContractors.add(created);
      return created;
    }

    final uri = Uri.parse('$baseUrl/api/clients/$clientId/sub-contractors');
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(input.toJson()),
    );
    final payload = _decodeJsonObject(response.body);

    if (response.statusCode < 200 || response.statusCode >= 300 || payload['success'] == false) {
      throw SubContractorApiException(payload['error'] as String? ?? 'Failed to create sub-contractor.');
    }

    return SubContractorDefinition.fromJson(payload['subContractor'] as Map<String, dynamic>);
  }

  @override
  Future<SubContractorDefinition> updateSubContractor(int id, UpdateSubContractorInput input) async {
    if (useMockResponses) {
      final index = _mockSubContractors.indexWhere((s) => s.id == id);
      if (index == -1) throw const SubContractorApiException('Not found');
      
      final current = _mockSubContractors[index];
      final updated = current.copyWith(
        name: input.name,
        phone: input.phone,
        email: input.email,
        notes: input.notes,
        gstNumber: input.gstNumber,
        address: input.address,
        photoUrl: input.photoUrl,
        updatedAt: DateTime.now(),
      );
      _mockSubContractors[index] = updated;
      return updated;
    }

    final uri = Uri.parse('$baseUrl/api/sub-contractors/$id');
    final response = await _client.put(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(input.toJson()),
    );
    final payload = _decodeJsonObject(response.body);

    if (response.statusCode < 200 || response.statusCode >= 300 || payload['success'] == false) {
      throw SubContractorApiException(payload['error'] as String? ?? 'Failed to update sub-contractor.');
    }

    return SubContractorDefinition.fromJson(payload['subContractor'] as Map<String, dynamic>);
  }

  @override
  Future<void> deleteSubContractor(int id) async {
    if (useMockResponses) {
      _mockSubContractors.removeWhere((s) => s.id == id);
      return;
    }

    final uri = Uri.parse('$baseUrl/api/sub-contractors/$id');
    final response = await _client.delete(uri);
    final payload = _decodeJsonObject(response.body);

    if (response.statusCode < 200 || response.statusCode >= 300 || payload['success'] == false) {
      throw SubContractorApiException(payload['error'] as String? ?? 'Failed to delete sub-contractor.');
    }
  }
}

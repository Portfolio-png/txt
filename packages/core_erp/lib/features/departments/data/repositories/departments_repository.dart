import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../domain/department_definition.dart';
import '../../domain/employee_definition.dart';

class DepartmentsRepository {
  DepartmentsRepository({
    http.Client? client,
    this.baseUrl = 'http://localhost:8080',
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  Future<void> init() async {}

  Future<List<DepartmentDefinition>> getDepartments() async {
    final uri = Uri.parse('$baseUrl/api/departments');
    final response = await _client.get(uri);
    final payload = _decodeJsonObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300 || payload['success'] != true) {
      throw DepartmentsApiException(payload['error'] as String? ?? 'Failed to fetch departments.');
    }
    final list = payload['departments'] as List<dynamic>? ?? [];
    return list.map((e) => DepartmentDefinition.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<DepartmentDefinition> createDepartment(String name, String description, String photoUrl) async {
    final uri = Uri.parse('$baseUrl/api/departments');
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name, 'description': description, 'photoUrl': photoUrl}),
    );
    final payload = _decodeJsonObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300 || payload['success'] != true) {
      throw DepartmentsApiException(payload['error'] as String? ?? 'Failed to create department.');
    }
    return DepartmentDefinition.fromJson(payload['department'] as Map<String, dynamic>);
  }

  Future<DepartmentDefinition> updateDepartment(int id, String name, String description, String photoUrl) async {
    final uri = Uri.parse('$baseUrl/api/departments/$id');
    final response = await _client.patch(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name, 'description': description, 'photoUrl': photoUrl}),
    );
    final payload = _decodeJsonObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300 || payload['success'] != true) {
      throw DepartmentsApiException(payload['error'] as String? ?? 'Failed to update department.');
    }
    return DepartmentDefinition.fromJson(payload['department'] as Map<String, dynamic>);
  }

  Future<void> deleteDepartment(int id) async {
    final uri = Uri.parse('$baseUrl/api/departments/$id');
    final response = await _client.delete(uri);
    final payload = _decodeJsonObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300 || payload['success'] != true) {
      throw DepartmentsApiException(payload['error'] as String? ?? 'Failed to delete department.');
    }
  }

  Future<List<EmployeeDefinition>> getEmployees() async {
    final uri = Uri.parse('$baseUrl/api/employees');
    final response = await _client.get(uri);
    final payload = _decodeJsonObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300 || payload['success'] != true) {
      throw DepartmentsApiException(payload['error'] as String? ?? 'Failed to fetch employees.');
    }
    final list = payload['employees'] as List<dynamic>? ?? [];
    return list.map((e) => EmployeeDefinition.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<EmployeeDefinition> createEmployee(int departmentId, String name, String role, String phone, String email, String employmentType, String barcodeId) async {
    final uri = Uri.parse('$baseUrl/api/employees');
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'departmentId': departmentId,
        'name': name,
        'role': role,
        'phone': phone,
        'email': email,
        'employmentType': employmentType,
        'barcodeId': barcodeId,
      }),
    );
    final payload = _decodeJsonObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300 || payload['success'] != true) {
      throw DepartmentsApiException(payload['error'] as String? ?? 'Failed to create employee.');
    }
    return EmployeeDefinition.fromJson(payload['employee'] as Map<String, dynamic>);
  }

  Future<EmployeeDefinition> updateEmployee(int id, int departmentId, String name, String role, String phone, String email, String employmentType, String barcodeId) async {
    final uri = Uri.parse('$baseUrl/api/employees/$id');
    final response = await _client.patch(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'departmentId': departmentId,
        'name': name,
        'role': role,
        'phone': phone,
        'email': email,
        'employmentType': employmentType,
        'barcodeId': barcodeId,
      }),
    );
    final payload = _decodeJsonObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300 || payload['success'] != true) {
      throw DepartmentsApiException(payload['error'] as String? ?? 'Failed to update employee.');
    }
    return EmployeeDefinition.fromJson(payload['employee'] as Map<String, dynamic>);
  }

  Future<void> deleteEmployee(int id) async {
    final uri = Uri.parse('$baseUrl/api/employees/$id');
    final response = await _client.delete(uri);
    final payload = _decodeJsonObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300 || payload['success'] != true) {
      throw DepartmentsApiException(payload['error'] as String? ?? 'Failed to delete employee.');
    }
  }

  Map<String, dynamic> _decodeJsonObject(String body) {
    if (body.isEmpty) return const {'success': false, 'error': 'Empty response'};
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      return {'success': false, 'error': 'Unexpected format'};
    } catch (_) {
      return {'success': false, 'error': 'Unexpected response'};
    }
  }
}

class DepartmentsApiException implements Exception {
  const DepartmentsApiException(this.message);
  final String message;
  @override
  String toString() => message;
}


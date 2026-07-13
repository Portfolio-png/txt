import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/vendor_definition.dart';
import '../../domain/vendor_inputs.dart';
import 'vendor_repository.dart';

class ApiVendorRepository implements VendorRepository {
  ApiVendorRepository({
    required http.Client client,
    required this.baseUrl,
    this.useMockResponses = false,
  }) : _client = client;

  final http.Client _client;
  final String baseUrl;
  final bool useMockResponses;
  static final List<VendorDefinition> _mockVendors = <VendorDefinition>[];

  @override
  Future<void> init() async {}

  @override
  Future<List<VendorDefinition>> getVendors() async {
    if (useMockResponses) {
      return List<VendorDefinition>.from(_mockVendors);
    }
    final payload = await _request('GET', '/api/vendors');
    final rows = payload['vendors'] as List<dynamic>? ?? const [];
    return rows
        .map((row) => _vendorFromJson(row as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<VendorDefinition?> getVendor(int id) async {
    if (useMockResponses) {
      try {
        return _mockVendors.firstWhere((v) => v.id == id);
      } catch (e) {
        return null;
      }
    }
    try {
      final payload = await _request('GET', '/api/vendors/$id');
      if (payload['vendor'] == null) return null;
      return _vendorFromJson(payload['vendor'] as Map<String, dynamic>);
    } catch (e) {
      if (e.toString().contains('404')) return null;
      rethrow;
    }
  }

  @override
  Future<VendorDefinition> createVendor(CreateVendorInput input) async {
    if (useMockResponses) {
      final created = VendorDefinition(
        id: _mockVendors.length + 1,
        name: input.name,
        alias: input.alias,
        gstNumber: input.gstNumber,
        address: input.address,
        contactName: input.contactName,
        phone: input.phone,
        email: input.email,
        isArchived: false,
        usageCount: 0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        logoUrl: input.logoUrl,
        photoUrl: input.photoUrl,
      );
      _mockVendors.add(created);
      return created;
    }
    final payload = await _request(
      'POST',
      '/api/vendors',
      body: {
        'name': input.name,
        'alias': input.alias,
        'gstNumber': input.gstNumber,
        'address': input.address,
        'contactName': input.contactName,
        'phone': input.phone,
        'email': input.email,
        'logoUrl': input.logoUrl,
        'photoUrl': input.photoUrl,
      },
    );
    return _vendorFromJson(payload['vendor'] as Map<String, dynamic>);
  }

  @override
  Future<VendorDefinition> updateVendor(UpdateVendorInput input) async {
    if (useMockResponses) {
      final index = _mockVendors.indexWhere((vendor) => vendor.id == input.id);
      final current = _mockVendors[index];
      final updated = VendorDefinition(
        id: current.id,
        name: input.name,
        alias: input.alias,
        gstNumber: input.gstNumber,
        address: input.address,
        contactName: input.contactName,
        phone: input.phone,
        email: input.email,
        isArchived: current.isArchived,
        usageCount: current.usageCount,
        createdAt: current.createdAt,
        updatedAt: DateTime.now(),
        logoUrl: input.logoUrl,
        photoUrl: input.photoUrl,
      );
      _mockVendors[index] = updated;
      return updated;
    }
    final payload = await _request(
      'PATCH',
      '/api/vendors/${input.id}',
      body: {
        'name': input.name,
        'alias': input.alias,
        'gstNumber': input.gstNumber,
        'address': input.address,
        'contactName': input.contactName,
        'phone': input.phone,
        'email': input.email,
        'logoUrl': input.logoUrl,
        'photoUrl': input.photoUrl,
      },
    );
    return _vendorFromJson(payload['vendor'] as Map<String, dynamic>);
  }

  @override
  Future<void> deleteVendor(int id) async {
    if (useMockResponses) {
      _mockVendors.removeWhere((vendor) => vendor.id == id);
      return;
    }
    await _request('DELETE', '/api/vendors/$id');
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    late final http.Response response;
    switch (method) {
      case 'GET':
        response = await _client.get(uri);
        break;
      case 'POST':
        response = await _client.post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body ?? const <String, dynamic>{}),
        );
        break;
      case 'PATCH':
        response = await _client.patch(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body ?? const <String, dynamic>{}),
        );
        break;
      default:
        throw UnsupportedError('Unsupported method $method');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw VendorApiException(
        payload['error'] as String? ?? 'Vendor request failed.',
      );
    }
    if (payload['success'] == false) {
      throw VendorApiException(
        payload['error'] as String? ?? 'Vendor request failed.',
      );
    }
    return payload;
  }

  VendorDefinition _vendorFromJson(Map<String, dynamic> json) {
    return VendorDefinition(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      alias: json['alias'] as String? ?? '',
      gstNumber:
          json['gstNumber'] as String? ?? json['gst_number'] as String? ?? '',
      address: json['address'] as String? ?? '',
      contactName:
          json['contactName'] as String? ??
          json['contact_name'] as String? ??
          '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      logoUrl: json['logoUrl'] as String? ?? json['logo_url'] as String? ?? '',
      photoUrl:
          json['photoUrl'] as String? ?? json['photo_url'] as String? ?? '',
      isArchived: json['isArchived'] as bool? ?? json['is_archived'] == 1,
      usageCount:
          json['usageCount'] as int? ?? json['usage_count'] as int? ?? 0,
      createdAt:
          DateTime.tryParse(
            json['createdAt'] as String? ?? json['created_at'] as String? ?? '',
          ) ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(
            json['updatedAt'] as String? ?? json['updated_at'] as String? ?? '',
          ) ??
          DateTime.now(),
    );
  }
}

class VendorApiException implements Exception {
  const VendorApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

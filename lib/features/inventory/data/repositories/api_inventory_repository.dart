import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/create_parent_material_input.dart';
import '../../domain/material_record.dart';
import '../models/api_models.dart';
import 'inventory_repository.dart';

class ApiInventoryRepository implements InventoryRepository {
  ApiInventoryRepository({
    http.Client? client,
    this.baseUrl = 'http://localhost:8080',
    this.useMockResponses = true,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final bool useMockResponses;

  static final List<MaterialDto> _mockMaterials = <MaterialDto>[];
  static bool _mockSeeded = false;
  static int _mockNextId = 1;

  @override
  Future<void> init() async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
    }
  }

  @override
  Future<void> seedIfEmpty() async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
    }
  }

  @override
  Future<SaveParentResult> saveParentWithChildren(
    CreateParentMaterialInput input,
  ) async {
    if (useMockResponses) {
      final response = _saveParentMock(input);
      return SaveParentResult(
        parentBarcode: response.material!.barcode,
        childBarcodes: response.material!.linkedChildBarcodes,
      );
    }

    final uri = Uri.parse('$baseUrl/api/materials/parent');
    final request = CreateParentRequest.fromInput(input);
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );
    final payload = _decodeJson(response.body) as Map<String, dynamic>;
    final materialResponse = MaterialResponse.fromJson(payload);

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !materialResponse.success ||
        materialResponse.material == null) {
      throw InventoryApiException(
        materialResponse.error ?? 'Failed to create parent material.',
      );
    }

    final material = materialResponse.material!;
    return SaveParentResult(
      parentBarcode: material.barcode,
      childBarcodes: material.linkedChildBarcodes,
    );
  }

  @override
  Future<MaterialRecord?> getMaterialByBarcode(String barcode) async {
    if (useMockResponses) {
      return incrementScanCount(barcode);
    }

    final uri = Uri.parse('$baseUrl/api/materials/$barcode');
    final response = await _client.get(uri);
    final payload = _decodeJson(response.body) as Map<String, dynamic>;
    final materialResponse = MaterialResponse.fromJson(payload);

    if (response.statusCode == 404 || materialResponse.material == null) {
      return null;
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !materialResponse.success) {
      throw InventoryApiException(
        materialResponse.error ?? 'Failed to fetch material.',
      );
    }

    await incrementScanCount(barcode);
    final refreshedResponse = await _client.get(uri);
    final refreshedPayload =
        _decodeJson(refreshedResponse.body) as Map<String, dynamic>;
    final refreshed = MaterialResponse.fromJson(refreshedPayload);
    return refreshed.material?.toRecord();
  }

  @override
  Future<List<MaterialRecord>> getAllMaterials() async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      return _sortedMockMaterials()
          .map((material) => material.toRecord())
          .toList(growable: false);
    }

    final uri = Uri.parse('$baseUrl/api/materials');
    final response = await _client.get(uri);
    final payload = _decodeJson(response.body) as Map<String, dynamic>;
    final materialsResponse = MaterialsListResponse.fromJson(payload);

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !materialsResponse.success) {
      throw InventoryApiException('Failed to fetch materials list.');
    }

    return materialsResponse.materials
        .map((material) => material.toRecord())
        .toList(growable: false);
  }

  @override
  Future<MaterialRecord?> incrementScanCount(String barcode) async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      final normalized = _normalizeBarcode(barcode);
      final index = _mockMaterials.indexWhere(
        (item) => _normalizeBarcode(item.barcode) == normalized,
      );
      if (index == -1) {
        return null;
      }

      final current = _mockMaterials[index];
      final updated = MaterialDto(
        id: current.id,
        barcode: current.barcode,
        name: current.name,
        type: current.type,
        grade: current.grade,
        thickness: current.thickness,
        supplier: current.supplier,
        unit: current.unit,
        notes: current.notes,
        isParent: current.isParent,
        parentBarcode: current.parentBarcode,
        numberOfChildren: current.numberOfChildren,
        linkedChildBarcodes: current.linkedChildBarcodes,
        scanCount: current.scanCount + 1,
        createdAt: current.createdAt,
      );
      _mockMaterials[index] = updated;
      return updated.toRecord();
    }

    final uri = Uri.parse('$baseUrl/api/materials/$barcode/scan');
    final response = await _client.patch(uri);
    final payload = _decodeJson(response.body) as Map<String, dynamic>;
    final materialResponse = MaterialResponse.fromJson(payload);

    if (response.statusCode == 404 || materialResponse.material == null) {
      return null;
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !materialResponse.success) {
      throw InventoryApiException(
        materialResponse.error ?? 'Failed to increment scan count.',
      );
    }

    return materialResponse.material!.toRecord();
  }

  @override
  Future<MaterialRecord?> resetScanTrace(String barcode) async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      final normalized = _normalizeBarcode(barcode);
      final index = _mockMaterials.indexWhere(
        (item) => _normalizeBarcode(item.barcode) == normalized,
      );
      if (index == -1) {
        return null;
      }

      final current = _mockMaterials[index];
      final updated = MaterialDto(
        id: current.id,
        barcode: current.barcode,
        name: current.name,
        type: current.type,
        grade: current.grade,
        thickness: current.thickness,
        supplier: current.supplier,
        unit: current.unit,
        notes: current.notes,
        isParent: current.isParent,
        parentBarcode: current.parentBarcode,
        numberOfChildren: current.numberOfChildren,
        linkedChildBarcodes: current.linkedChildBarcodes,
        scanCount: 0,
        createdAt: current.createdAt,
      );
      _mockMaterials[index] = updated;
      return updated.toRecord();
    }

    final uri = Uri.parse('$baseUrl/api/materials/$barcode/scan/reset');
    final response = await _client.patch(uri);
    final payload = _decodeJson(response.body) as Map<String, dynamic>;
    final materialResponse = MaterialResponse.fromJson(payload);

    if (response.statusCode == 404 || materialResponse.material == null) {
      return null;
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !materialResponse.success) {
      throw InventoryApiException(
        materialResponse.error ?? 'Failed to reset scan count.',
      );
    }

    return materialResponse.material!.toRecord();
  }

  MaterialResponse _saveParentMock(CreateParentMaterialInput input) {
    _seedMockStoreIfNeeded();

    final parentId = _mockNextId++;
    final now = DateTime.now();
    final parentBarcode = _generateParentBarcode();
    final childBarcodes = List<String>.generate(
      input.numberOfChildren,
      (index) => _generateChildBarcode(parentBarcode, index + 1),
    );

    final parent = MaterialDto(
      id: parentId,
      barcode: parentBarcode,
      name: input.name,
      type: input.type,
      grade: input.grade,
      thickness: input.thickness,
      supplier: input.supplier,
      unit: input.unit,
      notes: input.notes,
      isParent: true,
      parentBarcode: null,
      numberOfChildren: input.numberOfChildren,
      linkedChildBarcodes: childBarcodes,
      scanCount: 0,
      createdAt: now,
    );

    _mockMaterials.add(parent);

    for (var i = 0; i < childBarcodes.length; i++) {
      _mockMaterials.add(
        MaterialDto(
          id: _mockNextId++,
          barcode: childBarcodes[i],
          name: '${input.name} - Child ${i + 1}',
          type: input.type,
          grade: input.grade,
          thickness: input.thickness,
          supplier: input.supplier,
          unit: input.unit,
          notes: input.notes,
          isParent: false,
          parentBarcode: parentBarcode,
          numberOfChildren: 0,
          linkedChildBarcodes: const [],
          scanCount: 0,
          createdAt: now,
        ),
      );
    }

    return MaterialResponse(success: true, material: parent);
  }

  void _seedMockStoreIfNeeded() {
    if (_mockSeeded) {
      return;
    }

    _mockSeeded = true;
    _mockMaterials.clear();
    _mockNextId = 1;

    _saveParentMock(
      const CreateParentMaterialInput(
        name: 'Copper Master Roll',
        type: 'Raw Material',
        grade: 'A1',
        thickness: '1.2 mm',
        supplier: 'Shree Metals',
        unit: 'Kg',
        notes: 'Shared API seed',
        numberOfChildren: 3,
      ),
    );
    _saveParentMock(
      const CreateParentMaterialInput(
        name: 'Steel Sheet Batch',
        type: 'Raw Material',
        grade: 'B2',
        thickness: '2.0 mm',
        supplier: 'Metro Steels',
        unit: 'Sheet',
        notes: 'Shared API seed',
        numberOfChildren: 2,
      ),
    );
  }

  List<MaterialDto> _sortedMockMaterials() {
    final materials = List<MaterialDto>.from(_mockMaterials);
    materials.sort((a, b) {
      if (a.isParent == b.isParent) {
        if (!a.isParent) {
          final parentCompare = (a.parentBarcode ?? '').compareTo(
            b.parentBarcode ?? '',
          );
          if (parentCompare != 0) {
            return parentCompare;
          }
        }
        return a.barcode.compareTo(b.barcode);
      }
      return a.isParent ? -1 : 1;
    });
    return materials;
  }

  Object? _decodeJson(String body) {
    if (body.isEmpty) {
      return null;
    }
    return jsonDecode(body);
  }

  String _generateParentBarcode() {
    final suffix = 1000 + DateTime.now().microsecondsSinceEpoch % 9000;
    return 'PAR-${DateTime.now().millisecondsSinceEpoch}-$suffix';
  }

  String _generateChildBarcode(String parentBarcode, int index) {
    final parts = parentBarcode.split('-');
    final suffix = parts.isNotEmpty ? parts.last : parentBarcode;
    return 'CHD-$suffix-${index.toString().padLeft(2, '0')}';
  }

  String _normalizeBarcode(String value) {
    return value
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[^\x20-\x7E]'), '')
        .trim()
        .toUpperCase();
  }
}

class InventoryApiException implements Exception {
  const InventoryApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

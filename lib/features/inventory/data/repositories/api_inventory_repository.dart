import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/create_parent_material_input.dart';
import '../../domain/group_property_draft.dart';
import '../../domain/inventory_control_tower.dart';
import '../../domain/material_activity_event.dart';
import '../../domain/material_control_tower_detail.dart';
import '../../domain/material_group_configuration.dart';
import '../../domain/material_inputs.dart';
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
  static final Map<String, MaterialGroupConfiguration> _mockGroupConfigs =
      <String, MaterialGroupConfiguration>{};
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
  Future<MaterialGroupConfiguration> getGroupConfiguration(
    String barcode,
  ) async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      return _mockGroupConfigs[barcode] ?? const MaterialGroupConfiguration();
    }

    final uri = Uri.parse('$baseUrl/api/materials/$barcode');
    final response = await _client.get(uri);
    final payload = _decodeJson(response.body) as Map<String, dynamic>? ?? {};
    final materialResponse = MaterialResponse.fromJson(payload);

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !materialResponse.success ||
        materialResponse.material == null) {
      throw InventoryApiException(
        materialResponse.error ?? 'Failed to fetch group configuration.',
      );
    }

    return materialResponse.groupConfiguration?.toDomain(
          inheritanceEnabled: materialResponse.material!.inheritanceEnabled,
        ) ??
        MaterialGroupConfiguration(
          inheritanceEnabled: materialResponse.material!.inheritanceEnabled,
        );
  }

  @override
  Future<MaterialGroupConfiguration> updateGroupConfiguration(
    String barcode, {
    required bool inheritanceEnabled,
    required List<int> selectedItemIds,
    required List<GroupPropertyDraft> propertyDrafts,
    required List<GroupUnitGovernance> unitGovernance,
    required GroupUiPreferences uiPreferences,
  }) async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      final index = _mockMaterials.indexWhere(
        (item) => _normalizeBarcode(item.barcode) == _normalizeBarcode(barcode),
      );
      if (index == -1) {
        throw const InventoryApiException('Material not found.');
      }
      final current = _mockMaterials[index];
      _mockMaterials[index] = MaterialDto(
        id: current.id,
        barcode: current.barcode,
        name: current.name,
        type: current.type,
        grade: current.grade,
        thickness: current.thickness,
        supplier: current.supplier,
        location: current.location,
        unitId: current.unitId,
        unit: current.unit,
        notes: current.notes,
        groupMode: current.groupMode,
        inheritanceEnabled: inheritanceEnabled,
        isParent: current.isParent,
        parentBarcode: current.parentBarcode,
        numberOfChildren: current.numberOfChildren,
        linkedChildBarcodes: current.linkedChildBarcodes,
        scanCount: current.scanCount,
        createdAt: current.createdAt,
        linkedGroupId: current.linkedGroupId,
        linkedItemId: current.linkedItemId,
        displayStock: current.displayStock,
        createdBy: current.createdBy,
        workflowStatus: current.workflowStatus,
        updatedAt: DateTime.now(),
        lastScannedAt: current.lastScannedAt,
      );
      final config = MaterialGroupConfiguration(
        inheritanceEnabled: inheritanceEnabled,
        selectedItemIds: selectedItemIds,
        propertyDrafts: propertyDrafts,
        unitGovernance: unitGovernance,
        uiPreferences: uiPreferences,
      );
      _mockGroupConfigs[barcode] = config;
      return config;
    }

    final uri = Uri.parse('$baseUrl/api/materials/$barcode/group-config');
    final request = {
      'inheritanceEnabled': inheritanceEnabled,
      'selectedItemIds': selectedItemIds,
      'propertyDrafts': propertyDrafts
          .map((draft) => GroupPropertyDraftDto.fromDomain(draft).toJson())
          .toList(growable: false),
      'unitGovernance': unitGovernance
          .map((row) => GroupUnitGovernanceDto.fromDomain(row).toJson())
          .toList(growable: false),
      'uiPreferences': GroupUiPreferencesDto.fromDomain(uiPreferences).toJson(),
    };
    final response = await _client.patch(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(request),
    );
    final payload = _decodeJson(response.body) as Map<String, dynamic>? ?? {};
    final materialResponse = MaterialResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !materialResponse.success ||
        materialResponse.material == null) {
      throw InventoryApiException(
        materialResponse.error ?? 'Failed to update group configuration.',
      );
    }
    return materialResponse.groupConfiguration?.toDomain(
          inheritanceEnabled: materialResponse.material!.inheritanceEnabled,
        ) ??
        MaterialGroupConfiguration(
          inheritanceEnabled: materialResponse.material!.inheritanceEnabled,
        );
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
        location: current.location,
        unitId: current.unitId,
        unit: current.unit,
        notes: current.notes,
        groupMode: current.groupMode,
        inheritanceEnabled: current.inheritanceEnabled,
        isParent: current.isParent,
        parentBarcode: current.parentBarcode,
        numberOfChildren: current.numberOfChildren,
        linkedChildBarcodes: current.linkedChildBarcodes,
        scanCount: current.scanCount + 1,
        createdAt: current.createdAt,
        linkedGroupId: current.linkedGroupId,
        linkedItemId: current.linkedItemId,
        displayStock: current.displayStock,
        createdBy: current.createdBy,
        workflowStatus: current.workflowStatus,
        updatedAt: DateTime.now(),
        lastScannedAt: DateTime.now(),
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
        location: current.location,
        unitId: current.unitId,
        unit: current.unit,
        notes: current.notes,
        groupMode: current.groupMode,
        inheritanceEnabled: current.inheritanceEnabled,
        isParent: current.isParent,
        parentBarcode: current.parentBarcode,
        numberOfChildren: current.numberOfChildren,
        linkedChildBarcodes: current.linkedChildBarcodes,
        scanCount: 0,
        createdAt: current.createdAt,
        linkedGroupId: current.linkedGroupId,
        linkedItemId: current.linkedItemId,
        displayStock: current.displayStock,
        createdBy: current.createdBy,
        workflowStatus: current.workflowStatus,
        updatedAt: DateTime.now(),
        lastScannedAt: null,
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

  @override
  Future<MaterialRecord> createChildMaterial(
    CreateChildMaterialInput input,
  ) async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      final parentIndex = _mockMaterials.indexWhere(
        (item) =>
            _normalizeBarcode(item.barcode) ==
            _normalizeBarcode(input.parentBarcode),
      );
      if (parentIndex == -1) {
        throw const InventoryApiException('Parent material not found.');
      }
      final parent = _mockMaterials[parentIndex];
      final nextIndex = parent.numberOfChildren + 1;
      final child = MaterialDto(
        id: _mockNextId++,
        barcode: _generateChildBarcode(parent.barcode, nextIndex),
        name: input.name.trim(),
        type: parent.type,
        grade: parent.grade,
        thickness: parent.thickness,
        supplier: parent.supplier,
        location: parent.location,
        unitId: parent.unitId,
        unit: parent.unit,
        notes: input.notes,
        groupMode: parent.groupMode,
        inheritanceEnabled: parent.inheritanceEnabled,
        isParent: false,
        parentBarcode: parent.barcode,
        numberOfChildren: 0,
        linkedChildBarcodes: const [],
        scanCount: 0,
        createdAt: DateTime.now(),
        linkedGroupId: null,
        linkedItemId: null,
        displayStock: parent.displayStock,
        createdBy: parent.createdBy,
        workflowStatus: 'notStarted',
        updatedAt: DateTime.now(),
        lastScannedAt: null,
      );
      _mockMaterials[parentIndex] = MaterialDto(
        id: parent.id,
        barcode: parent.barcode,
        name: parent.name,
        type: parent.type,
        grade: parent.grade,
        thickness: parent.thickness,
        supplier: parent.supplier,
        location: parent.location,
        unitId: parent.unitId,
        unit: parent.unit,
        notes: parent.notes,
        groupMode: parent.groupMode,
        inheritanceEnabled: parent.inheritanceEnabled,
        isParent: true,
        parentBarcode: null,
        numberOfChildren: nextIndex,
        linkedChildBarcodes: [...parent.linkedChildBarcodes, child.barcode],
        scanCount: parent.scanCount,
        createdAt: parent.createdAt,
        linkedGroupId: parent.linkedGroupId,
        linkedItemId: parent.linkedItemId,
        displayStock: parent.displayStock,
        createdBy: parent.createdBy,
        workflowStatus: parent.workflowStatus,
        updatedAt: DateTime.now(),
        lastScannedAt: parent.lastScannedAt,
      );
      _mockMaterials.add(child);
      return child.toRecord();
    }

    final uri = Uri.parse(
      '$baseUrl/api/materials/${input.parentBarcode}/child',
    );
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'name': input.name, 'notes': input.notes}),
    );
    return _requireMaterialResponse(
      response,
      fallback: 'Failed to create sub-group.',
    );
  }

  @override
  Future<MaterialRecord> updateMaterial(UpdateMaterialInput input) async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      final index = _mockMaterials.indexWhere(
        (item) =>
            _normalizeBarcode(item.barcode) == _normalizeBarcode(input.barcode),
      );
      if (index == -1) {
        throw const InventoryApiException('Material not found.');
      }
      final current = _mockMaterials[index];
      final updated = MaterialDto(
        id: current.id,
        barcode: current.barcode,
        name: input.name.trim(),
        type: input.type.trim(),
        grade: input.grade.trim(),
        thickness: input.thickness.trim(),
        supplier: input.supplier.trim(),
        location: input.location.trim(),
        unitId: input.unitId,
        unit: input.unit.trim(),
        notes: input.notes.trim(),
        groupMode: current.groupMode,
        inheritanceEnabled: current.inheritanceEnabled,
        isParent: current.isParent,
        parentBarcode: current.parentBarcode,
        numberOfChildren: current.numberOfChildren,
        linkedChildBarcodes: current.linkedChildBarcodes,
        scanCount: current.scanCount,
        createdAt: current.createdAt,
        linkedGroupId: current.linkedGroupId,
        linkedItemId: current.linkedItemId,
        displayStock: current.displayStock,
        createdBy: current.createdBy,
        workflowStatus: current.workflowStatus,
        updatedAt: DateTime.now(),
        lastScannedAt: current.lastScannedAt,
      );
      _mockMaterials[index] = updated;
      return updated.toRecord();
    }

    final uri = Uri.parse('$baseUrl/api/materials/${input.barcode}');
    final response = await _client.patch(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': input.name,
        'type': input.type,
        'grade': input.grade,
        'thickness': input.thickness,
        'supplier': input.supplier,
        'location': input.location,
        'unitId': input.unitId,
        'unit': input.unit,
        'notes': input.notes,
      }),
    );
    return _requireMaterialResponse(
      response,
      fallback: 'Failed to update material.',
    );
  }

  @override
  Future<void> deleteMaterial(String barcode) async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      final normalized = _normalizeBarcode(barcode);
      final target = _mockMaterials
          .where((item) => _normalizeBarcode(item.barcode) == normalized)
          .firstOrNull;
      if (target == null) {
        throw const InventoryApiException('Material not found.');
      }
      _mockMaterials.removeWhere(
        (item) =>
            _normalizeBarcode(item.barcode) == normalized ||
            item.parentBarcode == target.barcode,
      );
      _mockGroupConfigs.removeWhere((key, value) {
        final normalizedKey = _normalizeBarcode(key);
        return normalizedKey == normalized ||
            normalizedKey == _normalizeBarcode(target.barcode);
      });
      if (target.parentBarcode != null) {
        final parentIndex = _mockMaterials.indexWhere(
          (item) => item.barcode == target.parentBarcode,
        );
        if (parentIndex != -1) {
          final parent = _mockMaterials[parentIndex];
          final nextChildren = parent.linkedChildBarcodes
              .where((childBarcode) => childBarcode != target.barcode)
              .toList(growable: false);
          _mockMaterials[parentIndex] = MaterialDto(
            id: parent.id,
            barcode: parent.barcode,
            name: parent.name,
            type: parent.type,
            grade: parent.grade,
            thickness: parent.thickness,
            supplier: parent.supplier,
            location: parent.location,
            unitId: parent.unitId,
            unit: parent.unit,
            notes: parent.notes,
            groupMode: parent.groupMode,
            inheritanceEnabled: parent.inheritanceEnabled,
            isParent: true,
            parentBarcode: null,
            numberOfChildren: nextChildren.length,
            linkedChildBarcodes: nextChildren,
            scanCount: parent.scanCount,
            createdAt: parent.createdAt,
            linkedGroupId: parent.linkedGroupId,
            linkedItemId: parent.linkedItemId,
            displayStock: parent.displayStock,
            createdBy: parent.createdBy,
            workflowStatus: parent.workflowStatus,
            updatedAt: DateTime.now(),
            lastScannedAt: parent.lastScannedAt,
          );
        }
      }
      return;
    }

    final uri = Uri.parse('$baseUrl/api/materials/$barcode');
    final response = await _client.delete(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final payload =
          _decodeJson(response.body) as Map<String, dynamic>? ?? const {};
      throw InventoryApiException(
        payload['error'] as String? ?? 'Failed to delete material.',
      );
    }
  }

  @override
  Future<MaterialRecord> linkMaterialToGroup(String barcode, int groupId) {
    return _linkMutation(
      barcode,
      endpoint: 'link-group',
      body: {'groupId': groupId},
      fallback: 'Failed to link group inheritance.',
      linkedGroupId: groupId,
      linkedItemId: null,
    );
  }

  @override
  Future<MaterialRecord> linkMaterialToItem(String barcode, int itemId) {
    return _linkMutation(
      barcode,
      endpoint: 'link-item',
      body: {'itemId': itemId},
      fallback: 'Failed to link item inheritance.',
      linkedGroupId: null,
      linkedItemId: itemId,
    );
  }

  @override
  Future<MaterialRecord> unlinkMaterial(String barcode) {
    return _linkMutation(
      barcode,
      endpoint: 'unlink',
      body: const {},
      fallback: 'Failed to unlink inherited properties.',
      linkedGroupId: null,
      linkedItemId: null,
    );
  }

  @override
  Future<List<MaterialActivityEvent>> getMaterialActivity(
    String barcode,
  ) async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      final material = _mockMaterials
          .where(
            (item) =>
                _normalizeBarcode(item.barcode) == _normalizeBarcode(barcode),
          )
          .firstOrNull;
      if (material == null) {
        return const [];
      }
      final events = <MaterialActivityEvent>[
        MaterialActivityEvent(
          barcode: material.barcode,
          type: 'created',
          label: material.isParent ? 'Group created' : 'Item created',
          description: material.isParent
              ? 'Inventory group ${material.name} was added to inventory.'
              : 'Inventory item ${material.name} was created under ${material.parentBarcode ?? 'its parent'}.',
          actor: material.createdBy,
          createdAt: material.createdAt,
        ),
      ];
      if (material.linkedGroupId != null || material.linkedItemId != null) {
        events.add(
          MaterialActivityEvent(
            barcode: material.barcode,
            type: 'linked',
            label: 'Inheritance linked',
            description: material.linkedItemId != null
                ? 'Linked to an item definition.'
                : 'Linked to a group definition.',
            actor: material.createdBy,
            createdAt: material.updatedAt,
          ),
        );
      }
      if ((material.scanCount > 0 || material.lastScannedAt != null) &&
          material.lastScannedAt != null) {
        events.add(
          MaterialActivityEvent(
            barcode: material.barcode,
            type: 'scan',
            label: 'Material scanned',
            description:
                'Scan trace updated to ${material.scanCount} total scans.',
            actor: 'Scanner',
            createdAt: material.lastScannedAt!,
          ),
        );
      }
      events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return events;
    }

    final uri = Uri.parse('$baseUrl/api/materials/$barcode/activity');
    final response = await _client.get(uri);
    final payload = _decodeJson(response.body);
    if (response.statusCode == 404 ||
        _isMissingActivityEndpoint(response.body, payload)) {
      return _fallbackActivityFromMaterial(barcode);
    }

    final jsonPayload = payload as Map<String, dynamic>? ?? const {};
    final activityResponse = MaterialActivityListResponse.fromJson(jsonPayload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !activityResponse.success) {
      throw InventoryApiException(
        activityResponse.error?.trim().isNotEmpty == true
            ? activityResponse.error!
            : 'Failed to fetch activity history.',
      );
    }

    return activityResponse.events
        .map((event) => event.toEvent())
        .toList(growable: false);
  }

  bool _isMissingActivityEndpoint(String rawBody, Object? decodedPayload) {
    final body = rawBody.toLowerCase();
    if (body.contains('cannot get') && body.contains('/activity')) {
      return true;
    }
    if (decodedPayload is Map<String, dynamic>) {
      final error = (decodedPayload['error'] as String?)?.toLowerCase() ?? '';
      if (error.contains('cannot get') && error.contains('/activity')) {
        return true;
      }
    }
    return false;
  }

  Future<List<MaterialActivityEvent>> _fallbackActivityFromMaterial(
    String barcode,
  ) async {
    final materials = await getAllMaterials();
    final material = materials
        .where(
          (item) =>
              _normalizeBarcode(item.barcode) == _normalizeBarcode(barcode),
        )
        .firstOrNull;
    if (material == null) {
      return const [];
    }
    final events = <MaterialActivityEvent>[
      MaterialActivityEvent(
        barcode: material.barcode,
        type: 'created',
        label: material.isParent ? 'Group created' : 'Item created',
        description: material.isParent
            ? 'Inventory group ${material.name} was added to inventory.'
            : 'Inventory item ${material.name} was created under ${material.parentBarcode ?? 'its parent'}.',
        actor: material.createdBy,
        createdAt: material.createdAt,
      ),
    ];
    if (material.hasInheritanceLink) {
      events.add(
        MaterialActivityEvent(
          barcode: material.barcode,
          type: 'linked',
          label: 'Inheritance linked',
          description: material.linkedItemId != null
              ? 'Linked to an item definition.'
              : 'Linked to a group definition.',
          actor: material.createdBy,
          createdAt: material.updatedAt,
        ),
      );
    }
    if (material.hasBeenScanned && material.lastScannedAt != null) {
      events.add(
        MaterialActivityEvent(
          barcode: material.barcode,
          type: 'scan',
          label: 'Material scanned',
          description:
              'Scan trace updated to ${material.scanCount} total scans.',
          actor: 'Scanner',
          createdAt: material.lastScannedAt!,
        ),
      );
    }
    events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return events;
  }

  @override
  Future<InventoryHealthSnapshot> getInventoryHealth() async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      final materials = _mockMaterials.map((item) => item.toRecord()).toList();
      final lowStock = materials
          .where((item) => item.availableToPromise <= 100 && item.onHand > 0)
          .length;
      final reservedRisk = materials
          .where((item) => item.reserved > item.onHand && item.reserved > 0)
          .length;
      return InventoryHealthSnapshot(
        lowStockCount: lowStock,
        reservedRiskCount: reservedRisk,
        incomingTodayCount: materials.where((item) => item.incoming > 0).length,
        qualityHoldCount: materials
            .where((item) => item.inventoryState == InventoryState.qualityHold)
            .length,
        unitMismatchCount: materials
            .where((item) => item.pendingAlertCount > 0)
            .length,
        pendingReconciliationCount: materials
            .where((item) => item.pendingAlertCount > 0)
            .length,
      );
    }

    final uri = Uri.parse('$baseUrl/api/inventory/health');
    final response = await _client.get(uri);
    final payload = _decodeJson(response.body) as Map<String, dynamic>? ?? {};
    final parsed = InventoryHealthResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success) {
      throw InventoryApiException(
        parsed.error ?? 'Failed to load inventory health.',
      );
    }
    return parsed.health;
  }

  @override
  Future<MaterialControlTowerDetail?> getMaterialControlTowerDetail(
    String barcode,
  ) async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      final material = _mockMaterials
          .where(
            (item) =>
                _normalizeBarcode(item.barcode) == _normalizeBarcode(barcode),
          )
          .firstOrNull;
      if (material == null) {
        return null;
      }
      final location = material.location.trim();
      final stock = StockPosition(
        locationId: location.isEmpty ? 'MAIN' : location,
        locationName: location.isEmpty ? 'Main Warehouse' : location,
        lotCode: material.barcode,
        unitId: material.unitId,
        onHandQty: material.onHand,
        reservedQty: material.reserved,
        damagedQty: 0,
        updatedAt: material.updatedAt,
      );
      return MaterialControlTowerDetail(
        material: material.toRecord(),
        stockPositions: [stock],
        movements: const [],
        reservations: const [],
        alerts: const [],
        linkedOrderDemand: material.linkedOrderCount.toDouble(),
        linkedPipelineDemand: material.linkedPipelineCount.toDouble(),
        pendingAlertsCount: material.pendingAlertCount,
      );
    }

    final uri = Uri.parse('$baseUrl/api/materials/$barcode/detail');
    final response = await _client.get(uri);
    final payload = _decodeJson(response.body) as Map<String, dynamic>? ?? {};
    final parsed = MaterialControlTowerDetailResponse.fromJson(payload);
    if (response.statusCode == 404 || parsed.material == null) {
      return null;
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success) {
      throw InventoryApiException(
        parsed.error ?? 'Failed to load material detail.',
      );
    }
    return parsed.toDomain();
  }

  @override
  Future<MaterialControlTowerDetail> createInventoryMovement(
    CreateInventoryMovementInput input,
  ) async {
    if (useMockResponses) {
      final material = await getMaterialControlTowerDetail(
        input.materialBarcode,
      );
      if (material == null) {
        throw const InventoryApiException('Material not found.');
      }
      return material;
    }

    final uri = Uri.parse('$baseUrl/api/inventory/movements');
    final request = CreateInventoryMovementRequest.fromInput(input);
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );
    final payload = _decodeJson(response.body) as Map<String, dynamic>? ?? {};
    final parsed = MaterialControlTowerDetailResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success) {
      throw InventoryApiException(
        parsed.error ?? 'Failed to apply inventory movement.',
      );
    }
    return parsed.toDomain();
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
      location: input.location,
      unitId: input.unitId,
      unit: input.unit,
      notes: input.notes,
      groupMode: input.groupMode,
      inheritanceEnabled: input.inheritanceEnabled,
      isParent: true,
      parentBarcode: null,
      numberOfChildren: input.numberOfChildren,
      linkedChildBarcodes: childBarcodes,
      scanCount: 0,
      createdAt: now,
      linkedGroupId: null,
      linkedItemId: null,
      displayStock: input.unit.trim().isEmpty
          ? '${input.numberOfChildren * 100} Pieces'
          : '${input.numberOfChildren * 100} ${input.unit.trim()}',
      createdBy: 'Demo Admin',
      workflowStatus: 'inProgress',
      updatedAt: now,
      lastScannedAt: null,
    );

    _mockMaterials.add(parent);
    _mockGroupConfigs[parentBarcode] = MaterialGroupConfiguration(
      inheritanceEnabled: input.inheritanceEnabled,
      selectedItemIds: input.selectedItemIds,
      propertyDrafts: input.propertyDrafts,
      unitGovernance: input.unitGovernance,
      uiPreferences: input.uiPreferences,
    );

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
          location: input.location,
          unitId: input.unitId,
          unit: input.unit,
          notes: input.notes,
          groupMode: input.groupMode,
          inheritanceEnabled: input.inheritanceEnabled,
          isParent: false,
          parentBarcode: parentBarcode,
          numberOfChildren: 0,
          linkedChildBarcodes: const [],
          scanCount: 0,
          createdAt: now,
          linkedGroupId: null,
          linkedItemId: null,
          displayStock: input.unit.trim().isEmpty
              ? '100 Pieces'
              : '100 ${input.unit.trim()}',
          createdBy: 'Demo Admin',
          workflowStatus: 'notStarted',
          updatedAt: now,
          lastScannedAt: null,
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
    _mockGroupConfigs.clear();
    _mockNextId = 1;

    final chemicals = _saveParentMock(
      const CreateParentMaterialInput(
        name: 'Chemicals',
        type: 'Raw Material',
        grade: 'Industrial',
        thickness: 'Mixed',
        supplier: 'Central Chemical Supply',
        unit: 'Kg',
        notes: 'Shared API seed',
        numberOfChildren: 0,
      ),
    );
    final adhesives = _saveParentMock(
      const CreateParentMaterialInput(
        name: 'Adhesives',
        type: 'Raw Material',
        grade: 'Reactive',
        thickness: 'Mixed',
        supplier: 'BondChem Industries',
        unit: 'Kg',
        notes: 'Shared API seed',
        numberOfChildren: 2,
      ),
    );
    final solvents = _saveParentMock(
      const CreateParentMaterialInput(
        name: 'Solvents',
        type: 'Raw Material',
        grade: 'Purified',
        thickness: 'Mixed',
        supplier: 'PureChem Logistics',
        unit: 'Litre',
        notes: 'Shared API seed',
        numberOfChildren: 1,
      ),
    );
    final inks = _saveParentMock(
      const CreateParentMaterialInput(
        name: 'Inks',
        type: 'Raw Material',
        grade: 'Flexo',
        thickness: 'Mixed',
        supplier: 'ColorBond Inks',
        unit: 'Kg',
        notes: 'Shared API seed',
        numberOfChildren: 1,
      ),
    );

    _applyMockSeedLinks(
      parentBarcode: chemicals.material!.barcode,
      linkedGroupId: 1,
      childItemIds: const [],
    );
    _applyMockSeedLinks(
      parentBarcode: adhesives.material!.barcode,
      linkedGroupId: 2,
      childItemIds: const [1, 2],
    );
    _applyMockSeedLinks(
      parentBarcode: solvents.material!.barcode,
      linkedGroupId: 3,
      childItemIds: const [3],
    );
    _applyMockSeedLinks(
      parentBarcode: inks.material!.barcode,
      linkedGroupId: 4,
      childItemIds: const [4],
    );
  }

  void _applyMockSeedLinks({
    required String parentBarcode,
    required int linkedGroupId,
    required List<int> childItemIds,
  }) {
    _setMockInheritanceLink(
      parentBarcode,
      linkedGroupId: linkedGroupId,
      linkedItemId: null,
    );
    final children = _mockMaterials
        .where((material) => material.parentBarcode == parentBarcode)
        .toList(growable: false);
    for (
      var index = 0;
      index < children.length && index < childItemIds.length;
      index++
    ) {
      _setMockInheritanceLink(
        children[index].barcode,
        linkedGroupId: null,
        linkedItemId: childItemIds[index],
      );
    }
  }

  void _setMockInheritanceLink(
    String barcode, {
    required int? linkedGroupId,
    required int? linkedItemId,
  }) {
    final index = _mockMaterials.indexWhere(
      (item) => _normalizeBarcode(item.barcode) == _normalizeBarcode(barcode),
    );
    if (index == -1) {
      return;
    }
    final current = _mockMaterials[index];
    _mockMaterials[index] = MaterialDto(
      id: current.id,
      barcode: current.barcode,
      name: current.name,
      type: current.type,
      grade: current.grade,
      thickness: current.thickness,
      supplier: current.supplier,
      location: current.location,
      unitId: current.unitId,
      unit: current.unit,
      notes: current.notes,
      groupMode: current.groupMode,
      inheritanceEnabled: current.inheritanceEnabled,
      isParent: current.isParent,
      parentBarcode: current.parentBarcode,
      numberOfChildren: current.numberOfChildren,
      linkedChildBarcodes: current.linkedChildBarcodes,
      scanCount: current.scanCount,
      createdAt: current.createdAt,
      linkedGroupId: linkedGroupId,
      linkedItemId: linkedItemId,
      displayStock: current.displayStock,
      createdBy: current.createdBy,
      workflowStatus: current.workflowStatus,
      updatedAt: DateTime.now(),
      lastScannedAt: current.lastScannedAt,
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
    try {
      return jsonDecode(body);
    } on FormatException {
      return {'success': false, 'error': _extractTransportError(body)};
    }
  }

  String _extractTransportError(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return 'Unexpected response from server.';
    }

    final lower = trimmed.toLowerCase();
    if (lower.contains('<!doctype html') || lower.contains('<html')) {
      final cannotGetMatch = RegExp(
        r'cannot\s+get\s+([^\s<]+)',
        caseSensitive: false,
      ).firstMatch(trimmed);
      if (cannotGetMatch != null) {
        return 'Endpoint unavailable: ${cannotGetMatch.group(1)}';
      }
      return 'Server returned HTML instead of JSON.';
    }

    return trimmed.replaceAll(RegExp(r'\s+'), ' ');
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

  Future<MaterialRecord> _linkMutation(
    String barcode, {
    required String endpoint,
    required Map<String, Object?> body,
    required String fallback,
    required int? linkedGroupId,
    required int? linkedItemId,
  }) async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      final index = _mockMaterials.indexWhere(
        (item) => _normalizeBarcode(item.barcode) == _normalizeBarcode(barcode),
      );
      if (index == -1) {
        throw const InventoryApiException('Material not found.');
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
        location: current.location,
        unitId: current.unitId,
        unit: current.unit,
        notes: current.notes,
        groupMode: current.groupMode,
        inheritanceEnabled: current.inheritanceEnabled,
        isParent: current.isParent,
        parentBarcode: current.parentBarcode,
        numberOfChildren: current.numberOfChildren,
        linkedChildBarcodes: current.linkedChildBarcodes,
        scanCount: current.scanCount,
        createdAt: current.createdAt,
        linkedGroupId: linkedGroupId,
        linkedItemId: linkedItemId,
        displayStock: current.displayStock,
        createdBy: current.createdBy,
        workflowStatus: current.workflowStatus,
        updatedAt: DateTime.now(),
        lastScannedAt: current.lastScannedAt,
      );
      _mockMaterials[index] = updated;
      return updated.toRecord();
    }

    final uri = Uri.parse('$baseUrl/api/materials/$barcode/$endpoint');
    final response = await _client.patch(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return _requireMaterialResponse(response, fallback: fallback);
  }

  MaterialRecord _requireMaterialResponse(
    http.Response response, {
    required String fallback,
  }) {
    final payload =
        _decodeJson(response.body) as Map<String, dynamic>? ?? const {};
    final materialResponse = MaterialResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !materialResponse.success ||
        materialResponse.material == null) {
      throw InventoryApiException(materialResponse.error ?? fallback);
    }
    return materialResponse.material!.toRecord();
  }
}

class InventoryApiException implements Exception {
  const InventoryApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

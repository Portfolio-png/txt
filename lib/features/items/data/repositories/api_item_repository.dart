import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/item_asset.dart';
import '../../domain/item_definition.dart';
import '../../domain/item_inputs.dart';
import '../models/item_api_models.dart';
import 'item_repository.dart';

class ApiItemRepository implements ItemRepository {
  ApiItemRepository({
    http.Client? client,
    this.baseUrl = 'http://localhost:8080',
    this.useMockResponses = true,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final bool useMockResponses;

  static final List<ItemDefinition> _mockItems = <ItemDefinition>[];
  static final Map<int, List<ItemAsset>> _mockAssetsByItemId =
      <int, List<ItemAsset>>{};
  static final Map<String, ItemAssetUploadIntentInput> _mockUploadSessions =
      <String, ItemAssetUploadIntentInput>{};
  static int _mockNextItemId = 1;
  static int _mockNextNodeId = 1;
  static int _mockNextAssetId = 1;
  static bool _mockSeeded = false;

  @override
  Future<void> init() async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
    }
  }

  @override
  Future<List<ItemDefinition>> getItems() async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      return List<ItemDefinition>.from(_mockItems);
    }

    final uri = Uri.parse('$baseUrl/api/items');
    final response = await _client.get(uri);
    final payload = _decodeJsonObject(response.body);
    final parsed = ItemsListResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success) {
      throw ItemApiException(
        payload['error'] as String? ?? 'Failed to fetch items.',
      );
    }
    return parsed.items.map((item) => item.toDomain()).toList(growable: false);
  }

  @override
  Future<ItemDefinition> createItem(CreateItemInput input) async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      _validateCreateOrUpdate(
        name: input.name,
        groupId: input.groupId,
        variationTree: input.variationTree,
      );
      final now = DateTime.now();
      final itemId = _mockNextItemId++;
      final tree = _buildTree(
        itemId: itemId,
        inputs: input.variationTree,
        existing: const [],
        parentNodeId: null,
        timestamp: now,
      );
      final created = ItemDefinition(
        id: itemId,
        name: input.name.trim(),
        alias: input.alias.trim(),
        displayName: _itemDisplayNameOrFallback(
          input.displayName,
          name: input.name,
          alias: input.alias,
        ),
        quantity: 0,
        groupId: input.groupId,
        unitId: input.unitId,
        unitConversions: input.unitConversions
            .map(
              (entry) => ItemUnitConversionDefinition(
                unitId: entry.unitId,
                unitName: '',
                unitSymbol: '',
                factorToPrimary: entry.factorToPrimary,
              ),
            )
            .toList(growable: false),
        namingFormat: input.namingFormat,
        isArchived: false,
        usageCount: 0,
        createdAt: now,
        updatedAt: now,
        variationTree: tree,
      );
      _mockItems.add(created);
      return created;
    }

    final uri = Uri.parse('$baseUrl/api/items');
    final request = CreateItemRequest.fromInput(input);
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );
    final payload = _decodeJsonObject(response.body);
    final parsed = ItemResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success ||
        parsed.item == null) {
      throw ItemApiException(parsed.error ?? 'Failed to create item.');
    }
    return parsed.item!.toDomain();
  }

  @override
  Future<ItemDefinition> updateItem(UpdateItemInput input) async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      final index = _mockItems.indexWhere((item) => item.id == input.id);
      if (index == -1) {
        throw ItemApiException('Item not found.');
      }
      final current = _mockItems[index];
      _validateCreateOrUpdate(
        id: input.id,
        name: input.name,
        groupId: input.groupId,
        variationTree: input.variationTree,
      );
      final now = DateTime.now();
      final tree = _buildTree(
        itemId: current.id,
        inputs: input.variationTree,
        existing: current.variationTree,
        parentNodeId: null,
        timestamp: now,
      );
      final updated = ItemDefinition(
        id: current.id,
        name: input.name.trim(),
        alias: input.alias.trim(),
        displayName: _itemDisplayNameOrFallback(
          input.displayName,
          name: input.name,
          alias: input.alias,
        ),
        quantity: 0,
        groupId: input.groupId,
        unitId: input.unitId,
        unitConversions: input.unitConversions
            .map(
              (entry) => ItemUnitConversionDefinition(
                unitId: entry.unitId,
                unitName: '',
                unitSymbol: '',
                factorToPrimary: entry.factorToPrimary,
              ),
            )
            .toList(growable: false),
        namingFormat: input.namingFormat,
        isArchived: current.isArchived,
        usageCount: current.usageCount,
        createdAt: current.createdAt,
        updatedAt: now,
        variationTree: tree,
      );
      _mockItems[index] = updated;
      return updated;
    }

    final uri = Uri.parse('$baseUrl/api/items/${input.id}');
    final request = UpdateItemRequest.fromInput(input);
    final response = await _client.patch(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );
    final payload = _decodeJsonObject(response.body);
    final parsed = ItemResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success ||
        parsed.item == null) {
      throw ItemApiException(parsed.error ?? 'Failed to update item.');
    }
    return parsed.item!.toDomain();
  }

  @override
  Future<ItemDefinition> archiveItem(int id) async {
    return _updateArchiveState(id, archive: true);
  }

  @override
  Future<ItemDefinition> restoreItem(int id) async {
    return _updateArchiveState(id, archive: false);
  }

  @override
  Future<List<ItemAsset>> getItemAssets(int itemId) async {
    if (useMockResponses) {
      return List<ItemAsset>.from(
        _mockAssetsByItemId[itemId] ?? const <ItemAsset>[],
      );
    }

    final uri = Uri.parse('$baseUrl/api/items/$itemId/assets');
    final response = await _client.get(uri);
    final payload = _decodeJsonObject(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw ItemApiException(
        payload['error'] as String? ?? 'Failed to fetch item images.',
      );
    }
    return (payload['assets'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_itemAssetFromJson)
        .toList(growable: false);
  }

  @override
  Future<ItemAssetUploadIntent> createAssetUploadIntent(
    ItemAssetUploadIntentInput input,
  ) async {
    if (useMockResponses) {
      final existing =
          (_mockAssetsByItemId[input.itemId] ?? const <ItemAsset>[])
              .where((asset) => asset.sha256 == input.sha256)
              .firstOrNull;
      if (existing != null) {
        return ItemAssetUploadIntent(alreadyUploaded: true, asset: existing);
      }
      final sessionId =
          'mock-asset-session-${DateTime.now().microsecondsSinceEpoch}';
      _mockUploadSessions[sessionId] = input;
      return ItemAssetUploadIntent(
        alreadyUploaded: false,
        upload: ItemAssetUploadTarget(
          uploadSessionId: sessionId,
          objectKey:
              'item-images/${input.itemId}/${input.sha256}/${input.fileName}',
          uploadUrl: Uri.parse('https://mock.local/$sessionId'),
          headers: const <String, String>{},
        ),
      );
    }

    final uri = Uri.parse('$baseUrl/api/assets/upload-intent');
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'entityType': 'item',
        'entityId': input.itemId,
        'fileName': input.fileName,
        'contentType': input.contentType,
        'sizeBytes': input.sizeBytes,
        'sha256': input.sha256,
        'isPrimary': input.isPrimary,
      }),
    );
    final payload = _decodeJsonObject(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true ||
        payload['intent'] is! Map<String, dynamic>) {
      throw ItemApiException(
        payload['error'] as String? ?? 'Failed to create image upload.',
      );
    }
    return _itemAssetUploadIntentFromJson(
      payload['intent'] as Map<String, dynamic>,
    );
  }

  @override
  Future<ItemAsset> completeAssetUpload(
    CompleteItemAssetUploadInput input,
  ) async {
    if (useMockResponses) {
      final session = _mockUploadSessions[input.uploadSessionId];
      if (session == null) {
        throw ItemApiException('Upload session not found.');
      }
      final current = List<ItemAsset>.from(
        _mockAssetsByItemId[session.itemId] ?? const <ItemAsset>[],
      );
      final existing = current
          .where((asset) => asset.sha256 == session.sha256)
          .firstOrNull;
      if (existing != null) {
        return existing;
      }
      final now = DateTime.now();
      final shouldBePrimary = session.isPrimary || current.isEmpty;
      final created = ItemAsset(
        id: _mockNextAssetId++,
        entityType: 'item',
        entityId: session.itemId,
        fileName: session.fileName,
        contentType: session.contentType,
        sizeBytes: session.sizeBytes,
        sha256: session.sha256,
        objectKey: input.objectKey,
        status: 'uploaded',
        isPrimary: shouldBePrimary,
        createdAt: now,
        uploadedAt: now,
      );
      _mockAssetsByItemId[session.itemId] = <ItemAsset>[
        if (shouldBePrimary)
          for (final asset in current) _copyAsset(asset, isPrimary: false)
        else
          ...current,
        created,
      ];
      return created;
    }

    final uri = Uri.parse('$baseUrl/api/assets/upload-complete');
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'uploadSessionId': input.uploadSessionId,
        'objectKey': input.objectKey,
      }),
    );
    final payload = _decodeJsonObject(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true ||
        payload['asset'] is! Map<String, dynamic>) {
      throw ItemApiException(
        payload['error'] as String? ?? 'Failed to complete image upload.',
      );
    }
    return _itemAssetFromJson(payload['asset'] as Map<String, dynamic>);
  }

  @override
  Future<ItemAsset> setPrimaryAsset(int assetId) async {
    if (useMockResponses) {
      for (final entry in _mockAssetsByItemId.entries) {
        final index = entry.value.indexWhere((asset) => asset.id == assetId);
        if (index == -1) {
          continue;
        }
        final updated = entry.value
            .map((asset) => _copyAsset(asset, isPrimary: asset.id == assetId))
            .toList(growable: false);
        _mockAssetsByItemId[entry.key] = updated;
        return updated[index];
      }
      throw ItemApiException('Asset not found.');
    }

    final uri = Uri.parse('$baseUrl/api/assets/$assetId/primary');
    final response = await _client.patch(uri);
    final payload = _decodeJsonObject(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true ||
        payload['asset'] is! Map<String, dynamic>) {
      throw ItemApiException(
        payload['error'] as String? ?? 'Failed to set primary image.',
      );
    }
    return _itemAssetFromJson(payload['asset'] as Map<String, dynamic>);
  }

  @override
  Future<void> deleteAsset(int assetId) async {
    if (useMockResponses) {
      for (final entry in _mockAssetsByItemId.entries) {
        final current = entry.value;
        if (!current.any((asset) => asset.id == assetId)) {
          continue;
        }
        final removed = current.firstWhere((asset) => asset.id == assetId);
        final retained = current
            .where((asset) => asset.id != assetId)
            .toList(growable: true);
        if (removed.isPrimary && retained.isNotEmpty) {
          retained[0] = _copyAsset(retained[0], isPrimary: true);
        }
        _mockAssetsByItemId[entry.key] = retained;
        return;
      }
      throw ItemApiException('Asset not found.');
    }

    final uri = Uri.parse('$baseUrl/api/assets/$assetId');
    final response = await _client.delete(uri);
    final payload = _decodeJsonObject(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw ItemApiException(
        payload['error'] as String? ?? 'Failed to delete image.',
      );
    }
  }

  Future<ItemDefinition> _updateArchiveState(
    int id, {
    required bool archive,
  }) async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      final index = _mockItems.indexWhere((item) => item.id == id);
      if (index == -1) {
        throw ItemApiException('Item not found.');
      }
      final current = _mockItems[index];
      final now = DateTime.now();
      final updated = ItemDefinition(
        id: current.id,
        name: current.name,
        alias: current.alias,
        displayName: current.displayName,
        quantity: current.quantity,
        groupId: current.groupId,
        unitId: current.unitId,
        unitConversions: current.unitConversions,
        namingFormat: current.namingFormat,
        isArchived: archive,
        usageCount: current.usageCount,
        createdAt: current.createdAt,
        updatedAt: now,
        variationTree: _copyTreeArchiveState(
          current.variationTree,
          archive,
          now,
        ),
      );
      _mockItems[index] = updated;
      return updated;
    }

    final path = archive ? 'archive' : 'restore';
    final uri = Uri.parse('$baseUrl/api/items/$id/$path');
    final response = await _client.patch(uri);
    final payload = _decodeJsonObject(response.body);
    final parsed = ItemResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success ||
        parsed.item == null) {
      throw ItemApiException(parsed.error ?? 'Failed to update item status.');
    }
    return parsed.item!.toDomain();
  }

  List<ItemVariationNodeDefinition> _copyTreeArchiveState(
    List<ItemVariationNodeDefinition> nodes,
    bool archive,
    DateTime timestamp,
  ) {
    return nodes
        .map(
          (node) => ItemVariationNodeDefinition(
            code: '',
            id: node.id,
            itemId: node.itemId,
            parentNodeId: node.parentNodeId,
            kind: node.kind,
            name: node.name,
            displayName: node.displayName,
            position: node.position,
            isArchived: archive,
            createdAt: node.createdAt,
            updatedAt: timestamp,
            children: _copyTreeArchiveState(node.children, archive, timestamp),
          ),
        )
        .toList(growable: false);
  }

  void _validateCreateOrUpdate({
    int? id,
    required String name,
    required int groupId,
    required List<ItemVariationNodeInput> variationTree,
  }) {
    final normalizedName = _normalize(name);
    if (normalizedName.isEmpty || groupId <= 0) {
      throw ItemApiException('Item name and group are required.');
    }
    final duplicate = _mockItems.any(
      (item) =>
          item.id != id &&
          item.groupId == groupId &&
          _normalize(item.name) == normalizedName,
    );
    if (duplicate) {
      throw ItemApiException(
        'An item with the same name already exists in this group.',
      );
    }
    for (var index = 0; index < variationTree.length; index++) {
      _validateNode(
        variationTree[index],
        expectedKind: ItemVariationNodeKind.property,
        siblingNames: variationTree
            .map((node) => _normalize(node.name))
            .toList(growable: false),
      );
    }
  }

  void _validateNode(
    ItemVariationNodeInput node, {
    required ItemVariationNodeKind expectedKind,
    required List<String> siblingNames,
  }) {
    final normalizedName = _normalize(node.name);
    if (normalizedName.isEmpty) {
      throw ItemApiException('Variation tree node names are required.');
    }
    if (node.kind != expectedKind) {
      throw ItemApiException(
        'Variation tree must alternate between property groups and values.',
      );
    }
    if (siblingNames.where((name) => name == normalizedName).length > 1) {
      throw ItemApiException('Sibling variation nodes must have unique names.');
    }
    final nextKind = node.kind == ItemVariationNodeKind.property
        ? ItemVariationNodeKind.value
        : ItemVariationNodeKind.property;
    final childNames = node.children
        .map((child) => _normalize(child.name))
        .toList(growable: false);
    for (final child in node.children) {
      _validateNode(child, expectedKind: nextKind, siblingNames: childNames);
    }
  }

  List<ItemVariationNodeDefinition> _buildTree({
    required int itemId,
    required List<ItemVariationNodeInput> inputs,
    required List<ItemVariationNodeDefinition> existing,
    required int? parentNodeId,
    required DateTime timestamp,
  }) {
    return inputs
        .asMap()
        .entries
        .map((entry) {
          final input = entry.value;
          final current = existing
              .where((node) => node.id == input.id)
              .firstOrNull;
          final nodeId = input.id ?? _mockNextNodeId++;
          final builtChildren = _buildTree(
            itemId: itemId,
            inputs: input.children,
            existing: current?.children ?? const [],
            parentNodeId: nodeId,
            timestamp: timestamp,
          );
          return ItemVariationNodeDefinition(
            code: '',
            id: nodeId,
            itemId: itemId,
            parentNodeId: parentNodeId,
            kind: input.kind,
            name: input.name.trim(),
            displayName:
                input.kind == ItemVariationNodeKind.value &&
                    builtChildren.isEmpty
                ? input.displayName.trim()
                : '',
            position: entry.key,
            isArchived: false,
            createdAt: current?.createdAt ?? timestamp,
            updatedAt: timestamp,
            children: builtChildren,
          );
        })
        .toList(growable: false);
  }

  void _seedMockStoreIfNeeded() {
    if (_mockSeeded) {
      return;
    }
    _mockSeeded = true;
    final now = DateTime(2024);

    final bottleId = _mockNextItemId++;
    final ampPropertyId = _mockNextNodeId++;
    final fiveAmpValueId = _mockNextNodeId++;
    final fiveAmpCountPropertyId = _mockNextNodeId++;
    final fiveAmpCountValueId = _mockNextNodeId++;
    final fiveAmpAlloyPropertyId = _mockNextNodeId++;
    final fiveAmpAlloyValueId = _mockNextNodeId++;
    final fiveAmpContactPropertyId = _mockNextNodeId++;
    final fiveAmpContactValueId = _mockNextNodeId++;
    final fiveAmpTypePropertyId = _mockNextNodeId++;
    final fiveAmpTypeValueId = _mockNextNodeId++;
    final fiveAmpPlatingPropertyId = _mockNextNodeId++;
    final withoutPlatingValueId = _mockNextNodeId++;
    final withPlatingValueId = _mockNextNodeId++;
    final sixAmpValueId = _mockNextNodeId++;
    final sixAmpCountPropertyId = _mockNextNodeId++;
    final sixAmpCountValueId = _mockNextNodeId++;
    final sixAmpAlloyPropertyId = _mockNextNodeId++;
    final sixAmpAlloyValueId = _mockNextNodeId++;
    final sixAmpContactPropertyId = _mockNextNodeId++;
    final sixAmpContactValueId = _mockNextNodeId++;
    final sixAmpTypePropertyId = _mockNextNodeId++;
    final sixAmpTypeValueId = _mockNextNodeId++;
    final sixAmpPlatingPropertyId = _mockNextNodeId++;
    final sixAmpWithoutPlatingValueId = _mockNextNodeId++;
    final bottleTree = [
      ItemVariationNodeDefinition(
        code: '',
        id: ampPropertyId,
        itemId: bottleId,
        parentNodeId: null,
        kind: ItemVariationNodeKind.property,
        name: 'Action Dolly Amp',
        displayName: '',
        position: 0,
        isArchived: false,
        createdAt: now,
        updatedAt: now,
        children: [
          ItemVariationNodeDefinition(
            code: '',
            id: fiveAmpValueId,
            itemId: bottleId,
            parentNodeId: ampPropertyId,
            kind: ItemVariationNodeKind.value,
            name: '5 Amp',
            displayName: '',
            position: 0,
            isArchived: false,
            createdAt: now,
            updatedAt: now,
            children: [
              ItemVariationNodeDefinition(
                code: '',
                id: fiveAmpCountPropertyId,
                itemId: bottleId,
                parentNodeId: fiveAmpValueId,
                kind: ItemVariationNodeKind.property,
                name: 'Action Patti + Dabbi',
                displayName: '',
                position: 0,
                isArchived: false,
                createdAt: now,
                updatedAt: now,
                children: [
                  ItemVariationNodeDefinition(
                    code: '',
                    id: fiveAmpCountValueId,
                    itemId: bottleId,
                    parentNodeId: fiveAmpCountPropertyId,
                    kind: ItemVariationNodeKind.value,
                    name: '11+1',
                    displayName: '',
                    position: 0,
                    isArchived: false,
                    createdAt: now,
                    updatedAt: now,
                    children: [
                      ItemVariationNodeDefinition(
                        code: '',
                        id: fiveAmpAlloyPropertyId,
                        itemId: bottleId,
                        parentNodeId: fiveAmpCountValueId,
                        kind: ItemVariationNodeKind.property,
                        name: 'Action Dolly Alloy',
                        displayName: '',
                        position: 0,
                        isArchived: false,
                        createdAt: now,
                        updatedAt: now,
                        children: [
                          ItemVariationNodeDefinition(
                            code: '',
                            id: fiveAmpAlloyValueId,
                            itemId: bottleId,
                            parentNodeId: fiveAmpAlloyPropertyId,
                            kind: ItemVariationNodeKind.value,
                            name: 'Brass',
                            displayName: '',
                            position: 0,
                            isArchived: false,
                            createdAt: now,
                            updatedAt: now,
                            children: [
                              ItemVariationNodeDefinition(
                                code: '',
                                id: fiveAmpContactPropertyId,
                                itemId: bottleId,
                                parentNodeId: fiveAmpAlloyValueId,
                                kind: ItemVariationNodeKind.property,
                                name: 'Action Dolly Contact',
                                displayName: '',
                                position: 0,
                                isArchived: false,
                                createdAt: now,
                                updatedAt: now,
                                children: [
                                  ItemVariationNodeDefinition(
                                    code: '',
                                    id: fiveAmpContactValueId,
                                    itemId: bottleId,
                                    parentNodeId: fiveAmpContactPropertyId,
                                    kind: ItemVariationNodeKind.value,
                                    name: '1 Way',
                                    displayName: '',
                                    position: 0,
                                    isArchived: false,
                                    createdAt: now,
                                    updatedAt: now,
                                    children: [
                                      ItemVariationNodeDefinition(
                                        code: '',
                                        id: fiveAmpTypePropertyId,
                                        itemId: bottleId,
                                        parentNodeId: fiveAmpContactValueId,
                                        kind: ItemVariationNodeKind.property,
                                        name: 'Action Dolly Type',
                                        displayName: '',
                                        position: 0,
                                        isArchived: false,
                                        createdAt: now,
                                        updatedAt: now,
                                        children: [
                                          ItemVariationNodeDefinition(
                                            code: '',
                                            id: fiveAmpTypeValueId,
                                            itemId: bottleId,
                                            parentNodeId: fiveAmpTypePropertyId,
                                            kind: ItemVariationNodeKind.value,
                                            name: 'Dolly',
                                            displayName: '',
                                            position: 0,
                                            isArchived: false,
                                            createdAt: now,
                                            updatedAt: now,
                                            children: [
                                              ItemVariationNodeDefinition(
                                                code: '',
                                                id: fiveAmpPlatingPropertyId,
                                                itemId: bottleId,
                                                parentNodeId:
                                                    fiveAmpTypeValueId,
                                                kind: ItemVariationNodeKind
                                                    .property,
                                                name: 'Action Dolly Plating',
                                                displayName: '',
                                                position: 0,
                                                isArchived: false,
                                                createdAt: now,
                                                updatedAt: now,
                                                children: [
                                                  ItemVariationNodeDefinition(
                                                    code: '',
                                                    id: withoutPlatingValueId,
                                                    itemId: bottleId,
                                                    parentNodeId:
                                                        fiveAmpPlatingPropertyId,
                                                    kind: ItemVariationNodeKind
                                                        .value,
                                                    name: 'Without Plating',
                                                    displayName:
                                                        '5 Amp 11+1 Brass 1 Way Dolly Without Plating',
                                                    position: 0,
                                                    isArchived: false,
                                                    createdAt: now,
                                                    updatedAt: now,
                                                    children: const [],
                                                  ),
                                                  ItemVariationNodeDefinition(
                                                    code: '',
                                                    id: withPlatingValueId,
                                                    itemId: bottleId,
                                                    parentNodeId:
                                                        fiveAmpPlatingPropertyId,
                                                    kind: ItemVariationNodeKind
                                                        .value,
                                                    name: 'With Plating',
                                                    displayName:
                                                        '5 Amp 11+1 Brass 1 Way Dolly With Plating',
                                                    position: 1,
                                                    isArchived: false,
                                                    createdAt: now,
                                                    updatedAt: now,
                                                    children: const [],
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          ItemVariationNodeDefinition(
            code: '',
            id: sixAmpValueId,
            itemId: bottleId,
            parentNodeId: ampPropertyId,
            kind: ItemVariationNodeKind.value,
            name: '6 Amp',
            displayName: '',
            position: 1,
            isArchived: false,
            createdAt: now,
            updatedAt: now,
            children: [
              ItemVariationNodeDefinition(
                code: '',
                id: sixAmpCountPropertyId,
                itemId: bottleId,
                parentNodeId: sixAmpValueId,
                kind: ItemVariationNodeKind.property,
                name: 'Action Patti + Dabbi',
                displayName: '',
                position: 0,
                isArchived: false,
                createdAt: now,
                updatedAt: now,
                children: [
                  ItemVariationNodeDefinition(
                    code: '',
                    id: sixAmpCountValueId,
                    itemId: bottleId,
                    parentNodeId: sixAmpCountPropertyId,
                    kind: ItemVariationNodeKind.value,
                    name: '11+1',
                    displayName: '',
                    position: 0,
                    isArchived: false,
                    createdAt: now,
                    updatedAt: now,
                    children: [
                      ItemVariationNodeDefinition(
                        code: '',
                        id: sixAmpAlloyPropertyId,
                        itemId: bottleId,
                        parentNodeId: sixAmpCountValueId,
                        kind: ItemVariationNodeKind.property,
                        name: 'Action Dolly Alloy',
                        displayName: '',
                        position: 0,
                        isArchived: false,
                        createdAt: now,
                        updatedAt: now,
                        children: [
                          ItemVariationNodeDefinition(
                            code: '',
                            id: sixAmpAlloyValueId,
                            itemId: bottleId,
                            parentNodeId: sixAmpAlloyPropertyId,
                            kind: ItemVariationNodeKind.value,
                            name: 'Brass',
                            displayName: '',
                            position: 0,
                            isArchived: false,
                            createdAt: now,
                            updatedAt: now,
                            children: [
                              ItemVariationNodeDefinition(
                                code: '',
                                id: sixAmpContactPropertyId,
                                itemId: bottleId,
                                parentNodeId: sixAmpAlloyValueId,
                                kind: ItemVariationNodeKind.property,
                                name: 'Action Dolly Contact',
                                displayName: '',
                                position: 0,
                                isArchived: false,
                                createdAt: now,
                                updatedAt: now,
                                children: [
                                  ItemVariationNodeDefinition(
                                    code: '',
                                    id: sixAmpContactValueId,
                                    itemId: bottleId,
                                    parentNodeId: sixAmpContactPropertyId,
                                    kind: ItemVariationNodeKind.value,
                                    name: '1 Way',
                                    displayName: '',
                                    position: 0,
                                    isArchived: false,
                                    createdAt: now,
                                    updatedAt: now,
                                    children: [
                                      ItemVariationNodeDefinition(
                                        code: '',
                                        id: sixAmpTypePropertyId,
                                        itemId: bottleId,
                                        parentNodeId: sixAmpContactValueId,
                                        kind: ItemVariationNodeKind.property,
                                        name: 'Action Dolly Type',
                                        displayName: '',
                                        position: 0,
                                        isArchived: false,
                                        createdAt: now,
                                        updatedAt: now,
                                        children: [
                                          ItemVariationNodeDefinition(
                                            code: '',
                                            id: sixAmpTypeValueId,
                                            itemId: bottleId,
                                            parentNodeId: sixAmpTypePropertyId,
                                            kind: ItemVariationNodeKind.value,
                                            name: 'Dolly',
                                            displayName: '',
                                            position: 0,
                                            isArchived: false,
                                            createdAt: now,
                                            updatedAt: now,
                                            children: [
                                              ItemVariationNodeDefinition(
                                                code: '',
                                                id: sixAmpPlatingPropertyId,
                                                itemId: bottleId,
                                                parentNodeId: sixAmpTypeValueId,
                                                kind: ItemVariationNodeKind
                                                    .property,
                                                name: 'Action Dolly Plating',
                                                displayName: '',
                                                position: 0,
                                                isArchived: false,
                                                createdAt: now,
                                                updatedAt: now,
                                                children: [
                                                  ItemVariationNodeDefinition(
                                                    code: '',
                                                    id: sixAmpWithoutPlatingValueId,
                                                    itemId: bottleId,
                                                    parentNodeId:
                                                        sixAmpPlatingPropertyId,
                                                    kind: ItemVariationNodeKind
                                                        .value,
                                                    name: 'Without Plating',
                                                    displayName:
                                                        '6 Amp 11+1 Brass 1 Way Dolly Without Plating',
                                                    position: 0,
                                                    isArchived: false,
                                                    createdAt: now,
                                                    updatedAt: now,
                                                    children: const [],
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ];
    _mockItems.add(
      ItemDefinition(
        namingFormat: const <String>[],
        id: bottleId,
        name: 'Epoxy Resin Base',
        alias: 'Binder',
        displayName: 'Epoxy Resin Base - 25',
        quantity: 25,
        groupId: 2,
        unitId: 1,
        isArchived: false,
        usageCount: 2,
        createdAt: now,
        updatedAt: now,
        variationTree: bottleTree,
      ),
    );

    final glueId = _mockNextItemId++;
    final cureSpeedPropertyId = _mockNextNodeId++;
    final fastCureValueId = _mockNextNodeId++;
    final glueTree = [
      ItemVariationNodeDefinition(
        code: '',
        id: cureSpeedPropertyId,
        itemId: glueId,
        parentNodeId: null,
        kind: ItemVariationNodeKind.property,
        name: 'Cure Speed',
        displayName: '',
        position: 0,
        isArchived: false,
        createdAt: now,
        updatedAt: now,
        children: [
          ItemVariationNodeDefinition(
            code: '',
            id: fastCureValueId,
            itemId: glueId,
            parentNodeId: cureSpeedPropertyId,
            kind: ItemVariationNodeKind.value,
            name: 'Fast Cure',
            displayName: 'Fast Cure',
            position: 0,
            isArchived: false,
            createdAt: now,
            updatedAt: now,
            children: const [],
          ),
        ],
      ),
    ];
    _mockItems.add(
      ItemDefinition(
        namingFormat: const <String>[],
        id: glueId,
        name: 'Hardener Compound',
        alias: 'Catalyst',
        displayName: 'Hardener Compound - 5',
        quantity: 5,
        groupId: 2,
        unitId: 1,
        isArchived: false,
        usageCount: 0,
        createdAt: now,
        updatedAt: now,
        variationTree: glueTree,
      ),
    );

    final bottleShowcaseId = _mockNextItemId++;
    final bottleMaterialPropertyId = _mockNextNodeId++;
    final petValueId = _mockNextNodeId++;
    final bottleColorPropertyId = _mockNextNodeId++;
    final frostedClearValueId = _mockNextNodeId++;
    final pumpFinishPropertyId = _mockNextNodeId++;
    final matteSilverValueId = _mockNextNodeId++;
    final lockTypePropertyId = _mockNextNodeId++;
    final leftLockValueId = _mockNextNodeId++;
    final rightLockValueId = _mockNextNodeId++;
    final amberValueId = _mockNextNodeId++;
    final amberPumpFinishPropertyId = _mockNextNodeId++;
    final glossGoldValueId = _mockNextNodeId++;
    final amberLockTypePropertyId = _mockNextNodeId++;
    final amberLeftLockValueId = _mockNextNodeId++;
    final glassValueId = _mockNextNodeId++;
    final glassColorPropertyId = _mockNextNodeId++;
    final clearValueId = _mockNextNodeId++;
    final glassPumpFinishPropertyId = _mockNextNodeId++;
    final roseGoldValueId = _mockNextNodeId++;
    final glassLockTypePropertyId = _mockNextNodeId++;
    final glassRightLockValueId = _mockNextNodeId++;
    final bottleShowcaseTree = [
      ItemVariationNodeDefinition(
        code: '',
        id: bottleMaterialPropertyId,
        itemId: bottleShowcaseId,
        parentNodeId: null,
        kind: ItemVariationNodeKind.property,
        name: 'Bottle Material',
        displayName: '',
        position: 0,
        isArchived: false,
        createdAt: now,
        updatedAt: now,
        children: [
          ItemVariationNodeDefinition(
            code: '',
            id: petValueId,
            itemId: bottleShowcaseId,
            parentNodeId: bottleMaterialPropertyId,
            kind: ItemVariationNodeKind.value,
            name: 'PET',
            displayName: '',
            position: 0,
            isArchived: false,
            createdAt: now,
            updatedAt: now,
            children: [
              ItemVariationNodeDefinition(
                code: '',
                id: bottleColorPropertyId,
                itemId: bottleShowcaseId,
                parentNodeId: petValueId,
                kind: ItemVariationNodeKind.property,
                name: 'Bottle Color',
                displayName: '',
                position: 0,
                isArchived: false,
                createdAt: now,
                updatedAt: now,
                children: [
                  ItemVariationNodeDefinition(
                    code: '',
                    id: frostedClearValueId,
                    itemId: bottleShowcaseId,
                    parentNodeId: bottleColorPropertyId,
                    kind: ItemVariationNodeKind.value,
                    name: 'Frosted Clear',
                    displayName: '',
                    position: 0,
                    isArchived: false,
                    createdAt: now,
                    updatedAt: now,
                    children: [
                      ItemVariationNodeDefinition(
                        code: '',
                        id: pumpFinishPropertyId,
                        itemId: bottleShowcaseId,
                        parentNodeId: frostedClearValueId,
                        kind: ItemVariationNodeKind.property,
                        name: 'Pump Finish',
                        displayName: '',
                        position: 0,
                        isArchived: false,
                        createdAt: now,
                        updatedAt: now,
                        children: [
                          ItemVariationNodeDefinition(
                            code: '',
                            id: matteSilverValueId,
                            itemId: bottleShowcaseId,
                            parentNodeId: pumpFinishPropertyId,
                            kind: ItemVariationNodeKind.value,
                            name: 'Matte Silver',
                            displayName: '',
                            position: 0,
                            isArchived: false,
                            createdAt: now,
                            updatedAt: now,
                            children: [
                              ItemVariationNodeDefinition(
                                code: '',
                                id: lockTypePropertyId,
                                itemId: bottleShowcaseId,
                                parentNodeId: matteSilverValueId,
                                kind: ItemVariationNodeKind.property,
                                name: 'Lock Type',
                                displayName: '',
                                position: 0,
                                isArchived: false,
                                createdAt: now,
                                updatedAt: now,
                                children: [
                                  ItemVariationNodeDefinition(
                                    code: '',
                                    id: leftLockValueId,
                                    itemId: bottleShowcaseId,
                                    parentNodeId: lockTypePropertyId,
                                    kind: ItemVariationNodeKind.value,
                                    name: 'Left Lock',
                                    displayName:
                                        'PET Frosted Clear Matte Silver Left Lock',
                                    position: 0,
                                    isArchived: false,
                                    createdAt: now,
                                    updatedAt: now,
                                    children: const [],
                                  ),
                                  ItemVariationNodeDefinition(
                                    code: '',
                                    id: rightLockValueId,
                                    itemId: bottleShowcaseId,
                                    parentNodeId: lockTypePropertyId,
                                    kind: ItemVariationNodeKind.value,
                                    name: 'Right Lock',
                                    displayName:
                                        'PET Frosted Clear Matte Silver Right Lock',
                                    position: 1,
                                    isArchived: false,
                                    createdAt: now,
                                    updatedAt: now,
                                    children: const [],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  ItemVariationNodeDefinition(
                    code: '',
                    id: amberValueId,
                    itemId: bottleShowcaseId,
                    parentNodeId: bottleColorPropertyId,
                    kind: ItemVariationNodeKind.value,
                    name: 'Amber',
                    displayName: '',
                    position: 1,
                    isArchived: false,
                    createdAt: now,
                    updatedAt: now,
                    children: [
                      ItemVariationNodeDefinition(
                        code: '',
                        id: amberPumpFinishPropertyId,
                        itemId: bottleShowcaseId,
                        parentNodeId: amberValueId,
                        kind: ItemVariationNodeKind.property,
                        name: 'Pump Finish',
                        displayName: '',
                        position: 0,
                        isArchived: false,
                        createdAt: now,
                        updatedAt: now,
                        children: [
                          ItemVariationNodeDefinition(
                            code: '',
                            id: glossGoldValueId,
                            itemId: bottleShowcaseId,
                            parentNodeId: amberPumpFinishPropertyId,
                            kind: ItemVariationNodeKind.value,
                            name: 'Gloss Gold',
                            displayName: '',
                            position: 0,
                            isArchived: false,
                            createdAt: now,
                            updatedAt: now,
                            children: [
                              ItemVariationNodeDefinition(
                                code: '',
                                id: amberLockTypePropertyId,
                                itemId: bottleShowcaseId,
                                parentNodeId: glossGoldValueId,
                                kind: ItemVariationNodeKind.property,
                                name: 'Lock Type',
                                displayName: '',
                                position: 0,
                                isArchived: false,
                                createdAt: now,
                                updatedAt: now,
                                children: [
                                  ItemVariationNodeDefinition(
                                    code: '',
                                    id: amberLeftLockValueId,
                                    itemId: bottleShowcaseId,
                                    parentNodeId: amberLockTypePropertyId,
                                    kind: ItemVariationNodeKind.value,
                                    name: 'Left Lock',
                                    displayName:
                                        'PET Amber Gloss Gold Left Lock',
                                    position: 0,
                                    isArchived: false,
                                    createdAt: now,
                                    updatedAt: now,
                                    children: const [],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          ItemVariationNodeDefinition(
            code: '',
            id: glassValueId,
            itemId: bottleShowcaseId,
            parentNodeId: bottleMaterialPropertyId,
            kind: ItemVariationNodeKind.value,
            name: 'Glass',
            displayName: '',
            position: 1,
            isArchived: false,
            createdAt: now,
            updatedAt: now,
            children: [
              ItemVariationNodeDefinition(
                code: '',
                id: glassColorPropertyId,
                itemId: bottleShowcaseId,
                parentNodeId: glassValueId,
                kind: ItemVariationNodeKind.property,
                name: 'Bottle Color',
                displayName: '',
                position: 0,
                isArchived: false,
                createdAt: now,
                updatedAt: now,
                children: [
                  ItemVariationNodeDefinition(
                    code: '',
                    id: clearValueId,
                    itemId: bottleShowcaseId,
                    parentNodeId: glassColorPropertyId,
                    kind: ItemVariationNodeKind.value,
                    name: 'Clear',
                    displayName: '',
                    position: 0,
                    isArchived: false,
                    createdAt: now,
                    updatedAt: now,
                    children: [
                      ItemVariationNodeDefinition(
                        code: '',
                        id: glassPumpFinishPropertyId,
                        itemId: bottleShowcaseId,
                        parentNodeId: clearValueId,
                        kind: ItemVariationNodeKind.property,
                        name: 'Pump Finish',
                        displayName: '',
                        position: 0,
                        isArchived: false,
                        createdAt: now,
                        updatedAt: now,
                        children: [
                          ItemVariationNodeDefinition(
                            code: '',
                            id: roseGoldValueId,
                            itemId: bottleShowcaseId,
                            parentNodeId: glassPumpFinishPropertyId,
                            kind: ItemVariationNodeKind.value,
                            name: 'Rose Gold',
                            displayName: '',
                            position: 0,
                            isArchived: false,
                            createdAt: now,
                            updatedAt: now,
                            children: [
                              ItemVariationNodeDefinition(
                                code: '',
                                id: glassLockTypePropertyId,
                                itemId: bottleShowcaseId,
                                parentNodeId: roseGoldValueId,
                                kind: ItemVariationNodeKind.property,
                                name: 'Lock Type',
                                displayName: '',
                                position: 0,
                                isArchived: false,
                                createdAt: now,
                                updatedAt: now,
                                children: [
                                  ItemVariationNodeDefinition(
                                    code: '',
                                    id: glassRightLockValueId,
                                    itemId: bottleShowcaseId,
                                    parentNodeId: glassLockTypePropertyId,
                                    kind: ItemVariationNodeKind.value,
                                    name: 'Right Lock',
                                    displayName:
                                        'Glass Clear Rose Gold Right Lock',
                                    position: 0,
                                    isArchived: false,
                                    createdAt: now,
                                    updatedAt: now,
                                    children: const [],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ];
    _mockItems.add(
      ItemDefinition(
        namingFormat: const <String>[],
        id: bottleShowcaseId,
        name: 'Isopropyl Cleaner',
        alias: 'Solvent',
        displayName: 'Isopropyl Cleaner - 20',
        quantity: 20,
        groupId: 3,
        unitId: 1,
        isArchived: false,
        usageCount: 1,
        createdAt: now,
        updatedAt: now,
        variationTree: bottleShowcaseTree,
      ),
    );

    final cartonShowcaseId = _mockNextItemId++;
    final boardGsmPropertyId = _mockNextNodeId++;
    final gsm300ValueId = _mockNextNodeId++;
    final printFinishPropertyId = _mockNextNodeId++;
    final matteValueId = _mockNextNodeId++;
    final foilPropertyId = _mockNextNodeId++;
    final goldFoilValueId = _mockNextNodeId++;
    final windowPropertyId = _mockNextNodeId++;
    final withWindowValueId = _mockNextNodeId++;
    final noWindowValueId = _mockNextNodeId++;
    final glossValueId = _mockNextNodeId++;
    final glossFoilPropertyId = _mockNextNodeId++;
    final noFoilValueId = _mockNextNodeId++;
    final glossWindowPropertyId = _mockNextNodeId++;
    final glossNoWindowValueId = _mockNextNodeId++;
    final gsm350ValueId = _mockNextNodeId++;
    final gsm350FinishPropertyId = _mockNextNodeId++;
    final gsm350MatteValueId = _mockNextNodeId++;
    final gsm350FoilPropertyId = _mockNextNodeId++;
    final roseGoldFoilValueId = _mockNextNodeId++;
    final gsm350WindowPropertyId = _mockNextNodeId++;
    final gsm350WithWindowValueId = _mockNextNodeId++;
    final cartonShowcaseTree = [
      ItemVariationNodeDefinition(
        code: '',
        id: boardGsmPropertyId,
        itemId: cartonShowcaseId,
        parentNodeId: null,
        kind: ItemVariationNodeKind.property,
        name: 'Board GSM',
        displayName: '',
        position: 0,
        isArchived: false,
        createdAt: now,
        updatedAt: now,
        children: [
          ItemVariationNodeDefinition(
            code: '',
            id: gsm300ValueId,
            itemId: cartonShowcaseId,
            parentNodeId: boardGsmPropertyId,
            kind: ItemVariationNodeKind.value,
            name: '300 GSM',
            displayName: '',
            position: 0,
            isArchived: false,
            createdAt: now,
            updatedAt: now,
            children: [
              ItemVariationNodeDefinition(
                code: '',
                id: printFinishPropertyId,
                itemId: cartonShowcaseId,
                parentNodeId: gsm300ValueId,
                kind: ItemVariationNodeKind.property,
                name: 'Print Finish',
                displayName: '',
                position: 0,
                isArchived: false,
                createdAt: now,
                updatedAt: now,
                children: [
                  ItemVariationNodeDefinition(
                    code: '',
                    id: matteValueId,
                    itemId: cartonShowcaseId,
                    parentNodeId: printFinishPropertyId,
                    kind: ItemVariationNodeKind.value,
                    name: 'Matte',
                    displayName: '',
                    position: 0,
                    isArchived: false,
                    createdAt: now,
                    updatedAt: now,
                    children: [
                      ItemVariationNodeDefinition(
                        code: '',
                        id: foilPropertyId,
                        itemId: cartonShowcaseId,
                        parentNodeId: matteValueId,
                        kind: ItemVariationNodeKind.property,
                        name: 'Foil',
                        displayName: '',
                        position: 0,
                        isArchived: false,
                        createdAt: now,
                        updatedAt: now,
                        children: [
                          ItemVariationNodeDefinition(
                            code: '',
                            id: goldFoilValueId,
                            itemId: cartonShowcaseId,
                            parentNodeId: foilPropertyId,
                            kind: ItemVariationNodeKind.value,
                            name: 'Gold Foil',
                            displayName: '',
                            position: 0,
                            isArchived: false,
                            createdAt: now,
                            updatedAt: now,
                            children: [
                              ItemVariationNodeDefinition(
                                code: '',
                                id: windowPropertyId,
                                itemId: cartonShowcaseId,
                                parentNodeId: goldFoilValueId,
                                kind: ItemVariationNodeKind.property,
                                name: 'Window',
                                displayName: '',
                                position: 0,
                                isArchived: false,
                                createdAt: now,
                                updatedAt: now,
                                children: [
                                  ItemVariationNodeDefinition(
                                    code: '',
                                    id: withWindowValueId,
                                    itemId: cartonShowcaseId,
                                    parentNodeId: windowPropertyId,
                                    kind: ItemVariationNodeKind.value,
                                    name: 'With Window',
                                    displayName:
                                        '300 GSM Matte Gold Foil With Window',
                                    position: 0,
                                    isArchived: false,
                                    createdAt: now,
                                    updatedAt: now,
                                    children: const [],
                                  ),
                                  ItemVariationNodeDefinition(
                                    code: '',
                                    id: noWindowValueId,
                                    itemId: cartonShowcaseId,
                                    parentNodeId: windowPropertyId,
                                    kind: ItemVariationNodeKind.value,
                                    name: 'No Window',
                                    displayName:
                                        '300 GSM Matte Gold Foil No Window',
                                    position: 1,
                                    isArchived: false,
                                    createdAt: now,
                                    updatedAt: now,
                                    children: const [],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  ItemVariationNodeDefinition(
                    code: '',
                    id: glossValueId,
                    itemId: cartonShowcaseId,
                    parentNodeId: printFinishPropertyId,
                    kind: ItemVariationNodeKind.value,
                    name: 'Gloss',
                    displayName: '',
                    position: 1,
                    isArchived: false,
                    createdAt: now,
                    updatedAt: now,
                    children: [
                      ItemVariationNodeDefinition(
                        code: '',
                        id: glossFoilPropertyId,
                        itemId: cartonShowcaseId,
                        parentNodeId: glossValueId,
                        kind: ItemVariationNodeKind.property,
                        name: 'Foil',
                        displayName: '',
                        position: 0,
                        isArchived: false,
                        createdAt: now,
                        updatedAt: now,
                        children: [
                          ItemVariationNodeDefinition(
                            code: '',
                            id: noFoilValueId,
                            itemId: cartonShowcaseId,
                            parentNodeId: glossFoilPropertyId,
                            kind: ItemVariationNodeKind.value,
                            name: 'No Foil',
                            displayName: '',
                            position: 0,
                            isArchived: false,
                            createdAt: now,
                            updatedAt: now,
                            children: [
                              ItemVariationNodeDefinition(
                                code: '',
                                id: glossWindowPropertyId,
                                itemId: cartonShowcaseId,
                                parentNodeId: noFoilValueId,
                                kind: ItemVariationNodeKind.property,
                                name: 'Window',
                                displayName: '',
                                position: 0,
                                isArchived: false,
                                createdAt: now,
                                updatedAt: now,
                                children: [
                                  ItemVariationNodeDefinition(
                                    code: '',
                                    id: glossNoWindowValueId,
                                    itemId: cartonShowcaseId,
                                    parentNodeId: glossWindowPropertyId,
                                    kind: ItemVariationNodeKind.value,
                                    name: 'No Window',
                                    displayName:
                                        '300 GSM Gloss No Foil No Window',
                                    position: 0,
                                    isArchived: false,
                                    createdAt: now,
                                    updatedAt: now,
                                    children: const [],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          ItemVariationNodeDefinition(
            code: '',
            id: gsm350ValueId,
            itemId: cartonShowcaseId,
            parentNodeId: boardGsmPropertyId,
            kind: ItemVariationNodeKind.value,
            name: '350 GSM',
            displayName: '',
            position: 1,
            isArchived: false,
            createdAt: now,
            updatedAt: now,
            children: [
              ItemVariationNodeDefinition(
                code: '',
                id: gsm350FinishPropertyId,
                itemId: cartonShowcaseId,
                parentNodeId: gsm350ValueId,
                kind: ItemVariationNodeKind.property,
                name: 'Print Finish',
                displayName: '',
                position: 0,
                isArchived: false,
                createdAt: now,
                updatedAt: now,
                children: [
                  ItemVariationNodeDefinition(
                    code: '',
                    id: gsm350MatteValueId,
                    itemId: cartonShowcaseId,
                    parentNodeId: gsm350FinishPropertyId,
                    kind: ItemVariationNodeKind.value,
                    name: 'Matte',
                    displayName: '',
                    position: 0,
                    isArchived: false,
                    createdAt: now,
                    updatedAt: now,
                    children: [
                      ItemVariationNodeDefinition(
                        code: '',
                        id: gsm350FoilPropertyId,
                        itemId: cartonShowcaseId,
                        parentNodeId: gsm350MatteValueId,
                        kind: ItemVariationNodeKind.property,
                        name: 'Foil',
                        displayName: '',
                        position: 0,
                        isArchived: false,
                        createdAt: now,
                        updatedAt: now,
                        children: [
                          ItemVariationNodeDefinition(
                            code: '',
                            id: roseGoldFoilValueId,
                            itemId: cartonShowcaseId,
                            parentNodeId: gsm350FoilPropertyId,
                            kind: ItemVariationNodeKind.value,
                            name: 'Rose Gold Foil',
                            displayName: '',
                            position: 0,
                            isArchived: false,
                            createdAt: now,
                            updatedAt: now,
                            children: [
                              ItemVariationNodeDefinition(
                                code: '',
                                id: gsm350WindowPropertyId,
                                itemId: cartonShowcaseId,
                                parentNodeId: roseGoldFoilValueId,
                                kind: ItemVariationNodeKind.property,
                                name: 'Window',
                                displayName: '',
                                position: 0,
                                isArchived: false,
                                createdAt: now,
                                updatedAt: now,
                                children: [
                                  ItemVariationNodeDefinition(
                                    code: '',
                                    id: gsm350WithWindowValueId,
                                    itemId: cartonShowcaseId,
                                    parentNodeId: gsm350WindowPropertyId,
                                    kind: ItemVariationNodeKind.value,
                                    name: 'With Window',
                                    displayName:
                                        '350 GSM Matte Rose Gold Foil With Window',
                                    position: 0,
                                    isArchived: false,
                                    createdAt: now,
                                    updatedAt: now,
                                    children: const [],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ];
    _mockItems.add(
      ItemDefinition(
        namingFormat: const <String>[],
        id: cartonShowcaseId,
        name: 'Cyan Flexo Ink',
        alias: 'Pigment',
        displayName: 'Cyan Flexo Ink - 15',
        quantity: 15,
        groupId: 4,
        unitId: 1,
        isArchived: false,
        usageCount: 0,
        createdAt: now,
        updatedAt: now,
        variationTree: cartonShowcaseTree,
      ),
    );

    final legacyId = _mockNextItemId++;
    _mockItems.add(
      ItemDefinition(
        namingFormat: const <String>[],
        id: legacyId,
        name: 'Legacy Stock',
        alias: '',
        displayName: 'Legacy Stock - 5',
        quantity: 5,
        groupId: 5,
        unitId: 1,
        isArchived: true,
        usageCount: 0,
        createdAt: now,
        updatedAt: now,
        variationTree: const [],
      ),
    );
  }

  static String _itemDisplayNameOrFallback(
    String value, {
    required String name,
    required String alias,
  }) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
    final base = [
      name.trim(),
      alias.trim(),
    ].where((entry) => entry.isNotEmpty).join(' / ');
    return base;
  }

  static String _normalize(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  Map<String, dynamic> _decodeJsonObject(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const ItemApiException('Unexpected response shape.');
    }
    return decoded;
  }

  ItemAsset _itemAssetFromJson(Map<String, dynamic> json) {
    return ItemAsset(
      id: json['id'] as int? ?? 0,
      entityType: json['entityType'] as String? ?? '',
      entityId: json['entityId'] as int? ?? 0,
      fileName: json['fileName'] as String? ?? '',
      contentType: json['contentType'] as String? ?? '',
      sizeBytes: json['sizeBytes'] as int? ?? 0,
      sha256: json['sha256'] as String? ?? '',
      objectKey: json['objectKey'] as String? ?? '',
      status: json['status'] as String? ?? 'uploaded',
      isPrimary: json['isPrimary'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      uploadedAt: DateTime.tryParse(json['uploadedAt'] as String? ?? ''),
      readUrl: _optionalUri(json['readUrl']),
      readUrlExpiresAt: DateTime.tryParse(
        json['readUrlExpiresAt'] as String? ?? '',
      ),
    );
  }

  ItemAssetUploadIntent _itemAssetUploadIntentFromJson(
    Map<String, dynamic> json,
  ) {
    return ItemAssetUploadIntent(
      alreadyUploaded: json['alreadyUploaded'] as bool? ?? false,
      asset: json['asset'] is Map<String, dynamic>
          ? _itemAssetFromJson(json['asset'] as Map<String, dynamic>)
          : null,
      upload: json['upload'] is Map<String, dynamic>
          ? _itemAssetUploadTargetFromJson(
              json['upload'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  ItemAssetUploadTarget _itemAssetUploadTargetFromJson(
    Map<String, dynamic> json,
  ) {
    return ItemAssetUploadTarget(
      uploadSessionId: json['uploadSessionId'] as String? ?? '',
      objectKey: json['objectKey'] as String? ?? '',
      uploadUrl: Uri.parse(json['uploadUrl'] as String? ?? ''),
      headers: (json['headers'] as Map<String, dynamic>? ?? const {}).map(
        (key, value) => MapEntry(key, '$value'),
      ),
      expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? ''),
    );
  }

  Uri? _optionalUri(Object? value) {
    final raw = value as String? ?? '';
    if (raw.trim().isEmpty) {
      return null;
    }
    return Uri.tryParse(raw);
  }

  static ItemAsset _copyAsset(ItemAsset asset, {required bool isPrimary}) {
    return ItemAsset(
      id: asset.id,
      entityType: asset.entityType,
      entityId: asset.entityId,
      fileName: asset.fileName,
      contentType: asset.contentType,
      sizeBytes: asset.sizeBytes,
      sha256: asset.sha256,
      objectKey: asset.objectKey,
      status: asset.status,
      isPrimary: isPrimary,
      createdAt: asset.createdAt,
      uploadedAt: asset.uploadedAt,
      readUrl: asset.readUrl,
      readUrlExpiresAt: asset.readUrlExpiresAt,
    );
  }
}

class ItemApiException implements Exception {
  const ItemApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

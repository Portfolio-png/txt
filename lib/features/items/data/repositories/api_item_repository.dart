import 'dart:convert';

import 'package:http/http.dart' as http;

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
  static int _mockNextItemId = 1;
  static int _mockNextNodeId = 1;
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
        quantity: input.quantity,
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
          quantity: input.quantity,
        ),
        quantity: input.quantity,
        groupId: input.groupId,
        unitId: input.unitId,
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
      if (current.isUsed) {
        throw ItemApiException('Used items cannot be edited.');
      }
      _validateCreateOrUpdate(
        id: input.id,
        name: input.name,
        quantity: input.quantity,
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
          quantity: input.quantity,
        ),
        quantity: input.quantity,
        groupId: input.groupId,
        unitId: input.unitId,
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
    required double quantity,
    required int groupId,
    required List<ItemVariationNodeInput> variationTree,
  }) {
    final normalizedName = _normalize(name);
    if (normalizedName.isEmpty || quantity <= 0 || groupId <= 0) {
      throw ItemApiException('Item name, quantity, and group are required.');
    }
    final duplicate = _mockItems.any(
      (item) =>
          item.id != id &&
          item.groupId == groupId &&
          _normalize(item.name) == normalizedName &&
          item.quantity == quantity,
    );
    if (duplicate) {
      throw ItemApiException(
        'An item with the same name and quantity already exists in this group.',
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
    final colorPropertyId = _mockNextNodeId++;
    final blackValueId = _mockNextNodeId++;
    final blackFinishPropertyId = _mockNextNodeId++;
    final matteValueId = _mockNextNodeId++;
    final glossyBlackValueId = _mockNextNodeId++;
    final whiteValueId = _mockNextNodeId++;
    final whiteFinishPropertyId = _mockNextNodeId++;
    final glossyWhiteValueId = _mockNextNodeId++;
    final bottleTree = [
      ItemVariationNodeDefinition(
        id: colorPropertyId,
        itemId: bottleId,
        parentNodeId: null,
        kind: ItemVariationNodeKind.property,
        name: 'Color',
        displayName: '',
        position: 0,
        isArchived: false,
        createdAt: now,
        updatedAt: now,
        children: [
          ItemVariationNodeDefinition(
            id: blackValueId,
            itemId: bottleId,
            parentNodeId: colorPropertyId,
            kind: ItemVariationNodeKind.value,
            name: 'Black',
            displayName: '',
            position: 0,
            isArchived: false,
            createdAt: now,
            updatedAt: now,
            children: [
              ItemVariationNodeDefinition(
                id: blackFinishPropertyId,
                itemId: bottleId,
                parentNodeId: blackValueId,
                kind: ItemVariationNodeKind.property,
                name: 'Finish',
                displayName: '',
                position: 0,
                isArchived: false,
                createdAt: now,
                updatedAt: now,
                children: [
                  ItemVariationNodeDefinition(
                    id: matteValueId,
                    itemId: bottleId,
                    parentNodeId: blackFinishPropertyId,
                    kind: ItemVariationNodeKind.value,
                    name: 'Matte',
                    displayName: 'Color: Black | Finish: Matte',
                    position: 0,
                    isArchived: false,
                    createdAt: now,
                    updatedAt: now,
                    children: const [],
                  ),
                  ItemVariationNodeDefinition(
                    id: glossyBlackValueId,
                    itemId: bottleId,
                    parentNodeId: blackFinishPropertyId,
                    kind: ItemVariationNodeKind.value,
                    name: 'Glossy',
                    displayName: 'Color: Black | Finish: Glossy',
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
          ItemVariationNodeDefinition(
            id: whiteValueId,
            itemId: bottleId,
            parentNodeId: colorPropertyId,
            kind: ItemVariationNodeKind.value,
            name: 'White',
            displayName: '',
            position: 1,
            isArchived: false,
            createdAt: now,
            updatedAt: now,
            children: [
              ItemVariationNodeDefinition(
                id: whiteFinishPropertyId,
                itemId: bottleId,
                parentNodeId: whiteValueId,
                kind: ItemVariationNodeKind.property,
                name: 'Finish',
                displayName: '',
                position: 0,
                isArchived: false,
                createdAt: now,
                updatedAt: now,
                children: [
                  ItemVariationNodeDefinition(
                    id: glossyWhiteValueId,
                    itemId: bottleId,
                    parentNodeId: whiteFinishPropertyId,
                    kind: ItemVariationNodeKind.value,
                    name: 'Glossy',
                    displayName: 'Color: White | Finish: Glossy',
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
    ];
    _mockItems.add(
      ItemDefinition(
        id: bottleId,
        name: 'Bottle',
        alias: 'Classic Bottle',
        displayName: 'Bottle - 100',
        quantity: 100,
        groupId: 2,
        unitId: 2,
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
            id: fastCureValueId,
            itemId: glueId,
            parentNodeId: cureSpeedPropertyId,
            kind: ItemVariationNodeKind.value,
            name: 'Fast Cure',
            displayName: 'Cure Speed: Fast Cure',
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
        id: glueId,
        name: 'Glue Compound',
        alias: 'Adhesive',
        displayName: 'Glue Compound - 1',
        quantity: 1,
        groupId: 3,
        unitId: 1,
        isArchived: false,
        usageCount: 0,
        createdAt: now,
        updatedAt: now,
        variationTree: glueTree,
      ),
    );

    final legacyId = _mockNextItemId++;
    _mockItems.add(
      ItemDefinition(
        id: legacyId,
        name: 'Legacy Stock',
        alias: '',
        displayName: 'Legacy Stock - 5',
        quantity: 5,
        groupId: 4,
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
    required double quantity,
  }) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
    final base = [
      name.trim(),
      alias.trim(),
    ].where((entry) => entry.isNotEmpty).join(' / ');
    final qty = _formatQuantity(quantity);
    return base.isEmpty ? qty : '$base - $qty';
  }

  static String _formatQuantity(double quantity) {
    if (quantity == quantity.roundToDouble()) {
      return quantity.toStringAsFixed(0);
    }
    return quantity.toString();
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

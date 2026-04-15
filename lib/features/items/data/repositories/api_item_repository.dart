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
        id: bottleId,
        name: 'Switch Action Dolly',
        alias: 'Finish Goods Variant',
        displayName: 'Switch Action Dolly - 1',
        quantity: 1,
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
        id: bottleShowcaseId,
        name: 'Luxury Pump Bottle',
        alias: 'Cosmetic Pack',
        displayName: 'Luxury Pump Bottle - 100',
        quantity: 100,
        groupId: 2,
        unitId: 2,
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
        id: cartonShowcaseId,
        name: 'Premium Mono Carton',
        alias: 'Retail Carton',
        displayName: 'Premium Mono Carton - 500',
        quantity: 500,
        groupId: 2,
        unitId: 2,
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

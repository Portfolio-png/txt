import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/order_entry.dart';
import '../../domain/order_inputs.dart';
import '../models/order_api_models.dart';
import 'order_repository.dart';

class ApiOrderRepository implements OrderRepository {
  ApiOrderRepository({
    http.Client? client,
    this.baseUrl = 'http://localhost:8080',
    this.useMockResponses = true,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final bool useMockResponses;

  static final List<OrderEntry> _mockOrders = <OrderEntry>[];
  static final Map<int, List<OrderActivityEntry>> _mockActivities =
      <int, List<OrderActivityEntry>>{};
  static final Map<int, List<OrderStatusHistoryEntry>> _mockStatusHistory =
      <int, List<OrderStatusHistoryEntry>>{};
  static final Map<int, OrderMaterialSnapshot> _mockMaterialSnapshots =
      <int, OrderMaterialSnapshot>{};
  static int _mockActivityNextId = 1;
  static int _mockStatusHistoryNextId = 1;
  static int _mockNextId = 1;

  @override
  Future<void> init() async {}

  @override
  Future<List<OrderEntry>> getOrders() async {
    if (useMockResponses) {
      return List<OrderEntry>.from(_mockOrders);
    }

    final uri = Uri.parse('$baseUrl/api/orders');
    final response = await _client.get(uri);
    final payload = _decodeJsonObject(response.body);
    final parsed = OrdersListResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success) {
      throw OrderApiException(
        payload['error'] as String? ?? 'Failed to fetch orders.',
      );
    }
    return parsed.orders
        .map((order) => order.toDomain())
        .toList(growable: false);
  }

  @override
  Future<OrderEntry> createOrder(CreateOrderInput input) async {
    if (useMockResponses) {
      final normalizedOrderNo = _normalize(input.orderNo);
      final normalizedPoNumber = _normalize(input.poNumber);
      final index = _mockOrders.indexWhere(
        (order) =>
            _normalize(order.orderNo) == normalizedOrderNo &&
            order.clientId == input.clientId &&
            order.itemId == input.itemId &&
            order.variationLeafNodeId == input.variationLeafNodeId &&
            _normalize(order.poNumber) == normalizedPoNumber,
      );
      if (index != -1) {
        final existing = _mockOrders[index];
        final updated = OrderEntry(
          id: existing.id,
          orderNo: input.orderNo.trim(),
          clientId: input.clientId,
          clientName: input.clientName.trim(),
          poNumber: input.poNumber.trim(),
          clientCode: input.clientCode.trim(),
          itemId: input.itemId,
          itemName: input.itemName.trim(),
          variationLeafNodeId: input.variationLeafNodeId,
          variationPathLabel: input.variationPathLabel.trim(),
          variationPathNodeIds: List<int>.from(input.variationPathNodeIds),
          quantity: existing.quantity + input.quantity,
          status: existing.status,
          priority: existing.priority,
          createdAt: existing.createdAt,
          hasMaterialShortage: existing.hasMaterialShortage,
          procurementPending: existing.procurementPending,
          materialReadiness: existing.materialReadiness,
          startDate: existing.startDate,
          endDate: existing.endDate,
          previousStatus: existing.previousStatus,
          holdReason: existing.holdReason,
          cancelReason: existing.cancelReason,
          confirmedAt: existing.confirmedAt,
          allocatedAt: existing.allocatedAt,
          productionStartedAt: existing.productionStartedAt,
          completedAt: existing.completedAt,
          dispatchedAt: existing.dispatchedAt,
          closedAt: existing.closedAt,
          updatedBy: existing.updatedBy,
        );
        _mockOrders[index] = updated;
        return updated;
      }

      final created = OrderEntry(
        id: _mockNextId++,
        orderNo: input.orderNo.trim(),
        clientId: input.clientId,
        clientName: input.clientName.trim(),
        poNumber: input.poNumber.trim(),
        clientCode: input.clientCode.trim(),
        itemId: input.itemId,
        itemName: input.itemName.trim(),
        variationLeafNodeId: input.variationLeafNodeId,
        variationPathLabel: input.variationPathLabel.trim(),
        variationPathNodeIds: List<int>.from(input.variationPathNodeIds),
        quantity: input.quantity,
        status: input.status,
        priority: input.priority,
        createdAt: DateTime.now(),
        hasMaterialShortage: false,
        procurementPending: false,
        materialReadiness: 'none',
        startDate: input.startDate,
        endDate: input.endDate,
        previousStatus: null,
        holdReason: null,
        cancelReason: null,
        confirmedAt: null,
        allocatedAt: null,
        productionStartedAt: null,
        completedAt: null,
        dispatchedAt: null,
        closedAt: null,
        updatedBy: null,
      );
      _mockOrders.add(created);
      final now = DateTime.now();
      _mockStatusHistory[created.id] = <OrderStatusHistoryEntry>[
        OrderStatusHistoryEntry(
          id: _mockStatusHistoryNextId++,
          orderId: created.id,
          fromStatus: null,
          toStatus: created.status,
          reason: 'Order created',
          changedByUserId: null,
          changedByName: 'System',
          changedByRole: 'system',
          source: 'ui',
          changedAt: now,
        ),
      ];
      _mockActivities[created.id] = <OrderActivityEntry>[
        OrderActivityEntry(
          id: _mockActivityNextId++,
          orderId: created.id,
          eventType: 'order_created',
          title: 'Order created',
          description: 'Order created with status ${created.status.name}.',
          actorUserId: null,
          actorName: 'System',
          actorRole: 'system',
          oldValue: null,
          newValue: created.status.name,
          metadata: const {},
          source: 'ui',
          createdAt: now,
        ),
      ];
      _mockMaterialSnapshots[created.id] = _buildMockMaterialSnapshot(created);
      return created;
    }

    final uri = Uri.parse('$baseUrl/api/orders');
    final request = CreateOrderRequest.fromInput(input);
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );
    final payload = _decodeJsonObject(response.body);
    final parsed = OrderResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success ||
        parsed.order == null) {
      throw OrderApiException(parsed.error ?? 'Failed to create order.');
    }
    return parsed.order!.toDomain();
  }

  @override
  Future<OrderEntry> updateOrderLifecycle(
    UpdateOrderLifecycleInput input,
  ) async {
    if (useMockResponses) {
      final index = _mockOrders.indexWhere((order) => order.id == input.id);
      if (index == -1) {
        throw const OrderApiException('Order not found.');
      }
      final current = _mockOrders[index];
      final updated = OrderEntry(
        id: current.id,
        orderNo: current.orderNo,
        clientId: current.clientId,
        clientName: current.clientName,
        poNumber: current.poNumber,
        clientCode: current.clientCode,
        itemId: current.itemId,
        itemName: current.itemName,
        variationLeafNodeId: current.variationLeafNodeId,
        variationPathLabel: current.variationPathLabel,
        variationPathNodeIds: List<int>.from(current.variationPathNodeIds),
        quantity: current.quantity,
        status: input.toStatus,
        priority: current.priority,
        createdAt: current.createdAt,
        hasMaterialShortage: current.hasMaterialShortage,
        procurementPending: current.procurementPending,
        materialReadiness: current.materialReadiness,
        startDate: input.startDate,
        endDate: input.endDate,
        previousStatus: input.toStatus == OrderStatus.onHold
            ? current.status
            : current.previousStatus,
        holdReason: input.toStatus == OrderStatus.onHold ? input.reason : null,
        cancelReason: input.toStatus == OrderStatus.cancelled
            ? input.reason
            : current.cancelReason,
        confirmedAt: current.confirmedAt,
        allocatedAt: current.allocatedAt,
        productionStartedAt: current.productionStartedAt,
        completedAt: current.completedAt,
        dispatchedAt: current.dispatchedAt,
        closedAt: current.closedAt,
        updatedBy: current.updatedBy,
      );
      _mockOrders[index] = updated;
      final now = DateTime.now();
      final history = _mockStatusHistory.putIfAbsent(
        current.id,
        () => <OrderStatusHistoryEntry>[],
      );
      history.insert(
        0,
        OrderStatusHistoryEntry(
          id: _mockStatusHistoryNextId++,
          orderId: current.id,
          fromStatus: current.status,
          toStatus: input.toStatus,
          reason: input.reason,
          changedByUserId: null,
          changedByName: 'System',
          changedByRole: 'system',
          source: 'ui',
          changedAt: now,
        ),
      );
      final events = _mockActivities.putIfAbsent(
        current.id,
        () => <OrderActivityEntry>[],
      );
      events.insert(
        0,
        OrderActivityEntry(
          id: _mockActivityNextId++,
          orderId: current.id,
          eventType: 'status_changed',
          title: 'Status changed',
          description:
              'Status changed from ${current.status.name} to ${input.toStatus.name}.',
          actorUserId: null,
          actorName: 'System',
          actorRole: 'system',
          oldValue: current.status.name,
          newValue: input.toStatus.name,
          metadata: <String, dynamic>{'reason': input.reason},
          source: 'ui',
          createdAt: now,
        ),
      );
      return updated;
    }

    final uri = Uri.parse('$baseUrl/api/orders/${input.id}/transition');
    final request = UpdateOrderLifecycleRequest.fromInput(input);
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );
    final payload = _decodeJsonObject(response.body);
    final parsed = OrderResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success ||
        parsed.order == null) {
      throw OrderApiException(parsed.error ?? 'Failed to update order.');
    }
    return parsed.order!.toDomain();
  }

  @override
  Future<OrderEntry> transitionOrderByAction({
    required int orderId,
    required String action,
    String? reason,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (useMockResponses) {
      final option = _transitionOptionForAction(action);
      if (option == null) {
        throw const OrderApiException('Unknown transition action.');
      }
      return updateOrderLifecycle(
        UpdateOrderLifecycleInput(
          id: orderId,
          toStatus: option.transitionStatus,
          reason: reason,
          startDate: startDate,
          endDate: endDate,
        ),
      );
    }
    final uri = Uri.parse('$baseUrl/api/orders/$orderId/$action');
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{
        'reason': reason,
        'startDate': startDate?.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
      }),
    );
    final payload = _decodeJsonObject(response.body);
    final parsed = OrderResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success ||
        parsed.order == null) {
      throw OrderApiException(parsed.error ?? 'Failed to update order.');
    }
    return parsed.order!.toDomain();
  }

  @override
  Future<OrderEntry> updateOrderPriority({
    required int orderId,
    required OrderPriority priority,
  }) async {
    if (useMockResponses) {
      final index = _mockOrders.indexWhere((order) => order.id == orderId);
      if (index == -1) {
        throw const OrderApiException('Order not found.');
      }
      final current = _mockOrders[index];
      final updated = OrderEntry(
        id: current.id,
        orderNo: current.orderNo,
        clientId: current.clientId,
        clientName: current.clientName,
        poNumber: current.poNumber,
        clientCode: current.clientCode,
        itemId: current.itemId,
        itemName: current.itemName,
        variationLeafNodeId: current.variationLeafNodeId,
        variationPathLabel: current.variationPathLabel,
        variationPathNodeIds: List<int>.from(current.variationPathNodeIds),
        quantity: current.quantity,
        status: current.status,
        priority: priority,
        createdAt: current.createdAt,
        hasMaterialShortage: current.hasMaterialShortage,
        procurementPending: current.procurementPending,
        materialReadiness: current.materialReadiness,
        startDate: current.startDate,
        endDate: current.endDate,
        previousStatus: current.previousStatus,
        holdReason: current.holdReason,
        cancelReason: current.cancelReason,
        confirmedAt: current.confirmedAt,
        allocatedAt: current.allocatedAt,
        productionStartedAt: current.productionStartedAt,
        completedAt: current.completedAt,
        dispatchedAt: current.dispatchedAt,
        closedAt: current.closedAt,
        updatedBy: current.updatedBy,
      );
      _mockOrders[index] = updated;
      return updated;
    }
    final uri = Uri.parse('$baseUrl/api/orders/$orderId/priority');
    final response = await _client.patch(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{'priority': priority.name}),
    );
    final payload = _decodeJsonObject(response.body);
    final parsed = OrderResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success ||
        parsed.order == null) {
      throw OrderApiException(
        parsed.error ?? 'Failed to update order priority.',
      );
    }
    return parsed.order!.toDomain();
  }

  @override
  Future<List<OrderActivityEntry>> getOrderActivity(int orderId) async {
    if (useMockResponses) {
      return List<OrderActivityEntry>.from(
        _mockActivities[orderId] ?? const [],
      );
    }
    final uri = Uri.parse('$baseUrl/api/orders/$orderId/activity');
    final response = await _client.get(uri);
    final payload = _decodeJsonObject(response.body);
    final parsed = OrderActivityListResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success) {
      throw OrderApiException(
        parsed.error ?? 'Failed to fetch order activity.',
      );
    }
    return parsed.events
        .map((event) => event.toDomain())
        .toList(growable: false);
  }

  @override
  Future<List<OrderStatusHistoryEntry>> getOrderStatusHistory(
    int orderId,
  ) async {
    if (useMockResponses) {
      return List<OrderStatusHistoryEntry>.from(
        _mockStatusHistory[orderId] ?? const [],
      );
    }
    final uri = Uri.parse('$baseUrl/api/orders/$orderId/status-history');
    final response = await _client.get(uri);
    final payload = _decodeJsonObject(response.body);
    final parsed = OrderStatusHistoryListResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success) {
      throw OrderApiException(
        parsed.error ?? 'Failed to fetch order status history.',
      );
    }
    return parsed.history
        .map((entry) => entry.toDomain())
        .toList(growable: false);
  }

  @override
  Future<List<OrderTransitionOption>> getOrderTransitionOptions(
    int orderId,
  ) async {
    if (useMockResponses) {
      final order = _mockOrders
          .where((entry) => entry.id == orderId)
          .firstOrNull;
      if (order == null) {
        return const <OrderTransitionOption>[];
      }
      return _mockTransitionOptions(order.status);
    }
    final uri = Uri.parse('$baseUrl/api/orders/$orderId/transition-options');
    final response = await _client.get(uri);
    final payload = _decodeJsonObject(response.body);
    final parsed = OrderTransitionOptionsResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success) {
      throw OrderApiException(
        parsed.error ?? 'Failed to fetch transition options.',
      );
    }
    return parsed.options
        .map((entry) => entry.toDomain())
        .toList(growable: false);
  }

  @override
  Future<OrderActivityEntry> addOrderNote(AddOrderNoteInput input) async {
    if (useMockResponses) {
      final event = OrderActivityEntry(
        id: _mockActivityNextId++,
        orderId: input.orderId,
        eventType: 'note_added',
        title: 'Note added',
        description: input.note.trim(),
        actorUserId: null,
        actorName: 'System',
        actorRole: 'system',
        oldValue: null,
        newValue: null,
        metadata: <String, dynamic>{'note': input.note.trim()},
        source: 'ui',
        createdAt: DateTime.now(),
      );
      _mockActivities
          .putIfAbsent(input.orderId, () => <OrderActivityEntry>[])
          .insert(0, event);
      return event;
    }
    final uri = Uri.parse('$baseUrl/api/orders/${input.orderId}/notes');
    final request = AddOrderNoteRequest.fromInput(input);
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );
    final payload = _decodeJsonObject(response.body);
    final parsed = OrderActivityResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success ||
        parsed.event == null) {
      throw OrderApiException(parsed.error ?? 'Failed to add order note.');
    }
    return parsed.event!.toDomain();
  }

  @override
  Future<OrderMaterialSnapshot> getOrderMaterialRequirements(
    int orderId,
  ) async {
    if (useMockResponses) {
      final order = _mockOrders
          .where((entry) => entry.id == orderId)
          .firstOrNull;
      if (order == null) {
        throw const OrderApiException('Order not found.');
      }
      return _mockMaterialSnapshots.putIfAbsent(
        orderId,
        () => _buildMockMaterialSnapshot(order),
      );
    }
    final uri = Uri.parse('$baseUrl/api/orders/$orderId/material-requirements');
    final response = await _client.get(uri);
    final payload = _decodeJsonObject(response.body);
    final parsed = OrderMaterialSnapshotResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success) {
      throw OrderApiException(
        parsed.error ?? 'Failed to fetch order material requirements.',
      );
    }
    return parsed.toDomain();
  }

  @override
  Future<OrderMaterialSnapshot> checkOrderMaterialAvailability(
    int orderId,
  ) async {
    if (useMockResponses) {
      return getOrderMaterialRequirements(orderId);
    }
    final uri = Uri.parse('$baseUrl/api/orders/$orderId/check-availability');
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
    );
    final payload = _decodeJsonObject(response.body);
    final parsed = OrderMaterialSnapshotResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success) {
      throw OrderApiException(
        parsed.error ?? 'Failed to check material availability.',
      );
    }
    return parsed.toDomain();
  }

  @override
  Future<OrderMaterialSnapshot> allocateOrderMaterials(int orderId) async {
    if (useMockResponses) {
      final existing = await getOrderMaterialRequirements(orderId);
      final requirements = existing.requirements
          .map(
            (entry) => OrderMaterialRequirementEntry(
              id: entry.id,
              orderId: entry.orderId,
              itemId: entry.itemId,
              materialBarcode: entry.materialBarcode,
              materialName: entry.materialName,
              requiredQty: entry.requiredQty,
              allocatedQty: entry.requiredQty,
              consumedQty: entry.consumedQty,
              availableQty: entry.availableQty - entry.requiredQty,
              shortageQty: 0,
              unitId: entry.unitId,
              unitSymbol: entry.unitSymbol,
              status: 'allocated',
              procurementRequestNumber: entry.procurementRequestNumber,
              procurementRequestStatus: entry.procurementRequestStatus,
              procurementRequestedQty: entry.procurementRequestedQty,
              procurementReceivedQty: entry.procurementReceivedQty,
              procurementPendingQty: entry.procurementPendingQty,
              updatedAt: DateTime.now(),
            ),
          )
          .toList(growable: false);
      final summary = _toSummary(requirements);
      final snapshot = OrderMaterialSnapshot(
        requirements: requirements,
        summary: summary,
      );
      _mockMaterialSnapshots[orderId] = snapshot;
      return snapshot;
    }
    final uri = Uri.parse('$baseUrl/api/orders/$orderId/allocate-materials');
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
    );
    final payload = _decodeJsonObject(response.body);
    final parsed = OrderMaterialSnapshotResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success) {
      throw OrderApiException(parsed.error ?? 'Failed to allocate materials.');
    }
    return parsed.toDomain();
  }

  @override
  Future<OrderMaterialSnapshot> releaseOrderMaterials(int orderId) async {
    if (useMockResponses) {
      final existing = await getOrderMaterialRequirements(orderId);
      final requirements = existing.requirements
          .map(
            (entry) => OrderMaterialRequirementEntry(
              id: entry.id,
              orderId: entry.orderId,
              itemId: entry.itemId,
              materialBarcode: entry.materialBarcode,
              materialName: entry.materialName,
              requiredQty: entry.requiredQty,
              allocatedQty: 0,
              consumedQty: entry.consumedQty,
              availableQty: entry.availableQty + entry.requiredQty,
              shortageQty: entry.requiredQty,
              unitId: entry.unitId,
              unitSymbol: entry.unitSymbol,
              status: 'short',
              procurementRequestNumber: entry.procurementRequestNumber,
              procurementRequestStatus: entry.procurementRequestStatus,
              procurementRequestedQty: entry.procurementRequestedQty,
              procurementReceivedQty: entry.procurementReceivedQty,
              procurementPendingQty: entry.procurementPendingQty,
              updatedAt: DateTime.now(),
            ),
          )
          .toList(growable: false);
      final summary = _toSummary(requirements);
      final snapshot = OrderMaterialSnapshot(
        requirements: requirements,
        summary: summary,
      );
      _mockMaterialSnapshots[orderId] = snapshot;
      return snapshot;
    }
    final uri = Uri.parse('$baseUrl/api/orders/$orderId/release-materials');
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
    );
    final payload = _decodeJsonObject(response.body);
    final parsed = OrderMaterialSnapshotResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success) {
      throw OrderApiException(parsed.error ?? 'Failed to release materials.');
    }
    return parsed.toDomain();
  }

  @override
  Future<OrderMaterialSnapshot> consumeOrderMaterials(int orderId) async {
    if (useMockResponses) {
      final existing = await getOrderMaterialRequirements(orderId);
      final requirements = existing.requirements
          .map(
            (entry) => OrderMaterialRequirementEntry(
              id: entry.id,
              orderId: entry.orderId,
              itemId: entry.itemId,
              materialBarcode: entry.materialBarcode,
              materialName: entry.materialName,
              requiredQty: entry.requiredQty,
              allocatedQty: 0,
              consumedQty: entry.requiredQty,
              availableQty: (entry.availableQty - entry.requiredQty).clamp(
                0,
                double.infinity,
              ),
              shortageQty: 0,
              unitId: entry.unitId,
              unitSymbol: entry.unitSymbol,
              status: 'consumed',
              procurementRequestNumber: entry.procurementRequestNumber,
              procurementRequestStatus: entry.procurementRequestStatus,
              procurementRequestedQty: entry.procurementRequestedQty,
              procurementReceivedQty: entry.procurementReceivedQty,
              procurementPendingQty: entry.procurementPendingQty,
              updatedAt: DateTime.now(),
            ),
          )
          .toList(growable: false);
      final summary = _toSummary(requirements);
      final snapshot = OrderMaterialSnapshot(
        requirements: requirements,
        summary: summary,
      );
      _mockMaterialSnapshots[orderId] = snapshot;
      return snapshot;
    }
    final uri = Uri.parse('$baseUrl/api/orders/$orderId/consume-materials');
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
    );
    final payload = _decodeJsonObject(response.body);
    final parsed = OrderMaterialSnapshotResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success) {
      throw OrderApiException(parsed.error ?? 'Failed to consume materials.');
    }
    return parsed.toDomain();
  }

  @override
  Future<List<OrderProcurementSuggestionEntry>> getOrderProcurementSuggestions(
    int orderId,
  ) async {
    if (useMockResponses) {
      final snapshot = await getOrderMaterialRequirements(orderId);
      final order = _mockOrders
          .where((entry) => entry.id == orderId)
          .firstOrNull;
      if (order == null) {
        return const <OrderProcurementSuggestionEntry>[];
      }
      return _buildMockProcurementSuggestions(order, snapshot);
    }
    final uri = Uri.parse(
      '$baseUrl/api/orders/$orderId/procurement-suggestions',
    );
    final response = await _client.get(uri);
    final payload = _decodeJsonObject(response.body);
    final parsed = OrderProcurementSuggestionsResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success) {
      throw OrderApiException(
        parsed.error ?? 'Failed to fetch procurement suggestions.',
      );
    }
    return parsed.suggestions
        .map((entry) => entry.toDomain())
        .toList(growable: false);
  }

  @override
  Future<List<OrderProcurementSuggestionEntry>>
  getAllProcurementSuggestions() async {
    if (useMockResponses) {
      final suggestions = <OrderProcurementSuggestionEntry>[];
      for (final order in _mockOrders) {
        final snapshot = await getOrderMaterialRequirements(order.id);
        suggestions.addAll(_buildMockProcurementSuggestions(order, snapshot));
      }
      return suggestions;
    }
    final uri = Uri.parse('$baseUrl/api/orders/procurement-suggestions');
    final response = await _client.get(uri);
    final payload = _decodeJsonObject(response.body);
    final parsed = OrderProcurementSuggestionsResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success) {
      throw OrderApiException(
        parsed.error ?? 'Failed to fetch procurement suggestions.',
      );
    }
    return parsed.suggestions
        .map((entry) => entry.toDomain())
        .toList(growable: false);
  }

  @override
  Future<List<OrderProcurementSuggestionEntry>>
  refreshOrderProcurementSuggestions(int orderId) async {
    if (useMockResponses) {
      return getOrderProcurementSuggestions(orderId);
    }
    final uri = Uri.parse(
      '$baseUrl/api/orders/$orderId/procurement-suggestions/refresh',
    );
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
    );
    final payload = _decodeJsonObject(response.body);
    final parsed = OrderProcurementSuggestionsResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success) {
      throw OrderApiException(
        parsed.error ?? 'Failed to refresh procurement suggestions.',
      );
    }
    return parsed.suggestions
        .map((entry) => entry.toDomain())
        .toList(growable: false);
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
      return const {
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

  static OrderTransitionOption? _transitionOptionForAction(String action) {
    const options = <OrderTransitionOption>[
      OrderTransitionOption(
        action: 'confirm',
        label: 'Confirm',
        toStatus: OrderStatus.confirmed,
        transitionStatus: OrderStatus.confirmed,
        needsReason: false,
      ),
      OrderTransitionOption(
        action: 'allocate',
        label: 'Allocate',
        toStatus: OrderStatus.allocated,
        transitionStatus: OrderStatus.allocated,
        needsReason: false,
      ),
      OrderTransitionOption(
        action: 'start-production',
        label: 'Start Production',
        toStatus: OrderStatus.inProduction,
        transitionStatus: OrderStatus.inProduction,
        needsReason: false,
      ),
      OrderTransitionOption(
        action: 'complete',
        label: 'Mark Completed',
        toStatus: OrderStatus.completed,
        transitionStatus: OrderStatus.completed,
        needsReason: false,
      ),
      OrderTransitionOption(
        action: 'dispatch',
        label: 'Dispatch',
        toStatus: OrderStatus.dispatched,
        transitionStatus: OrderStatus.dispatched,
        needsReason: false,
      ),
      OrderTransitionOption(
        action: 'close',
        label: 'Close Order',
        toStatus: OrderStatus.closed,
        transitionStatus: OrderStatus.closed,
        needsReason: false,
      ),
      OrderTransitionOption(
        action: 'hold',
        label: 'Hold',
        toStatus: OrderStatus.onHold,
        transitionStatus: OrderStatus.onHold,
        needsReason: true,
      ),
      OrderTransitionOption(
        action: 'cancel',
        label: 'Cancel',
        toStatus: OrderStatus.cancelled,
        transitionStatus: OrderStatus.cancelled,
        needsReason: true,
      ),
      OrderTransitionOption(
        action: 'revert-to-draft',
        label: 'Revert to Draft',
        toStatus: OrderStatus.draft,
        transitionStatus: OrderStatus.draft,
        needsReason: false,
      ),
    ];
    for (final option in options) {
      if (option.action == action) {
        return option;
      }
    }
    return null;
  }

  static List<OrderTransitionOption> _mockTransitionOptions(
    OrderStatus status,
  ) {
    if (status == OrderStatus.draft) {
      return const <OrderTransitionOption>[
        OrderTransitionOption(
          action: 'confirm',
          label: 'Confirm',
          toStatus: OrderStatus.confirmed,
          transitionStatus: OrderStatus.confirmed,
          needsReason: false,
        ),
        OrderTransitionOption(
          action: 'cancel',
          label: 'Cancel',
          toStatus: OrderStatus.cancelled,
          transitionStatus: OrderStatus.cancelled,
          needsReason: true,
        ),
      ];
    }
    if (status == OrderStatus.confirmed) {
      return const <OrderTransitionOption>[
        OrderTransitionOption(
          action: 'allocate',
          label: 'Allocate',
          toStatus: OrderStatus.allocated,
          transitionStatus: OrderStatus.allocated,
          needsReason: false,
        ),
        OrderTransitionOption(
          action: 'hold',
          label: 'Hold',
          toStatus: OrderStatus.onHold,
          transitionStatus: OrderStatus.onHold,
          needsReason: true,
        ),
        OrderTransitionOption(
          action: 'cancel',
          label: 'Cancel',
          toStatus: OrderStatus.cancelled,
          transitionStatus: OrderStatus.cancelled,
          needsReason: true,
        ),
      ];
    }
    if (status == OrderStatus.allocated) {
      return const <OrderTransitionOption>[
        OrderTransitionOption(
          action: 'start-production',
          label: 'Start Production',
          toStatus: OrderStatus.inProduction,
          transitionStatus: OrderStatus.inProduction,
          needsReason: false,
        ),
        OrderTransitionOption(
          action: 'hold',
          label: 'Hold',
          toStatus: OrderStatus.onHold,
          transitionStatus: OrderStatus.onHold,
          needsReason: true,
        ),
      ];
    }
    if (status == OrderStatus.inProduction) {
      return const <OrderTransitionOption>[
        OrderTransitionOption(
          action: 'complete',
          label: 'Mark Completed',
          toStatus: OrderStatus.completed,
          transitionStatus: OrderStatus.completed,
          needsReason: false,
        ),
        OrderTransitionOption(
          action: 'hold',
          label: 'Hold',
          toStatus: OrderStatus.onHold,
          transitionStatus: OrderStatus.onHold,
          needsReason: true,
        ),
      ];
    }
    if (status == OrderStatus.completed) {
      return const <OrderTransitionOption>[
        OrderTransitionOption(
          action: 'dispatch',
          label: 'Dispatch',
          toStatus: OrderStatus.dispatched,
          transitionStatus: OrderStatus.dispatched,
          needsReason: false,
        ),
        OrderTransitionOption(
          action: 'hold',
          label: 'Hold',
          toStatus: OrderStatus.onHold,
          transitionStatus: OrderStatus.onHold,
          needsReason: true,
        ),
      ];
    }
    if (status == OrderStatus.dispatched) {
      return const <OrderTransitionOption>[
        OrderTransitionOption(
          action: 'close',
          label: 'Close Order',
          toStatus: OrderStatus.closed,
          transitionStatus: OrderStatus.closed,
          needsReason: false,
        ),
      ];
    }
    return const <OrderTransitionOption>[];
  }

  static OrderMaterialSnapshot _buildMockMaterialSnapshot(OrderEntry order) {
    final required = (order.quantity * 1.5).toDouble();
    final available = required + 120;
    final requirement = OrderMaterialRequirementEntry(
      id: order.id * 10,
      orderId: order.id,
      itemId: order.itemId,
      materialBarcode: 'MOCK-${order.itemId.toString().padLeft(4, '0')}',
      materialName: '${order.itemName} Raw',
      requiredQty: required,
      allocatedQty: 0,
      consumedQty: 0,
      availableQty: available,
      shortageQty: required,
      unitId: null,
      unitSymbol: 'Kg',
      status: 'short',
      procurementRequestNumber: null,
      procurementRequestStatus: null,
      procurementRequestedQty: required,
      procurementReceivedQty: 0,
      procurementPendingQty: required,
      updatedAt: DateTime.now(),
    );
    final requirements = <OrderMaterialRequirementEntry>[requirement];
    return OrderMaterialSnapshot(
      requirements: requirements,
      summary: _toSummary(requirements),
    );
  }

  static List<OrderProcurementSuggestionEntry> _buildMockProcurementSuggestions(
    OrderEntry order,
    OrderMaterialSnapshot snapshot,
  ) {
    return snapshot.requirements
        .where((entry) => entry.shortageQty > 0)
        .map(
          (entry) => OrderProcurementSuggestionEntry(
            orderId: order.id,
            orderNo: order.orderNo,
            materialBarcode: entry.materialBarcode,
            materialName: entry.materialName,
            supplier: 'Mock Supplier',
            unitSymbol: entry.unitSymbol,
            requiredQty: entry.requiredQty,
            allocatedQty: entry.allocatedQty,
            consumedQty: entry.consumedQty,
            availableQty: entry.availableQty,
            shortageQty: entry.shortageQty,
            suggestedQty: entry.shortageQty,
            procurementState: 'not_ordered',
          ),
        )
        .toList(growable: false);
  }

  static OrderMaterialSummary _toSummary(
    List<OrderMaterialRequirementEntry> requirements,
  ) {
    var requiredQty = 0.0;
    var allocatedQty = 0.0;
    var consumedQty = 0.0;
    var availableQty = 0.0;
    var shortageQty = 0.0;
    var shortageCount = 0;
    for (final entry in requirements) {
      requiredQty += entry.requiredQty;
      allocatedQty += entry.allocatedQty;
      consumedQty += entry.consumedQty;
      availableQty += entry.availableQty;
      shortageQty += entry.shortageQty;
      if (entry.shortageQty > 0) {
        shortageCount += 1;
      }
    }
    final readiness = requirements.isEmpty
        ? 'no_bom'
        : shortageCount == 0
        ? 'ready'
        : (allocatedQty + consumedQty) > 0
        ? 'partial'
        : 'blocked';
    return OrderMaterialSummary(
      requiredQty: requiredQty,
      allocatedQty: allocatedQty,
      consumedQty: consumedQty,
      availableQty: availableQty,
      shortageQty: shortageQty,
      materialCount: requirements.length,
      shortageCount: shortageCount,
      readiness: readiness,
    );
  }
}

class OrderApiException implements Exception {
  const OrderApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

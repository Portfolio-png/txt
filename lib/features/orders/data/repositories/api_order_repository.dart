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
          createdAt: existing.createdAt,
          startDate: existing.startDate,
          endDate: existing.endDate,
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
        createdAt: DateTime.now(),
        startDate: input.startDate,
        endDate: input.endDate,
      );
      _mockOrders.add(created);
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
        status: input.status,
        createdAt: current.createdAt,
        startDate: input.startDate,
        endDate: input.endDate,
      );
      _mockOrders[index] = updated;
      return updated;
    }

    final uri = Uri.parse('$baseUrl/api/orders/${input.id}/lifecycle');
    final request = UpdateOrderLifecycleRequest.fromInput(input);
    final response = await _client.patch(
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
}

class OrderApiException implements Exception {
  const OrderApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

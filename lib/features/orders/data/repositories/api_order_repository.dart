import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/order_entry.dart';
import '../../domain/order_history.dart';
import '../../domain/order_inputs.dart';
import '../../domain/po_document.dart';
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
  static final List<PoDocumentEntry> _mockPoDocuments = <PoDocumentEntry>[];
  static final Map<int, List<OrderActivityEntry>> _mockOrderActivities =
      <int, List<OrderActivityEntry>>{};
  static final Map<int, List<OrderStatusHistoryEntry>> _mockStatusHistory =
      <int, List<OrderStatusHistoryEntry>>{};
  static final Map<int, Set<int>> _mockOrderPoDocumentIds = <int, Set<int>>{};
  static final Map<String, PoUploadIntentInput> _mockUploadSessions =
      <String, PoUploadIntentInput>{};
  static int _mockNextId = 1;
  static int _mockNextDocumentId = 1;

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
        _linkMockPoDocuments(updated.id, input.poDocumentIds);
        _recordMockActivity(
          updated.id,
          'order_updated',
          details: <String, dynamic>{'quantity': updated.quantity},
        );
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
      _linkMockPoDocuments(created.id, input.poDocumentIds);
      _recordMockActivity(
        created.id,
        'order_created',
        details: <String, dynamic>{
          'status': created.status.name,
          'quantity': created.quantity,
        },
      );
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
  Future<PoUploadIntent> createPoUploadIntent(PoUploadIntentInput input) async {
    if (useMockResponses) {
      final existing = _mockPoDocuments
          .where((document) => document.sha256 == input.sha256)
          .firstOrNull;
      if (existing != null) {
        return PoUploadIntent(alreadyUploaded: true, document: existing);
      }
      final sessionId = 'mock-session-${DateTime.now().microsecondsSinceEpoch}';
      _mockUploadSessions[sessionId] = input;
      return PoUploadIntent(
        alreadyUploaded: false,
        upload: PoUploadTarget(
          uploadSessionId: sessionId,
          objectKey: 'mock-po-documents/${input.sha256}/${input.fileName}',
          uploadUrl: Uri.parse('https://mock.local/$sessionId'),
          headers: const <String, String>{},
        ),
      );
    }

    final uri = Uri.parse('$baseUrl/api/order-po-uploads/intent');
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'fileName': input.fileName,
        'contentType': input.contentType,
        'sizeBytes': input.sizeBytes,
        'sha256': input.sha256,
      }),
    );
    final payload = _decodeJsonObject(response.body);
    final parsed = PoUploadIntentResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success ||
        parsed.intent == null) {
      throw OrderApiException(parsed.error ?? 'Failed to create PO upload.');
    }
    return parsed.intent!;
  }

  @override
  Future<PoDocumentEntry> completePoUpload(CompletePoUploadInput input) async {
    if (useMockResponses) {
      final session = _mockUploadSessions[input.uploadSessionId];
      if (session == null) {
        throw const OrderApiException('Upload session not found.');
      }
      final existing = _mockPoDocuments
          .where((document) => document.sha256 == session.sha256)
          .firstOrNull;
      if (existing != null) {
        return existing;
      }
      final now = DateTime.now();
      final created = PoDocumentEntry(
        id: _mockNextDocumentId++,
        fileName: session.fileName,
        contentType: session.contentType,
        sizeBytes: session.sizeBytes,
        sha256: session.sha256,
        objectKey: input.objectKey,
        status: 'uploaded',
        createdAt: now,
        uploadedAt: now,
      );
      _mockPoDocuments.add(created);
      return created;
    }

    final uri = Uri.parse('$baseUrl/api/order-po-uploads/complete');
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'uploadSessionId': input.uploadSessionId,
        'objectKey': input.objectKey,
      }),
    );
    final payload = _decodeJsonObject(response.body);
    final parsed = PoDocumentResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success ||
        parsed.document == null) {
      throw OrderApiException(parsed.error ?? 'Failed to complete PO upload.');
    }
    return parsed.document!.toDomain();
  }

  @override
  Future<List<PoDocumentEntry>> getPoDocuments(int orderId) async {
    if (useMockResponses) {
      final ids = _mockOrderPoDocumentIds[orderId] ?? const <int>{};
      return _mockPoDocuments
          .where((document) => ids.contains(document.id))
          .toList(growable: false);
    }

    final uri = Uri.parse('$baseUrl/api/orders/$orderId/po-documents');
    final response = await _client.get(uri);
    final payload = _decodeJsonObject(response.body);
    final parsed = PoDocumentsListResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success) {
      throw OrderApiException(parsed.error ?? 'Failed to fetch PO documents.');
    }
    return parsed.documents
        .map((document) => document.toDomain())
        .toList(growable: false);
  }

  @override
  Future<List<OrderActivityEntry>> getOrderActivity(int orderId) async {
    if (useMockResponses) {
      final existing = _mockOrderActivities[orderId];
      if (existing != null && existing.isNotEmpty) {
        return List<OrderActivityEntry>.from(existing);
      }
      final order = _mockOrders
          .where((entry) => entry.id == orderId)
          .firstOrNull;
      if (order == null) {
        return const <OrderActivityEntry>[];
      }
      return <OrderActivityEntry>[
        OrderActivityEntry(
          id: 1,
          orderId: orderId,
          activityType: 'order_created',
          actorName: 'Demo Admin',
          actorRole: 'admin',
          source: 'demo',
          details: <String, dynamic>{
            'status': order.status.name,
            'quantity': order.quantity,
          },
          createdAt: order.createdAt,
        ),
      ];
    }

    final uri = Uri.parse('$baseUrl/api/orders/$orderId/activity');
    final response = await _client.get(uri);
    final payload = _decodeJsonObject(response.body);
    final parsed = OrderActivitiesResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success) {
      throw OrderApiException(
        parsed.error ?? 'Failed to fetch order activity.',
      );
    }
    return parsed.activities
        .map((activity) => activity.toDomain())
        .toList(growable: false);
  }

  @override
  Future<List<OrderStatusHistoryEntry>> getOrderStatusHistory(
    int orderId,
  ) async {
    if (useMockResponses) {
      return List<OrderStatusHistoryEntry>.from(
        _mockStatusHistory[orderId] ?? const <OrderStatusHistoryEntry>[],
      );
    }

    final uri = Uri.parse('$baseUrl/api/orders/$orderId/status-history');
    final response = await _client.get(uri);
    final payload = _decodeJsonObject(response.body);
    final parsed = OrderStatusHistoryResponse.fromJson(payload);
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
  Future<void> linkPoDocuments(int orderId, List<int> documentIds) async {
    if (useMockResponses) {
      _linkMockPoDocuments(orderId, documentIds);
      return;
    }

    final uri = Uri.parse('$baseUrl/api/orders/$orderId/po-documents');
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'documentIds': documentIds}),
    );
    final payload = _decodeJsonObject(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw OrderApiException(
        payload['error'] as String? ?? 'Failed to attach PO documents.',
      );
    }
  }

  @override
  Future<Uri> createPoDocumentReadUrl(int documentId) async {
    if (useMockResponses) {
      return Uri.parse('https://mock.local/po-documents/$documentId');
    }

    final uri = Uri.parse(
      '$baseUrl/api/order-po-documents/$documentId/read-url',
    );
    final response = await _client.post(uri);
    final payload = _decodeJsonObject(response.body);
    final parsed = PoReadUrlResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success ||
        parsed.readUrl == null) {
      throw OrderApiException(parsed.error ?? 'Failed to open PO document.');
    }
    return parsed.readUrl!;
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
      if (current.status != updated.status) {
        final history = _mockStatusHistory.putIfAbsent(
          updated.id,
          () => <OrderStatusHistoryEntry>[],
        );
        history.add(
          OrderStatusHistoryEntry(
            id: history.length + 1,
            orderId: updated.id,
            previousStatus: current.status.name,
            newStatus: updated.status.name,
            changedByUserId: 1,
            changedAt: DateTime.now(),
          ),
        );
      }
      _recordMockActivity(
        updated.id,
        'lifecycle_updated',
        details: <String, dynamic>{
          'previousStatus': current.status.name,
          'newStatus': updated.status.name,
        },
      );
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

  static void _linkMockPoDocuments(int orderId, List<int> documentIds) {
    if (documentIds.isEmpty) {
      return;
    }
    final bucket = _mockOrderPoDocumentIds.putIfAbsent(orderId, () => <int>{});
    bucket.addAll(documentIds);
  }

  static void _recordMockActivity(
    int orderId,
    String activityType, {
    Map<String, dynamic>? details,
  }) {
    final activities = _mockOrderActivities.putIfAbsent(
      orderId,
      () => <OrderActivityEntry>[],
    );
    activities.add(
      OrderActivityEntry(
        id: activities.length + 1,
        orderId: orderId,
        activityType: activityType,
        actorName: 'Demo Admin',
        actorRole: 'admin',
        source: 'demo',
        details: details,
        createdAt: DateTime.now(),
      ),
    );
  }
}

class OrderApiException implements Exception {
  const OrderApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

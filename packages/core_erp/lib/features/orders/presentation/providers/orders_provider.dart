import '../../domain/order_fulfilment.dart';
import 'package:flutter/material.dart';

import '../../domain/order_entry.dart';
import '../../domain/order_history.dart';
import '../../domain/order_inputs.dart';
import '../../domain/order_production_report.dart';
import '../../domain/order_trace.dart';
import '../../domain/po_document.dart';
import '../../data/repositories/order_repository.dart';

import '../../data/models/order_api_models.dart';

import '../../../../core/services/socket_service.dart';

class OrdersProvider extends ChangeNotifier {
  OrdersProvider({required OrderRepository repository})
    : _repository = repository;

  final OrderRepository _repository;

  List<OrderEntry> _orders = const <OrderEntry>[];
  String _searchQuery = '';
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;
  String? _lastCreateOutcomeMessage;
  bool _lastCreateWasMerged = false;
  bool _initialized = false;

  Future<OrderProductionReport> loadProductionReport(String orderNo) =>
      _repository.getProductionReport(orderNo);

  Future<List<OrderReturn>> loadOrderReturns(String orderNo) =>
      _repository.getOrderReturns(orderNo);

  Future<OrderReturn> logOrderReturn(CreateOrderReturnInput input) =>
      _repository.createOrderReturn(input);

  Future<OrderTrace> loadOrderTrace(String orderNo) =>
      _repository.getOrderTrace(orderNo);

  List<OrderEntry> get orders => List<OrderEntry>.unmodifiable(_orders);
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  String? get lastCreateOutcomeMessage => _lastCreateOutcomeMessage;
  bool get lastCreateWasMerged => _lastCreateWasMerged;

  List<OrderEntry> get filteredOrders {
    final query = _normalize(_searchQuery);
    final source = List<OrderEntry>.from(_orders)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (query.isEmpty) {
      return source;
    }
    return source
        .where(
          (order) =>
              _normalize(order.orderNo).contains(query) ||
              _normalize(order.clientName).contains(query) ||
              _normalize(order.poNumber).contains(query) ||
              _normalize(order.clientCode).contains(query) ||
              _normalize(order.itemName).contains(query) ||
              _normalize(order.variationPathLabel).contains(query) ||
              _normalize(order.status.name).contains(query) ||
              order.quantity.toString().contains(query),
        )
        .toList(growable: false);
  }

  /// Ordered / delivered / produced per line, keyed by order-item id. Empty
  /// until [loadFulfilment] runs — the insights view asks for it, the order
  /// book does not need it.
  Map<int, OrderFulfilment> _fulfilment = const <int, OrderFulfilment>{};
  Map<int, OrderFulfilment> get fulfilment => _fulfilment;

  bool _isLoadingFulfilment = false;
  bool get isLoadingFulfilment => _isLoadingFulfilment;

  /// Whether the rollup has ever come back. Until it has, callers must not read
  /// an empty [fulfilment] as "nothing is in production" — it means "not asked
  /// yet", which is a different thing entirely.
  bool _fulfilmentLoaded = false;
  bool get fulfilmentLoaded => _fulfilmentLoaded;

  Future<void> loadFulfilment() async {
    if (_isLoadingFulfilment) return;
    _isLoadingFulfilment = true;
    notifyListeners();
    try {
      final rows = await _repository.getFulfilment();
      _fulfilment = {for (final row in rows) row.orderItemId: row};
      _fulfilmentLoaded = true;
    } catch (_) {
      // Keep the last good rollup: a dropped request is not evidence that
      // production stopped, and blanking the map silently reclassifies every
      // card as having no pipeline.
    } finally {
      _isLoadingFulfilment = false;
      notifyListeners();
    }
  }

  List<OrderGroup> get filteredOrderGroups {
    final filtered = filteredOrders;
    final map = <String, OrderGroup>{};
    for (final order in filtered) {
      if (map.containsKey(order.orderNo)) {
        map[order.orderNo]!.items.add(order);
      } else {
        map[order.orderNo] = OrderGroup(
          orderNo: order.orderNo,
          clientId: order.clientId,
          clientName: order.clientName,
          poNumber: order.poNumber,
          createdAt: order.createdAt,
          items: [order],
        );
      }
    }
    return map.values.toList();
  }

  /// Builds the [OrderGroup] for a given order number from all loaded orders
  /// (unfiltered) — used to open an order's detail modal from another feature
  /// (e.g. an inventory card's origin link). Returns null if not loaded.
  OrderGroup? findGroupByOrderNo(String orderNo) {
    final key = orderNo.trim();
    if (key.isEmpty) return null;
    final items = _orders.where((o) => o.orderNo == key).toList();
    if (items.isEmpty) return null;
    final first = items.first;
    return OrderGroup(
      orderNo: first.orderNo,
      clientId: first.clientId,
      clientName: first.clientName,
      poNumber: first.poNumber,
      createdAt: first.createdAt,
      items: items,
    );
  }

  void setSearchQuery(String value) {
    _searchQuery = value;
    notifyListeners();
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    SocketService.instance.on('orders_changed', (data) => refresh());

    await refresh();
  }

  Future<void> refresh() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _repository.init();
      _orders = await _repository.getOrders();
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    // Anything that moves the order book can also move production: starting a
    // run, issuing a challan, completing a stage. Once insights has been opened
    // its figures must track those, not stay frozen at first load.
    if (_fulfilmentLoaded) {
      await loadFulfilment();
    }
  }

  Future<OrderEntry?> createOrder(CreateOrderInput input) async {
    final existing = _matchingOrderForInput(input);
    _lastCreateOutcomeMessage = null;
    _lastCreateWasMerged = false;
    return _save(
      () => _repository.createOrder(input),
      onSuccess: (saved) {
        if (existing != null && existing.id == saved.id) {
          _lastCreateWasMerged = true;
          _lastCreateOutcomeMessage =
              '${input.quantity} added to existing order (was ${existing.quantity}, now ${saved.quantity}).';
          return;
        }
        _lastCreateWasMerged = false;
        _lastCreateOutcomeMessage = null;
      },
    );
  }

  Future<OrderEntry?> updateOrder(int orderId, CreateOrderInput input) async {
    return _save(() => _repository.updateOrder(orderId, input));
  }

  Future<List<OrderDeletionSummary>?> deleteOrder(
    int orderId, {
    String? wipBarcode,
    double? wipQty,
  }) async {
    if (_isSaving) return null;
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final summary = await _repository.deleteOrder(
        orderId,
        wipBarcode: wipBarcode,
        wipQty: wipQty,
      );
      await refresh();
      return summary;
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<OrderEntry?> updateOrderLifecycle(
    UpdateOrderLifecycleInput input,
  ) async {
    return _save(() => _repository.updateOrderLifecycle(input));
  }

  Future<PoUploadIntent> createPoUploadIntent(PoUploadIntentInput input) async {
    return _repository.createPoUploadIntent(input);
  }

  Future<PoDocumentEntry> completePoUpload(CompletePoUploadInput input) async {
    return _repository.completePoUpload(input);
  }

  Future<List<PoDocumentEntry>> getPoDocuments(int orderId) {
    return _repository.getPoDocuments(orderId);
  }

  Future<List<OrderActivityEntry>> getOrderActivity(int orderId) {
    return _repository.getOrderActivity(orderId);
  }

  Future<List<OrderStatusHistoryEntry>> getOrderStatusHistory(int orderId) {
    return _repository.getOrderStatusHistory(orderId);
  }

  Future<void> linkPoDocuments(int orderId, List<int> documentIds) {
    return _repository.linkPoDocuments(orderId, documentIds);
  }

  Future<Uri> createPoDocumentReadUrl(int documentId) {
    return _repository.createPoDocumentReadUrl(documentId);
  }

  Future<OrderEntry?> _save(
    Future<OrderEntry> Function() action, {
    void Function(OrderEntry saved)? onSuccess,
  }) async {
    if (_isSaving) return null;
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final saved = await action();
      onSuccess?.call(saved);
      await refresh();
      return _orders.where((order) => order.id == saved.id).firstOrNull ??
          saved;
    } catch (error) {
      _lastCreateOutcomeMessage = null;
      _lastCreateWasMerged = false;
      _errorMessage = error.toString();
      notifyListeners();
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  static String _normalize(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  OrderEntry? _matchingOrderForInput(CreateOrderInput input) {
    return _orders.where((order) {
      return _normalize(order.orderNo) == _normalize(input.orderNo) &&
          order.clientId == input.clientId &&
          order.itemId == input.itemId &&
          order.variationLeafNodeId == input.variationLeafNodeId &&
          _normalize(order.poNumber) == _normalize(input.poNumber) &&
          _sameMoment(order.startDate, input.startDate) &&
          _sameMoment(order.endDate, input.endDate);
    }).firstOrNull;
  }

  bool _sameMoment(DateTime? left, DateTime? right) {
    if (left == null || right == null) {
      return left == right;
    }
    return left.toUtc().millisecondsSinceEpoch ==
        right.toUtc().millisecondsSinceEpoch;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

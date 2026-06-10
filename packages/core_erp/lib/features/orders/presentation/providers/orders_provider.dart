import 'package:flutter/material.dart';

import '../../domain/order_entry.dart';
import '../../domain/order_history.dart';
import '../../domain/order_inputs.dart';
import '../../domain/po_document.dart';
import '../../data/repositories/order_repository.dart';

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


  void setSearchQuery(String value) {
    _searchQuery = value;
    notifyListeners();
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
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

  Future<bool> deleteOrder(int orderId) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _repository.deleteOrder(orderId);
      await refresh();
      return true;
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return false;
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

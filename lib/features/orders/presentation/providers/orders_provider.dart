import 'package:flutter/material.dart';

import '../../domain/order_entry.dart';
import '../../domain/order_inputs.dart';
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
  bool _initialized = false;
  int? _focusedOrderId;
  bool _openFocusedOrderDetails = false;

  List<OrderEntry> get orders => List<OrderEntry>.unmodifiable(_orders);
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  int? get focusedOrderId => _focusedOrderId;
  bool get openFocusedOrderDetails => _openFocusedOrderDetails;

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

  void setSearchQuery(String value) {
    _searchQuery = value;
    notifyListeners();
  }

  void focusOrderFromExternal({
    required int orderId,
    String? query,
    bool openDetails = true,
  }) {
    if (query != null) {
      _searchQuery = query;
    }
    _focusedOrderId = orderId;
    _openFocusedOrderDetails = openDetails;
    notifyListeners();
  }

  void clearExternalOrderFocus() {
    _focusedOrderId = null;
    _openFocusedOrderDetails = false;
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
    return _save(() => _repository.createOrder(input));
  }

  Future<OrderEntry?> updateOrderLifecycle(
    UpdateOrderLifecycleInput input,
  ) async {
    return _save(() => _repository.updateOrderLifecycle(input));
  }

  Future<OrderEntry?> transitionOrderByAction({
    required int orderId,
    required String action,
    String? reason,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    return _save(
      () => _repository.transitionOrderByAction(
        orderId: orderId,
        action: action,
        reason: reason,
        startDate: startDate,
        endDate: endDate,
      ),
    );
  }

  Future<OrderEntry?> updateOrderPriority({
    required int orderId,
    required OrderPriority priority,
  }) async {
    return _save(
      () =>
          _repository.updateOrderPriority(orderId: orderId, priority: priority),
    );
  }

  Future<List<OrderActivityEntry>> getOrderActivity(int orderId) async {
    try {
      return await _repository.getOrderActivity(orderId);
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return const <OrderActivityEntry>[];
    }
  }

  Future<List<OrderStatusHistoryEntry>> getOrderStatusHistory(
    int orderId,
  ) async {
    try {
      return await _repository.getOrderStatusHistory(orderId);
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return const <OrderStatusHistoryEntry>[];
    }
  }

  Future<List<OrderTransitionOption>> getOrderTransitionOptions(
    int orderId,
  ) async {
    try {
      return await _repository.getOrderTransitionOptions(orderId);
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return const <OrderTransitionOption>[];
    }
  }

  Future<OrderActivityEntry?> addOrderNote(AddOrderNoteInput input) async {
    try {
      final event = await _repository.addOrderNote(input);
      return event;
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return null;
    }
  }

  Future<OrderMaterialSnapshot?> getOrderMaterialRequirements(
    int orderId,
  ) async {
    try {
      return await _repository.getOrderMaterialRequirements(orderId);
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return null;
    }
  }

  Future<OrderMaterialSnapshot?> checkOrderMaterialAvailability(
    int orderId,
  ) async {
    try {
      return await _repository.checkOrderMaterialAvailability(orderId);
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return null;
    }
  }

  Future<OrderMaterialSnapshot?> allocateOrderMaterials(int orderId) async {
    try {
      return await _repository.allocateOrderMaterials(orderId);
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return null;
    }
  }

  Future<OrderMaterialSnapshot?> releaseOrderMaterials(int orderId) async {
    try {
      return await _repository.releaseOrderMaterials(orderId);
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return null;
    }
  }

  Future<OrderMaterialSnapshot?> consumeOrderMaterials(int orderId) async {
    try {
      return await _repository.consumeOrderMaterials(orderId);
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return null;
    }
  }

  Future<List<OrderProcurementSuggestionEntry>> getOrderProcurementSuggestions(
    int orderId,
  ) async {
    try {
      return await _repository.getOrderProcurementSuggestions(orderId);
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return const <OrderProcurementSuggestionEntry>[];
    }
  }

  Future<List<OrderProcurementSuggestionEntry>>
  refreshOrderProcurementSuggestions(int orderId) async {
    try {
      return await _repository.refreshOrderProcurementSuggestions(orderId);
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return const <OrderProcurementSuggestionEntry>[];
    }
  }

  Future<List<OrderProcurementSuggestionEntry>>
  getAllProcurementSuggestions() async {
    try {
      return await _repository.getAllProcurementSuggestions();
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return const <OrderProcurementSuggestionEntry>[];
    }
  }

  Future<OrderEntry?> _save(Future<OrderEntry> Function() action) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final saved = await action();
      await refresh();
      return _orders.where((order) => order.id == saved.id).firstOrNull ??
          saved;
    } catch (error) {
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
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

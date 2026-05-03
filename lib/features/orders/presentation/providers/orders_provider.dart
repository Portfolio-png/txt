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
  bool _initialized = false;

  List<OrderEntry> get orders => List<OrderEntry>.unmodifiable(_orders);
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;

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

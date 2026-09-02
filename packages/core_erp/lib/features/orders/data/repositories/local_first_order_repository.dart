import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../core/sync/replica_reader.dart';
import '../../domain/order_entry.dart';
import '../../domain/order_fulfilment.dart';
import '../../domain/order_history.dart';
import '../../domain/order_inputs.dart';
import '../../domain/order_production_report.dart';
import '../../domain/order_trace.dart';
import '../../domain/po_document.dart';
import '../models/order_api_models.dart';
import 'order_repository.dart';

/// Serves the order list from the local replica.
///
/// Orders are the largest payload in the app — 93 lines is 5.9 KB on the wire,
/// and it grows with the business rather than staying put. Everything except
/// the plain list still goes to the server: reports, traces, activity, PO
/// documents and every write.
///
/// **Only the unfiltered list is answered locally.** The server understands
/// `search`, `clientId`, `statuses`, `ids`, `limit` and `offset`, and its search
/// runs across eight columns with SQL semantics. Reproducing that here would
/// mean two implementations of one filter that must agree exactly — and the way
/// they would disagree is a user searching for an order that exists and being
/// told it does not. A narrowed request goes to the server, which is both
/// correct and small: `?client_id=` returns nine rows where the list returns
/// ninety-three.
class LocalFirstOrderRepository implements OrderRepository {
  LocalFirstOrderRepository({
    required OrderRepository remote,
    required Future<Database?> Function() replica,
    required bool Function() isHydrated,
  }) : _remote = remote,
       _reader = ReplicaReader(replica: replica, isHydrated: isHydrated);

  final OrderRepository _remote;
  final ReplicaReader _reader;

  @override
  Future<void> init() => _remote.init();

  @override
  Future<List<OrderEntry>> getOrders({
    String search = '',
    int? clientId,
    List<String> statuses = const <String>[],
    List<int> ids = const <int>[],
    int? limit,
    int offset = 0,
  }) async {
    final narrowed = search.trim().isNotEmpty ||
        (clientId != null && clientId > 0) ||
        statuses.isNotEmpty ||
        ids.isNotEmpty ||
        limit != null ||
        offset > 0;
    if (narrowed) {
      return _remote.getOrders(
        search: search,
        clientId: clientId,
        statuses: statuses,
        ids: ids,
        limit: limit,
        offset: offset,
      );
    }

    // `ORDER BY datetime(created_at) DESC, id DESC` — the id is the tiebreaker
    // and dropping it reorders rows created in the same second.
    final local = await _reader.readAll<OrderEntry>(
      'local_order_items',
      orderBy: 'datetime(created_at) DESC, id DESC',
      fromJson: (json) => OrderDto.fromJson(json).toDomain(),
    );
    return local ?? _remote.getOrders();
  }

  // --- everything below only the server can answer --------------------------

  @override
  Future<OrderEntry> createOrder(CreateOrderInput input) => _remote.createOrder(input);

  @override
  Future<OrderEntry> updateOrder(int orderId, CreateOrderInput input) =>
      _remote.updateOrder(orderId, input);

  @override
  Future<List<OrderDeletionSummary>> deleteOrder(
    int orderId, {
    String? wipBarcode,
    double? wipQty,
  }) => _remote.deleteOrder(orderId, wipBarcode: wipBarcode, wipQty: wipQty);

  @override
  Future<OrderEntry> updateOrderLifecycle(UpdateOrderLifecycleInput input) =>
      _remote.updateOrderLifecycle(input);

  @override
  Future<PoUploadIntent> createPoUploadIntent(PoUploadIntentInput input) =>
      _remote.createPoUploadIntent(input);

  @override
  Future<PoDocumentEntry> completePoUpload(CompletePoUploadInput input) =>
      _remote.completePoUpload(input);

  @override
  Future<List<PoDocumentEntry>> getPoDocuments(int orderId) =>
      _remote.getPoDocuments(orderId);

  @override
  Future<List<OrderActivityEntry>> getOrderActivity(int orderId) =>
      _remote.getOrderActivity(orderId);

  @override
  Future<List<OrderStatusHistoryEntry>> getOrderStatusHistory(int orderId) =>
      _remote.getOrderStatusHistory(orderId);

  @override
  Future<void> linkPoDocuments(int orderId, List<int> documentIds) =>
      _remote.linkPoDocuments(orderId, documentIds);

  @override
  Future<Uri> createPoDocumentReadUrl(int documentId) =>
      _remote.createPoDocumentReadUrl(documentId);

  @override
  Future<OrderProductionReport> getProductionReport(String orderNo) =>
      _remote.getProductionReport(orderNo);

  @override
  Future<List<OrderReturn>> getOrderReturns(String orderNo) =>
      _remote.getOrderReturns(orderNo);

  @override
  Future<OrderReturn> createOrderReturn(CreateOrderReturnInput input) =>
      _remote.createOrderReturn(input);

  @override
  Future<OrderTrace> getOrderTrace(String orderNo) => _remote.getOrderTrace(orderNo);

  @override
  Future<List<OrderFulfilment>> getFulfilment() => _remote.getFulfilment();
}

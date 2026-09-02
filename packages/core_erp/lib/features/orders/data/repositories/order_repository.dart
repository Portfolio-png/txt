import '../../domain/order_fulfilment.dart';
import '../../domain/order_entry.dart';
import '../../domain/order_history.dart';
import '../../domain/order_inputs.dart';
import '../../domain/order_production_report.dart';
import '../../domain/order_trace.dart';
import '../../domain/po_document.dart';
import '../models/order_api_models.dart';

abstract class OrderRepository {
  Future<void> init();
  /// The order list, optionally narrowed and paged.
  ///
  /// Called with no arguments it returns every order, because several features
  /// legitimately need the whole set resident — the production order picker,
  /// challan order-selection, a client's history. A default page size would
  /// silently truncate them.
  ///
  /// `search` is applied by the server across the same eight fields the list
  /// used to filter in memory, so the two agree exactly.
  Future<List<OrderEntry>> getOrders({
    String search,
    int? clientId,
    List<String> statuses,
    List<int> ids,
    int? limit,
    int offset,
  });
  Future<OrderEntry> createOrder(CreateOrderInput input);
  Future<OrderEntry> updateOrder(int orderId, CreateOrderInput input);
  Future<List<OrderDeletionSummary>> deleteOrder(
    int orderId, {
    String? wipBarcode,
    double? wipQty,
  });
  Future<OrderEntry> updateOrderLifecycle(UpdateOrderLifecycleInput input);
  Future<PoUploadIntent> createPoUploadIntent(PoUploadIntentInput input);
  Future<PoDocumentEntry> completePoUpload(CompletePoUploadInput input);
  Future<List<PoDocumentEntry>> getPoDocuments(int orderId);
  Future<List<OrderActivityEntry>> getOrderActivity(int orderId);
  Future<List<OrderStatusHistoryEntry>> getOrderStatusHistory(int orderId);
  Future<void> linkPoDocuments(int orderId, List<int> documentIds);
  Future<Uri> createPoDocumentReadUrl(int documentId);
  Future<OrderProductionReport> getProductionReport(String orderNo);

  /// Customer return / defect events logged on an order.
  Future<List<OrderReturn>> getOrderReturns(String orderNo);

  /// Logs a new customer return / defect event.
  Future<OrderReturn> createOrderReturn(CreateOrderReturnInput input);

  /// Backward QC lineage for an order: returns → runs → die/machine → sheets.
  Future<OrderTrace> getOrderTrace(String orderNo);

  /// Ordered / delivered / produced for every order line, in one request.
  Future<List<OrderFulfilment>> getFulfilment();
}

import '../../domain/order_entry.dart';
import '../../domain/order_history.dart';
import '../../domain/order_inputs.dart';
import '../../domain/po_document.dart';

abstract class OrderRepository {
  Future<void> init();
  Future<List<OrderEntry>> getOrders();
  Future<OrderEntry> createOrder(CreateOrderInput input);
  Future<OrderEntry> updateOrderLifecycle(UpdateOrderLifecycleInput input);
  Future<PoUploadIntent> createPoUploadIntent(PoUploadIntentInput input);
  Future<PoDocumentEntry> completePoUpload(CompletePoUploadInput input);
  Future<List<PoDocumentEntry>> getPoDocuments(int orderId);
  Future<List<OrderActivityEntry>> getOrderActivity(int orderId);
  Future<List<OrderStatusHistoryEntry>> getOrderStatusHistory(int orderId);
  Future<void> linkPoDocuments(int orderId, List<int> documentIds);
  Future<Uri> createPoDocumentReadUrl(int documentId);
}

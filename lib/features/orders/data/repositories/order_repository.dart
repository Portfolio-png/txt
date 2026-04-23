import '../../domain/order_entry.dart';
import '../../domain/order_inputs.dart';

abstract class OrderRepository {
  Future<void> init();
  Future<List<OrderEntry>> getOrders();
  Future<OrderEntry> createOrder(CreateOrderInput input);
  Future<OrderEntry> updateOrderLifecycle(UpdateOrderLifecycleInput input);
  Future<OrderEntry> transitionOrderByAction({
    required int orderId,
    required String action,
    String? reason,
    DateTime? startDate,
    DateTime? endDate,
  });
  Future<OrderEntry> updateOrderPriority({
    required int orderId,
    required OrderPriority priority,
  });
  Future<List<OrderActivityEntry>> getOrderActivity(int orderId);
  Future<List<OrderStatusHistoryEntry>> getOrderStatusHistory(int orderId);
  Future<List<OrderTransitionOption>> getOrderTransitionOptions(int orderId);
  Future<OrderActivityEntry> addOrderNote(AddOrderNoteInput input);
  Future<OrderMaterialSnapshot> getOrderMaterialRequirements(int orderId);
  Future<OrderMaterialSnapshot> checkOrderMaterialAvailability(int orderId);
  Future<OrderMaterialSnapshot> allocateOrderMaterials(int orderId);
  Future<OrderMaterialSnapshot> releaseOrderMaterials(int orderId);
  Future<OrderMaterialSnapshot> consumeOrderMaterials(int orderId);
  Future<List<OrderProcurementSuggestionEntry>> getOrderProcurementSuggestions(
    int orderId,
  );
  Future<List<OrderProcurementSuggestionEntry>> getAllProcurementSuggestions();
  Future<List<OrderProcurementSuggestionEntry>>
  refreshOrderProcurementSuggestions(int orderId);
}

import '../../domain/order_entry.dart';
import '../../domain/order_inputs.dart';

abstract class OrderRepository {
  Future<void> init();
  Future<List<OrderEntry>> getOrders();
  Future<OrderEntry> createOrder(CreateOrderInput input);
  Future<OrderEntry> updateOrderLifecycle(UpdateOrderLifecycleInput input);
}

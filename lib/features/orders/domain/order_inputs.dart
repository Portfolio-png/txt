import 'order_entry.dart';

class CreateOrderInput {
  const CreateOrderInput({
    required this.orderNo,
    required this.clientId,
    required this.clientName,
    required this.poNumber,
    required this.clientCode,
    required this.itemId,
    required this.itemName,
    required this.variationLeafNodeId,
    required this.variationPathLabel,
    required this.variationPathNodeIds,
    required this.quantity,
    this.status = OrderStatus.draft,
    this.priority = OrderPriority.normal,
    this.startDate,
    this.endDate,
  });

  final String orderNo;
  final int clientId;
  final String clientName;
  final String poNumber;
  final String clientCode;
  final int itemId;
  final String itemName;
  final int variationLeafNodeId;
  final String variationPathLabel;
  final List<int> variationPathNodeIds;
  final int quantity;
  final OrderStatus status;
  final OrderPriority priority;
  final DateTime? startDate;
  final DateTime? endDate;
}

class UpdateOrderLifecycleInput {
  const UpdateOrderLifecycleInput({
    required this.id,
    required this.toStatus,
    this.reason,
    this.startDate,
    this.endDate,
  });

  final int id;
  final OrderStatus toStatus;
  final String? reason;
  final DateTime? startDate;
  final DateTime? endDate;
}

class AddOrderNoteInput {
  const AddOrderNoteInput({required this.orderId, required this.note});

  final int orderId;
  final String note;
}

import '../../domain/order_entry.dart';
import '../../domain/order_inputs.dart';

OrderStatus _statusFromJson(String value) {
  return OrderStatus.values
          .where((status) => status.name == value)
          .firstOrNull ??
      OrderStatus.notStarted;
}

class OrderDto {
  const OrderDto({
    required this.id,
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
    required this.status,
    required this.createdAt,
    required this.startDate,
    required this.endDate,
  });

  final int id;
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
  final DateTime createdAt;
  final DateTime? startDate;
  final DateTime? endDate;

  factory OrderDto.fromJson(Map<String, dynamic> json) {
    return OrderDto(
      id: json['id'] as int? ?? 0,
      orderNo: json['orderNo'] as String? ?? '',
      clientId: json['clientId'] as int? ?? 0,
      clientName: json['clientName'] as String? ?? '',
      poNumber: json['poNumber'] as String? ?? '',
      clientCode: json['clientCode'] as String? ?? '',
      itemId: json['itemId'] as int? ?? 0,
      itemName: json['itemName'] as String? ?? '',
      variationLeafNodeId: json['variationLeafNodeId'] as int? ?? 0,
      variationPathLabel: json['variationPathLabel'] as String? ?? '',
      variationPathNodeIds:
          (json['variationPathNodeIds'] as List<dynamic>? ?? const [])
              .map((entry) => entry as int)
              .toList(growable: false),
      quantity: json['quantity'] as int? ?? 0,
      status: _statusFromJson(json['status'] as String? ?? ''),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      startDate: DateTime.tryParse(json['startDate'] as String? ?? ''),
      endDate: DateTime.tryParse(json['endDate'] as String? ?? ''),
    );
  }

  OrderEntry toDomain() {
    return OrderEntry(
      id: id,
      orderNo: orderNo,
      clientId: clientId,
      clientName: clientName,
      poNumber: poNumber,
      clientCode: clientCode,
      itemId: itemId,
      itemName: itemName,
      variationLeafNodeId: variationLeafNodeId,
      variationPathLabel: variationPathLabel,
      variationPathNodeIds: variationPathNodeIds,
      quantity: quantity,
      status: status,
      createdAt: createdAt,
      startDate: startDate,
      endDate: endDate,
    );
  }
}

class OrderResponse {
  const OrderResponse({required this.success, this.order, this.error});

  final bool success;
  final OrderDto? order;
  final String? error;

  factory OrderResponse.fromJson(Map<String, dynamic> json) {
    return OrderResponse(
      success: json['success'] as bool? ?? false,
      order: json['order'] == null
          ? null
          : OrderDto.fromJson(json['order'] as Map<String, dynamic>),
      error: json['error'] as String?,
    );
  }
}

class OrdersListResponse {
  const OrdersListResponse({required this.success, required this.orders});

  final bool success;
  final List<OrderDto> orders;

  factory OrdersListResponse.fromJson(Map<String, dynamic> json) {
    return OrdersListResponse(
      success: json['success'] as bool? ?? false,
      orders: (json['orders'] as List<dynamic>? ?? const [])
          .map((item) => OrderDto.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

class CreateOrderRequest {
  const CreateOrderRequest({
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
    required this.status,
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
  final DateTime? startDate;
  final DateTime? endDate;

  factory CreateOrderRequest.fromInput(CreateOrderInput input) {
    return CreateOrderRequest(
      orderNo: input.orderNo,
      clientId: input.clientId,
      clientName: input.clientName,
      poNumber: input.poNumber,
      clientCode: input.clientCode,
      itemId: input.itemId,
      itemName: input.itemName,
      variationLeafNodeId: input.variationLeafNodeId,
      variationPathLabel: input.variationPathLabel,
      variationPathNodeIds: input.variationPathNodeIds,
      quantity: input.quantity,
      status: input.status,
      startDate: input.startDate,
      endDate: input.endDate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'orderNo': orderNo,
      'clientId': clientId,
      'clientName': clientName,
      'poNumber': poNumber,
      'clientCode': clientCode,
      'itemId': itemId,
      'itemName': itemName,
      'variationLeafNodeId': variationLeafNodeId,
      'variationPathLabel': variationPathLabel,
      'variationPathNodeIds': variationPathNodeIds,
      'quantity': quantity,
      'status': status.name,
      'startDate': startDate?.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
    };
  }
}

class UpdateOrderLifecycleRequest {
  const UpdateOrderLifecycleRequest({
    required this.status,
    this.startDate,
    this.endDate,
  });

  final OrderStatus status;
  final DateTime? startDate;
  final DateTime? endDate;

  factory UpdateOrderLifecycleRequest.fromInput(
    UpdateOrderLifecycleInput input,
  ) {
    return UpdateOrderLifecycleRequest(
      status: input.status,
      startDate: input.startDate,
      endDate: input.endDate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status.name,
      'startDate': startDate?.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
    };
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

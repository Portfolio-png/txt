import 'order_entry.dart';

class CreateOrderInput {
  const CreateOrderInput({
    required this.orderNo,
    required this.clientId,
    this.subContractorId,
    required this.clientName,
    required this.poNumber,
    required this.clientCode,
    required this.itemId,
    required this.itemName,
    required this.variationLeafNodeId,
    required this.variationPathLabel,
    required this.variationPathNodeIds,
    this.customVariationValues = const <String, String>{},
    required this.quantity,
    this.unitId,
    this.unitName = 'Pieces',
    this.unitSymbol = 'Pieces',
    this.status = OrderStatus.notStarted,
    this.unitPrice = 0,
    this.totalInvoicedQty = 0,
    this.startDate,
    this.endDate,
    this.poDocumentIds = const <int>[],
  });

  final String orderNo;
  final int clientId;
  final int? subContractorId;
  final String clientName;
  final String poNumber;
  final String clientCode;
  final int itemId;
  final String itemName;
  final int variationLeafNodeId;
  final String variationPathLabel;
  final List<int> variationPathNodeIds;
  final Map<String, String> customVariationValues;
  final int quantity;
  final int? unitId;
  final String unitName;
  final String unitSymbol;
  final OrderStatus status;
  final double unitPrice;
  final double totalInvoicedQty;
  final DateTime? startDate;
  final DateTime? endDate;
  final List<int> poDocumentIds;
}

class UpdateOrderLifecycleInput {
  const UpdateOrderLifecycleInput({
    required this.id,
    required this.status,
    this.startDate,
    this.endDate,
  });

  final int id;
  final OrderStatus status;
  final DateTime? startDate;
  final DateTime? endDate;
}

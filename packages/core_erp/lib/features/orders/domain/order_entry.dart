enum OrderStatus { draft, notStarted, inProgress, completed, delayed }

OrderStatus orderStatusFromName(String value) {
  return OrderStatus.values
          .where((status) => status.name == value)
          .firstOrNull ??
      OrderStatus.notStarted;
}

class OrderEntry {
  const OrderEntry({
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
    this.unitId,
    this.unitName = 'Pieces',
    this.unitSymbol = 'Pieces',
    this.unitPrice = 0,
    this.totalInvoicedQty = 0,
    this.totalDeliveredQty = 0,
    this.startDate,
    this.endDate,
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
  final int? unitId;
  final String unitName;
  final String unitSymbol;
  final double unitPrice;
  final double totalInvoicedQty;
  final double totalDeliveredQty;
  final OrderStatus status;
  final DateTime createdAt;
  final DateTime? startDate;
  final DateTime? endDate;

  String get unitDisplayLabel {
    final symbol = unitSymbol.trim();
    if (symbol.isNotEmpty) {
      return symbol;
    }
    final name = unitName.trim();
    return name.isNotEmpty ? name : 'Pieces';
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class OrderGroup {
  const OrderGroup({
    required this.orderNo,
    required this.clientId,
    required this.clientName,
    required this.poNumber,
    required this.createdAt,
    required this.items,
  });

  final String orderNo;
  final int clientId;
  final String clientName;
  final String poNumber;
  final DateTime createdAt;
  final List<OrderEntry> items;

  OrderStatus get overallStatus {
    if (items.isEmpty) return OrderStatus.notStarted;
    if (items.every((i) => i.status == OrderStatus.completed)) {
      return OrderStatus.completed;
    }
    if (items.every((i) => i.status == OrderStatus.draft)) {
      return OrderStatus.draft;
    }
    if (items.every((i) => i.status == OrderStatus.notStarted)) {
      return OrderStatus.notStarted;
    }
    if (items.any((i) => i.status == OrderStatus.delayed)) {
      return OrderStatus.delayed;
    }
    return OrderStatus.inProgress;
  }
}


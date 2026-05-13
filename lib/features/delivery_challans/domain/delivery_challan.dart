enum DeliveryChallanStatus { draft, issued, cancelled }

enum ChallanType { delivery, reception }

ChallanType challanTypeFromName(String value) {
  return ChallanType.values.firstWhere(
    (type) => type.name == value.toLowerCase(),
    orElse: () => ChallanType.delivery,
  );
}

DeliveryChallanStatus deliveryChallanStatusFromName(String value) {
  return DeliveryChallanStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => DeliveryChallanStatus.draft,
  );
}

class CompanyProfile {
  const CompanyProfile({
    required this.id,
    required this.companyName,
    required this.mobile,
    required this.businessDescription,
    required this.address,
    required this.stateCode,
    required this.gstin,
    required this.logoUrl,
    required this.signatureLabel,
  });

  final int id;
  final String companyName;
  final String mobile;
  final String businessDescription;
  final String address;
  final String stateCode;
  final String gstin;
  final String logoUrl;
  final String signatureLabel;

  factory CompanyProfile.empty() {
    return const CompanyProfile(
      id: 0,
      companyName: '',
      mobile: '',
      businessDescription: '',
      address: '',
      stateCode: '',
      gstin: '',
      logoUrl: '',
      signatureLabel: '',
    );
  }

  factory CompanyProfile.fromJson(Map<String, dynamic> json) {
    return CompanyProfile(
      id: json['id'] as int? ?? 0,
      companyName:
          json['companyName'] as String? ??
          json['company_name'] as String? ??
          '',
      mobile: json['mobile'] as String? ?? '',
      businessDescription:
          json['businessDescription'] as String? ??
          json['business_description'] as String? ??
          '',
      address: json['address'] as String? ?? '',
      stateCode:
          json['stateCode'] as String? ?? json['state_code'] as String? ?? '',
      gstin: json['gstin'] as String? ?? '',
      logoUrl:
          json['logoUrl'] as String? ??
          json['logo_url'] as String? ??
          json['logoPath'] as String? ??
          json['logo_path'] as String? ??
          '',
      signatureLabel:
          json['signatureLabel'] as String? ??
          json['signature_label'] as String? ??
          json['authorizedSignatoryName'] as String? ??
          json['authorized_signatory_name'] as String? ??
          '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'companyName': companyName,
      'mobile': mobile,
      'businessDescription': businessDescription,
      'address': address,
      'stateCode': stateCode,
      'gstin': gstin,
      'logoUrl': logoUrl,
      'signatureLabel': signatureLabel,
    };
  }
}

class DeliveryChallanItem {
  const DeliveryChallanItem({
    required this.id,
    required this.orderItemId,
    required this.productionRunId,
    required this.itemId,
    required this.variationLeafNodeId,
    required this.lineNo,
    required this.particulars,
    required this.hsnCode,
    required this.variationPathLabel,
    required this.quantityPcs,
    required this.weight,
  });

  final int id;
  final int? orderItemId;
  final int? productionRunId;
  final int? itemId;
  final int variationLeafNodeId;
  final int lineNo;
  final String particulars;
  final String hsnCode;
  final String variationPathLabel;
  final String quantityPcs;
  final String weight;

  factory DeliveryChallanItem.blank(int lineNo) {
    return DeliveryChallanItem(
      id: 0,
      orderItemId: null,
      productionRunId: null,
      itemId: null,
      variationLeafNodeId: 0,
      lineNo: lineNo,
      particulars: '',
      hsnCode: '',
      variationPathLabel: '',
      quantityPcs: '',
      weight: '',
    );
  }

  factory DeliveryChallanItem.fromJson(Map<String, dynamic> json) {
    return DeliveryChallanItem(
      id: json['id'] as int? ?? 0,
      orderItemId: json['orderItemId'] as int? ?? json['order_item_id'] as int?,
      productionRunId:
          json['productionRunId'] as int? ?? json['production_run_id'] as int?,
      itemId: json['itemId'] as int? ?? json['item_id'] as int?,
      variationLeafNodeId:
          json['variationLeafNodeId'] as int? ??
          json['variation_leaf_node_id'] as int? ??
          0,
      lineNo: json['lineNo'] as int? ?? json['line_no'] as int? ?? 0,
      particulars: json['particulars'] as String? ?? '',
      hsnCode: json['hsnCode'] as String? ?? json['hsn_code'] as String? ?? '',
      variationPathLabel:
          json['variationPathLabel'] as String? ??
          json['variation_path_label'] as String? ??
          '',
      quantityPcs:
          json['quantityPcs'] as String? ??
          json['quantity_pcs'] as String? ??
          '',
      weight: json['weight'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'line_no': lineNo,
      if (orderItemId != null) 'order_item_id': orderItemId,
      if (productionRunId != null) 'production_run_id': productionRunId,
      if (itemId != null) 'item_id': itemId,
      'variation_leaf_node_id': variationLeafNodeId,
      'particulars': particulars,
      'hsn_code': hsnCode,
      'variation_path_label': variationPathLabel,
      'quantity_pcs': quantityPcs,
      'weight': weight,
    };
  }
}

class CompletedProductionRun {
  const CompletedProductionRun({
    required this.id,
    required this.runCode,
    required this.status,
    required this.completedAt,
    required this.itemId,
    required this.itemName,
    required this.variationLeafNodeId,
    required this.variationPathLabel,
    required this.outputQuantity,
    required this.uom,
    required this.location,
  });

  final int id;
  final String runCode;
  final String status;
  final DateTime? completedAt;
  final int itemId;
  final String itemName;
  final int variationLeafNodeId;
  final String variationPathLabel;
  final double outputQuantity;
  final String uom;
  final String location;

  String get displayLabel {
    final variation = variationPathLabel.trim();
    return variation.isEmpty
        ? '$runCode - $itemName'
        : '$runCode - $itemName - $variation';
  }

  factory CompletedProductionRun.fromJson(Map<String, dynamic> json) {
    return CompletedProductionRun(
      id: json['id'] as int? ?? 0,
      runCode: json['runCode'] as String? ?? json['run_code'] as String? ?? '',
      status: json['status'] as String? ?? '',
      completedAt: DateTime.tryParse(
        json['completedAt'] as String? ?? json['completed_at'] as String? ?? '',
      ),
      itemId: json['itemId'] as int? ?? json['item_id'] as int? ?? 0,
      itemName:
          json['itemName'] as String? ?? json['item_name'] as String? ?? '',
      variationLeafNodeId:
          json['variationLeafNodeId'] as int? ??
          json['variation_leaf_node_id'] as int? ??
          0,
      variationPathLabel:
          json['variationPathLabel'] as String? ??
          json['variation_path_label'] as String? ??
          '',
      outputQuantity:
          (json['outputQuantity'] as num? ??
                  json['output_quantity'] as num? ??
                  0)
              .toDouble(),
      uom: json['uom'] as String? ?? 'pcs',
      location: json['location'] as String? ?? '',
    );
  }
}

class DeliveryChallan {
  const DeliveryChallan({
    required this.id,
    required this.type,
    required this.orderId,
    required this.orderIds,
    required this.clientId,
    required this.orderNo,
    required this.orderNos,
    required this.challanNo,
    required this.date,
    required this.location,
    required this.customerName,
    required this.customerGstin,
    required this.vendorId,
    required this.vendorName,
    required this.vendorGstin,
    required this.sourceReference,
    required this.companyProfileSnapshot,
    required this.notes,
    required this.status,
    required this.items,
    required this.itemsCount,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final ChallanType type;
  final int? orderId;
  final List<int> orderIds;
  final int? clientId;
  final String orderNo;
  final List<String> orderNos;
  final String challanNo;
  final DateTime date;
  final String location;
  final String customerName;
  final String customerGstin;
  final int? vendorId;
  final String vendorName;
  final String vendorGstin;
  final String sourceReference;
  final CompanyProfile? companyProfileSnapshot;
  final String notes;
  final DeliveryChallanStatus status;
  final List<DeliveryChallanItem> items;
  final int itemsCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isDraft => status == DeliveryChallanStatus.draft;
  bool get isIssued => status == DeliveryChallanStatus.issued;
  bool get isCancelled => status == DeliveryChallanStatus.cancelled;
  bool get isReception => type == ChallanType.reception;
  bool get isDelivery => type == ChallanType.delivery;

  factory DeliveryChallan.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? const [])
        .map(
          (item) => DeliveryChallanItem.fromJson(item as Map<String, dynamic>),
        )
        .toList(growable: false);
    final snapshot =
        json['companyProfileSnapshot'] ?? json['company_profile_snapshot'];
    return DeliveryChallan(
      id: json['id'] as int? ?? 0,
      type: challanTypeFromName(
        json['type'] as String? ??
            json['challan_type'] as String? ??
            'delivery',
      ),
      orderId: json['orderId'] as int? ?? json['order_id'] as int?,
      orderIds:
          (json['orderIds'] as List<dynamic>? ??
                  json['order_ids'] as List<dynamic>? ??
                  const <dynamic>[])
              .map((value) => value as int? ?? 0)
              .where((value) => value > 0)
              .toList(growable: false),
      clientId: json['clientId'] as int? ?? json['client_id'] as int?,
      orderNo: json['orderNo'] as String? ?? json['order_no'] as String? ?? '',
      orderNos:
          (json['orderNos'] as List<dynamic>? ??
                  json['order_nos'] as List<dynamic>? ??
                  const <dynamic>[])
              .map((value) => value.toString())
              .where((value) => value.trim().isNotEmpty)
              .toList(growable: false),
      challanNo:
          json['challanNo'] as String? ?? json['challan_no'] as String? ?? '',
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      location: json['location'] as String? ?? '',
      customerName:
          json['customerName'] as String? ??
          json['customer_name'] as String? ??
          '',
      customerGstin:
          json['customerGstin'] as String? ??
          json['customer_gstin'] as String? ??
          '',
      vendorId: json['vendorId'] as int? ?? json['vendor_id'] as int?,
      vendorName:
          json['vendorName'] as String? ?? json['vendor_name'] as String? ?? '',
      vendorGstin:
          json['vendorGstin'] as String? ??
          json['vendor_gstin'] as String? ??
          '',
      sourceReference:
          json['sourceReference'] as String? ??
          json['source_reference'] as String? ??
          '',
      companyProfileSnapshot: snapshot is Map<String, dynamic>
          ? CompanyProfile.fromJson(snapshot)
          : null,
      notes: json['notes'] as String? ?? '',
      status: deliveryChallanStatusFromName(json['status'] as String? ?? ''),
      items: items,
      itemsCount:
          json['itemsCount'] as int? ??
          json['items_count'] as int? ??
          items.length,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    );
  }

  DeliveryChallan copyWith({List<DeliveryChallanItem>? items}) {
    return DeliveryChallan(
      id: id,
      type: type,
      orderId: orderId,
      orderIds: orderIds,
      clientId: clientId,
      orderNo: orderNo,
      orderNos: orderNos,
      challanNo: challanNo,
      date: date,
      location: location,
      customerName: customerName,
      customerGstin: customerGstin,
      vendorId: vendorId,
      vendorName: vendorName,
      vendorGstin: vendorGstin,
      sourceReference: sourceReference,
      companyProfileSnapshot: companyProfileSnapshot,
      notes: notes,
      status: status,
      items: items ?? this.items,
      itemsCount: items?.length ?? itemsCount,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

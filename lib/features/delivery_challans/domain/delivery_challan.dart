enum DeliveryChallanStatus { draft, issued, cancelled }

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
    required this.itemId,
    required this.lineNo,
    required this.particulars,
    required this.hsnCode,
    required this.quantityPcs,
    required this.weight,
  });

  final int id;
  final int? orderItemId;
  final int? itemId;
  final int lineNo;
  final String particulars;
  final String hsnCode;
  final String quantityPcs;
  final String weight;

  factory DeliveryChallanItem.blank(int lineNo) {
    return DeliveryChallanItem(
      id: 0,
      orderItemId: null,
      itemId: null,
      lineNo: lineNo,
      particulars: '',
      hsnCode: '',
      quantityPcs: '',
      weight: '',
    );
  }

  factory DeliveryChallanItem.fromJson(Map<String, dynamic> json) {
    return DeliveryChallanItem(
      id: json['id'] as int? ?? 0,
      orderItemId: json['orderItemId'] as int? ?? json['order_item_id'] as int?,
      itemId: json['itemId'] as int? ?? json['item_id'] as int?,
      lineNo: json['lineNo'] as int? ?? json['line_no'] as int? ?? 0,
      particulars: json['particulars'] as String? ?? '',
      hsnCode: json['hsnCode'] as String? ?? json['hsn_code'] as String? ?? '',
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
      if (itemId != null) 'item_id': itemId,
      'particulars': particulars,
      'hsn_code': hsnCode,
      'quantity_pcs': quantityPcs,
      'weight': weight,
    };
  }
}

class DeliveryChallan {
  const DeliveryChallan({
    required this.id,
    required this.orderId,
    required this.orderNo,
    required this.challanNo,
    required this.date,
    required this.customerName,
    required this.customerGstin,
    required this.companyProfileSnapshot,
    required this.notes,
    required this.status,
    required this.items,
    required this.itemsCount,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int? orderId;
  final String orderNo;
  final String challanNo;
  final DateTime date;
  final String customerName;
  final String customerGstin;
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
      orderId: json['orderId'] as int? ?? json['order_id'] as int?,
      orderNo: json['orderNo'] as String? ?? json['order_no'] as String? ?? '',
      challanNo:
          json['challanNo'] as String? ?? json['challan_no'] as String? ?? '',
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      customerName:
          json['customerName'] as String? ??
          json['customer_name'] as String? ??
          '',
      customerGstin:
          json['customerGstin'] as String? ??
          json['customer_gstin'] as String? ??
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
      orderId: orderId,
      orderNo: orderNo,
      challanNo: challanNo,
      date: date,
      customerName: customerName,
      customerGstin: customerGstin,
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

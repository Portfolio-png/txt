class ReconciliationReportSnapshot {
  const ReconciliationReportSnapshot({
    required this.internalAuditor,
    required this.clientStatement,
    required this.misc,
    this.conversionOverrides = const <ConversionOverride>[],
    required this.generatedAt,
  });

  final List<InternalAuditorRow> internalAuditor;
  final List<ClientStatementRow> clientStatement;
  final List<WasteAuditRow> misc;
  final List<ConversionOverride> conversionOverrides;
  final DateTime? generatedAt;

  factory ReconciliationReportSnapshot.empty() {
    return const ReconciliationReportSnapshot(
      internalAuditor: <InternalAuditorRow>[],
      clientStatement: <ClientStatementRow>[],
      misc: <WasteAuditRow>[],
      conversionOverrides: <ConversionOverride>[],
      generatedAt: null,
    );
  }

  factory ReconciliationReportSnapshot.fromJson(Map<String, dynamic> json) {
    return ReconciliationReportSnapshot(
      internalAuditor: _asMapList(
        json['internalAuditor'] ??
            json['internal_auditor'] ??
            const <dynamic>[],
      ).map(InternalAuditorRow.fromJson).toList(growable: false),
      clientStatement: _asMapList(
        json['clientStatement'] ??
            json['client_statement'] ??
            const <dynamic>[],
      ).map(ClientStatementRow.fromJson).toList(growable: false),
      misc: _asMapList(
        json['misc'] ??
            json['wasteAudit'] ??
            json['waste_audit'] ??
            const <dynamic>[],
      ).map(WasteAuditRow.fromJson).toList(growable: false),
      conversionOverrides: _asMapList(
        json['conversionOverrides'] ??
            json['conversion_overrides'] ??
            const <dynamic>[],
      ).map(ConversionOverride.fromJson).toList(growable: false),
      generatedAt: _asDate(json['generatedAt'] ?? json['generated_at']),
    );
  }
}

class ClientStatementReport {
  const ClientStatementReport({
    required this.rows,
    required this.challanCount,
    required this.totalQuantityPcs,
    required this.totalWeight,
    required this.generatedAt,
  });

  final List<ClientStatementReportRow> rows;
  final int challanCount;
  final double totalQuantityPcs;
  final double totalWeight;
  final DateTime? generatedAt;

  factory ClientStatementReport.empty() {
    return const ClientStatementReport(
      rows: <ClientStatementReportRow>[],
      challanCount: 0,
      totalQuantityPcs: 0,
      totalWeight: 0,
      generatedAt: null,
    );
  }

  factory ClientStatementReport.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] is Map<String, dynamic>
        ? json['summary'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return ClientStatementReport(
      rows: _asMapList(
        json['rows'],
      ).map(ClientStatementReportRow.fromJson).toList(growable: false),
      challanCount: _asInt(summary['challanCount'] ?? summary['challan_count']),
      totalQuantityPcs: _asDouble(
        summary['totalQuantityPcs'] ?? summary['total_quantity_pcs'],
      ),
      totalWeight: _asDouble(summary['totalWeight'] ?? summary['total_weight']),
      generatedAt: _asDate(json['generatedAt'] ?? json['generated_at']),
    );
  }
}

class ClientStatementReportRow {
  const ClientStatementReportRow({
    required this.date,
    required this.challanNo,
    required this.clientName,
    required this.orderNo,
    required this.itemName,
    required this.note,
    required this.quantityPcs,
    required this.weight,
  });

  final DateTime? date;
  final String challanNo;
  final String clientName;
  final String orderNo;
  final String itemName;
  final String note;
  final double quantityPcs;
  final double weight;

  factory ClientStatementReportRow.fromJson(Map<String, dynamic> json) {
    return ClientStatementReportRow(
      date: _asDate(json['date']),
      challanNo: _asString(json['challanNo'] ?? json['challan_no']),
      clientName: _asString(json['clientName'] ?? json['client_name']),
      orderNo: _asString(json['orderNo'] ?? json['order_no']),
      itemName: _asString(json['itemName'] ?? json['item_name']),
      note: _asString(json['note']),
      quantityPcs: _asDouble(json['quantityPcs'] ?? json['quantity_pcs']),
      weight: _asDouble(json['weight']),
    );
  }
}

class InternalAuditorRow {
  const InternalAuditorRow({
    required this.challanId,
    required this.challanItemId,
    this.orderId,
    this.clientId,
    this.itemId,
    this.variationLeafNodeId = 0,
    required this.dcNumber,
    this.challanDate,
    required this.clientName,
    required this.itemName,
    required this.hsnCode,
    required this.totalDispatchedWeightKg,
    required this.convertedUnits,
    required this.invoicedQuantity,
    this.invoiceableQuantity = 0,
    this.unitPrice = 0,
    this.financialExposure = 0,
    required this.gstin,
    required this.cgst,
    required this.sgst,
    this.cgstRate = 0,
    this.sgstRate = 0,
    required this.wastePercentage,
    this.conversionRatio = 1,
    this.toUnitLabel = 'units',
    this.variancePercent = 0,
    required this.status,
    this.unlinkedReason = '',
    required this.isAttentionRequired,
    required this.isDirectPrint,
    required this.isUnbilled,
    this.invoiceLineIds = const <int>[],
    this.linkedInvoices = const <InvoiceReference>[],
  });

  final int challanId;
  final int challanItemId;
  final int? orderId;
  final int? clientId;
  final int? itemId;
  final int variationLeafNodeId;
  final String dcNumber;
  final DateTime? challanDate;
  final String clientName;
  final String itemName;
  final String hsnCode;
  final double totalDispatchedWeightKg;
  final double convertedUnits;
  final double invoicedQuantity;
  final double invoiceableQuantity;
  final double unitPrice;
  final double financialExposure;
  final String gstin;
  final double cgst;
  final double sgst;
  final double cgstRate;
  final double sgstRate;
  final double wastePercentage;
  final double conversionRatio;
  final String toUnitLabel;
  final double variancePercent;
  final String status;
  final String unlinkedReason;
  final bool isAttentionRequired;
  final bool isDirectPrint;
  final bool isUnbilled;
  final List<int> invoiceLineIds;
  final List<InvoiceReference> linkedInvoices;

  double get unbilledQuantity => invoiceableQuantity > 0
      ? invoiceableQuantity
      : (convertedUnits - invoicedQuantity).clamp(0.0, double.infinity);

  factory InternalAuditorRow.fromJson(Map<String, dynamic> json) {
    return InternalAuditorRow(
      challanId: _asInt(json['challanId'] ?? json['challan_id']),
      challanItemId: _asInt(json['challanItemId'] ?? json['challan_item_id']),
      orderId: _asNullableInt(json['orderId'] ?? json['order_id']),
      clientId: _asNullableInt(json['clientId'] ?? json['client_id']),
      itemId: _asNullableInt(json['itemId'] ?? json['item_id']),
      variationLeafNodeId: _asInt(
        json['variationLeafNodeId'] ?? json['variation_leaf_node_id'],
      ),
      dcNumber: _asString(json['dcNumber'] ?? json['dc_number']),
      challanDate: _asDate(json['challanDate'] ?? json['challan_date']),
      clientName: _asString(json['clientName'] ?? json['client_name']),
      itemName: _asString(json['itemName'] ?? json['item_name']),
      hsnCode: _asString(json['hsnCode'] ?? json['hsn_code']),
      totalDispatchedWeightKg: _asDouble(
        json['totalDispatchedWeightKg'] ?? json['total_dispatched_weight_kg'],
      ),
      convertedUnits: _asDouble(
        json['convertedUnits'] ?? json['converted_units'],
      ),
      invoicedQuantity: _asDouble(
        json['invoicedQuantity'] ?? json['invoiced_quantity'],
      ),
      invoiceableQuantity: _asDouble(
        json['invoiceableQuantity'] ?? json['invoiceable_quantity'],
      ),
      unitPrice: _asDouble(json['unitPrice'] ?? json['unit_price']),
      financialExposure: _asDouble(
        json['financialExposure'] ?? json['financial_exposure'],
      ),
      gstin: _asString(json['gstin']),
      cgst: _asDouble(json['cgst']),
      sgst: _asDouble(json['sgst']),
      cgstRate: _asDouble(json['cgstRate'] ?? json['cgst_rate']),
      sgstRate: _asDouble(json['sgstRate'] ?? json['sgst_rate']),
      wastePercentage: _asDouble(
        json['wastePercentage'] ?? json['waste_percentage'],
      ),
      conversionRatio: _asDouble(
        json['conversionRatio'] ?? json['conversion_ratio'],
        fallback: 1,
      ),
      toUnitLabel:
          _asString(json['toUnitLabel'] ?? json['to_unit_label']).isEmpty
          ? 'units'
          : _asString(json['toUnitLabel'] ?? json['to_unit_label']),
      variancePercent: _asDouble(
        json['variancePercent'] ?? json['variance_percent'],
      ),
      status: _asString(json['status']),
      unlinkedReason: _asString(
        json['unlinkedReason'] ?? json['unlinked_reason'],
      ),
      isAttentionRequired:
          json['isAttentionRequired'] == true ||
          json['is_attention_required'] == true,
      isDirectPrint:
          json['isDirectPrint'] == true || json['is_direct_print'] == true,
      isUnbilled: json['isUnbilled'] == true || json['is_unbilled'] == true,
      invoiceLineIds: _asList(
        json['invoiceLineIds'] ?? json['invoice_line_ids'],
      ).map(_asInt).where((id) => id > 0).toList(growable: false),
      linkedInvoices: _asMapList(
        json['linkedInvoices'] ?? json['linked_invoices'],
      ).map(InvoiceReference.fromJson).toList(growable: false),
    );
  }
}

class ClientStatementRow {
  const ClientStatementRow({
    this.clientId,
    this.itemId,
    this.variationLeafNodeId = 0,
    required this.clientName,
    required this.itemName,
    required this.materialReceivedInputKg,
    required this.totalFinishedUnitsDelivered,
    required this.netBalanceMaterialRemainingKg,
    required this.status,
  });

  final int? clientId;
  final int? itemId;
  final int variationLeafNodeId;
  final String clientName;
  final String itemName;
  final double materialReceivedInputKg;
  final double totalFinishedUnitsDelivered;
  final double netBalanceMaterialRemainingKg;
  final String status;

  factory ClientStatementRow.fromJson(Map<String, dynamic> json) {
    return ClientStatementRow(
      clientId: _asNullableInt(json['clientId'] ?? json['client_id']),
      itemId: _asNullableInt(json['itemId'] ?? json['item_id']),
      variationLeafNodeId: _asInt(
        json['variationLeafNodeId'] ?? json['variation_leaf_node_id'],
      ),
      clientName: _asString(json['clientName'] ?? json['client_name']),
      itemName: _asString(json['itemName'] ?? json['item_name']),
      materialReceivedInputKg: _asDouble(
        json['materialReceivedInputKg'] ?? json['material_received_input_kg'],
      ),
      totalFinishedUnitsDelivered: _asDouble(
        json['totalFinishedUnitsDelivered'] ??
            json['total_finished_units_delivered'],
      ),
      netBalanceMaterialRemainingKg: _asDouble(
        json['netBalanceMaterialRemainingKg'] ??
            json['net_balance_material_remaining_kg'],
      ),
      status: _asString(json['status']),
    );
  }
}

class WasteAuditRow {
  const WasteAuditRow({
    this.id = 0,
    required this.auditTime,
    this.clientId,
    this.itemId,
    this.variationLeafNodeId = 0,
    this.challanId,
    required this.clientName,
    required this.itemName,
    required this.challanNo,
    required this.inputWeightKg,
    required this.shippedWeightKg,
    required this.wasteWeightKg,
    required this.wastePercentage,
    required this.source,
  });

  final int id;
  final DateTime? auditTime;
  final int? clientId;
  final int? itemId;
  final int variationLeafNodeId;
  final int? challanId;
  final String clientName;
  final String itemName;
  final String challanNo;
  final double inputWeightKg;
  final double shippedWeightKg;
  final double wasteWeightKg;
  final double wastePercentage;
  final String source;

  factory WasteAuditRow.fromJson(Map<String, dynamic> json) {
    return WasteAuditRow(
      id: _asInt(json['id']),
      auditTime: _asDate(
        json['auditTime'] ?? json['audit_time'] ?? json['createdAt'],
      ),
      clientId: _asNullableInt(json['clientId'] ?? json['client_id']),
      itemId: _asNullableInt(json['itemId'] ?? json['item_id']),
      variationLeafNodeId: _asInt(
        json['variationLeafNodeId'] ?? json['variation_leaf_node_id'],
      ),
      challanId: _asNullableInt(json['challanId'] ?? json['challan_id']),
      clientName: _asString(json['clientName'] ?? json['client_name']),
      itemName: _asString(json['itemName'] ?? json['item_name']),
      challanNo: _asString(json['challanNo'] ?? json['challan_no']),
      inputWeightKg: _asDouble(
        json['inputWeightKg'] ?? json['input_weight_kg'],
      ),
      shippedWeightKg: _asDouble(
        json['shippedWeightKg'] ?? json['shipped_weight_kg'],
      ),
      wasteWeightKg: _asDouble(
        json['wasteWeightKg'] ?? json['waste_weight_kg'],
      ),
      wastePercentage: _asDouble(
        json['wastePercentage'] ?? json['waste_percentage'],
      ),
      source: _asString(json['source']),
    );
  }
}

class InvoiceReference {
  const InvoiceReference({
    required this.id,
    required this.invoiceNo,
    required this.status,
    required this.invoiceDate,
  });

  final int id;
  final String invoiceNo;
  final String status;
  final DateTime? invoiceDate;

  factory InvoiceReference.fromJson(Map<String, dynamic> json) {
    return InvoiceReference(
      id: _asInt(json['id'] ?? json['invoiceId'] ?? json['invoice_id']),
      invoiceNo: _asString(json['invoiceNo'] ?? json['invoice_no']),
      status: _asString(json['status']),
      invoiceDate: _asDate(json['invoiceDate'] ?? json['invoice_date']),
    );
  }
}

class InvoiceHeader {
  const InvoiceHeader({
    required this.id,
    required this.invoiceNo,
    required this.clientId,
    required this.clientName,
    required this.gstin,
    required this.status,
    required this.invoiceDate,
    required this.totalQuantity,
    required this.taxableValue,
    required this.cgstAmount,
    required this.sgstAmount,
    required this.totalAmount,
    required this.lines,
  });

  final int id;
  final String invoiceNo;
  final int? clientId;
  final String clientName;
  final String gstin;
  final String status;
  final DateTime? invoiceDate;
  final double totalQuantity;
  final double taxableValue;
  final double cgstAmount;
  final double sgstAmount;
  final double totalAmount;
  final List<InvoiceLine> lines;

  factory InvoiceHeader.fromJson(Map<String, dynamic> json) {
    return InvoiceHeader(
      id: _asInt(json['id']),
      invoiceNo: _asString(json['invoiceNo'] ?? json['invoice_no']),
      clientId: _asNullableInt(json['clientId'] ?? json['client_id']),
      clientName: _asString(json['clientName'] ?? json['client_name']),
      gstin: _asString(json['gstin']),
      status: _asString(json['status']),
      invoiceDate: _asDate(json['invoiceDate'] ?? json['invoice_date']),
      totalQuantity: _asDouble(json['totalQuantity'] ?? json['total_quantity']),
      taxableValue: _asDouble(json['taxableValue'] ?? json['taxable_value']),
      cgstAmount: _asDouble(json['cgstAmount'] ?? json['cgst_amount']),
      sgstAmount: _asDouble(json['sgstAmount'] ?? json['sgst_amount']),
      totalAmount: _asDouble(json['totalAmount'] ?? json['total_amount']),
      lines: _asMapList(
        json['lines'],
      ).map(InvoiceLine.fromJson).toList(growable: false),
    );
  }
}

class InvoiceLine {
  const InvoiceLine({
    required this.id,
    required this.invoiceId,
    required this.orderId,
    required this.challanId,
    required this.challanItemId,
    required this.itemId,
    required this.variationLeafNodeId,
    required this.itemName,
    required this.hsnCode,
    required this.quantity,
    required this.unitPrice,
    required this.taxableValue,
    required this.cgstRate,
    required this.sgstRate,
    required this.cgstAmount,
    required this.sgstAmount,
  });

  final int id;
  final int invoiceId;
  final int? orderId;
  final int? challanId;
  final int? challanItemId;
  final int? itemId;
  final int variationLeafNodeId;
  final String itemName;
  final String hsnCode;
  final double quantity;
  final double unitPrice;
  final double taxableValue;
  final double cgstRate;
  final double sgstRate;
  final double cgstAmount;
  final double sgstAmount;

  factory InvoiceLine.fromJson(Map<String, dynamic> json) {
    return InvoiceLine(
      id: _asInt(json['id']),
      invoiceId: _asInt(json['invoiceId'] ?? json['invoice_id']),
      orderId: _asNullableInt(json['orderId'] ?? json['order_id']),
      challanId: _asNullableInt(json['challanId'] ?? json['challan_id']),
      challanItemId: _asNullableInt(
        json['challanItemId'] ?? json['challan_item_id'],
      ),
      itemId: _asNullableInt(json['itemId'] ?? json['item_id']),
      variationLeafNodeId: _asInt(
        json['variationLeafNodeId'] ?? json['variation_leaf_node_id'],
      ),
      itemName: _asString(json['itemName'] ?? json['item_name']),
      hsnCode: _asString(json['hsnCode'] ?? json['hsn_code']),
      quantity: _asDouble(json['quantity']),
      unitPrice: _asDouble(json['unitPrice'] ?? json['unit_price']),
      taxableValue: _asDouble(json['taxableValue'] ?? json['taxable_value']),
      cgstRate: _asDouble(json['cgstRate'] ?? json['cgst_rate']),
      sgstRate: _asDouble(json['sgstRate'] ?? json['sgst_rate']),
      cgstAmount: _asDouble(json['cgstAmount'] ?? json['cgst_amount']),
      sgstAmount: _asDouble(json['sgstAmount'] ?? json['sgst_amount']),
    );
  }
}

class InvoiceDraftInput {
  const InvoiceDraftInput({
    required this.invoiceNo,
    required this.clientId,
    required this.clientName,
    required this.gstin,
    required this.invoiceDate,
    required this.lines,
  });

  final String invoiceNo;
  final int? clientId;
  final String clientName;
  final String gstin;
  final DateTime invoiceDate;
  final List<InvoiceDraftLineInput> lines;

  Map<String, dynamic> toJson() {
    return {
      if (invoiceNo.trim().isNotEmpty) 'invoiceNo': invoiceNo.trim(),
      if (clientId != null && clientId! > 0) 'clientId': clientId,
      'clientName': clientName.trim(),
      'gstin': gstin.trim(),
      'status': 'draft',
      'invoiceDate': invoiceDate.toIso8601String().substring(0, 10),
      'lines': lines.map((line) => line.toJson()).toList(growable: false),
    };
  }
}

class InvoiceDraftLineInput {
  const InvoiceDraftLineInput({
    required this.orderId,
    required this.challanId,
    required this.challanItemId,
    required this.itemId,
    required this.variationLeafNodeId,
    required this.itemName,
    required this.hsnCode,
    required this.quantity,
    required this.unitPrice,
    required this.cgstRate,
    required this.sgstRate,
  });

  final int? orderId;
  final int? challanId;
  final int? challanItemId;
  final int? itemId;
  final int variationLeafNodeId;
  final String itemName;
  final String hsnCode;
  final double quantity;
  final double unitPrice;
  final double cgstRate;
  final double sgstRate;

  Map<String, dynamic> toJson() {
    return {
      if (orderId != null && orderId! > 0) 'orderId': orderId,
      if (challanId != null && challanId! > 0) 'challanId': challanId,
      if (challanItemId != null && challanItemId! > 0)
        'challanItemId': challanItemId,
      if (itemId != null && itemId! > 0) 'itemId': itemId,
      'variationLeafNodeId': variationLeafNodeId,
      'itemName': itemName.trim(),
      'hsnCode': hsnCode.trim(),
      'quantity': quantity,
      'unitPrice': unitPrice,
      'cgstRate': cgstRate,
      'sgstRate': sgstRate,
    };
  }
}

class ConversionOverride {
  const ConversionOverride({
    required this.id,
    required this.itemId,
    required this.variationLeafNodeId,
    required this.conversionRatio,
    required this.fromUnit,
    required this.toUnitLabel,
    required this.updatedAt,
  });

  final int id;
  final int itemId;
  final int variationLeafNodeId;
  final double conversionRatio;
  final String fromUnit;
  final String toUnitLabel;
  final DateTime? updatedAt;

  factory ConversionOverride.fromJson(Map<String, dynamic> json) {
    return ConversionOverride(
      id: _asInt(json['id']),
      itemId: _asInt(json['itemId'] ?? json['item_id']),
      variationLeafNodeId: _asInt(
        json['variationLeafNodeId'] ?? json['variation_leaf_node_id'],
      ),
      conversionRatio: _asDouble(
        json['conversionRatio'] ?? json['conversion_ratio'],
        fallback: 1,
      ),
      fromUnit: _asString(json['fromUnit'] ?? json['from_unit']).isEmpty
          ? 'kg'
          : _asString(json['fromUnit'] ?? json['from_unit']),
      toUnitLabel:
          _asString(json['toUnitLabel'] ?? json['to_unit_label']).isEmpty
          ? 'units'
          : _asString(json['toUnitLabel'] ?? json['to_unit_label']),
      updatedAt: _asDate(json['updatedAt'] ?? json['updated_at']),
    );
  }
}

class ConversionOverrideInput {
  const ConversionOverrideInput({
    required this.itemId,
    required this.variationLeafNodeId,
    required this.conversionRatio,
    required this.toUnitLabel,
  });

  final int itemId;
  final int variationLeafNodeId;
  final double conversionRatio;
  final String toUnitLabel;

  Map<String, dynamic> toJson() {
    return {
      'itemId': itemId,
      'variationLeafNodeId': variationLeafNodeId,
      'conversionRatio': conversionRatio,
      'fromUnit': 'kg',
      'toUnitLabel': toUnitLabel.trim().isEmpty ? 'units' : toUnitLabel.trim(),
    };
  }
}

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _asNullableInt(Object? value) {
  final parsed = _asInt(value);
  return parsed > 0 ? parsed : null;
}

double _asDouble(Object? value, {double fallback = 0}) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

String _asString(Object? value) => value?.toString() ?? '';

DateTime? _asDate(Object? value) {
  final raw = value?.toString();
  return raw == null || raw.trim().isEmpty ? null : DateTime.tryParse(raw);
}

List<dynamic> _asList(Object? value) {
  return value is List ? value : const <dynamic>[];
}

List<Map<String, dynamic>> _asMapList(Object? value) {
  return _asList(
    value,
  ).whereType<Map<String, dynamic>>().toList(growable: false);
}

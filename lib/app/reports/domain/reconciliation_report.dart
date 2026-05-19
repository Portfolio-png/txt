class ReconciliationReportSnapshot {
  const ReconciliationReportSnapshot({
    required this.internalAuditor,
    required this.clientStatement,
    required this.misc,
    required this.generatedAt,
  });

  final List<InternalAuditorRow> internalAuditor;
  final List<ClientStatementRow> clientStatement;
  final List<WasteAuditRow> misc;
  final DateTime? generatedAt;

  factory ReconciliationReportSnapshot.empty() {
    return const ReconciliationReportSnapshot(
      internalAuditor: <InternalAuditorRow>[],
      clientStatement: <ClientStatementRow>[],
      misc: <WasteAuditRow>[],
      generatedAt: null,
    );
  }

  factory ReconciliationReportSnapshot.fromJson(Map<String, dynamic> json) {
    return ReconciliationReportSnapshot(
      internalAuditor:
          (json['internalAuditor'] as List<dynamic>? ??
                  json['internal_auditor'] as List<dynamic>? ??
                  const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(InternalAuditorRow.fromJson)
              .toList(growable: false),
      clientStatement:
          (json['clientStatement'] as List<dynamic>? ??
                  json['client_statement'] as List<dynamic>? ??
                  const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(ClientStatementRow.fromJson)
              .toList(growable: false),
      misc:
          (json['misc'] as List<dynamic>? ??
                  json['wasteAudit'] as List<dynamic>? ??
                  json['waste_audit'] as List<dynamic>? ??
                  const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(WasteAuditRow.fromJson)
              .toList(growable: false),
      generatedAt: DateTime.tryParse(json['generatedAt']?.toString() ?? ''),
    );
  }
}

class InternalAuditorRow {
  const InternalAuditorRow({
    required this.challanId,
    required this.challanItemId,
    required this.dcNumber,
    required this.clientName,
    required this.itemName,
    required this.hsnCode,
    required this.totalDispatchedWeightKg,
    required this.convertedUnits,
    required this.invoicedQuantity,
    required this.gstin,
    required this.cgst,
    required this.sgst,
    required this.wastePercentage,
    required this.status,
    required this.isAttentionRequired,
    required this.isDirectPrint,
    required this.isUnbilled,
  });

  final int challanId;
  final int challanItemId;
  final String dcNumber;
  final String clientName;
  final String itemName;
  final String hsnCode;
  final double totalDispatchedWeightKg;
  final double convertedUnits;
  final double invoicedQuantity;
  final String gstin;
  final double cgst;
  final double sgst;
  final double wastePercentage;
  final String status;
  final bool isAttentionRequired;
  final bool isDirectPrint;
  final bool isUnbilled;

  double get unbilledQuantity => (convertedUnits - invoicedQuantity)
      .clamp(0.0, double.infinity)
      .toDouble();

  factory InternalAuditorRow.fromJson(Map<String, dynamic> json) {
    return InternalAuditorRow(
      challanId: _asInt(json['challanId'] ?? json['challan_id']),
      challanItemId: _asInt(json['challanItemId'] ?? json['challan_item_id']),
      dcNumber: (json['dcNumber'] ?? json['dc_number'] ?? '').toString(),
      clientName: (json['clientName'] ?? json['client_name'] ?? '').toString(),
      itemName: (json['itemName'] ?? json['item_name'] ?? '').toString(),
      hsnCode: (json['hsnCode'] ?? json['hsn_code'] ?? '').toString(),
      totalDispatchedWeightKg: _asDouble(
        json['totalDispatchedWeightKg'] ?? json['total_dispatched_weight_kg'],
      ),
      convertedUnits: _asDouble(
        json['convertedUnits'] ?? json['converted_units'],
      ),
      invoicedQuantity: _asDouble(
        json['invoicedQuantity'] ?? json['invoiced_quantity'],
      ),
      gstin: (json['gstin'] ?? '').toString(),
      cgst: _asDouble(json['cgst']),
      sgst: _asDouble(json['sgst']),
      wastePercentage: _asDouble(
        json['wastePercentage'] ?? json['waste_percentage'],
      ),
      status: (json['status'] ?? '').toString(),
      isAttentionRequired:
          json['isAttentionRequired'] == true ||
          json['is_attention_required'] == true,
      isDirectPrint:
          json['isDirectPrint'] == true || json['is_direct_print'] == true,
      isUnbilled: json['isUnbilled'] == true || json['is_unbilled'] == true,
    );
  }
}

class ClientStatementRow {
  const ClientStatementRow({
    required this.clientName,
    required this.itemName,
    required this.materialReceivedInputKg,
    required this.totalFinishedUnitsDelivered,
    required this.netBalanceMaterialRemainingKg,
    required this.status,
  });

  final String clientName;
  final String itemName;
  final double materialReceivedInputKg;
  final double totalFinishedUnitsDelivered;
  final double netBalanceMaterialRemainingKg;
  final String status;

  factory ClientStatementRow.fromJson(Map<String, dynamic> json) {
    return ClientStatementRow(
      clientName: (json['clientName'] ?? json['client_name'] ?? '').toString(),
      itemName: (json['itemName'] ?? json['item_name'] ?? '').toString(),
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
      status: (json['status'] ?? '').toString(),
    );
  }
}

class WasteAuditRow {
  const WasteAuditRow({
    required this.auditTime,
    required this.clientName,
    required this.itemName,
    required this.challanNo,
    required this.inputWeightKg,
    required this.shippedWeightKg,
    required this.wasteWeightKg,
    required this.wastePercentage,
    required this.source,
  });

  final DateTime? auditTime;
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
      auditTime: DateTime.tryParse(
        (json['auditTime'] ?? json['audit_time'] ?? json['createdAt'] ?? '')
            .toString(),
      ),
      clientName: (json['clientName'] ?? json['client_name'] ?? '').toString(),
      itemName: (json['itemName'] ?? json['item_name'] ?? '').toString(),
      challanNo: (json['challanNo'] ?? json['challan_no'] ?? '').toString(),
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
      source: (json['source'] ?? '').toString(),
    );
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

double _asDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

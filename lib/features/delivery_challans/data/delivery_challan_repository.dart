import 'dart:typed_data';

import '../../../app/reports/domain/reconciliation_report.dart';
import '../domain/delivery_challan.dart';
import '../domain/challan_template.dart';

abstract class ChallanRepository {
  String? get lastWarningMessage;

  Future<void> init();

  Future<CompanyProfile> getCompanyProfile();

  Future<CompanyProfile> updateCompanyProfile(CompanyProfile profile);

  Future<List<DeliveryChallan>> getChallans({
    ChallanType? type,
    DeliveryChallanStatus? status,
    String search = '',
    DateTime? dateFrom,
    DateTime? dateTo,
    int? orderId,
  });

  Future<List<DeliveryChallan>> getOrderChallans(int orderId);

  Future<DeliveryChallan> getChallan(int id);

  Future<DeliveryChallan> createChallan(DeliveryChallanDraftInput input);

  Future<DeliveryChallan> updateChallan(
    int id,
    DeliveryChallanDraftInput input,
  );

  Future<DeliveryChallan> issueChallan(int id);

  Future<DeliveryChallan> cancelChallan(int id);

  Future<void> deleteChallan(int id);

  Future<void> recordPrint(int id);

  Future<DeliveryChallan> updateChallanReportGroups(
    int id,
    List<String> reportGroupCodes,
  );

  Future<ReconciliationReportSnapshot> getReconciliationReport();

  Future<List<InvoiceHeader>> getInvoices();

  Future<InvoiceHeader> getInvoice(int id);

  Future<InvoiceHeader> updateInvoiceStatus(int id, String status);

  Future<InvoiceHeader> createInvoice(InvoiceDraftInput input);

  Future<Uint8List> fetchInvoicePdf(int invoiceId);

  Future<List<ConversionOverride>> getConversionOverrides();

  Future<ConversionOverride> saveConversionOverride(
    ConversionOverrideInput input,
  );

  Future<List<WasteAuditRow>> getWasteAuditRows();

  Future<ClientStatementReport> generateClientStatementReport({
    required String reportGroupCode,
    required List<String> challanNos,
    required List<String> receptionChallanNos,
  });

  Future<List<CompletedProductionRun>> getCompletedProductionRuns({
    String search = '',
    int limit = 25,
  });

  Future<List<ChallanTemplate>> getTemplates({
    ChallanTemplatePartyType? partyType,
    int? partyId,
    ChallanType? challanType,
    bool activeOnly = false,
  });

  Future<List<ChallanTemplateScan>> getTemplateScans({int limit = 24});

  Future<ChallanTemplate> createTemplate(ChallanTemplateInput input);

  Future<ChallanTemplate> updateTemplate(int id, ChallanTemplateInput input);

  Future<void> deleteTemplate(int id);

  Future<ChallanTemplateUploadTarget> createTemplateUploadIntent(
    ChallanTemplateUploadIntentInput input,
  );

  Future<ChallanTemplateBackground> completeTemplateUpload({
    required String uploadSessionId,
    required String objectKey,
  });

  Future<ChallanTemplateUploadTarget> createTemplateStampUploadIntent(
    ChallanTemplateUploadIntentInput input,
  );

  Future<ChallanTemplateBackground> completeTemplateStampUpload({
    required String uploadSessionId,
    required String objectKey,
  });

  Uri templatePreviewUri({
    required int challanId,
    int? templateId,
    required String mode,
  });

  Future<Uint8List> fetchTemplatePreviewPdf({
    required int challanId,
    int? templateId,
    required String mode,
  });

  Uri templateTestPrintUri({
    required int templateId,
    required String mode,
    int? itemCount,
  });

  Future<Uint8List> fetchTemplateTestPrintPdf({
    required int templateId,
    required String mode,
    int? itemCount,
    List<ChallanTemplateMapping>? mappings,
  });
}

typedef DeliveryChallanRepository = ChallanRepository;

class ChallanDraftInput {
  const ChallanDraftInput({
    required this.type,
    required this.challanNo,
    required this.orderId,
    required this.orderIds,
    this.reportGroupCodes = const <String>[],
    required this.vendorId,
    required this.date,
    required this.location,
    required this.sourceReference,
    required this.notes,
    required this.maintainStocks,
    required this.customerName,
    required this.customerGstin,
    required this.vendorName,
    required this.vendorGstin,
    required this.items,
  });

  final ChallanType type;
  final String challanNo;
  final int orderId;
  final List<int> orderIds;
  final List<String> reportGroupCodes;
  final int vendorId;
  final DateTime date;
  final String location;
  final String sourceReference;
  final String notes;
  final bool maintainStocks;
  final String customerName;
  final String customerGstin;
  final String vendorName;
  final String vendorGstin;
  final List<DeliveryChallanItem> items;

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'challan_no': challanNo.trim(),
      if (orderId > 0) 'order_id': orderId,
      if (orderIds.isNotEmpty) 'order_ids': orderIds,
      if (reportGroupCodes.isNotEmpty)
        'report_group_codes': reportGroupCodes
            .map((code) => code.trim())
            .where((code) => code.isNotEmpty)
            .toList(growable: false),
      if (vendorId > 0) 'vendor_id': vendorId,
      'date': date.toIso8601String().substring(0, 10),
      'location': location.trim(),
      'source_reference': sourceReference.trim(),
      'notes': notes.trim(),
      'maintain_stocks': maintainStocks,
      'customer_name': customerName.trim(),
      'customer_gstin': customerGstin.trim(),
      'vendor_name': vendorName.trim(),
      'vendor_gstin': vendorGstin.trim(),
      'items': items
          .map(
            (item) => {
              if (item.orderItemId != null) 'order_item_id': item.orderItemId,
              if (item.productionRunId != null)
                'production_run_id': item.productionRunId,
              if (item.itemId != null) 'item_id': item.itemId,
              'variation_leaf_node_id': item.variationLeafNodeId,
              'particulars': item.particulars,
              'hsn_code': item.hsnCode,
              'variation_path_label': item.variationPathLabel,
              'note': item.note.trim(),
              'quantity_pcs': item.quantityPcs.trim(),
              'weight': item.weight.trim(),
            },
          )
          .toList(growable: false),
    };
  }
}

typedef DeliveryChallanDraftInput = ChallanDraftInput;

class ChallanApiException implements Exception {
  const ChallanApiException(this.message, {this.debugMessage});

  final String message;
  final String? debugMessage;

  @override
  String toString() => message;
}

typedef DeliveryChallanApiException = ChallanApiException;

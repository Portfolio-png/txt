import 'dart:typed_data';

import 'package:core_erp/features/delivery_challans/domain/models/cancel_challan_options.dart';
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
    int? itemId,
    int? variationLeafNodeId,
    bool mineOnly = false,
  });

  Future<List<DeliveryChallan>> getOrderChallans(int orderId);

  Future<DeliveryChallan> getChallan(int id);

  Future<DeliveryChallan> createChallan(DeliveryChallanDraftInput input);

  Future<DeliveryChallan> updateChallan(
    int id,
    DeliveryChallanDraftInput input,
  );

  Future<DeliveryChallan> issueChallan(int id);

  /// Settles an internal-use challan: each consumed line's quantity is split
  /// across scrap/leftover/lost/rejection/finished-goods, reverted back into
  /// inventory under the Primary Group's sub-groups, and the challan (and, once
  /// all of an order's use challans are reconciled, the order) is completed.
  Future<DeliveryChallan> reconcileChallan(int id, ChallanReconcileInput input);

  Future<DeliveryChallan> cancelChallan(int id, {String? actionType});
  Future<CancelChallanOptions> getCancelOptions(int id);

  Future<void> deleteChallan(int id);

  Future<void> recordPrint(int id);

  /// Persists the piece/sheet barcodes generated on the mobile wizard's Done
  /// step (after the challan already exists). Each map carries `challanItemId`,
  /// `parentCode`, `childCode`, and `weight`. Idempotent — re-sending replaces
  /// the barcodes for the referenced items. Returns the refreshed challan.
  Future<DeliveryChallan> savePieceBarcodes(
    int challanId,
    List<Map<String, dynamic>> barcodes,
  );

  /// Resolves a scanned sheet tag (`parent_code`/`child_code`) to its origin —
  /// item, weight, vendor and returned status — via `/api/barcode/lookup`.
  /// Returns null when the code is not a known sheet.
  Future<Map<String, dynamic>?> lookupSheetBarcode(String code);

  Future<DeliveryChallan> updateChallanReportGroups(
    int id,
    List<String> reportGroupCodes,
  );

  Future<ReconciliationReportSnapshot> getReconciliationReport();

  Future<List<InvoiceHeader>> getInvoices();

  Future<InvoiceHeader> getInvoice(int id);

  Future<InvoiceHeader> updateInvoiceStatus(int id, String status);

  Future<InvoiceHeader> createInvoice(InvoiceDraftInput input);

  Future<InvoiceHeader> updateInvoice(int id, InvoiceDraftInput input);

  Future<void> deleteInvoice(int id);

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
    this.purpose = ChallanPurpose.trading,
    this.internalPurpose = '',
    this.internalSubtype = '',
    this.returnedSheetCodes = const <String>[],
    required this.challanNo,
    required this.orderId,
    required this.orderIds,
    this.orderNo = '',
    this.reportGroupCodes = const <String>[],
    required this.vendorId,
    this.materialOwnerClientId,
    required this.date,
    required this.location,
    required this.sourceReference,
    this.poNumber = '',
    this.poDate,
    required this.notes,
    required this.maintainStocks,
    required this.customerName,
    required this.customerGstin,
    required this.vendorName,
    required this.vendorGstin,
    required this.items,
    this.genericAssets = const [],
  });

  final ChallanType type;
  final ChallanPurpose purpose;

  /// Free-text purpose for internal challans; ignored for delivery/reception.
  final String internalPurpose;

  /// Structured internal subtype (e.g. 'vendor_return'); ignored otherwise.
  final String internalSubtype;

  /// Scanned sheet tag codes a vendor-return challan flags returned on issue.
  final List<String> returnedSheetCodes;
  final String challanNo;
  final int orderId;
  final List<int> orderIds;

  /// Optional client order this (reception/procurement) challan was made for —
  /// Scenario B on-demand procurement ties the incoming sheets to an order.
  final String orderNo;
  final List<String> reportGroupCodes;
  final int vendorId;
  final int? materialOwnerClientId;
  final DateTime date;
  final String location;
  final String sourceReference;
  final String poNumber;
  final DateTime? poDate;
  final String notes;
  final bool maintainStocks;
  final String customerName;
  final String customerGstin;
  final String vendorName;
  final String vendorGstin;
  final List<DeliveryChallanItem> items;
  final List<Map<String, dynamic>> genericAssets;

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'purpose': purpose.name,
      if (internalPurpose.trim().isNotEmpty)
        'internal_purpose': internalPurpose.trim(),
      if (internalSubtype.trim().isNotEmpty)
        'internal_subtype': internalSubtype.trim(),
      if (returnedSheetCodes.isNotEmpty)
        'returned_sheet_codes': returnedSheetCodes
            .map((c) => c.trim())
            .where((c) => c.isNotEmpty)
            .toList(growable: false),
      'challan_no': challanNo.trim(),
      if (orderId > 0) 'order_id': orderId,
      if (orderIds.isNotEmpty) 'order_ids': orderIds,
      if (orderNo.trim().isNotEmpty) 'order_no': orderNo.trim(),
      if (reportGroupCodes.isNotEmpty)
        'report_group_codes': reportGroupCodes
            .map((code) => code.trim())
            .where((code) => code.isNotEmpty)
            .toList(growable: false),
      if (vendorId > 0) 'vendor_id': vendorId,
      if (materialOwnerClientId != null && materialOwnerClientId! > 0)
        'material_owner_client_id': materialOwnerClientId,
      'date': date.toIso8601String().substring(0, 10),
      'location': location.trim(),
      'source_reference': sourceReference.trim(),
      if (poNumber.trim().isNotEmpty) 'po_number': poNumber.trim(),
      if (poDate != null) 'po_date': poDate!.toIso8601String().substring(0, 10),
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
              'variation_path_node_ids': item.variationPathNodeIds,
              'customVariationValues': item.customVariationValues.map(
                (key, value) => MapEntry(key.toString(), value),
              ),
              'note': item.note.trim(),
              'quantity_pcs': item.quantityPcs.trim(),
              'weight': item.weight.trim(),
              if (item.sheetWeights.isNotEmpty)
                'sheet_weights': item.sheetWeights,
            },
          )
          .toList(growable: false),
      if (genericAssets.isNotEmpty) 'genericAssets': genericAssets,
    };
  }
}

typedef DeliveryChallanDraftInput = ChallanDraftInput;

/// One challan line's five-bucket settlement. The five amounts must sum to the
/// line's consumed quantity (the backend rejects the reconcile otherwise).
class ChallanReconcileLineInput {
  const ChallanReconcileLineInput({
    required this.challanItemId,
    this.scrap = 0,
    this.leftover = 0,
    this.lost = 0,
    this.rejection = 0,
    this.finishedGoods = 0,
  });

  /// The `delivery_challan_items.id` (DeliveryChallanItem.id) this settles.
  final int challanItemId;
  final double scrap;
  final double leftover;
  final double lost;
  final double rejection;
  final double finishedGoods;

  double get total => scrap + leftover + lost + rejection + finishedGoods;

  Map<String, dynamic> toJson() => {
    'challanItemId': challanItemId,
    'buckets': {
      'scrap': scrap,
      'leftover': leftover,
      'lost': lost,
      'rejection': rejection,
      'finishedGoods': finishedGoods,
    },
  };
}

/// Payload for [ChallanRepository.reconcileChallan]: one entry per challan line.
class ChallanReconcileInput {
  const ChallanReconcileInput({required this.lines});

  final List<ChallanReconcileLineInput> lines;

  Map<String, dynamic> toJson() => {
    'lines': lines.map((line) => line.toJson()).toList(growable: false),
  };
}

class ChallanApiException implements Exception {
  const ChallanApiException(this.message, {this.debugMessage});

  final String message;
  final String? debugMessage;

  @override
  String toString() => message;
}

typedef DeliveryChallanApiException = ChallanApiException;

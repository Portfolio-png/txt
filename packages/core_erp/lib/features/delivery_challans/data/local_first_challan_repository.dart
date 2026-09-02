import 'dart:typed_data';

import 'package:core_erp/features/delivery_challans/domain/models/cancel_challan_options.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../app/reports/domain/reconciliation_report.dart';
import '../../../core/sync/replica_reader.dart';
import '../domain/challan_template.dart';
import '../domain/delivery_challan.dart';
import 'delivery_challan_repository.dart';

/// Serves the challan list from the local replica.
///
/// The list only, and that limit is the interesting part. Two things make the
/// rest of this interface unservable locally, and both would be silent:
///
/// **The replica holds the SUMMARY shape.** `/api/challans` stops sending the
/// nested `items` array — it sends `lineCount`, `totalQty` and `totalWeight`
/// instead — so a challan read back from the replica has no lines. Answering
/// `getChallan(id)` from it would hand the editor and the printable document an
/// empty challan, which is exactly the regression the detail-hydration work
/// fixed on the client side. Detail always goes to the server.
///
/// **Several filters cannot be answered from a mirror of the list.** `mineOnly`
/// resolves server-side to `dc.created_by = req.user.id`, and filtering by item
/// or variation is a line-level EXISTS over `delivery_challan_items` — rows the
/// replica does not hold. A narrowed request goes to the server rather than
/// being approximated.
class LocalFirstChallanRepository implements ChallanRepository {
  LocalFirstChallanRepository({
    required ChallanRepository remote,
    required Future<Database?> Function() replica,
    required bool Function() isHydrated,
  }) : _remote = remote,
       _reader = ReplicaReader(replica: replica, isHydrated: isHydrated);

  final ChallanRepository _remote;
  final ReplicaReader _reader;

  @override
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
  }) async {
    final narrowed = type != null ||
        status != null ||
        search.trim().isNotEmpty ||
        dateFrom != null ||
        dateTo != null ||
        orderId != null ||
        itemId != null ||
        variationLeafNodeId != null ||
        mineOnly;
    if (narrowed) {
      return _remote.getChallans(
        type: type,
        status: status,
        search: search,
        dateFrom: dateFrom,
        dateTo: dateTo,
        orderId: orderId,
        itemId: itemId,
        variationLeafNodeId: variationLeafNodeId,
        mineOnly: mineOnly,
      );
    }

    // `ORDER BY date(dc.date) DESC, dc.id DESC` — the id is the tiebreaker, and
    // challans routinely share a date.
    final local = await _reader.readAll<DeliveryChallan>(
      'local_delivery_challans',
      orderBy: 'date(challan_date) DESC, id DESC',
      fromJson: DeliveryChallan.fromJson,
    );
    return local ?? _remote.getChallans();
  }

  @override
  String? get lastWarningMessage => _remote.lastWarningMessage;

  @override
  Future<void> init() => _remote.init();

  @override
  Future<CompanyProfile> getCompanyProfile() => _remote.getCompanyProfile();

  @override
  Future<CompanyProfile> updateCompanyProfile(CompanyProfile profile) => _remote.updateCompanyProfile(profile);

  @override
  Future<List<DeliveryChallan>> getOrderChallans(int orderId) => _remote.getOrderChallans(orderId);

  @override
  Future<DeliveryChallan> getChallan(int id) => _remote.getChallan(id);

  @override
  Future<DeliveryChallan> createChallan(DeliveryChallanDraftInput input) => _remote.createChallan(input);

  @override
  Future<DeliveryChallan> updateChallan(
    int id,
    DeliveryChallanDraftInput input,
  ) => _remote.updateChallan(id, input);

  @override
  Future<DeliveryChallan> issueChallan(int id) => _remote.issueChallan(id);

  @override
  Future<DeliveryChallan> reconcileChallan(int id, ChallanReconcileInput input) => _remote.reconcileChallan(id, input);

  @override
  Future<DeliveryChallan> cancelChallan(int id, {String? actionType}) => _remote.cancelChallan(id, actionType: actionType);

  @override
  Future<CancelChallanOptions> getCancelOptions(int id) => _remote.getCancelOptions(id);

  @override
  Future<void> deleteChallan(int id) => _remote.deleteChallan(id);

  @override
  Future<void> recordPrint(int id) => _remote.recordPrint(id);

  @override
  Future<DeliveryChallan> savePieceBarcodes(
    int challanId,
    List<Map<String, dynamic>> barcodes,
  ) => _remote.savePieceBarcodes(challanId, barcodes);

  @override
  Future<Map<String, dynamic>?> lookupSheetBarcode(String code) => _remote.lookupSheetBarcode(code);

  @override
  Future<DeliveryChallan> updateChallanReportGroups(
    int id,
    List<String> reportGroupCodes,
  ) => _remote.updateChallanReportGroups(id, reportGroupCodes);

  @override
  Future<ReconciliationReportSnapshot> getReconciliationReport() => _remote.getReconciliationReport();

  @override
  Future<List<InvoiceHeader>> getInvoices() => _remote.getInvoices();

  @override
  Future<InvoiceHeader> getInvoice(int id) => _remote.getInvoice(id);

  @override
  Future<InvoiceHeader> updateInvoiceStatus(int id, String status) => _remote.updateInvoiceStatus(id, status);

  @override
  Future<InvoiceHeader> createInvoice(InvoiceDraftInput input) => _remote.createInvoice(input);

  @override
  Future<InvoiceHeader> updateInvoice(int id, InvoiceDraftInput input) => _remote.updateInvoice(id, input);

  @override
  Future<void> deleteInvoice(int id) => _remote.deleteInvoice(id);

  @override
  Future<Uint8List> fetchInvoicePdf(int invoiceId) => _remote.fetchInvoicePdf(invoiceId);

  @override
  Future<List<ConversionOverride>> getConversionOverrides() => _remote.getConversionOverrides();

  @override
  Future<ConversionOverride> saveConversionOverride(
    ConversionOverrideInput input,
  ) => _remote.saveConversionOverride(input);

  @override
  Future<List<WasteAuditRow>> getWasteAuditRows() => _remote.getWasteAuditRows();

  @override
  Future<ClientStatementReport> generateClientStatementReport({
    required String reportGroupCode,
    required List<String> challanNos,
    required List<String> receptionChallanNos,
  }) => _remote.generateClientStatementReport(reportGroupCode: reportGroupCode, challanNos: challanNos, receptionChallanNos: receptionChallanNos);

  @override
  Future<List<CompletedProductionRun>> getCompletedProductionRuns({
    String search = '',
    int limit = 25,
  }) => _remote.getCompletedProductionRuns(search: search, limit: limit);

  @override
  Future<List<ChallanTemplate>> getTemplates({
    ChallanTemplatePartyType? partyType,
    int? partyId,
    ChallanType? challanType,
    bool activeOnly = false,
  }) => _remote.getTemplates(partyType: partyType, partyId: partyId, challanType: challanType, activeOnly: activeOnly);

  @override
  Future<List<ChallanTemplateScan>> getTemplateScans({int limit = 24}) => _remote.getTemplateScans(limit: limit);

  @override
  Future<ChallanTemplate> createTemplate(ChallanTemplateInput input) => _remote.createTemplate(input);

  @override
  Future<ChallanTemplate> updateTemplate(int id, ChallanTemplateInput input) => _remote.updateTemplate(id, input);

  @override
  Future<void> deleteTemplate(int id) => _remote.deleteTemplate(id);

  @override
  Future<ChallanTemplateUploadTarget> createTemplateUploadIntent(
    ChallanTemplateUploadIntentInput input,
  ) => _remote.createTemplateUploadIntent(input);

  @override
  Future<ChallanTemplateBackground> completeTemplateUpload({
    required String uploadSessionId,
    required String objectKey,
  }) => _remote.completeTemplateUpload(uploadSessionId: uploadSessionId, objectKey: objectKey);

  @override
  Future<ChallanTemplateUploadTarget> createTemplateStampUploadIntent(
    ChallanTemplateUploadIntentInput input,
  ) => _remote.createTemplateStampUploadIntent(input);

  @override
  Future<ChallanTemplateBackground> completeTemplateStampUpload({
    required String uploadSessionId,
    required String objectKey,
  }) => _remote.completeTemplateStampUpload(uploadSessionId: uploadSessionId, objectKey: objectKey);

  @override
  Uri templatePreviewUri({
    required int challanId,
    int? templateId,
    required String mode,
  }) => _remote.templatePreviewUri(challanId: challanId, templateId: templateId, mode: mode);

  @override
  Future<Uint8List> fetchTemplatePreviewPdf({
    required int challanId,
    int? templateId,
    required String mode,
  }) => _remote.fetchTemplatePreviewPdf(challanId: challanId, templateId: templateId, mode: mode);

  @override
  Uri templateTestPrintUri({
    required int templateId,
    required String mode,
    int? itemCount,
  }) => _remote.templateTestPrintUri(templateId: templateId, mode: mode, itemCount: itemCount);

  @override
  Future<Uint8List> fetchTemplateTestPrintPdf({
    required int templateId,
    required String mode,
    int? itemCount,
    List<ChallanTemplateMapping>? mappings,
  }) => _remote.fetchTemplateTestPrintPdf(templateId: templateId, mode: mode, itemCount: itemCount, mappings: mappings);
}

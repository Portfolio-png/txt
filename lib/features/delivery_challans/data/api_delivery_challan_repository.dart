import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../app/reports/domain/reconciliation_report.dart';
import '../domain/challan_template.dart';
import '../domain/delivery_challan.dart';
import 'delivery_challan_repository.dart';

class ApiChallanRepository implements ChallanRepository {
  ApiChallanRepository({
    http.Client? client,
    this.baseUrl = 'http://localhost:18080',
    this.useMockResponses = false,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final bool useMockResponses;

  static CompanyProfile _mockProfile = const CompanyProfile(
    id: 1,
    companyName: 'Shree Ganesh Metal Works',
    mobile: '9324041030',
    businessDescription: 'Manufacturers of: FOUNTAIN PEN, BALL PEN & PEN PARTS',
    address:
        'Gala No. 1 Ground Floor, Vasundhara Udyog Bhavan, Behind KT Phase No. 1 Industrial Estate, Gaurai Pada, Vasai (East), Dist. Palghar - 401 208.',
    stateCode: '27',
    gstin: '27ABHPC1349L1ZN',
    logoUrl: '',
    signatureLabel: '',
  );
  static final List<DeliveryChallan> _mockChallans = <DeliveryChallan>[];
  static final List<InvoiceHeader> _mockInvoices = <InvoiceHeader>[];
  static final List<ConversionOverride> _mockConversionOverrides =
      <ConversionOverride>[];
  static final List<ChallanTemplate> _mockTemplates = <ChallanTemplate>[];
  static final List<ChallanTemplateScan> _mockTemplateScans =
      <ChallanTemplateScan>[];
  static final Map<String, ChallanTemplateUploadIntentInput>
  _mockTemplateUploads = <String, ChallanTemplateUploadIntentInput>{};
  static int _mockNextId = 1;
  static int _mockNextTemplateId = 1;
  String? _lastWarningMessage;

  @override
  String? get lastWarningMessage => _lastWarningMessage;

  @override
  Future<void> init() async {}

  @override
  Future<CompanyProfile> getCompanyProfile() async {
    if (useMockResponses) {
      return _mockProfile;
    }
    final uri = Uri.parse('$baseUrl/api/company-profile');
    final response = await _sendRequest(method: 'GET', uri: uri);
    final payload = _decodeApiResponse(
      method: 'GET',
      uri: uri,
      response: response,
      fallback: 'Failed to fetch company profile.',
    );
    return CompanyProfile.fromJson(_dataObject(payload, 'companyProfile'));
  }

  @override
  Future<CompanyProfile> updateCompanyProfile(CompanyProfile profile) async {
    if (useMockResponses) {
      _mockProfile = profile;
      return _mockProfile;
    }
    final uri = Uri.parse('$baseUrl/api/company-profile');
    final body = jsonEncode(profile.toJson());
    final response = await _sendRequest(
      method: 'PUT',
      uri: uri,
      headers: const {'Content-Type': 'application/json'},
      body: body,
    );
    final payload = _decodeApiResponse(
      method: 'PUT',
      uri: uri,
      response: response,
      fallback: 'Failed to update company profile.',
    );
    return CompanyProfile.fromJson(_dataObject(payload, 'companyProfile'));
  }

  @override
  Future<List<DeliveryChallan>> getChallans({
    ChallanType? type,
    DeliveryChallanStatus? status,
    String search = '',
    DateTime? dateFrom,
    DateTime? dateTo,
    int? orderId,
  }) async {
    if (useMockResponses) {
      final query = search.trim().toLowerCase();
      return _mockChallans
          .where((challan) {
            if (orderId != null && challan.orderId != orderId) {
              return false;
            }
            if (type != null && challan.type != type) {
              return false;
            }
            if (status != null && challan.status != status) {
              return false;
            }
            if (query.isNotEmpty &&
                !challan.challanNo.toLowerCase().contains(query) &&
                !challan.orderNo.toLowerCase().contains(query) &&
                !challan.customerName.toLowerCase().contains(query) &&
                !challan.vendorName.toLowerCase().contains(query) &&
                !challan.sourceReference.toLowerCase().contains(query)) {
              return false;
            }
            return true;
          })
          .toList(growable: false);
    }
    final uri = Uri.parse('$baseUrl/api/challans').replace(
      queryParameters: <String, String>{
        if (type != null) 'type': type.name,
        if (status != null) 'status': status.name,
        if (search.trim().isNotEmpty) 'search': search.trim(),
        if (dateFrom != null) 'date_from': _dateOnly(dateFrom),
        if (dateTo != null) 'date_to': _dateOnly(dateTo),
        if (orderId != null) 'order_id': '$orderId',
      },
    );
    final response = await _sendRequest(method: 'GET', uri: uri);
    final payload = _decodeApiResponse(
      method: 'GET',
      uri: uri,
      response: response,
      fallback: 'Failed to fetch challans.',
    );
    return (_dataList(payload, 'challans'))
        .map((item) => DeliveryChallan.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<List<DeliveryChallan>> getOrderChallans(int orderId) async {
    if (useMockResponses) {
      return getChallans(orderId: orderId);
    }
    final uri = Uri.parse('$baseUrl/api/orders/$orderId/delivery-challans');
    final response = await _sendRequest(method: 'GET', uri: uri);
    final payload = _decodeApiResponse(
      method: 'GET',
      uri: uri,
      response: response,
      fallback: 'Failed to fetch order challans.',
    );
    return (_dataList(payload, 'challans'))
        .map((item) => DeliveryChallan.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<DeliveryChallan> getChallan(int id) async {
    if (useMockResponses) {
      return _mockChallans.firstWhere((challan) => challan.id == id);
    }
    final uri = Uri.parse('$baseUrl/api/challans/$id');
    final response = await _sendRequest(method: 'GET', uri: uri);
    final payload = _decodeApiResponse(
      method: 'GET',
      uri: uri,
      response: response,
      fallback: 'Failed to fetch challan.',
    );
    return DeliveryChallan.fromJson(_dataObject(payload, 'challan'));
  }

  @override
  Future<DeliveryChallan> createChallan(DeliveryChallanDraftInput input) async {
    _lastWarningMessage = null;
    if (useMockResponses) {
      final created = DeliveryChallan(
        id: _mockNextId++,
        type: input.type,
        orderId: input.orderId,
        orderIds: input.orderIds,
        clientId: null,
        orderNo: input.orderIds.isEmpty
            ? 'Order ${input.orderId}'
            : 'Order ${input.orderIds.first}',
        orderNos: input.orderIds
            .map((id) => 'Order $id')
            .toList(growable: false),
        challanNo: input.challanNo.trim().isEmpty
            ? '${input.type == ChallanType.reception ? 'RC' : 'DC'}-${_mockNextId.toString().padLeft(5, '0')}'
            : input.challanNo.trim(),
        date: input.date,
        location: input.location,
        customerName: input.customerName,
        customerGstin: input.customerGstin,
        vendorId: input.vendorId > 0 ? input.vendorId : null,
        vendorName: input.vendorName,
        vendorGstin: input.vendorGstin,
        sourceReference: input.sourceReference,
        companyProfileSnapshot: null,
        notes: input.notes,
        maintainStocks: input.maintainStocks,
        status: DeliveryChallanStatus.draft,
        items: input.items,
        itemsCount: input.items.length,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        usedInReport: false,
      );
      _mockChallans.add(created);
      return created;
    }
    return _sendChallan(
      method: 'POST',
      uri: Uri.parse('$baseUrl/api/challans'),
      input: input,
      fallback: 'Failed to create challan.',
    );
  }

  @override
  Future<DeliveryChallan> updateChallan(
    int id,
    DeliveryChallanDraftInput input,
  ) async {
    _lastWarningMessage = null;
    if (useMockResponses) {
      final index = _mockChallans.indexWhere((challan) => challan.id == id);
      final current = _mockChallans[index];
      final updated = DeliveryChallan(
        id: current.id,
        type: input.type,
        orderId: input.orderId,
        orderIds: input.orderIds,
        clientId: current.clientId,
        orderNo: current.orderNo,
        orderNos: current.orderNos,
        challanNo: current.challanNo,
        date: input.date,
        location: input.location,
        customerName: input.customerName.isEmpty
            ? current.customerName
            : input.customerName,
        customerGstin: input.customerGstin.isEmpty
            ? current.customerGstin
            : input.customerGstin,
        vendorId: input.vendorId > 0 ? input.vendorId : current.vendorId,
        vendorName: input.vendorName.isEmpty
            ? current.vendorName
            : input.vendorName,
        vendorGstin: input.vendorGstin.isEmpty
            ? current.vendorGstin
            : input.vendorGstin,
        sourceReference: input.sourceReference,
        companyProfileSnapshot: current.companyProfileSnapshot,
        notes: input.notes,
        maintainStocks: input.maintainStocks,
        status: current.status,
        items: input.items,
        itemsCount: input.items.length,
        createdAt: current.createdAt,
        updatedAt: DateTime.now(),
        usedInReport: current.usedInReport,
      );
      _mockChallans[index] = updated;
      return updated;
    }
    return _sendChallan(
      method: 'PUT',
      uri: Uri.parse('$baseUrl/api/challans/$id'),
      input: input,
      fallback: 'Failed to update challan.',
    );
  }

  @override
  Future<DeliveryChallan> issueChallan(int id) =>
      _statusAction(id, 'issue', 'Failed to issue challan.');

  @override
  Future<DeliveryChallan> cancelChallan(int id) =>
      _statusAction(id, 'cancel', 'Failed to cancel challan.');

  @override
  Future<void> deleteChallan(int id) async {
    if (useMockResponses) {
      _mockChallans.removeWhere(
        (challan) => challan.id == id && challan.isDraft,
      );
      return;
    }
    final uri = Uri.parse('$baseUrl/api/challans/$id');
    final response = await _sendRequest(method: 'DELETE', uri: uri);
    _decodeApiResponse(
      method: 'DELETE',
      uri: uri,
      response: response,
      fallback: 'Failed to delete challan.',
    );
  }

  @override
  Future<void> recordPrint(int id) async {
    if (useMockResponses) {
      return;
    }
    final uri = Uri.parse('$baseUrl/api/challans/$id/print');
    final response = await _sendRequest(method: 'POST', uri: uri);
    _decodeApiResponse(
      method: 'POST',
      uri: uri,
      response: response,
      fallback: 'Failed to record challan print.',
    );
  }

  @override
  Future<ReconciliationReportSnapshot> getReconciliationReport() async {
    if (useMockResponses) {
      return ReconciliationReportSnapshot.empty();
    }
    final uri = Uri.parse('$baseUrl/api/reconciliation/report');
    final response = await _sendRequest(method: 'GET', uri: uri);
    final payload = _decodeApiResponse(
      method: 'GET',
      uri: uri,
      response: response,
      fallback: 'Failed to fetch reconciliation report.',
    );
    return ReconciliationReportSnapshot.fromJson(
      _dataObject(payload, 'report'),
    );
  }

  @override
  Future<List<InvoiceHeader>> getInvoices() async {
    if (useMockResponses) {
      return List<InvoiceHeader>.unmodifiable(_mockInvoices);
    }
    final uri = Uri.parse('$baseUrl/api/invoices');
    final response = await _sendRequest(method: 'GET', uri: uri);
    final payload = _decodeApiResponse(
      method: 'GET',
      uri: uri,
      response: response,
      fallback: 'Failed to fetch invoices.',
    );
    return _dataList(payload, 'invoices')
        .whereType<Map<String, dynamic>>()
        .map(InvoiceHeader.fromJson)
        .toList(growable: false);
  }

  @override
  Future<InvoiceHeader> getInvoice(int id) async {
    if (useMockResponses) {
      return _mockInvoices.firstWhere((invoice) => invoice.id == id);
    }
    final uri = Uri.parse('$baseUrl/api/invoices/$id');
    final response = await _sendRequest(method: 'GET', uri: uri);
    final payload = _decodeApiResponse(
      method: 'GET',
      uri: uri,
      response: response,
      fallback: 'Failed to fetch invoice.',
    );
    return InvoiceHeader.fromJson(_dataObject(payload, 'invoice'));
  }

  @override
  Future<InvoiceHeader> updateInvoiceStatus(int id, String status) async {
    if (useMockResponses) {
      final index = _mockInvoices.indexWhere((invoice) => invoice.id == id);
      if (index == -1) {
        throw const ChallanApiException('Invoice not found.');
      }
      final existing = _mockInvoices[index];
      final updated = InvoiceHeader(
        id: existing.id,
        invoiceNo: existing.invoiceNo,
        clientId: existing.clientId,
        clientName: existing.clientName,
        gstin: existing.gstin,
        status: status,
        invoiceDate: existing.invoiceDate,
        totalQuantity: existing.totalQuantity,
        taxableValue: existing.taxableValue,
        cgstAmount: existing.cgstAmount,
        sgstAmount: existing.sgstAmount,
        totalAmount: existing.totalAmount,
        lines: existing.lines,
      );
      _mockInvoices[index] = updated;
      return updated;
    }
    final uri = Uri.parse('$baseUrl/api/invoices/$id/status');
    final response = await _sendRequest(
      method: 'PATCH',
      uri: uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'status': status}),
    );
    final payload = _decodeApiResponse(
      method: 'PATCH',
      uri: uri,
      response: response,
      fallback: 'Failed to update invoice status.',
    );
    return InvoiceHeader.fromJson(_dataObject(payload, 'invoice'));
  }

  @override
  Future<InvoiceHeader> createInvoice(InvoiceDraftInput input) async {
    if (useMockResponses) {
      final id = _mockInvoices.length + 1;
      final lines = input.lines
          .asMap()
          .entries
          .map((entry) {
            final line = entry.value;
            final taxableValue = line.quantity * line.unitPrice;
            return InvoiceLine(
              id: entry.key + 1,
              invoiceId: id,
              orderId: line.orderId,
              challanId: line.challanId,
              challanItemId: line.challanItemId,
              itemId: line.itemId,
              variationLeafNodeId: line.variationLeafNodeId,
              itemName: line.itemName,
              hsnCode: line.hsnCode,
              quantity: line.quantity,
              unitPrice: line.unitPrice,
              taxableValue: taxableValue,
              cgstRate: line.cgstRate,
              sgstRate: line.sgstRate,
              cgstAmount: taxableValue * line.cgstRate / 100,
              sgstAmount: taxableValue * line.sgstRate / 100,
            );
          })
          .toList(growable: false);
      final taxableValue = lines.fold<double>(
        0,
        (sum, line) => sum + line.taxableValue,
      );
      final cgstAmount = lines.fold<double>(
        0,
        (sum, line) => sum + line.cgstAmount,
      );
      final sgstAmount = lines.fold<double>(
        0,
        (sum, line) => sum + line.sgstAmount,
      );
      final invoice = InvoiceHeader(
        id: id,
        invoiceNo: input.invoiceNo.trim().isEmpty
            ? 'INV-${id.toString().padLeft(5, '0')}'
            : input.invoiceNo.trim(),
        clientId: input.clientId,
        clientName: input.clientName,
        gstin: input.gstin,
        status: 'draft',
        invoiceDate: input.invoiceDate,
        totalQuantity: lines.fold<double>(
          0,
          (sum, line) => sum + line.quantity,
        ),
        taxableValue: taxableValue,
        cgstAmount: cgstAmount,
        sgstAmount: sgstAmount,
        totalAmount: taxableValue + cgstAmount + sgstAmount,
        lines: lines,
      );
      _mockInvoices.add(invoice);
      return invoice;
    }
    final uri = Uri.parse('$baseUrl/api/invoices');
    final response = await _sendRequest(
      method: 'POST',
      uri: uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(input.toJson()),
    );
    final payload = _decodeApiResponse(
      method: 'POST',
      uri: uri,
      response: response,
      fallback: 'Failed to create invoice.',
    );
    return InvoiceHeader.fromJson(_dataObject(payload, 'invoice'));
  }

  @override
  Future<Uint8List> fetchInvoicePdf(int invoiceId) async {
    if (useMockResponses) {
      return Uint8List(0);
    }
    final uri = Uri.parse('$baseUrl/api/invoices/$invoiceId/pdf');
    final response = await _sendRequest(method: 'GET', uri: uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DeliveryChallanApiException(
        'Failed to fetch invoice PDF (${response.statusCode}).',
        debugMessage:
            'PDF fetch failed for invoice $invoiceId. Status: ${response.statusCode}. URI: $uri',
      );
    }
    return response.bodyBytes;
  }

  @override
  Future<List<ConversionOverride>> getConversionOverrides() async {
    if (useMockResponses) {
      return List<ConversionOverride>.unmodifiable(_mockConversionOverrides);
    }
    final uri = Uri.parse('$baseUrl/api/reconciliation/conversion-overrides');
    final response = await _sendRequest(method: 'GET', uri: uri);
    final payload = _decodeApiResponse(
      method: 'GET',
      uri: uri,
      response: response,
      fallback: 'Failed to fetch conversion overrides.',
    );
    return _dataList(payload, 'conversionOverrides')
        .whereType<Map<String, dynamic>>()
        .map(ConversionOverride.fromJson)
        .toList(growable: false);
  }

  @override
  Future<ConversionOverride> saveConversionOverride(
    ConversionOverrideInput input,
  ) async {
    if (useMockResponses) {
      final saved = ConversionOverride(
        id: _mockConversionOverrides.length + 1,
        itemId: input.itemId,
        variationLeafNodeId: input.variationLeafNodeId,
        conversionRatio: input.conversionRatio,
        fromUnit: 'kg',
        toUnitLabel: input.toUnitLabel,
        updatedAt: DateTime.now(),
      );
      _mockConversionOverrides.removeWhere(
        (override) =>
            override.itemId == input.itemId &&
            override.variationLeafNodeId == input.variationLeafNodeId,
      );
      _mockConversionOverrides.add(saved);
      return saved;
    }
    final uri = Uri.parse('$baseUrl/api/reconciliation/conversion-overrides');
    final response = await _sendRequest(
      method: 'PATCH',
      uri: uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(input.toJson()),
    );
    final payload = _decodeApiResponse(
      method: 'PATCH',
      uri: uri,
      response: response,
      fallback: 'Failed to save conversion override.',
    );
    return ConversionOverride.fromJson(_dataObject(payload, 'conversion'));
  }

  @override
  Future<List<WasteAuditRow>> getWasteAuditRows() async {
    if (useMockResponses) {
      return const <WasteAuditRow>[];
    }
    final uri = Uri.parse('$baseUrl/api/reconciliation/waste-audit');
    final response = await _sendRequest(method: 'GET', uri: uri);
    final payload = _decodeApiResponse(
      method: 'GET',
      uri: uri,
      response: response,
      fallback: 'Failed to fetch waste audit rows.',
    );
    return _dataList(payload, 'wasteAudit')
        .whereType<Map<String, dynamic>>()
        .map(WasteAuditRow.fromJson)
        .toList(growable: false);
  }

  @override
  Future<ClientStatementReport> generateClientStatementReport({
    required List<String> challanNos,
    required List<String> receptionChallanNos,
  }) async {
    final normalized = challanNos
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final normalizedReception = receptionChallanNos
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (useMockResponses) {
      final selected = _mockChallans
          .where(
            (challan) =>
                normalized.contains(challan.challanNo) &&
                challan.type == ChallanType.delivery &&
                challan.status == DeliveryChallanStatus.issued,
          )
          .toList(growable: false);
      final selectedReceptions = _mockChallans
          .where(
            (challan) =>
                normalizedReception.contains(challan.challanNo) &&
                challan.type == ChallanType.reception &&
                challan.status == DeliveryChallanStatus.issued,
          )
          .toList(growable: false);
      final rows = selected
          .expand(
            (challan) => challan.items.map(
              (item) => ClientStatementReportRow(
                date: challan.date,
                challanNo: challan.challanNo,
                clientName: challan.customerName,
                orderNo: challan.orderNo,
                itemName: item.particulars,
                note: item.note,
                quantityPcs: double.tryParse(item.quantityPcs) ?? 0,
                weight: double.tryParse(item.weight) ?? 0,
              ),
            ),
          )
          .toList(growable: false);
      for (final challan in [...selected, ...selectedReceptions]) {
        final index = _mockChallans.indexWhere(
          (candidate) => candidate.challanNo == challan.challanNo,
        );
        if (index != -1) {
          _mockChallans[index] = _mockChallans[index].copyWith(
            usedInReport: true,
          );
        }
      }
      final groups = selectedReceptions.map((rc) {
        final rcWeight = rc.items.fold<double>(0.0, (sum, i) => sum + (double.tryParse(i.weight) ?? 0.0));
        final deliveries = selected.expand((dc) => dc.items.map((i) => ClientStatementGroupDeliveryItem(
          date: dc.date,
          challanNo: dc.challanNo,
          particulars: i.particulars,
          note: i.note,
          weight: double.tryParse(i.weight) ?? 0.0,
          quantityPcs: double.tryParse(i.quantityPcs) ?? 0.0,
        ))).toList(growable: false);
        return ClientStatementGroup(
          receptionChallanNo: rc.challanNo,
          receptionDate: rc.date,
          receptionSize: rc.items.isNotEmpty ? rc.items.first.particulars : '',
          receptionWeight: rcWeight,
          lessWeight: rcWeight * 0.05,
          totalWeight: rcWeight,
          deliveries: deliveries,
        );
      }).toList(growable: false);
      return ClientStatementReport(
        rows: rows,
        receptionGroups: groups,
        challanCount: selected.length,
        totalQuantityPcs: rows.fold<double>(
          0,
          (sum, row) => sum + row.quantityPcs,
        ),
        totalWeight: rows.fold<double>(0, (sum, row) => sum + row.weight),
        generatedAt: DateTime.now(),
      );
    }
    final uri = Uri.parse('$baseUrl/api/reports/client-statement');
    final response = await _sendRequest(
      method: 'POST',
      uri: uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'challanIds': normalized,
        'receptionChallanIds': normalizedReception,
      }),
    );
    final payload = _decodeApiResponse(
      method: 'POST',
      uri: uri,
      response: response,
      fallback: 'Failed to generate client statement.',
    );
    return ClientStatementReport.fromJson(_dataObject(payload, 'report'));
  }

  @override
  Future<List<CompletedProductionRun>> getCompletedProductionRuns({
    String search = '',
    int limit = 25,
  }) async {
    if (useMockResponses) {
      return const <CompletedProductionRun>[];
    }
    final uri = Uri.parse('$baseUrl/api/production-runs/completed').replace(
      queryParameters: <String, String>{
        if (search.trim().isNotEmpty) 'search': search.trim(),
        'limit': '$limit',
      },
    );
    final response = await _sendRequest(method: 'GET', uri: uri);
    final payload = _decodeApiResponse(
      method: 'GET',
      uri: uri,
      response: response,
      fallback: 'Failed to fetch completed production runs.',
    );
    return (_dataList(payload, 'productionRuns'))
        .map(
          (item) =>
              CompletedProductionRun.fromJson(item as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  @override
  Future<List<ChallanTemplate>> getTemplates({
    ChallanTemplatePartyType? partyType,
    int? partyId,
    ChallanType? challanType,
    bool activeOnly = false,
  }) async {
    if (useMockResponses) {
      return _mockTemplates
          .where((template) {
            if (partyType != null && template.partyType != partyType) {
              return false;
            }
            if (partyId != null && template.partyId != partyId) {
              return false;
            }
            if (challanType != null && template.challanType != challanType) {
              return false;
            }
            if (activeOnly && !template.isActive) {
              return false;
            }
            return true;
          })
          .toList(growable: false);
    }
    final uri = Uri.parse('$baseUrl/api/challan-templates').replace(
      queryParameters: <String, String>{
        if (partyType != null) 'partyType': partyType.name,
        if (partyId != null) 'partyId': '$partyId',
        if (challanType != null) 'challanType': challanType.name,
        if (activeOnly) 'activeOnly': 'true',
      },
    );
    final response = await _sendRequest(method: 'GET', uri: uri);
    final payload = _decodeApiResponse(
      method: 'GET',
      uri: uri,
      response: response,
      fallback: 'Failed to fetch challan templates.',
    );
    return _dataList(payload, 'templates')
        .map((item) => ChallanTemplate.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<List<ChallanTemplateScan>> getTemplateScans({int limit = 24}) async {
    if (useMockResponses) {
      return _mockTemplateScans.take(limit).toList(growable: false);
    }
    final uri = Uri.parse(
      '$baseUrl/api/challan-templates/scans',
    ).replace(queryParameters: <String, String>{'limit': '$limit'});
    final response = await _sendRequest(method: 'GET', uri: uri);
    final payload = _decodeApiResponse(
      method: 'GET',
      uri: uri,
      response: response,
      fallback: 'Failed to fetch challan template scans.',
    );
    return _dataList(payload, 'scans')
        .map(
          (item) => ChallanTemplateScan.fromJson(item as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  @override
  Future<ChallanTemplate> createTemplate(ChallanTemplateInput input) async {
    if (useMockResponses) {
      final template = ChallanTemplate(
        id: _mockNextTemplateId++,
        name: input.name,
        partyType: input.partyType,
        partyId: input.partyId,
        challanType: input.challanType,
        backgroundObjectKey: input.backgroundObjectKey,
        backgroundImageUrl: null,
        canvasWidth: input.canvasWidth,
        canvasHeight: input.canvasHeight,
        rotationDegrees: input.rotationDegrees,
        globalOffsetXmm: input.globalOffsetXmm,
        globalOffsetYmm: input.globalOffsetYmm,
        stockSize: input.stockSize,
        paperSize: input.paperSize,
        nUpLayout: input.nUpLayout,
        isActive: input.isActive,
        mappings: input.mappings,
      );
      if (template.isActive) {
        _mockTemplates.removeWhere(
          (entry) =>
              entry.partyType == template.partyType &&
              entry.partyId == template.partyId &&
              entry.challanType == template.challanType &&
              entry.isActive,
        );
      }
      _mockTemplates.add(template);
      return template;
    }
    return _sendTemplate(
      method: 'POST',
      uri: Uri.parse('$baseUrl/api/challan-templates'),
      input: input,
      fallback: 'Failed to create challan template.',
    );
  }

  @override
  Future<ChallanTemplate> updateTemplate(
    int id,
    ChallanTemplateInput input,
  ) async {
    if (useMockResponses) {
      final index = _mockTemplates.indexWhere((template) => template.id == id);
      final updated = ChallanTemplate(
        id: id,
        name: input.name,
        partyType: input.partyType,
        partyId: input.partyId,
        challanType: input.challanType,
        backgroundObjectKey: input.backgroundObjectKey,
        backgroundImageUrl: null,
        canvasWidth: input.canvasWidth,
        canvasHeight: input.canvasHeight,
        rotationDegrees: input.rotationDegrees,
        globalOffsetXmm: input.globalOffsetXmm,
        globalOffsetYmm: input.globalOffsetYmm,
        stockSize: input.stockSize,
        paperSize: input.paperSize,
        nUpLayout: input.nUpLayout,
        isActive: input.isActive,
        mappings: input.mappings,
      );
      if (index >= 0) {
        _mockTemplates[index] = updated;
      } else {
        _mockTemplates.add(updated);
      }
      return updated;
    }
    return _sendTemplate(
      method: 'PATCH',
      uri: Uri.parse('$baseUrl/api/challan-templates/$id'),
      input: input,
      fallback: 'Failed to update challan template.',
    );
  }

  @override
  Future<void> deleteTemplate(int id) async {
    if (useMockResponses) {
      _mockTemplates.removeWhere((template) => template.id == id);
      return;
    }
    final uri = Uri.parse('$baseUrl/api/challan-templates/$id');
    final response = await _sendRequest(method: 'DELETE', uri: uri);
    _decodeApiResponse(
      method: 'DELETE',
      uri: uri,
      response: response,
      fallback: 'Failed to delete challan template.',
    );
  }

  @override
  Future<ChallanTemplateUploadTarget> createTemplateUploadIntent(
    ChallanTemplateUploadIntentInput input,
  ) async {
    if (useMockResponses) {
      final sessionId =
          'template-upload-${DateTime.now().microsecondsSinceEpoch}';
      _mockTemplateUploads[sessionId] = input;
      return ChallanTemplateUploadTarget(
        uploadSessionId: sessionId,
        objectKey: 'mock/challan-templates/$sessionId-${input.fileName}',
        uploadUrl: Uri.parse('https://mock.local/$sessionId'),
        headers: const <String, String>{},
        reused: false,
        canvasWidth: 0,
        canvasHeight: 0,
      );
    }
    final uri = Uri.parse('$baseUrl/api/challan-templates/upload-intent');
    final response = await _sendRequest(
      method: 'POST',
      uri: uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'fileName': input.fileName,
        'contentType': input.contentType,
        'sizeBytes': input.sizeBytes,
        'sha256': input.sha256,
      }),
    );
    final payload = _decodeApiResponse(
      method: 'POST',
      uri: uri,
      response: response,
      fallback: 'Failed to prepare challan template upload.',
    );
    return ChallanTemplateUploadTarget.fromJson(_dataObject(payload, 'upload'));
  }

  @override
  Future<ChallanTemplateBackground> completeTemplateUpload({
    required String uploadSessionId,
    required String objectKey,
  }) async {
    if (useMockResponses) {
      _mockTemplateUploads.remove(uploadSessionId);
      final scan = ChallanTemplateScan(
        uploadSessionId: uploadSessionId,
        objectKey: objectKey,
        fileName: objectKey.split('/').last,
        contentType: 'image/png',
        sizeBytes: 0,
        sha256: '',
        canvasWidth: 1240,
        canvasHeight: 1754,
        imageUrl: null,
        uploadedAt: DateTime.now().toIso8601String(),
      );
      _mockTemplateScans.removeWhere((entry) => entry.objectKey == objectKey);
      _mockTemplateScans.insert(0, scan);
      return ChallanTemplateBackground(
        objectKey: objectKey,
        canvasWidth: 1240,
        canvasHeight: 1754,
      );
    }
    final uri = Uri.parse('$baseUrl/api/challan-templates/upload-complete');
    final response = await _sendRequest(
      method: 'POST',
      uri: uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'uploadSessionId': uploadSessionId,
        'objectKey': objectKey,
      }),
    );
    final payload = _decodeApiResponse(
      method: 'POST',
      uri: uri,
      response: response,
      fallback: 'Failed to complete challan template upload.',
    );
    return ChallanTemplateBackground.fromJson(
      _dataObject(payload, 'background'),
    );
  }

  @override
  Future<ChallanTemplateUploadTarget> createTemplateStampUploadIntent(
    ChallanTemplateUploadIntentInput input,
  ) async {
    if (useMockResponses) {
      final sessionId =
          'template-stamp-upload-${DateTime.now().microsecondsSinceEpoch}';
      _mockTemplateUploads[sessionId] = input;
      return ChallanTemplateUploadTarget(
        uploadSessionId: sessionId,
        objectKey: 'mock/challan-template-stamps/$sessionId-${input.fileName}',
        uploadUrl: Uri.parse('https://mock.local/$sessionId'),
        headers: const <String, String>{},
        reused: false,
        canvasWidth: 0,
        canvasHeight: 0,
      );
    }
    final uri = Uri.parse('$baseUrl/api/challan-templates/stamp-upload-intent');
    final response = await _sendRequest(
      method: 'POST',
      uri: uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'fileName': input.fileName,
        'contentType': input.contentType,
        'sizeBytes': input.sizeBytes,
        'sha256': input.sha256,
      }),
    );
    final payload = _decodeApiResponse(
      method: 'POST',
      uri: uri,
      response: response,
      fallback: 'Failed to prepare stamp upload.',
    );
    return ChallanTemplateUploadTarget.fromJson(_dataObject(payload, 'upload'));
  }

  @override
  Future<ChallanTemplateBackground> completeTemplateStampUpload({
    required String uploadSessionId,
    required String objectKey,
  }) async {
    if (useMockResponses) {
      _mockTemplateUploads.remove(uploadSessionId);
      return ChallanTemplateBackground(
        objectKey: objectKey,
        canvasWidth: 800,
        canvasHeight: 320,
      );
    }
    final uri = Uri.parse(
      '$baseUrl/api/challan-templates/stamp-upload-complete',
    );
    final response = await _sendRequest(
      method: 'POST',
      uri: uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'uploadSessionId': uploadSessionId,
        'objectKey': objectKey,
      }),
    );
    final payload = _decodeApiResponse(
      method: 'POST',
      uri: uri,
      response: response,
      fallback: 'Failed to complete stamp upload.',
    );
    return ChallanTemplateBackground.fromJson(_dataObject(payload, 'stamp'));
  }

  @override
  Uri templatePreviewUri({
    required int challanId,
    int? templateId,
    required String mode,
  }) {
    return Uri.parse(
      '$baseUrl/api/challans/$challanId/print-template-preview',
    ).replace(
      queryParameters: <String, String>{
        'mode': mode,
        if (templateId != null) 'templateId': '$templateId',
      },
    );
  }

  @override
  Future<Uint8List> fetchTemplatePreviewPdf({
    required int challanId,
    int? templateId,
    required String mode,
  }) async {
    final uri = templatePreviewUri(
      challanId: challanId,
      templateId: templateId,
      mode: mode,
    );
    final response = await _sendRequest(method: 'GET', uri: uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DeliveryChallanApiException(
        'Failed to fetch challan print PDF (${response.statusCode}).',
        debugMessage:
            'PDF fetch failed for challan $challanId. Status: ${response.statusCode}. URI: $uri',
      );
    }
    return response.bodyBytes;
  }

  @override
  Uri templateTestPrintUri({
    required int templateId,
    required String mode,
    int? itemCount,
  }) {
    return Uri.parse('$baseUrl/api/templates/$templateId/test-print').replace(
      queryParameters: <String, String>{
        'mode': mode,
        if (itemCount != null) 'itemCount': '$itemCount',
      },
    );
  }

  @override
  Future<Uint8List> fetchTemplateTestPrintPdf({
    required int templateId,
    required String mode,
    int? itemCount,
    List<ChallanTemplateMapping>? mappings,
  }) async {
    if (mappings != null) {
      final response = await _sendRequest(
        method: 'POST',
        uri: Uri.parse('$baseUrl/api/challan-templates/test-print'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(<String, dynamic>{
          'templateId': templateId,
          'mode': mode,
          'itemCount': itemCount,
          'mappings': mappings
              .map((mapping) => mapping.toJson())
              .toList(growable: false),
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw DeliveryChallanApiException(
          'Failed to fetch test print PDF (${response.statusCode}).',
          debugMessage:
              'PDF fetch failed for template $templateId with mapping override. Status: ${response.statusCode}.',
        );
      }
      return response.bodyBytes;
    }

    final uri = templateTestPrintUri(
      templateId: templateId,
      mode: mode,
      itemCount: itemCount,
    );
    var response = await _sendRequest(method: 'GET', uri: uri);
    if (response.statusCode == 404 || response.statusCode == 405) {
      response = await _sendRequest(
        method: 'POST',
        uri: Uri.parse('$baseUrl/api/challan-templates/test-print'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(<String, dynamic>{
          'templateId': templateId,
          'mode': mode,
          'itemCount': itemCount,
        }),
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DeliveryChallanApiException(
        'Failed to fetch test print PDF (${response.statusCode}).',
        debugMessage:
            'PDF fetch failed for template $templateId. Final status: ${response.statusCode}. GET uri: $uri',
      );
    }
    return response.bodyBytes;
  }

  Future<DeliveryChallan> _statusAction(
    int id,
    String action,
    String fallback,
  ) async {
    if (useMockResponses) {
      final index = _mockChallans.indexWhere((challan) => challan.id == id);
      final current = _mockChallans[index];
      final updated = DeliveryChallan(
        id: current.id,
        type: current.type,
        orderId: current.orderId,
        orderIds: current.orderIds,
        clientId: current.clientId,
        orderNo: current.orderNo,
        orderNos: current.orderNos,
        challanNo: current.challanNo,
        date: current.date,
        location: current.location,
        customerName: current.customerName,
        customerGstin: current.customerGstin,
        vendorId: current.vendorId,
        vendorName: current.vendorName,
        vendorGstin: current.vendorGstin,
        sourceReference: current.sourceReference,
        companyProfileSnapshot: action == 'issue'
            ? _mockProfile
            : current.companyProfileSnapshot,
        notes: current.notes,
        maintainStocks: current.maintainStocks,
        status: action == 'issue'
            ? DeliveryChallanStatus.issued
            : DeliveryChallanStatus.cancelled,
        items: current.items,
        itemsCount: current.itemsCount,
        createdAt: current.createdAt,
        updatedAt: DateTime.now(),
        usedInReport: current.usedInReport,
      );
      _mockChallans[index] = updated;
      return updated;
    }
    final uri = Uri.parse('$baseUrl/api/challans/$id/$action');
    final response = await _sendRequest(method: 'POST', uri: uri);
    final payload = _decodeApiResponse(
      method: 'POST',
      uri: uri,
      response: response,
      fallback: fallback,
    );
    return DeliveryChallan.fromJson(_dataObject(payload, 'challan'));
  }

  Future<DeliveryChallan> _sendChallan({
    required String method,
    required Uri uri,
    required DeliveryChallanDraftInput input,
    required String fallback,
  }) async {
    final body = jsonEncode(input.toJson());
    final response = await _sendRequest(
      method: method,
      uri: uri,
      headers: const {'Content-Type': 'application/json'},
      body: body,
    );
    final payload = _decodeApiResponse(
      method: method,
      uri: uri,
      response: response,
      fallback: fallback,
    );
    _lastWarningMessage = _extractWarningMessage(payload);
    return DeliveryChallan.fromJson(_dataObject(payload, 'challan'));
  }

  Future<ChallanTemplate> _sendTemplate({
    required String method,
    required Uri uri,
    required ChallanTemplateInput input,
    required String fallback,
  }) async {
    final response = await _sendRequest(
      method: method,
      uri: uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(input.toJson()),
    );
    final payload = _decodeApiResponse(
      method: method,
      uri: uri,
      response: response,
      fallback: fallback,
    );
    return ChallanTemplate.fromJson(_dataObject(payload, 'template'));
  }

  Future<http.Response> _sendRequest({
    required String method,
    required Uri uri,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final request = http.Request(method, uri);
    request.headers.addAll(headers);
    if (body != null) {
      request.body = body;
    }

    final streamedResponseFuture = _client.send(request);
    _logRequest(method, uri, request.headers, body);
    final streamedResponse = await streamedResponseFuture;
    return http.Response.fromStream(streamedResponse);
  }

  static Map<String, dynamic> _decodeApiResponse({
    required String method,
    required Uri uri,
    required http.Response response,
    required String fallback,
  }) {
    final contentType = response.headers['content-type'] ?? '';
    final trimmedBody = response.body.trimLeft();
    final bodyPreview = response.body.length > 500
        ? response.body.substring(0, 500)
        : response.body;
    debugPrint('DC API RESPONSE STATUS => ${response.statusCode}');
    debugPrint('DC API RESPONSE TYPE => $contentType');
    debugPrint('DC API RESPONSE BODY => $bodyPreview', wrapWidth: 2048);

    final returnedHtml =
        contentType.contains('text/html') || trimmedBody.startsWith('<');

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (returnedHtml) {
        throw DeliveryChallanApiException(
          '$fallback Server returned an invalid response.',
          debugMessage:
              'Server returned HTML instead of JSON. Check API route: $method $uri. Status: ${response.statusCode}. Body: ${response.body}',
        );
      }
      final payload = _tryDecodeJsonObject(response.body);
      throw DeliveryChallanApiException(
        payload?['error'] as String? ?? fallback,
        debugMessage:
            'API error for $method $uri. Status: ${response.statusCode}. Body: ${response.body}',
      );
    }

    if (returnedHtml) {
      throw DeliveryChallanApiException(
        '$fallback Server returned an invalid response.',
        debugMessage:
            'Server returned HTML instead of JSON. Check API route: $method $uri. Status: ${response.statusCode}. Body: ${response.body}',
      );
    }

    final payload = _tryDecodeJsonObject(response.body);
    if (payload == null) {
      throw DeliveryChallanApiException(
        '$fallback Server returned an invalid response.',
        debugMessage:
            'Expected JSON object for $method $uri. Status: ${response.statusCode}. Content-Type: $contentType. Body: ${response.body}',
      );
    }
    if (payload['success'] != true) {
      throw DeliveryChallanApiException(
        payload['error'] as String? ?? fallback,
        debugMessage:
            'API returned success=false for $method $uri. Status: ${response.statusCode}. Body: ${response.body}',
      );
    }
    return payload;
  }

  static Map<String, dynamic>? _tryDecodeJsonObject(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _dataObject(
    Map<String, dynamic> payload,
    String legacyKey,
  ) {
    final data = payload['data'] ?? payload[legacyKey];
    return data is Map<String, dynamic> ? data : const {};
  }

  static List<dynamic> _dataList(
    Map<String, dynamic> payload,
    String legacyKey,
  ) {
    final data = payload['data'] ?? payload[legacyKey];
    return data is List<dynamic> ? data : const [];
  }

  static String? _extractWarningMessage(Map<String, dynamic> payload) {
    final warnings = payload['warnings'];
    if (warnings is List && warnings.isNotEmpty) {
      final first = warnings.first;
      if (first is String && first.trim().isNotEmpty) {
        return first.trim();
      }
    }
    return null;
  }

  static void _logRequest(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) {
    debugPrint('DC API REQUEST => $method $uri');
    debugPrint('DC API HEADERS => ${jsonEncode(headers)}', wrapWidth: 2048);
    debugPrint('DC API BODY => ${body ?? ''}', wrapWidth: 2048);
  }

  static String _dateOnly(DateTime value) =>
      value.toIso8601String().substring(0, 10);
}

typedef ApiDeliveryChallanRepository = ApiChallanRepository;

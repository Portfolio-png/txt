import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../domain/delivery_challan.dart';
import 'delivery_challan_repository.dart';

class ApiDeliveryChallanRepository implements DeliveryChallanRepository {
  ApiDeliveryChallanRepository({
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
  static int _mockNextId = 1;

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
            if (status != null && challan.status != status) {
              return false;
            }
            if (query.isNotEmpty &&
                !challan.challanNo.toLowerCase().contains(query) &&
                !challan.orderNo.toLowerCase().contains(query) &&
                !challan.customerName.toLowerCase().contains(query)) {
              return false;
            }
            return true;
          })
          .toList(growable: false);
    }
    final uri = Uri.parse('$baseUrl/api/delivery-challans').replace(
      queryParameters: <String, String>{
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
      fallback: 'Failed to fetch delivery challans.',
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
      fallback: 'Failed to fetch order delivery challans.',
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
    final uri = Uri.parse('$baseUrl/api/delivery-challans/$id');
    final response = await _sendRequest(method: 'GET', uri: uri);
    final payload = _decodeApiResponse(
      method: 'GET',
      uri: uri,
      response: response,
      fallback: 'Failed to fetch delivery challan.',
    );
    return DeliveryChallan.fromJson(_dataObject(payload, 'challan'));
  }

  @override
  Future<DeliveryChallan> createChallan(DeliveryChallanDraftInput input) async {
    if (useMockResponses) {
      final created = DeliveryChallan(
        id: _mockNextId++,
        orderId: input.orderId,
        orderNo: 'Order ${input.orderId}',
        challanNo: 'DC-${_mockNextId.toString().padLeft(5, '0')}',
        date: input.date,
        customerName: '',
        customerGstin: '',
        companyProfileSnapshot: null,
        notes: input.notes,
        status: DeliveryChallanStatus.draft,
        items: input.items,
        itemsCount: input.items.length,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      _mockChallans.add(created);
      return created;
    }
    return _sendChallan(
      method: 'POST',
      uri: Uri.parse('$baseUrl/api/delivery-challans'),
      input: input,
      fallback: 'Failed to create delivery challan.',
    );
  }

  @override
  Future<DeliveryChallan> updateChallan(
    int id,
    DeliveryChallanDraftInput input,
  ) async {
    if (useMockResponses) {
      final index = _mockChallans.indexWhere((challan) => challan.id == id);
      final current = _mockChallans[index];
      final updated = DeliveryChallan(
        id: current.id,
        orderId: input.orderId,
        orderNo: current.orderNo,
        challanNo: current.challanNo,
        date: input.date,
        customerName: current.customerName,
        customerGstin: current.customerGstin,
        companyProfileSnapshot: current.companyProfileSnapshot,
        notes: input.notes,
        status: current.status,
        items: input.items,
        itemsCount: input.items.length,
        createdAt: current.createdAt,
        updatedAt: DateTime.now(),
      );
      _mockChallans[index] = updated;
      return updated;
    }
    return _sendChallan(
      method: 'PUT',
      uri: Uri.parse('$baseUrl/api/delivery-challans/$id'),
      input: input,
      fallback: 'Failed to update delivery challan.',
    );
  }

  @override
  Future<DeliveryChallan> issueChallan(int id) =>
      _statusAction(id, 'issue', 'Failed to issue delivery challan.');

  @override
  Future<DeliveryChallan> cancelChallan(int id) =>
      _statusAction(id, 'cancel', 'Failed to cancel delivery challan.');

  @override
  Future<void> deleteChallan(int id) async {
    if (useMockResponses) {
      _mockChallans.removeWhere(
        (challan) => challan.id == id && challan.isDraft,
      );
      return;
    }
    final uri = Uri.parse('$baseUrl/api/delivery-challans/$id');
    final response = await _sendRequest(method: 'DELETE', uri: uri);
    _decodeApiResponse(
      method: 'DELETE',
      uri: uri,
      response: response,
      fallback: 'Failed to delete delivery challan.',
    );
  }

  @override
  Future<void> recordPrint(int id) async {
    if (useMockResponses) {
      return;
    }
    return;
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
        orderId: current.orderId,
        orderNo: current.orderNo,
        challanNo: current.challanNo,
        date: current.date,
        customerName: current.customerName,
        customerGstin: current.customerGstin,
        companyProfileSnapshot: action == 'issue'
            ? _mockProfile
            : current.companyProfileSnapshot,
        notes: current.notes,
        status: action == 'issue'
            ? DeliveryChallanStatus.issued
            : DeliveryChallanStatus.cancelled,
        items: current.items,
        itemsCount: current.itemsCount,
        createdAt: current.createdAt,
        updatedAt: DateTime.now(),
      );
      _mockChallans[index] = updated;
      return updated;
    }
    final uri = Uri.parse('$baseUrl/api/delivery-challans/$id/$action');
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
    return DeliveryChallan.fromJson(_dataObject(payload, 'challan'));
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

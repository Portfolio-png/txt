import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/procurement_models.dart';
import '../models/procurement_api_models.dart';
import 'procurement_repository.dart';

class ApiProcurementRepository implements ProcurementRepository {
  ApiProcurementRepository({
    http.Client? client,
    this.baseUrl = 'http://localhost:8080',
    this.useMockResponses = true,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final bool useMockResponses;

  static int _mockNextRequestId = 1;
  static int _mockNextLineId = 1;
  static final List<ProcurementQueueRow> _mockQueueRows = <ProcurementQueueRow>[
    const ProcurementQueueRow(
      supplierName: 'Metro Steels',
      materialBarcode: 'PAR-1775707641373-7729',
      materialName: 'Steel Sheet Batch',
      totalShortageQty: 4100,
      openRequestedQty: 0,
      uncoveredQty: 4100,
      affectedOrderCount: 3,
      procurementStatus: 'unrequested',
      orderIds: <int>[1, 2, 3],
      sourceRequirementIds: <int>[11, 12, 13],
      unitSymbol: 'Sheet',
    ),
  ];
  static final List<ProcurementRequestSummary> _mockRequests =
      <ProcurementRequestSummary>[];
  static final Map<int, ProcurementRequestDetail> _mockDetails =
      <int, ProcurementRequestDetail>{};

  @override
  Future<void> init() async {}

  @override
  Future<List<ProcurementQueueRow>> getQueueRows() async {
    if (useMockResponses) {
      return List<ProcurementQueueRow>.from(_mockQueueRows);
    }
    final response = await _client.get(
      Uri.parse('$baseUrl/api/procurement-queue'),
    );
    final payload = _decode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw ProcurementApiException(
        payload['error'] as String? ?? 'Failed to load procurement queue.',
      );
    }
    return (payload['rows'] as List<dynamic>? ?? const <dynamic>[])
        .map(
          (entry) => ProcurementQueueRowDto.fromJson(
            entry as Map<String, dynamic>,
          ).toDomain(),
        )
        .toList(growable: false);
  }

  @override
  Future<List<ProcurementQueueRow>> refreshQueueRows() async {
    if (useMockResponses) {
      return getQueueRows();
    }
    final response = await _client.post(
      Uri.parse('$baseUrl/api/procurement-queue/refresh'),
      headers: const {'Content-Type': 'application/json'},
    );
    final payload = _decode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw ProcurementApiException(
        payload['error'] as String? ?? 'Failed to refresh procurement queue.',
      );
    }
    return (payload['rows'] as List<dynamic>? ?? const <dynamic>[])
        .map(
          (entry) => ProcurementQueueRowDto.fromJson(
            entry as Map<String, dynamic>,
          ).toDomain(),
        )
        .toList(growable: false);
  }

  @override
  Future<List<ProcurementRequestSummary>> getRequests() async {
    if (useMockResponses) {
      return List<ProcurementRequestSummary>.from(_mockRequests);
    }
    final response = await _client.get(
      Uri.parse('$baseUrl/api/procurement-requests'),
    );
    final payload = _decode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw ProcurementApiException(
        payload['error'] as String? ?? 'Failed to load procurement requests.',
      );
    }
    return (payload['requests'] as List<dynamic>? ?? const <dynamic>[])
        .map(
          (entry) => ProcurementRequestSummaryDto.fromJson(
            entry as Map<String, dynamic>,
          ).toDomain(),
        )
        .toList(growable: false);
  }

  @override
  Future<List<ProcurementRequestSummary>> createDraftRequests({
    required List<ProcurementQueueRow> rows,
  }) async {
    if (rows.isEmpty) {
      return const <ProcurementRequestSummary>[];
    }
    if (useMockResponses) {
      final created = <ProcurementRequestSummary>[];
      final grouped = <String, List<ProcurementQueueRow>>{};
      for (final row in rows) {
        grouped
            .putIfAbsent(row.supplierName, () => <ProcurementQueueRow>[])
            .add(row);
      }
      for (final entry in grouped.entries) {
        final id = _mockNextRequestId++;
        final totalQty = entry.value.fold<double>(
          0,
          (sum, row) => sum + row.uncoveredQty,
        );
        final summary = ProcurementRequestSummary(
          id: id,
          requestNumber: 'PR-${id.toString().padLeft(4, '0')}',
          supplierName: entry.key,
          status: 'draft',
          lineCount: entry.value.length,
          totalRequestedQty: totalQty,
          totalReceivedQty: 0,
          totalPendingQty: totalQty,
        );
        _mockRequests.insert(0, summary);
        final lines = entry.value
            .map(
              (row) => ProcurementRequestLine(
                id: _mockNextLineId++,
                procurementRequestId: id,
                materialBarcode: row.materialBarcode,
                materialName: row.materialName,
                requestedQty: row.uncoveredQty,
                receivedQty: 0,
                pendingQty: row.uncoveredQty,
                unitId: row.unitId,
                unitSymbol: row.unitSymbol,
                status: 'draft',
                linkedOrderCount: row.affectedOrderCount,
                linkedRequirementCount: row.sourceRequirementIds.length,
                linkedOrderIds: row.orderIds,
              ),
            )
            .toList(growable: false);
        _mockDetails[id] = ProcurementRequestDetail(
          request: summary,
          lines: lines,
          activity: const <ProcurementActivityEvent>[],
        );
        created.add(summary);
      }
      _mockQueueRows.clear();
      return created;
    }

    final response = await _client.post(
      Uri.parse('$baseUrl/api/procurement-requests'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{
        'selections': rows
            .map(
              (row) => <String, dynamic>{
                'supplierName': row.supplierName,
                'materialBarcode': row.materialBarcode,
                'requestedQty': row.uncoveredQty,
              },
            )
            .toList(growable: false),
      }),
    );
    final payload = _decode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw ProcurementApiException(
        payload['error'] as String? ?? 'Failed to create draft requests.',
      );
    }
    return (payload['requests'] as List<dynamic>? ?? const <dynamic>[])
        .map(
          (entry) => ProcurementRequestSummaryDto.fromJson(
            entry as Map<String, dynamic>,
          ).toDomain(),
        )
        .toList(growable: false);
  }

  @override
  Future<ProcurementRequestDetail> getRequestDetail(int requestId) async {
    if (useMockResponses) {
      final detail = _mockDetails[requestId];
      if (detail == null) {
        throw const ProcurementApiException('Request not found.');
      }
      return detail;
    }
    final response = await _client.get(
      Uri.parse('$baseUrl/api/procurement-requests/$requestId'),
    );
    final payload = _decode(response.body);
    final parsed = ProcurementDetailResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success ||
        parsed.request == null) {
      throw ProcurementApiException(
        parsed.error ?? 'Failed to fetch request detail.',
      );
    }
    return ProcurementRequestDetail(
      request: parsed.request!.toDomain(),
      lines: parsed.lines
          .map((line) => line.toDomain())
          .toList(growable: false),
      activity: parsed.activity
          .map((entry) => entry.toDomain())
          .toList(growable: false),
    );
  }

  @override
  Future<ProcurementRequestSummary> updateRequest({
    required int requestId,
    String? expectedDate,
    String? notes,
  }) async {
    if (useMockResponses) {
      final idx = _mockRequests.indexWhere((entry) => entry.id == requestId);
      if (idx == -1) {
        throw const ProcurementApiException('Request not found.');
      }
      final updated = ProcurementRequestSummary(
        id: _mockRequests[idx].id,
        requestNumber: _mockRequests[idx].requestNumber,
        supplierName: _mockRequests[idx].supplierName,
        status: _mockRequests[idx].status,
        lineCount: _mockRequests[idx].lineCount,
        totalRequestedQty: _mockRequests[idx].totalRequestedQty,
        totalReceivedQty: _mockRequests[idx].totalReceivedQty,
        totalPendingQty: _mockRequests[idx].totalPendingQty,
        expectedDate: expectedDate ?? _mockRequests[idx].expectedDate,
        notes: notes ?? _mockRequests[idx].notes,
      );
      _mockRequests[idx] = updated;
      final detail = _mockDetails[requestId];
      if (detail != null) {
        _mockDetails[requestId] = ProcurementRequestDetail(
          request: updated,
          lines: detail.lines,
          activity: detail.activity,
        );
      }
      return updated;
    }
    final response = await _client.patch(
      Uri.parse('$baseUrl/api/procurement-requests/$requestId'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{
        'expectedDate': expectedDate,
        'notes': notes,
      }),
    );
    final payload = _decode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw ProcurementApiException(
        payload['error'] as String? ?? 'Failed to update request.',
      );
    }
    return ProcurementRequestSummaryDto.fromJson(
      payload['request'] as Map<String, dynamic>? ?? const <String, dynamic>{},
    ).toDomain();
  }

  @override
  Future<ProcurementRequestSummary> raiseRequest(int requestId) {
    return _requestLifecycleAction(requestId, 'raise');
  }

  @override
  Future<ProcurementRequestSummary> cancelRequest({
    required int requestId,
    required String reason,
  }) async {
    if (useMockResponses) {
      final idx = _mockRequests.indexWhere((entry) => entry.id == requestId);
      if (idx == -1) {
        throw const ProcurementApiException('Request not found.');
      }
      final updated = ProcurementRequestSummary(
        id: _mockRequests[idx].id,
        requestNumber: _mockRequests[idx].requestNumber,
        supplierName: _mockRequests[idx].supplierName,
        status: 'cancelled',
        lineCount: _mockRequests[idx].lineCount,
        totalRequestedQty: _mockRequests[idx].totalRequestedQty,
        totalReceivedQty: _mockRequests[idx].totalReceivedQty,
        totalPendingQty: _mockRequests[idx].totalPendingQty,
        expectedDate: _mockRequests[idx].expectedDate,
        notes: _mockRequests[idx].notes,
      );
      _mockRequests[idx] = updated;
      final detail = _mockDetails[requestId];
      if (detail != null) {
        _mockDetails[requestId] = ProcurementRequestDetail(
          request: updated,
          lines: detail.lines,
          activity: detail.activity,
        );
      }
      return updated;
    }
    final response = await _client.post(
      Uri.parse('$baseUrl/api/procurement-requests/$requestId/cancel'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{'reason': reason}),
    );
    final payload = _decode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw ProcurementApiException(
        payload['error'] as String? ?? 'Failed to cancel request.',
      );
    }
    return ProcurementRequestSummaryDto.fromJson(
      payload['request'] as Map<String, dynamic>? ?? const <String, dynamic>{},
    ).toDomain();
  }

  @override
  Future<ProcurementRequestSummary> closeRequest(int requestId) {
    return _requestLifecycleAction(requestId, 'close');
  }

  @override
  Future<ProcurementRequestDetail> receiveRequestLines({
    required int requestId,
    required List<ProcurementReceiveLineInput> lines,
  }) async {
    if (useMockResponses) {
      final detail = _mockDetails[requestId];
      if (detail == null) {
        throw const ProcurementApiException('Request not found.');
      }
      final updatedLines = detail.lines
          .map((line) {
            final input = lines
                .where((entry) => entry.requestLineId == line.id)
                .firstOrNull;
            if (input == null) {
              return line;
            }
            final nextReceived = line.receivedQty + input.receivedQty;
            final nextPending = (line.requestedQty - nextReceived)
                .clamp(0, double.infinity)
                .toDouble();
            final status = nextPending <= 0 ? 'closed' : 'partially_received';
            return ProcurementRequestLine(
              id: line.id,
              procurementRequestId: line.procurementRequestId,
              materialBarcode: line.materialBarcode,
              materialName: line.materialName,
              requestedQty: line.requestedQty,
              receivedQty: nextReceived,
              pendingQty: nextPending,
              unitId: line.unitId,
              unitSymbol: line.unitSymbol,
              status: status,
              linkedOrderCount: line.linkedOrderCount,
              linkedRequirementCount: line.linkedRequirementCount,
              linkedOrderIds: line.linkedOrderIds,
            );
          })
          .toList(growable: false);
      final totalRequested = updatedLines.fold<double>(
        0,
        (sum, line) => sum + line.requestedQty,
      );
      final totalReceived = updatedLines.fold<double>(
        0,
        (sum, line) => sum + line.receivedQty,
      );
      final totalPending = updatedLines.fold<double>(
        0,
        (sum, line) => sum + line.pendingQty,
      );
      final status = totalPending <= 0
          ? 'closed'
          : totalReceived > 0
          ? 'partially_received'
          : detail.request.status;
      final summary = ProcurementRequestSummary(
        id: detail.request.id,
        requestNumber: detail.request.requestNumber,
        supplierName: detail.request.supplierName,
        status: status,
        lineCount: updatedLines.length,
        totalRequestedQty: totalRequested,
        totalReceivedQty: totalReceived,
        totalPendingQty: totalPending,
        expectedDate: detail.request.expectedDate,
        notes: detail.request.notes,
      );
      _mockDetails[requestId] = ProcurementRequestDetail(
        request: summary,
        lines: updatedLines,
        activity: detail.activity,
      );
      final idx = _mockRequests.indexWhere((entry) => entry.id == requestId);
      if (idx != -1) {
        _mockRequests[idx] = summary;
      }
      return _mockDetails[requestId]!;
    }
    final response = await _client.post(
      Uri.parse('$baseUrl/api/procurement-requests/$requestId/receive'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{
        'lines': lines
            .map(
              (line) => <String, dynamic>{
                'requestLineId': line.requestLineId,
                'receivedQty': line.receivedQty,
                'note': line.note,
              },
            )
            .toList(growable: false),
      }),
    );
    final payload = _decode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw ProcurementApiException(
        payload['error'] as String? ?? 'Failed to receive materials.',
      );
    }
    return getRequestDetail(requestId);
  }

  Future<ProcurementRequestSummary> _requestLifecycleAction(
    int requestId,
    String action,
  ) async {
    if (useMockResponses) {
      final idx = _mockRequests.indexWhere((entry) => entry.id == requestId);
      if (idx == -1) {
        throw const ProcurementApiException('Request not found.');
      }
      final nextStatus = switch (action) {
        'raise' => 'raised',
        'close' => 'closed',
        _ => _mockRequests[idx].status,
      };
      final updated = ProcurementRequestSummary(
        id: _mockRequests[idx].id,
        requestNumber: _mockRequests[idx].requestNumber,
        supplierName: _mockRequests[idx].supplierName,
        status: nextStatus,
        lineCount: _mockRequests[idx].lineCount,
        totalRequestedQty: _mockRequests[idx].totalRequestedQty,
        totalReceivedQty: _mockRequests[idx].totalReceivedQty,
        totalPendingQty: _mockRequests[idx].totalPendingQty,
        expectedDate: _mockRequests[idx].expectedDate,
        notes: _mockRequests[idx].notes,
      );
      _mockRequests[idx] = updated;
      final detail = _mockDetails[requestId];
      if (detail != null) {
        _mockDetails[requestId] = ProcurementRequestDetail(
          request: updated,
          lines: detail.lines,
          activity: detail.activity,
        );
      }
      return updated;
    }
    final response = await _client.post(
      Uri.parse('$baseUrl/api/procurement-requests/$requestId/$action'),
      headers: const {'Content-Type': 'application/json'},
    );
    final payload = _decode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw ProcurementApiException(
        payload['error'] as String? ?? 'Request action failed.',
      );
    }
    return ProcurementRequestSummaryDto.fromJson(
      payload['request'] as Map<String, dynamic>? ?? const <String, dynamic>{},
    ).toDomain();
  }

  Map<String, dynamic> _decode(String body) {
    if (body.trim().isEmpty) {
      return const <String, dynamic>{
        'success': false,
        'error': 'Empty server response.',
      };
    }
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return const <String, dynamic>{
      'success': false,
      'error': 'Unexpected server response format.',
    };
  }
}

class ProcurementApiException implements Exception {
  const ProcurementApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

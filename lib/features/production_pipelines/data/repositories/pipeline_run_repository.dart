import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/node_run_status.dart';
import '../../domain/pipeline_run.dart';
import '../../domain/pipeline_template.dart';

abstract class PipelineRunRepository {
  Future<List<PipelineTemplate>> getTemplates();
  Future<PipelineTemplate> createTemplate(PipelineTemplate template);
  Future<PipelineTemplate> updateTemplate(PipelineTemplate template);
  Future<PipelineTemplate?> getTemplate(String id);
  Future<List<PipelineRun>> getRuns({String? templateId});
  Future<PipelineRun> createRun(String templateId, {String? name});
  Future<PipelineRun?> getRun(String id);
  Future<PipelineRun> updateNodeStatus({
    required String runId,
    required String nodeId,
    required NodeRunStatus status,
    double? actualDurationHours,
    int? batchQuantity,
    String? machineOverride,
  });
  Future<PipelineRun> attachBarcodeToRunNode({
    required String runId,
    required String nodeId,
    required String barcode,
  });
}

class ApiPipelineRunRepository implements PipelineRunRepository {
  ApiPipelineRunRepository({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  @override
  Future<List<PipelineTemplate>> getTemplates() async {
    final uri = Uri.parse('$baseUrl/templates');
    final response = await _client.get(uri);
    final payload = _decodeJson(response.body) as Map<String, dynamic>;
    _ensureSuccess(response.statusCode, payload, 'Failed to fetch templates.');
    return (payload['templates'] as List<dynamic>? ?? const [])
        .map((item) => PipelineTemplate.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<PipelineTemplate> createTemplate(PipelineTemplate template) async {
    final uri = Uri.parse('$baseUrl/templates');
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(template.toJson()),
    );
    final payload = _decodeJson(response.body) as Map<String, dynamic>;
    _ensureSuccess(response.statusCode, payload, 'Failed to create template.');
    return PipelineTemplate.fromJson(
      payload['template'] as Map<String, dynamic>,
    );
  }

  @override
  Future<PipelineTemplate> updateTemplate(PipelineTemplate template) async {
    final uri = Uri.parse('$baseUrl/templates/${template.id}');
    final response = await _client.put(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(template.toJson()),
    );
    final payload = _decodeJson(response.body) as Map<String, dynamic>;
    _ensureSuccess(response.statusCode, payload, 'Failed to update template.');
    return PipelineTemplate.fromJson(
      payload['template'] as Map<String, dynamic>,
    );
  }

  @override
  Future<PipelineTemplate?> getTemplate(String id) async {
    final uri = Uri.parse('$baseUrl/templates/$id');
    final response = await _client.get(uri);
    final payload = _decodeJson(response.body) as Map<String, dynamic>;
    if (response.statusCode == 404) {
      return null;
    }
    _ensureSuccess(response.statusCode, payload, 'Failed to fetch template.');
    return PipelineTemplate.fromJson(
      payload['template'] as Map<String, dynamic>,
    );
  }

  @override
  Future<List<PipelineRun>> getRuns({String? templateId}) async {
    final uri = Uri.parse(
      templateId == null
          ? '$baseUrl/runs'
          : '$baseUrl/runs?template_id=$templateId',
    );
    final response = await _client.get(uri);
    final payload = _decodeJson(response.body) as Map<String, dynamic>;
    _ensureSuccess(response.statusCode, payload, 'Failed to fetch runs.');
    return (payload['runs'] as List<dynamic>? ?? const [])
        .map((item) => PipelineRun.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<PipelineRun> createRun(String templateId, {String? name}) async {
    final uri = Uri.parse('$baseUrl/runs');
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'templateId': templateId, 'name': name}),
    );
    final payload = _decodeJson(response.body) as Map<String, dynamic>;
    _ensureSuccess(response.statusCode, payload, 'Failed to create run.');
    return PipelineRun.fromJson(payload['run'] as Map<String, dynamic>);
  }

  @override
  Future<PipelineRun?> getRun(String id) async {
    final uri = Uri.parse('$baseUrl/runs/$id');
    final response = await _client.get(uri);
    final payload = _decodeJson(response.body) as Map<String, dynamic>;
    if (response.statusCode == 404) {
      return null;
    }
    _ensureSuccess(response.statusCode, payload, 'Failed to fetch run.');
    return PipelineRun.fromJson(payload['run'] as Map<String, dynamic>);
  }

  @override
  Future<PipelineRun> updateNodeStatus({
    required String runId,
    required String nodeId,
    required NodeRunStatus status,
    double? actualDurationHours,
    int? batchQuantity,
    String? machineOverride,
  }) async {
    final uri = Uri.parse('$baseUrl/runs/$runId/node-status');
    final response = await _client.put(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'nodeId': nodeId,
        'status': status.value,
        'actualDurationHours': actualDurationHours,
        'batchQuantity': batchQuantity,
        'machineOverride': machineOverride,
      }),
    );
    final payload = _decodeJson(response.body) as Map<String, dynamic>;
    _ensureSuccess(
      response.statusCode,
      payload,
      'Failed to update run node status.',
    );
    return PipelineRun.fromJson(payload['run'] as Map<String, dynamic>);
  }

  @override
  Future<PipelineRun> attachBarcodeToRunNode({
    required String runId,
    required String nodeId,
    required String barcode,
  }) async {
    final uri = Uri.parse('$baseUrl/runs/$runId/barcodes');
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'nodeId': nodeId, 'barcode': barcode}),
    );
    final payload = _decodeJson(response.body) as Map<String, dynamic>;
    _ensureSuccess(
      response.statusCode,
      payload,
      'Failed to attach barcode to run node.',
    );
    return PipelineRun.fromJson(payload['run'] as Map<String, dynamic>);
  }

  void _ensureSuccess(
    int statusCode,
    Map<String, dynamic> payload,
    String fallback,
  ) {
    if (statusCode < 200 || statusCode >= 300 || payload['success'] != true) {
      throw PipelineApiException(payload['error'] as String? ?? fallback);
    }
  }

  Object? _decodeJson(String body) {
    if (body.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(body);
    } on FormatException {
      return {
        'success': false,
        'error': body.trim().isEmpty
            ? 'Unexpected response from server.'
            : body.trim(),
      };
    }
  }
}

class PipelineApiException implements Exception {
  const PipelineApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

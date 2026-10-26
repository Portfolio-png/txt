import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/part_route.dart';
import '../domain/process_stage.dart';

class ProcessRouteException implements Exception {
  ProcessRouteException(this.message, {this.code = ''});

  final String message;

  /// The server's machine-readable reason (`route_stage_repeated`,
  /// `route_seq_gap`, …). Kept so a view can mark the offending control
  /// instead of only printing a sentence.
  final String code;

  @override
  String toString() => message;
}

/// The save was refused because the part's route is already active, and an
/// active route is never edited in place.
///
/// Carries the route to version, because "declare a new version" is only a
/// reasonable thing to ask of someone who can see which one.
class RouteActiveException extends ProcessRouteException {
  RouteActiveException(super.message, {required this.routeId, required this.version})
      : super(code: 'route_active');

  final int routeId;
  final int version;
}

/// The client for process routing.
///
/// Mirrors `VariationTreeService`, including its mock mode, because the two
/// features have the same shape: a structure on a master, fixed once declared,
/// changed by versioning rather than editing.
class ProcessRouteService {
  ProcessRouteService({
    http.Client? client,
    required this.baseUrl,
    this.useMockResponses = false,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final bool useMockResponses;

  /// Demo builds keep routes in memory, so the ribbon works with no backend.
  final Map<int, List<PartRoute>> _mock = {};
  int _mockSeq = 1;

  static const List<ProcessStage> _mockStages = [
    ProcessStage(id: 1, code: 'die', name: 'Die', position: 1),
    ProcessStage(id: 2, code: 'shearing', name: 'Shearing', position: 2),
    ProcessStage(id: 3, code: 'cutting', name: 'Cutting', position: 3),
    ProcessStage(id: 4, code: 'riveting', name: 'Riveting', position: 4),
    ProcessStage(id: 5, code: 'assembly', name: 'Assembly', position: 5),
    ProcessStage(id: 7, code: 'packing', name: 'Packing', position: 6),
    ProcessStage(id: 6, code: 'barcode', name: 'Barcode', position: 7),
    ProcessStage(id: 8, code: 'billing', name: 'Billing', position: 8),
    ProcessStage(id: 9, code: 'delivery', name: 'Delivery', position: 9),
  ];

  /// The demo master, which grows when someone adds a stage.
  late final List<ProcessStage> _mockStageList = [..._mockStages];

  Future<List<ProcessStage>> stages({bool includeInactive = false}) async {
    if (useMockResponses) return List.unmodifiable(_mockStageList);
    final payload = await _get(
      '/api/process-stages${includeInactive ? '?includeInactive=true' : ''}',
    );
    return [
      for (final entry in (payload['stages'] as List?) ?? const [])
        if (entry is Map<String, dynamic>) ?ProcessStage.fromJson(entry),
    ];
  }

  /// Adds a stage to the factory's master by name alone, and answers it.
  ///
  /// A name already in the master (in any case) answers THAT stage — the
  /// server says 409 `stage_exists` and hands it back — so typing a stage that
  /// somebody already made never makes a second one.
  Future<ProcessStage> createStage(String name) async {
    final clean = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) {
      throw ProcessRouteException('A stage needs a name.', code: 'stage_name_required');
    }
    if (useMockResponses) {
      for (final stage in _mockStageList) {
        if (stage.name.toLowerCase() == clean.toLowerCase()) return stage;
      }
      final made = ProcessStage(
        id: _mockStageList.fold<int>(0, (max, s) => s.id > max ? s.id : max) + 1,
        code: clean.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-'),
        name: clean,
        position: _mockStageList.fold<int>(
              0,
              (max, s) => s.position > max ? s.position : max,
            ) +
            1,
      );
      _mockStageList.add(made);
      return made;
    }
    final payload = await _post('/api/process-stages', {'name': clean});
    final raw = payload['stage'];
    final stage = raw is Map<String, dynamic> ? ProcessStage.fromJson(raw) : null;
    if (stage == null) {
      throw ProcessRouteException('The server did not send the stage back.');
    }
    return stage;
  }

  /// Every version of a part's route, active first then newest.
  Future<List<PartRoute>> routesFor(int partId) async {
    if (useMockResponses) return _mock[partId] ?? const [];
    final payload = await _get('/api/items/$partId/routes');
    return _readRoutes(payload);
  }

  /// The one route a shop floor cares about, or null if the part has none.
  Future<PartRoute?> activeRoute(int partId) async {
    final routes = await routesFor(partId);
    for (final route in routes) {
      if (route.isActive) return route;
    }
    return null;
  }

  /// Save a route. `status` is 'active' for a real route and 'draft' for a
  /// planner's work in progress.
  ///
  /// Throws [RouteActiveException] rather than silently versioning: replacing
  /// a live route is a decision somebody makes, not a side effect of saving.
  Future<List<PartRoute>> save(
    int partId,
    List<RouteStep> steps, {
    String status = 'active',
    String note = '',
  }) async {
    if (useMockResponses) return _mockSave(partId, steps, status: status, note: note);
    final payload = await _post('/api/items/$partId/routes', {
      'steps': [for (final step in steps) step.toJson()],
      'status': status,
      if (note.trim().isNotEmpty) 'note': note.trim(),
    });
    return _readRoutes(payload);
  }

  /// Declare a new version. The previous active route is retired, not edited
  /// and not deleted, so jobs that already ran keep their history.
  Future<List<PartRoute>> declareVersion(
    int partId,
    List<RouteStep> steps, {
    String note = '',
  }) async {
    if (useMockResponses) {
      final existing = [..._mock[partId] ?? const <PartRoute>[]];
      _mock[partId] = [
        for (final route in existing)
          if (route.isActive)
            PartRoute(
              id: route.id,
              partId: route.partId,
              version: route.version,
              status: RouteStatus.retired,
              note: route.note,
              steps: route.steps,
            )
          else
            route,
      ];
      return _mockSave(partId, steps, status: 'active', note: note);
    }
    final payload = await _post('/api/items/$partId/routes/versions', {
      'steps': [for (final step in steps) step.toJson()],
      if (note.trim().isNotEmpty) 'note': note.trim(),
    });
    return _readRoutes(payload);
  }

  List<PartRoute> _readRoutes(Map<String, dynamic> payload) => [
        for (final entry in (payload['routes'] as List?) ?? const [])
          if (entry is Map<String, dynamic>) ?PartRoute.fromJson(entry),
      ];

  List<PartRoute> _mockSave(
    int partId,
    List<RouteStep> steps, {
    required String status,
    required String note,
  }) {
    final existing = [..._mock[partId] ?? const <PartRoute>[]];
    if (status == 'active' && existing.any((r) => r.isActive)) {
      final live = existing.firstWhere((r) => r.isActive);
      throw RouteActiveException(
        'This part already has an active route. Declare a new version to change it.',
        routeId: live.id,
        version: live.version,
      );
    }
    final version = existing.fold<int>(0, (max, r) => r.version > max ? r.version : max) + 1;
    existing.add(PartRoute(
      id: _mockSeq++,
      partId: partId,
      version: version,
      status: RouteStatus.parse(status),
      note: note,
      steps: [
        for (var i = 0; i < steps.length; i += 1)
          RouteStep(
            stageId: steps[i].stageId,
            seq: i + 1,
            stageCode: _mockStageList
                .where((s) => s.id == steps[i].stageId)
                .map((s) => s.code)
                .firstOrNull ??
                '',
            stageName: _mockStageList
                .where((s) => s.id == steps[i].stageId)
                .map((s) => s.name)
                .firstOrNull ??
                '',
            notes: steps[i].notes,
            machineId: steps[i].machineId,
            dieId: steps[i].dieId,
          ),
      ],
    ));
    existing.sort((a, b) {
      int rank(PartRoute r) => switch (r.status) {
            RouteStatus.active => 0,
            RouteStatus.draft => 1,
            RouteStatus.retired => 2,
          };
      final byStatus = rank(a).compareTo(rank(b));
      return byStatus != 0 ? byStatus : b.version.compareTo(a.version);
    });
    _mock[partId] = existing;
    return existing;
  }

  Future<Map<String, dynamic>> _get(String path) =>
      _request(() => _client.get(Uri.parse('$baseUrl$path')));

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) {
    final uri = Uri.parse('$baseUrl$path');
    return _request(() {
      final request = http.Request('POST', uri)
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);
      return _client.send(request).then(http.Response.fromStream);
    });
  }

  Future<Map<String, dynamic>> _request(
    Future<http.Response> Function() send,
  ) async {
    late final http.Response response;
    try {
      response = await send();
    } catch (error) {
      throw ProcessRouteException('Could not reach the server. ($error)');
    }
    Map<String, dynamic>? payload;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) payload = decoded;
    } catch (_) {
      // No readable body — handled as a plain failure below.
    }
    final message = (payload?['error'] as String?)?.trim();
    final code = (payload?['code'] as String?)?.trim() ?? '';

    if (response.statusCode == 409 && code == 'route_active') {
      throw RouteActiveException(
        message?.isNotEmpty == true
            ? message!
            : 'This part already has an active route.',
        routeId: (payload?['routeId'] as num?)?.toInt() ?? 0,
        version: (payload?['version'] as num?)?.toInt() ?? 0,
      );
    }
    // Not a failure: the stage the caller wanted already exists, and the body
    // carries it.
    if (response.statusCode == 409 &&
        code == 'stage_exists' &&
        payload?['stage'] is Map<String, dynamic>) {
      return payload!;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ProcessRouteException(
        message?.isNotEmpty == true
            ? message!
            : 'The server refused that (${response.statusCode}).',
        code: code,
      );
    }
    if (payload == null || payload['success'] != true) {
      throw ProcessRouteException(
        message?.isNotEmpty == true
            ? message!
            : 'The server sent an answer we could not read.',
        code: code,
      );
    }
    return payload;
  }
}

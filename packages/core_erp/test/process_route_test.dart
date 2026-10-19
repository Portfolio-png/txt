import 'dart:convert';

import 'package:core_erp/features/process_routes/data/process_route_service.dart';
import 'package:core_erp/features/process_routes/domain/part_route.dart';
import 'package:core_erp/features/process_routes/domain/process_stage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

// Process routing on the client side.
//
// The rules themselves are the backend's (backend/test/process-routes.test.js);
// what is asserted here is that this side reads the server's shape correctly,
// sends the shape the server asked for, and turns a refusal into something a
// view can act on rather than a bare string.

/// Answers a fixed body, and records what was sent so the payload can be
/// asserted — the one thing a mock-mode test cannot check.
class _Recorder extends http.BaseClient {
  _Recorder(this.body, {this.status = 200});

  final Map<String, dynamic> body;
  final int status;
  final List<Map<String, dynamic>> sent = [];
  final List<String> paths = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    paths.add(request.url.path + (request.url.hasQuery ? '?${request.url.query}' : ''));
    if (request is http.Request && request.body.isNotEmpty) {
      sent.add(jsonDecode(request.body) as Map<String, dynamic>);
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      status,
      request: request,
    );
  }
}

void main() {
  group('ProcessStage', () {
    test('reads SQLite 0/1 flags and real booleans the same way', () {
      final fromDb = ProcessStage.fromJson({
        'id': 3,
        'code': 'cutting',
        'name': 'Cutting',
        'position': 3,
        'repeatable': 1,
        'active': 1,
      })!;
      expect(fromDb.repeatable, isTrue);
      expect(fromDb.active, isTrue);

      final fromJson = ProcessStage.fromJson({
        'id': 4,
        'code': 'riveting',
        'name': 'Riveting',
        'repeatable': false,
        'active': true,
      })!;
      expect(fromJson.repeatable, isFalse);
      expect(fromJson.active, isTrue);

      // A stage with no id is not a stage. Dropping it beats a 0 that reads
      // as a real row everywhere downstream.
      expect(ProcessStage.fromJson({'code': 'x'}), isNull);
      // Absent `active` means active: a master row that arrives without the
      // column should not vanish from every picker.
      expect(ProcessStage.fromJson({'id': 1, 'name': 'Die'})!.active, isTrue);
    });
  });

  group('PartRoute', () {
    test('reads the server shape, snake_case included', () {
      final route = PartRoute.fromJson({
        'id': 7,
        'part_id': 48,
        'version': 2,
        'status': 'active',
        'note': 'added packing',
        'steps': [
          {'seq': 1, 'stage_id': 1, 'stage_code': 'die', 'stage_name': 'Die', 'notes': ''},
          {'seq': 2, 'stage_id': 2, 'stage_code': 'shearing', 'stage_name': 'Shearing', 'die_id': 5},
        ],
      })!;
      expect(route.partId, 48);
      expect(route.version, 2);
      expect(route.status, RouteStatus.active);
      expect(route.isLocked, isTrue, reason: 'an active route is never edited in place');
      expect(route.steps.map((s) => s.stageName), ['Die', 'Shearing']);
      expect(route.steps.last.dieId, 5);
    });

    test('an unknown status reads as draft, never as active', () {
      // Getting this wrong the other way would put a route nobody declared on
      // a shop floor, so the fallback is the harmless one.
      expect(RouteStatus.parse('live'), RouteStatus.draft);
      expect(RouteStatus.parse(null), RouteStatus.draft);
      expect(RouteStatus.parse('RETIRED'), RouteStatus.retired);
    });

    test('a step sends its stage id and omits seq', () async {
      // seq is the server's to assign, from list order. Sending it too would
      // be two sources of truth about one ordering.
      final json = const RouteStep(stageId: 3, seq: 9, notes: '  ').toJson();
      expect(json, {'stageId': 3});
      expect(json.containsKey('seq'), isFalse);

      final full = const RouteStep(stageId: 3, notes: 'two passes', dieId: 4).toJson();
      expect(full, {'stageId': 3, 'notes': 'two passes', 'dieId': 4});
    });

    test('a step can name itself without the stage master loaded', () {
      const stages = [ProcessStage(id: 2, code: 'shearing', name: 'Shearing')];
      expect(const RouteStep(stageId: 2).labelWith(stages), 'Shearing');
      expect(const RouteStep(stageId: 99).labelWith(stages), 'Stage 99');
    });
  });

  group('ProcessRouteService', () {
    test('posts an ordered list of stage ids to the part', () async {
      final recorder = _Recorder({'success': true, 'routes': []});
      final service = ProcessRouteService(client: recorder, baseUrl: 'http://x');

      await service.save(48, const [
        RouteStep(stageId: 1),
        RouteStep(stageId: 2),
        RouteStep(stageId: 9),
      ]);

      expect(recorder.paths.single, '/api/items/48/routes');
      expect(recorder.sent.single['steps'], [
        {'stageId': 1},
        {'stageId': 2},
        {'stageId': 9},
      ]);
      expect(recorder.sent.single['status'], 'active');
    });

    test('a 409 on an active route carries the route to version', () async {
      final recorder = _Recorder({
        'success': false,
        'error': 'This part already has an active route. Declare a new version to change it.',
        'code': 'route_active',
        'routeId': 11,
        'version': 3,
      }, status: 409);
      final service = ProcessRouteService(client: recorder, baseUrl: 'http://x');

      // Not a plain exception: a view has to be able to offer "declare v4"
      // without parsing the sentence.
      await expectLater(
        service.save(48, const [RouteStep(stageId: 1)]),
        throwsA(isA<RouteActiveException>()
            .having((e) => e.routeId, 'routeId', 11)
            .having((e) => e.version, 'version', 3)
            .having((e) => e.code, 'code', 'route_active')),
      );
    });

    test('a refusal keeps the server’s machine-readable reason', () async {
      final recorder = _Recorder({
        'success': false,
        'error': 'Die is already in this route and cannot repeat.',
        'code': 'route_stage_repeated',
      }, status: 400);
      final service = ProcessRouteService(client: recorder, baseUrl: 'http://x');

      await expectLater(
        service.save(48, const [RouteStep(stageId: 1), RouteStep(stageId: 1)]),
        throwsA(isA<ProcessRouteException>()
            .having((e) => e.code, 'code', 'route_stage_repeated')),
      );
    });

    test('versioning posts to the versions endpoint', () async {
      final recorder = _Recorder({'success': true, 'routes': []});
      final service = ProcessRouteService(client: recorder, baseUrl: 'http://x');
      await service.declareVersion(48, const [RouteStep(stageId: 1)], note: 'added packing');
      expect(recorder.paths.single, '/api/items/48/routes/versions');
      expect(recorder.sent.single['note'], 'added packing');
    });

    test('mock mode mirrors the server: v1 active, then a refusal, then v2', () async {
      final service = ProcessRouteService(baseUrl: '', useMockResponses: true);
      expect(await service.routesFor(48), isEmpty);
      expect((await service.stages()).map((s) => s.code).take(2), ['die', 'shearing']);

      final saved = await service.save(48, const [
        RouteStep(stageId: 1),
        RouteStep(stageId: 2),
      ]);
      expect(saved.single.version, 1);
      expect(saved.single.status, RouteStatus.active);
      expect(saved.single.steps.map((s) => s.seq), [1, 2]);
      expect(saved.single.steps.map((s) => s.stageName), ['Die', 'Shearing']);

      await expectLater(
        service.save(48, const [RouteStep(stageId: 1)]),
        throwsA(isA<RouteActiveException>()),
      );

      final versioned = await service.declareVersion(48, const [
        RouteStep(stageId: 1),
        RouteStep(stageId: 2),
        RouteStep(stageId: 7),
      ]);
      // Active first, and v1 retired rather than rewritten.
      expect(versioned.first.version, 2);
      expect(versioned.first.status, RouteStatus.active);
      final v1 = versioned.firstWhere((r) => r.version == 1);
      expect(v1.status, RouteStatus.retired);
      expect(v1.steps.length, 2, reason: 'the old version keeps the steps it had');
      expect(await service.activeRoute(48), isNotNull);
      expect((await service.activeRoute(48))!.version, 2);
    });
  });
}

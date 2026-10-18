import 'dart:convert';
import 'dart:io';

import 'package:core_erp/features/inventory/data/models/api_models.dart';
import 'package:core_erp/features/inventory/data/repositories/api_inventory_repository.dart';
import 'package:core_erp/features/inventory/domain/inventory_set_definition.dart';
import 'package:flutter_test/flutter_test.dart';

/// A set is filed under a group through the entity_links graph, not a column of
/// its own, so the group travels on the set's payload as `groupId`/`groupName`.
///
/// The thing worth pinning is the tri-state on the way out. `saveInventorySet`
/// on the backend is a full replace, but the "add spawned items to a set" path
/// in the items master sends a name and lines only. So an absent key has to
/// mean "leave the group alone" and a present null has to mean "clear it" — and
/// that distinction only exists if the client omits the key rather than sending
/// null. Asserting on the value would pass either way; these assert on
/// presence.

Map<String, Object?> _setPayload({Object? groupId, String? groupName}) {
  return <String, Object?>{
    'id': 7,
    'name': 'Bathroom Kit',
    'totalItemCount': 3,
    'createdAt': '2026-01-02T03:04:05.000Z',
    'updatedAt': '2026-01-02T03:04:05.000Z',
    'lines': const <Map<String, Object?>>[],
    if (groupId != null) 'groupId': groupId,
    if (groupName != null) 'groupName': groupName,
  };
}

void main() {
  group('InventorySetDto', () {
    test('reads the group the set is filed under', () {
      final dto = InventorySetDto.fromJson(
        _setPayload(groupId: 4, groupName: 'Ash Trays'),
      );
      expect(dto.groupId, 4);
      expect(dto.groupName, 'Ash Trays');
      expect(dto.groupIsArchived, isFalse);

      final domain = dto.toDomain();
      expect(domain.groupId, 4);
      expect(domain.groupName, 'Ash Trays');
    });

    test('reads a set nobody filed, and a payload that predates grouping', () {
      final unfiled = InventorySetDto.fromJson(_setPayload());
      expect(unfiled.groupId, isNull);
      expect(unfiled.groupName, isNull);
      expect(unfiled.groupIsArchived, isFalse);
      expect(unfiled.toDomain().groupId, isNull);
    });

    test('carries the archived flag so a retired group can be marked', () {
      final dto = InventorySetDto.fromJson(<String, Object?>{
        ..._setPayload(groupId: 9, groupName: 'Retired'),
        'groupIsArchived': true,
      });
      expect(dto.groupIsArchived, isTrue);
      expect(dto.toDomain().groupIsArchived, isTrue);
    });
  });

  group('saveSet request body', () {
    late HttpServer server;
    late List<Map<String, dynamic>> captured;
    late ApiInventoryRepository repository;

    setUp(() async {
      captured = <Map<String, dynamic>>[];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        captured.add(jsonDecode(body) as Map<String, dynamic>);
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{
            'success': true,
            'set': _setPayload(groupId: 4, groupName: 'Ash Trays'),
            'error': null,
          }),
        );
        await request.response.close();
      });
      repository = ApiInventoryRepository(
        baseUrl: 'http://127.0.0.1:${server.port}',
        useMockResponses: false,
      );
    });

    tearDown(() async {
      await server.close(force: true);
    });

    Future<void> save({
      int? groupId,
      bool specified = false,
      int? expectedVersion,
    }) {
      return repository.saveSet(
        SaveInventorySetInput(
          id: 7,
          name: 'Bathroom Kit',
          groupId: groupId,
          groupIdSpecified: specified,
          expectedVersion: expectedVersion,
          lines: const <SaveInventorySetLineInput>[
            SaveInventorySetLineInput(
              itemId: 1,
              variationLeafNodeId: 2,
              quantity: 1,
              position: 0,
            ),
          ],
        ),
      );
    }

    test('a save that says nothing about the group omits the key', () async {
      await save();
      expect(captured.single.containsKey('groupId'), isFalse);
    });

    test('clearing the group sends the key as null', () async {
      await save(groupId: null, specified: true);
      expect(captured.single.containsKey('groupId'), isTrue);
      expect(captured.single['groupId'], isNull);
    });

    test('filing the set sends the group id', () async {
      await save(groupId: 4, specified: true);
      expect(captured.single['groupId'], 4);
    });

    test('a caller that knows the version it opened at sends it', () async {
      await save(expectedVersion: 3);
      expect(captured.single['expectedVersion'], 3);
    });

    test('a caller that does not know omits the key, so nothing is checked', () async {
      // Absent is how the create path and every pre-version caller say "I
      // cannot tell you" — sending null would read as a version of its own.
      await save();
      expect(captured.single.containsKey('expectedVersion'), isFalse);
    });
  });

  group('InventorySetDto version', () {
    test('round-trips, and defaults to 0 on a payload that predates it', () {
      expect(
        InventorySetDto.fromJson(<String, Object?>{
          ..._setPayload(),
          'version': 4,
        }).version,
        4,
      );
      expect(InventorySetDto.fromJson(_setPayload()).version, 0);
      expect(
        InventorySetDto.fromJson(<String, Object?>{
          ..._setPayload(),
          'version': 4,
        }).toDomain().version,
        4,
      );
    });
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:paper/features/dies/data/api_die_repository.dart';
import 'package:paper/features/dies/domain/die.dart';

// A new die has no id yet. It was sent as '' and the server's save, which
// takes an integer or nothing (since 2026-11-19), refused every new die with
// "id must be a number" — on the item sheet and the Dies screen alike.

Die _die(String id) => Die(
  id: id,
  name: 'CDATP48',
  toolCode: 'CDATP48',
  photoUrls: const [],
  operationalNotes: '',
  compatibleMachineGroupIds: const [],
  status: DieStatus.ready,
  ownership: DieOwnership.inHouse,
  createdAt: DateTime(2026, 11, 24),
  updatedAt: DateTime(2026, 11, 24),
);

void main() {
  Future<Map<String, dynamic>> sent(Die die) async {
    late Map<String, dynamic> body;
    final client = MockClient((request) async {
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({'success': true, 'die': {...body, 'id': '7'}, 'error': null}),
        200,
      );
    });
    final repo = ApiDieRepository(client: client, baseUrl: 'http://x', useMockResponses: false);
    await repo.saveDie(die);
    return body;
  }

  test('a new die goes without an id; a saved one with its number', () async {
    expect((await sent(_die('')))['id'], isNull);
    expect((await sent(_die('31')))['id'], 31);
  });
}

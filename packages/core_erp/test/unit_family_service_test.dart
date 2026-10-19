import 'dart:convert';

import 'package:core_erp/features/units/data/unit_family_service.dart';
import 'package:core_erp/features/units/domain/quantity.dart';
import 'package:core_erp/features/units/domain/units.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

// Reading the units master as families with real ladders.
//
// Before this, nothing in Dart could build a populated `UnitFamily` — the only
// things that did were literals in units_contract_test.dart — so any code that
// needed to know a gross is 144 wrote 144 down. That is invariant I2's whole
// subject, so the thing worth asserting is that a REAL server payload becomes
// a family whose factors make `Units.format` right.

class _Stub extends http.BaseClient {
  _Stub(this.body, {this.status = 200});

  final Object body;
  final int status;
  int calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls += 1;
    return http.StreamedResponse(
      Stream.value(utf8.encode(body is String ? body as String : jsonEncode(body))),
      status,
      request: request,
    );
  }
}

/// The shape /api/units/families actually sends: `SELECT *` over unit_groups
/// and units, so snake_case, 0/1 for booleans, and `precision` rather than
/// `max_decimals` (that column does not exist).
Map<String, dynamic> get _realPayload => {
      'success': true,
      'error': null,
      'families': [
        {
          'id': 1,
          'name': 'Count',
          'dimension': 'count',
          'code': 'count',
          'integral_only': 1,
          'base_unit_id': 11,
          'units': [
            {
              'id': 11, 'unit_group_id': 1, 'name': 'Piece', 'symbol': 'Pc',
              'factor_to_base': 1, 'is_base': 1, 'on_ladder': 1,
              'uqc': 'NOS', 'precision': 0, 'is_archived': 0,
            },
            {
              'id': 12, 'unit_group_id': 1, 'name': 'Dozen', 'symbol': 'doz',
              'factor_to_base': 12, 'is_base': 0, 'on_ladder': 1,
              'uqc': 'DOZ', 'precision': 2, 'is_archived': 0,
            },
            {
              'id': 13, 'unit_group_id': 1, 'name': 'Gross', 'symbol': 'gro',
              'factor_to_base': 144, 'is_base': 0, 'on_ladder': 1,
              'uqc': 'GRS', 'precision': 2, 'is_archived': 0,
            },
          ],
        },
        {
          'id': 2,
          'name': 'Mass',
          'dimension': 'mass',
          'code': 'mass',
          'integral_only': 0,
          'base_unit_id': 21,
          'units': [
            {
              'id': 21, 'unit_group_id': 2, 'name': 'Milligram', 'symbol': 'mg',
              'factor_to_base': 1, 'is_base': 1, 'on_ladder': 0, 'precision': 0,
            },
            {
              'id': 22, 'unit_group_id': 2, 'name': 'Gram', 'symbol': 'g',
              'factor_to_base': 1000, 'is_base': 0, 'on_ladder': 1, 'precision': 3,
            },
            {
              'id': 23, 'unit_group_id': 2, 'name': 'Kilogram', 'symbol': 'kg',
              'factor_to_base': 1000000, 'is_base': 0, 'on_ladder': 1, 'precision': 3,
            },
          ],
        },
      ],
    };

void main() {
  group('UnitFamilyService', () {
    test('turns the real payload into families with integer factors', () async {
      final service = UnitFamilyService(client: _Stub(_realPayload), baseUrl: 'http://x');
      final families = await service.families();

      expect(families.map((f) => f.code), ['count', 'mass']);

      final count = families.first;
      expect(count.integralOnly, isTrue);
      expect(count.base.symbol, 'Pc');
      // The ladder is sorted by factor and excludes nothing for Count, since
      // piece is on_ladder: 1.
      expect(count.ladder.map((u) => u.factorToBase), [1, 12, 144]);
      expect(count.units.firstWhere((u) => u.symbol == 'gro').uqc, 'GRS');

      final mass = families.last;
      expect(mass.integralOnly, isFalse);
      expect(mass.base.symbol, 'mg');
      // mg is on_ladder: 0, so it is the base but never a display rung.
      expect(mass.ladder.map((u) => u.symbol), ['g', 'kg']);
    });

    test('the factors it reads are the ones Units.format needs', () async {
      // The point of the whole file: a quantity formatted off a FETCHED family
      // must come out the same as one formatted off the hand-written fixture.
      final service = UnitFamilyService(client: _Stub(_realPayload), baseUrl: 'http://x');
      final count = (await service.byCode('count'))!;
      final mass = (await service.byCode('mass'))!;

      expect(Units.format(Quantity(228, count)), '19 doz');
      expect(Units.format(Quantity(288, count)), '2 gro');
      expect(Units.format(Quantity(229, count)), '229 Pc');
      expect(Units.format(Quantity(1250000, mass)), '1.25 kg');

      // And parsing back through a fetched unit is exact.
      final kg = mass.units.firstWhere((u) => u.symbol == 'kg');
      expect(Units.parse('2.080', kg, mass).base, 2080000);
      expect(
        (Units.parse('2.080', kg, mass) - Units.parse('0.842', kg, mass)).base,
        1238000,
        reason: 'integer milligrams, not 2.080 - 0.842 on doubles',
      );
    });

    test('reads precision when max_decimals is absent, because it always is', () async {
      final service = UnitFamilyService(client: _Stub(_realPayload), baseUrl: 'http://x');
      final mass = (await service.byCode('mass'))!;
      expect(mass.units.firstWhere((u) => u.symbol == 'kg').maxDecimals, 3);
      // Count's piece has precision 0 — a zero must survive, not fall back to 4.
      final count = (await service.byCode('count'))!;
      expect(count.base.maxDecimals, 0);
    });

    test('a group that predates migration 051 still reads', () async {
      // `code` and `factor_to_base` arrived with 051. A workspace that has not
      // migrated should degrade to a 1:1 family, not throw or report 0.
      final service = UnitFamilyService(
        client: _Stub({
          'success': true,
          'families': [
            {
              'id': 9,
              'name': 'Primary Group',
              'units': [
                {'id': 90, 'unit_group_id': 9, 'name': 'Primary Unit', 'symbol': '-'},
              ],
            },
          ],
        }),
        baseUrl: 'http://x',
      );
      final family = (await service.families()).single;
      expect(family.code, 'primary group');
      expect(family.units.single.factorToBase, 1, reason: 'never 0 — it divides');
      expect(family.integralOnly, isFalse);
    });

    test('a family with no units is dropped rather than left dividing by nothing', () async {
      final service = UnitFamilyService(
        client: _Stub({
          'success': true,
          'families': [
            {'id': 4, 'name': 'Area', 'code': 'area', 'units': []},
            {'id': 1, 'name': 'Count', 'code': 'count', 'units': [
              {'id': 11, 'name': 'Piece', 'symbol': 'Pc', 'factor_to_base': 1, 'is_base': 1},
            ]},
          ],
        }),
        baseUrl: 'http://x',
      );
      expect((await service.families()).map((f) => f.code), ['count']);
    });

    test('families are fetched once and cached until asked again', () async {
      final stub = _Stub(_realPayload);
      final service = UnitFamilyService(client: stub, baseUrl: 'http://x');
      await service.families();
      await service.families();
      await service.byCode('count');
      expect(stub.calls, 1, reason: 'a factor cannot change without a migration');
      await service.families(refresh: true);
      expect(stub.calls, 2);
    });

    test('a refusal and an unreadable body both raise, not return empty', () async {
      // Empty would read as "this workspace has no units", which is a
      // different and much more alarming fact than "you may not look".
      final refused = UnitFamilyService(
        client: _Stub({'success': false, 'error': 'You do not have permission.'}, status: 403),
        baseUrl: 'http://x',
      );
      await expectLater(refused.families(), throwsA(isA<UnitFamilyException>()));

      final garbled = UnitFamilyService(client: _Stub('<html>nope'), baseUrl: 'http://x');
      await expectLater(garbled.families(), throwsA(isA<UnitFamilyException>()));
    });

    test('mock mode gives a usable Count family with no backend', () async {
      final service = UnitFamilyService(baseUrl: '', useMockResponses: true);
      final count = (await service.byCode('count'))!;
      expect(Units.format(Quantity(228, count)), '19 doz');
      expect(await service.familyOfUnit(6), isNotNull);
      expect((await service.familyOfUnit(6))!.code, 'mass');
      expect(await service.familyOfUnit(4242), isNull);
    });
  });
}

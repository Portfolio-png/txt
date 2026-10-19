import 'package:core_erp/features/units/domain/quantity.dart';
import 'package:core_erp/features/units/domain/unit_family.dart';
import 'package:core_erp/features/units/domain/units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Units Contract & Quantity Math (SKILL.md §9)', () {
    // Canonical Count Family
    const piece = Unit(
      id: 1,
      familyId: 1,
      code: 'pc',
      label: 'Piece',
      symbol: 'Pc',
      factorToBase: 1,
      isBase: true,
      onLadder: true,
      uqc: 'NOS',
    );
    const dozen = Unit(
      id: 2,
      familyId: 1,
      code: 'doz',
      label: 'Dozen',
      symbol: 'doz',
      factorToBase: 12,
      isBase: false,
      onLadder: true,
      uqc: 'DOZ',
    );
    const gross = Unit(
      id: 3,
      familyId: 1,
      code: 'gro',
      label: 'Gross',
      symbol: 'gro',
      factorToBase: 144,
      isBase: false,
      onLadder: true,
      uqc: 'GRS',
    );
    final countFamily = UnitFamily(
      id: 1,
      code: 'count',
      name: 'Count',
      dimension: 'count',
      integralOnly: true,
      units: [piece, dozen, gross],
    );

    // Canonical Mass Family
    const mg = Unit(
      id: 10,
      familyId: 2,
      code: 'mg',
      label: 'Milligram',
      symbol: 'mg',
      factorToBase: 1,
      isBase: true,
      onLadder: false,
      uqc: 'MGM',
    );
    const g = Unit(
      id: 11,
      familyId: 2,
      code: 'g',
      label: 'Gram',
      symbol: 'g',
      factorToBase: 1000,
      isBase: false,
      onLadder: true,
      uqc: 'GMS',
    );
    const kg = Unit(
      id: 12,
      familyId: 2,
      code: 'kg',
      label: 'Kilogram',
      symbol: 'kg',
      factorToBase: 1000000,
      isBase: false,
      onLadder: true,
      uqc: 'KGS',
    );
    const quintal = Unit(
      id: 13,
      familyId: 2,
      code: 'qtl',
      label: 'Quintal',
      symbol: 'qtl',
      factorToBase: 100000000,
      isBase: false,
      onLadder: true,
      uqc: 'QTL',
    );
    const tonne = Unit(
      id: 14,
      familyId: 2,
      code: 't',
      label: 'Tonne',
      symbol: 't',
      factorToBase: 1000000000,
      isBase: false,
      onLadder: true,
      uqc: 'TON',
    );
    final massFamily = UnitFamily(
      id: 2,
      code: 'mass',
      name: 'Mass',
      dimension: 'dimension',
      integralOnly: false,
      units: [mg, g, kg, quintal, tonne],
    );

    test('Parsing vectors match contract', () {
      // parse("1.25", kg) == 1,250,000 mg
      final q1 = Units.parse('1.25', kg, massFamily);
      expect(q1.base, 1250000);

      // parse("0.1", g) == 100 mg
      final q2 = Units.parse('0.1', g, massFamily);
      expect(q2.base, 100);

      // parse("1.5", dozen) == 18 pieces
      final q3 = Units.parse('1.5', dozen, countFamily);
      expect(q3.base, 18);

      // parse("1.1", dozen) throws UnitParseError (13.2 pieces is not an integer)
      expect(
        () => Units.parse('1.1', dozen, countFamily),
        throwsA(isA<UnitParseError>()),
      );
    });

    test('Ladder ratios: 1 quintal == 100 kg, 1 tonne == 1000 kg, 1 gross == 144 pieces', () {
      expect(quintal.factorToBase / kg.factorToBase, 100);
      expect(tonne.factorToBase / kg.factorToBase, 1000);
      expect(gross.factorToBase / piece.factorToBase, 144);
      expect(dozen.factorToBase / piece.factorToBase, 12);
    });

    test('Formatting matches §5 examples exactly', () {
      // 999,000 mg -> "999 g"
      expect(Units.format(Quantity(999000, massFamily)), '999 g');

      // 1,000,000 mg -> "1 kg"
      expect(Units.format(Quantity(1000000, massFamily)), '1 kg');

      // 1,250,000 mg -> "1.25 kg"
      expect(Units.format(Quantity(1250000, massFamily)), '1.25 kg');

      // 150,000,000 mg -> "1.5 qtl"
      expect(Units.format(Quantity(150000000, massFamily)), '1.5 qtl');

      // 2,000,000,000 mg -> "2 t"
      expect(Units.format(Quantity(2000000000, massFamily)), '2 t');
    });

    // The same vectors are asserted in
    // backend/test/units-conversion-ladders.test.js. Two implementations are
    // allowed to exist; drifting apart is not.
    //
    // Count is integral-only, so auto-promotion may only land on a rung that
    // divides exactly. 228 pieces WAS rendered '1.5833 gro' — a third of a
    // piece, which is not a quantity of anything.
    test('An integral-only family never auto-promotes to a fraction', () {
      const fixture = <int, String>{
        228: '19 doz', // 228 = 19 x 12 exactly; 1.5833 gross is not a thing
        288: '2 gro', // divides at the top rung, so it promotes
        229: '229 Pc', // no rung above piece divides it
        144: '1 gro',
        143: '143 Pc',
        12: '1 doz',
        11: '11 Pc',
        0: '0 Pc',
        -24: '-2 doz',
      };
      fixture.forEach((base, text) {
        expect(
          Units.format(Quantity(base, countFamily)),
          text,
          reason: '$base base units',
        );
      });
    });

    test('A family that is not integral-only still promotes to a decimal', () {
      // The right answer for mass: 1.25 kg is a real weight, and the fix above
      // must not have made every family integral.
      expect(Units.format(Quantity(1250000, massFamily)), '1.25 kg');
      expect(massFamily.integralOnly, isFalse);
    });

    test('Pinned formatting does not auto-promote', () {
      final q = Quantity(1250000, massFamily);
      expect(Units.format(q, display: const QtyDisplay.pinned(kg)), '1.25 kg');
      expect(Units.format(q, display: const QtyDisplay.pinned(g)), '1250 g');
      expect(Units.format(q, display: const QtyDisplay.pinned(mg)), '1250000 mg');
    });

    test('Invariant I4: Adding or comparing Mass to Count throws ArgumentError', () {
      final qMass = Quantity(500, massFamily);
      final qCount = Quantity(10, countFamily);

      expect(() => qMass + qCount, throwsArgumentError);
      expect(() => qMass - qCount, throwsArgumentError);
      expect(() => qMass.compareTo(qCount), throwsArgumentError);
    });

    test('Round-trip parse(format(q, pinned(u)), u) == q', () {
      final testValues = [1000, 2500000, 50000000, 1234000];
      for (final val in testValues) {
        final original = Quantity(val, massFamily);
        final formatted = Units.format(original, display: const QtyDisplay.pinned(kg));
        // extract number portion before unit symbol
        final numPart = formatted.split(' ').first;
        final roundTrip = Units.parse(numPart, kg, massFamily);
        expect(roundTrip.base, original.base);
      }
    });
  });
}

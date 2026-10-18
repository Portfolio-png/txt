import 'package:core_erp/core/widgets/force_capacity_field.dart';
import 'package:core_erp/features/machines/domain/machine_no.dart';
import 'package:flutter_test/flutter_test.dart';

/// The machine-number rule and the capacity beside it, away from any widget.
///
/// The fixture table is asserted here AND in
/// `backend/test/machine-sheet-fields.test.js`. The two implementations are
/// allowed to exist — one fills a field as you pick a type, the other guards
/// the database — but drifting apart is not.

const List<(String, int, String)> _numberFixture = [
  ('Power Press', 4, 'PP-4'),
  ('Punching M', 1, 'PM-1'),
  ('Hand Press', 12, 'HP-12'),
  ('Jigs & Fixtures', 2, 'JF-2'),
  ('Feeder', 3, 'F-3'),
  ('', 4, ''),
  ('Power Press', 0, ''),
];

void main() {
  group('buildMachineNo', () {
    test('is the type initials and the next number in that type', () {
      for (final (type, next, expected) in _numberFixture) {
        expect(
          buildMachineNo(typeName: type, nextNumber: next),
          expected,
          reason: '$type / $next',
        );
      }
      expect(buildMachineNo(typeName: null, nextNumber: 1), isEmpty);
      expect(buildMachineNo(typeName: 'Power Press', nextNumber: null), isEmpty);
    });

    test('a clash moves to the next number, not to a suffix', () {
      // The series is a run of numbers, so PP-4-2 would read as a machine that
      // does not exist.
      expect(nextFreeMachineNo('PP-4', const <String>[]), 'PP-4');
      expect(nextFreeMachineNo('PP-4', const ['PP-4']), 'PP-5');
      expect(nextFreeMachineNo('PP-4', const ['pp-4', 'PP-5']), 'PP-6');
      // Something with no number on the end has nowhere to count, so it falls
      // back to a suffix.
      expect(nextFreeMachineNo('LATHE', const ['LATHE']), 'LATHE-2');
      expect(nextFreeMachineNo('', const <String>[]), isEmpty);
    });
  });

  group('capacity', () {
    test('both units land on a whole kilogram-force', () {
      expect(parseCapacityToKgf('35', 'Ton').kgf, 35000);
      expect(parseCapacityToKgf('1.5', 'Ton').kgf, 1500);
      expect(parseCapacityToKgf('250', 'kgf').kgf, 250);
      expect(parseCapacityToKgf('0', 'Ton').kgf, 0);
    });

    test('empty is not zero, and junk is refused rather than read as nothing', () {
      expect(parseCapacityToKgf('', 'Ton').kgf, isNull);
      expect(parseCapacityToKgf('', 'Ton').isFailure, isFalse);
      expect(parseCapacityToKgf('heavy', 'Ton').isFailure, isTrue);
      expect(parseCapacityToKgf('-3', 'Ton').isFailure, isTrue);
      // A fraction of a kilogram-force cannot be stored, and the contract says
      // to refuse rather than round it away.
      expect(parseCapacityToKgf('0.0005', 'Ton').isFailure, isTrue);
    });

    test('round-trips back into the field it came from', () {
      expect(formatCapacityFromKgf(35000, 'Ton'), '35');
      expect(formatCapacityFromKgf(1500, 'Ton'), '1.5');
      expect(formatCapacityFromKgf(250, 'kgf'), '250');
      expect(formatCapacityFromKgf(null, 'Ton'), isEmpty);
    });

    test('free hand is a recorded answer, not a blank and not a zero', () {
      expect(CapacityKind.fromWire('free_hand'), CapacityKind.freeHand);
      expect(CapacityKind.fromWire('rated'), CapacityKind.rated);
      expect(CapacityKind.fromWire(''), CapacityKind.unknown);
      // A kind from a newer server still opens the machine.
      expect(CapacityKind.fromWire('variable'), CapacityKind.unknown);

      expect(capacityLabel(CapacityKind.freeHand, null, 'Ton'), 'Free hand');
      expect(capacityLabel(CapacityKind.rated, 35000, 'Ton'), '35 Ton');
      // Nobody said: nothing to show, which is not "0 Ton".
      expect(capacityLabel(CapacityKind.unknown, null, 'Ton'), isEmpty);
      expect(capacityLabel(CapacityKind.rated, 0, 'Ton'), '0 Ton');
    });
  });
}

import 'package:core_erp/features/units/domain/starter_units.dart';
import 'package:flutter_test/flutter_test.dart';

/// The units a fresh workspace is offered.
///
/// A new install holds one unit — `Primary Unit`, symbol `-` — and an item
/// cannot be created without a real one, so this is the first thing that stops
/// somebody. What these guard is that the offer never makes a mess: no twin of
/// a unit already there, and nothing invented about conversions.

List<String> _names(List<StarterUnit> units) =>
    units.map((unit) => unit.name).toList();

void main() {
  group('what the starter units are', () {
    test('they carry no conversion factor and no family', () {
      // Nothing in Paper can convert yet: unit_groups is empty and every
      // conversion_factor is 1.0. A seeded ratio would be a claim the system
      // cannot honour.
      for (final unit in kStarterUnits) {
        final input = unit.toInput();
        expect(input.unitGroupName, isEmpty, reason: unit.name);
        expect(input.conversionFactor, 1, reason: unit.name);
        expect(input.symbol, isNotEmpty, reason: unit.name);
      }
    });

    test('they are spelled as the server spells them', () {
      // `ensureDemoUnitsPresent` on the server writes Piece/Pc, Kilogram/kg
      // and the rest. Seeding 'pcs' here would leave a workspace that had seen
      // demo data holding two spellings of one unit.
      final bySymbol = {
        for (final unit in kStarterUnits) unit.name: unit.symbol,
      };
      expect(bySymbol['Piece'], 'Pc');
      expect(bySymbol['Kilogram'], 'kg');
      expect(bySymbol['Gram'], 'g');
      expect(bySymbol['Meter'], 'm');
      expect(bySymbol['Liter'], 'L');
      expect(bySymbol['Carton'], 'Ctn');
    });
  });

  group('missingStarterUnits', () {
    test('an untouched workspace is offered all of them', () {
      final missing = missingStarterUnits(
        existingNames: const <String>['Primary Unit'],
        existingSymbols: const <String>['-'],
      );
      expect(missing, hasLength(kStarterUnits.length));
    });

    test('a unit already there is left alone, by name or by symbol', () {
      final missing = missingStarterUnits(
        // One matched on its name, one only on its symbol.
        existingNames: const <String>['Primary Unit', 'Kilogram', 'Pieces'],
        existingSymbols: const <String>['-', 'kg', 'Pc'],
      );

      expect(_names(missing), isNot(contains('Kilogram')));
      expect(
        _names(missing),
        isNot(contains('Piece')),
        reason: 'the symbol Pc was already taken, whatever it was called',
      );
      expect(_names(missing), contains('Gram'));
    });

    test('case and stray spaces do not make a twin', () {
      final missing = missingStarterUnits(
        existingNames: const <String>[' kilogram ', 'BOX'],
        existingSymbols: const <String>['KG ', ' box'],
      );
      expect(_names(missing), isNot(contains('Kilogram')));
      expect(_names(missing), isNot(contains('Box')));
    });

    test('pressing it a second time offers nothing', () {
      final missing = missingStarterUnits(
        existingNames: kStarterUnits.map((unit) => unit.name),
        existingSymbols: kStarterUnits.map((unit) => unit.symbol),
      );
      expect(missing, isEmpty);
    });
  });

  group('unitsLookUnset', () {
    test('only the placeholder means nobody has set anything up', () {
      // The server writes Primary Unit on first boot, so it is not evidence
      // that a person has been here.
      expect(unitsLookUnset(activeUnitNames: const <String>['Primary Unit']), isTrue);
      expect(unitsLookUnset(activeUnitNames: const <String>[]), isTrue);
    });

    test('one real unit is enough to stop asking', () {
      expect(
        unitsLookUnset(
          activeUnitNames: const <String>['Primary Unit', 'Kilogram'],
        ),
        isFalse,
      );
    });
  });
}

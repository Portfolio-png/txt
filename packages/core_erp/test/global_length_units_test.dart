import 'package:core_erp/features/units/domain/global_length_units.dart';
import 'package:flutter_test/flutter_test.dart';

// Every length unit the system can read a measurement in. The one that needs
// watching is gauge: it is a lookup, not a factor, and treating it as a factor
// would put a wrong thickness on a real sheet.

void main() {
  GlobalLengthUnit unit(String symbol) => lengthUnitBySymbol(symbol);

  group('the catalogue', () {
    test('carries the units a shop actually quotes in', () {
      final symbols = globalLengthUnits.map((u) => u.symbol).toList();
      expect(symbols, containsAll(<String>['m', 'ft', 'in', 'cm', 'mm']));
      // The two that were missing from anything usable.
      expect(symbols, contains('thou'));
      expect(symbols, contains('ga'));
    });

    test('is ordered coarsest first, the way a list is scanned', () {
      final linear = globalLengthUnits
          .where((u) => !u.isGauge)
          .map((u) => u.millimetres)
          .toList();
      for (var i = 1; i < linear.length; i++) {
        expect(linear[i], lessThan(linear[i - 1]));
      }
    });
  });

  group('linear units', () {
    test('convert both ways', () {
      expect(unit('in').toMm(1), closeTo(25.4, 0.0001));
      expect(unit('ft').toMm(1), closeTo(304.8, 0.0001));
      expect(unit('cm').toMm(4), 40);
      expect(unit('m').toMm(1), 1000);
      expect(unit('thou').toMm(1000), closeTo(25.4, 0.0001));
      expect(unit('mm').fromMm(40), 40);
      expect(unit('in').fromMm(25.4), closeTo(1, 0.0001));
    });

    test('thou is a thousandth of an inch, not a millimetre', () {
      // The unit exists precisely because drawings quote it; getting it wrong
      // by 25x would be invisible until something was cut.
      expect(unit('thou').millimetres, closeTo(0.0254, 0.00001));
      expect(unit('thou').toMm(40), closeTo(1.016, 0.0001));
    });
  });

  group('gauge', () {
    test('is a lookup, not a factor', () {
      // 20 gauge is not twice 10 gauge — it is thinner. A factor cannot say
      // that, which is why gauge carries no millimetres of its own.
      expect(unit('ga').isGauge, isTrue);
      expect(unit('ga').toMm(10), closeTo(3.251, 0.001));
      expect(unit('ga').toMm(20), closeTo(0.914, 0.001));
      expect(unit('ga').toMm(20), lessThan(unit('ga').toMm(10)));
    });

    test('a gauge the table does not have is not a thickness', () {
      // Rather than interpolating: guessing what 41 gauge means would put a
      // wrong number on a real sheet.
      expect(unit('ga').toMm(41), 0);
      expect(unit('ga').toMm(0), 0);
    });

    test('reads a thickness back as the nearest standard gauge', () {
      // 1.2 mm is 18 gauge to everyone on the floor, though the table says
      // 1.219.
      expect(unit('ga').fromMm(1.2), 18);
      expect(unit('ga').fromMm(3.251), 10);
    });

    test('round trips through the table, not through arithmetic', () {
      for (final gauge in <double>[8, 16, 24, 32]) {
        final mm = unit('ga').toMm(gauge);
        expect(unit('ga').fromMm(mm), gauge);
      }
    });
  });

  group('looking a unit up', () {
    test('falls back rather than throwing on something unknown', () {
      expect(lengthUnitBySymbol('furlong').symbol, 'mm');
      expect(lengthUnitBySymbol(null).symbol, 'mm');
      expect(lengthUnitBySymbol('furlong', fallback: 'in').symbol, 'in');
    });
  });

  group('search', () {
    test('matches the symbol, the name, and what people actually type', () {
      expect(unit('mm').matches('milli'), isTrue);
      expect(
        unit('mm').matches('millimetre'),
        isTrue,
        reason: 'British spelling',
      );
      expect(unit('ga').matches('swg'), isTrue);
      expect(unit('thou').matches('mil'), isTrue);
      expect(unit('in').matches('inches'), isTrue);
      expect(unit('ft').matches('feet'), isTrue);
    });

    test('an empty query matches everything, so the list opens full', () {
      expect(globalLengthUnits.every((u) => u.matches('')), isTrue);
      expect(globalLengthUnits.every((u) => u.matches('   ')), isTrue);
    });

    test('does not match what it is not', () {
      expect(unit('mm').matches('inch'), isFalse);
      expect(unit('ga').matches('metre'), isFalse);
    });
  });

  group('what can measure a face', () {
    test('gauge is left out — it only ever means a thickness', () {
      expect(faceLengthUnits.any((u) => u.isGauge), isFalse);
      expect(faceLengthUnits.length, globalLengthUnits.length - 1);
    });
  });
}

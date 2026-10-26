import 'package:core_erp/core/widgets/length_unit_field.dart';
import 'package:core_erp/features/dies/domain/die_code.dart';
import 'package:flutter_test/flutter_test.dart';

/// The die code rule and the measurement beside it, away from any widget.
///
/// The fixture table is asserted here AND in
/// `backend/test/die-sheet-fields.test.js`. The two implementations are
/// allowed to exist — one fills a field as you type, the other guards the
/// database — but drifting apart is not.

const List<(DieType?, String, String)> _codeFixture = [
  (DieType.cutting, 'SADP48', 'CDSADP48'),
  (DieType.bending, 'SADP48', 'BDSADP48'),
  // The factory sheet's other two dies. Note RD and AD, not R and A: the
  // mandatory D keeps a die code distinct from its own part code on a scan.
  (DieType.riveting, 'SADP48', 'RDSADP48'),
  (DieType.assembly, 'SADP48', 'ADSADP48'),
  (DieType.cutting, 'atl1', 'CDATL1'),
  (DieType.cutting, '', ''),
  (null, 'SADP48', ''),
];

void main() {
  group('buildDieCode', () {
    test('is the type initials, then D, then the part code', () {
      for (final (type, partCode, expected) in _codeFixture) {
        expect(
          buildDieCode(type: type, partCode: partCode),
          expected,
          reason: '${type?.slug} / $partCode',
        );
      }
    });

    test('a type nobody defined reads as none, rather than throwing', () {
      // A client one version behind the server still has to open the die.
      expect(DieType.fromSlug('deepdraw'), isNull);
      expect(DieType.fromSlug(null), isNull);
      expect(DieType.fromSlug('cutting'), DieType.cutting);
      expect(DieType.cutting.label, 'Cutting');
    });
  });

  // The four built-ins are the common types, not the only ones. These mirror
  // `backend/test/die-makers.test.js`, which asserts the same vectors.
  group('a die type the shop typed', () {
    test('slugifies the way the backend does', () {
      expect(slugifyDieType('Deep Drawing'), 'deep-drawing');
      expect(slugifyDieType('  Coining / Sizing  '), 'coining-sizing');
      expect(slugifyDieType(''), isEmpty);
    });

    test('derives its code from the words that were typed', () {
      final choice = DieTypeChoice.custom('Deep Drawing')!;
      expect(choice.builtIn, isFalse);
      expect(choice.slug, 'deep-drawing');
      expect(choice.storedLabel, 'Deep Drawing');
      expect(
        buildDieCodeFor(choice: choice, partCode: 'SADP48'),
        'DDDSADP48',
        reason: 'two words give two initials, then the mandatory D',
      );
    });

    test('typing the name of a built-in gives the built-in', () {
      // Otherwise the shop ends up with two "Cutting" types that read the
      // same and sort apart.
      final typed = DieTypeChoice.custom('cutting')!;
      expect(typed.builtIn, isTrue);
      expect(typed.slug, 'cutting');
      expect(
        typed.storedLabel,
        isEmpty,
        reason: 'a built-in stores no label — the slug is authoritative',
      );

      expect(DieTypeChoice.custom('Cutting')!.builtIn, isTrue);
    });

    test('there is no such thing as a nameless type', () {
      expect(DieTypeChoice.custom(''), isNull);
      expect(DieTypeChoice.custom('   '), isNull);
      expect(DieTypeChoice.custom('///'), isNull);
    });

    test('a stored type comes back, label or not', () {
      expect(DieTypeChoice.fromStored('cutting', '')!.label, 'Cutting');
      expect(
        DieTypeChoice.fromStored('cutting', 'Stale Words')!.label,
        'Cutting',
        reason: 'the slug is authoritative for the four',
      );
      expect(
        DieTypeChoice.fromStored('deep-drawing', 'Deep Drawing')!.label,
        'Deep Drawing',
      );
      // A slug whose words were never stored still shows as something, which
      // beats a blank Type cell on a die that plainly has one.
      expect(DieTypeChoice.fromStored('deep-drawing', '')!.label, 'deep-drawing');
      expect(DieTypeChoice.fromStored('', ''), isNull);
    });
  });

  group('liner size', () {
    test('every unit it offers lands on a whole nanometre', () {
      // This is the reason the column is nanometres and not micrometres: at
      // µm, thou is 25.4 and nothing but multiples of five could be stored
      // without the rounding the units contract forbids.
      expect(parseLengthToNanometres('94.50', 'mm').nanometres, 94500000);
      expect(parseLengthToNanometres('1', 'mm').nanometres, 1000000);
      expect(parseLengthToNanometres('1', 'in').nanometres, 25400000);
      expect(parseLengthToNanometres('15.5', 'thou').nanometres, 393700);
      expect(parseLengthToNanometres('1', 'cm').nanometres, 10000000);
    });

    test('empty is not zero, and junk is refused rather than read as nothing', () {
      expect(parseLengthToNanometres('', 'mm').nanometres, isNull);
      expect(parseLengthToNanometres('   ', 'mm').isFailure, isFalse);
      expect(parseLengthToNanometres('wide', 'mm').isFailure, isTrue);
      expect(parseLengthToNanometres('-3', 'mm').isFailure, isTrue);
    });

    test('a gauge the table does not have is not a thickness', () {
      // Guessing what 41 gauge means would put a wrong size on a real die.
      expect(parseLengthToNanometres('41', 'ga').isFailure, isTrue);
      expect(parseLengthToNanometres('20', 'ga').nanometres, isNotNull);
    });

    test('round-trips back into the field it came from', () {
      for (final unit in const ['mm', 'cm', 'in', 'thou']) {
        final parsed = parseLengthToNanometres('94.5', unit);
        expect(parsed.nanometres, isNotNull, reason: unit);
        expect(
          formatLengthFromNanometres(parsed.nanometres, unit),
          '94.5',
          reason: unit,
        );
      }
      expect(formatLengthFromNanometres(null, 'mm'), isEmpty);
      // Trailing zeros off: 94.50 and 94.5 are the same measurement.
      expect(formatLengthFromNanometres(94500000, 'mm'), '94.5');
      expect(formatLengthFromNanometres(1000000, 'mm'), '1');
    });
  });
}

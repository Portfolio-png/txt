import 'package:core_erp/features/items/domain/part_code.dart';
import 'package:flutter_test/flutter_test.dart';

// What a property value contributes to a part code.
//
// Numbers whole, letters first. The digits matter: strictly the first
// character would make "22 Gauge" and "24 Gauge" both "2", and those are the
// two parts a press shop most needs to tell apart.

void main() {
  group('partPropertyCode', () {
    test('a single word gives its first letter', () {
      expect(partPropertyCode('Brass'), 'B');
      expect(partPropertyCode('Nickel'), 'N');
      expect(partPropertyCode('copper'), 'C');
    });

    test('two words give two letters', () {
      expect(partPropertyCode('Mild Steel'), 'MS');
      expect(partPropertyCode('Brass Polish'), 'BP');
    });

    test('a number keeps all its digits', () {
      expect(partPropertyCode('22 Gauge'), '22G');
      expect(partPropertyCode('24 Gauge'), '24G');
    });

    test('the gauges that matter do not collide', () {
      // The whole reason the digits are kept.
      expect(
        partPropertyCode('22 Gauge'),
        isNot(partPropertyCode('24 Gauge')),
      );
    });

    test('nor do they when typed without the space', () {
      // A gauge cell takes typed values verbatim, so "22G" is the normal
      // spelling — and it used to come out "2", colliding with "24G". The
      // digits have to survive the spelling, not just the space.
      expect(partPropertyCode('22G'), '22G');
      expect(partPropertyCode('24G'), '24G');
      expect(partPropertyCode('22G'), isNot(partPropertyCode('24G')));
      expect(partPropertyCode('12GB'), isNot(partPropertyCode('16GB')));
    });

    test('nothing in, nothing out', () {
      expect(partPropertyCode(null), '');
      expect(partPropertyCode(''), '');
      expect(partPropertyCode('   '), '');
      expect(partPropertyCode('---'), '');
    });

    test('the Node twin asserts these same vectors', () {
      // The rule exists twice — here and as `propertyCodeFor` in
      // backend/modules/items/part-identity.js — because the sheet fills a
      // field in as someone types while the server is what reaches the
      // database. The two implementations are allowed to exist; drifting apart
      // is not, so this table is duplicated verbatim in
      // backend/test/item-part-identity.test.js under the same name.
      const fixture = <(String, String)>[
        ('Brass', 'B'),
        ('Nickel', 'N'),
        ('copper', 'C'),
        ('Mild Steel', 'MS'),
        ('Brass Polish', 'BP'),
        ('22 Gauge', '22G'),
        ('24 Gauge', '24G'),
        ('22G', '22G'),
        ('24G', '24G'),
        ('2mm', '2M'),
        ('M8', 'M8'),
        ('128GB', '128G'),
        ('12GB', '12G'),
        ('16GB', '16G'),
        ('SS 304', 'S304'),
        ('', ''),
        ('   ', ''),
        ('---', ''),
      ];
      for (final (value, want) in fixture) {
        expect(partPropertyCode(value), want, reason: '"$value"');
      }
    });

    test('it is not the variant fallback', () {
      // `variationValueCode` keeps a short single word whole, for a different
      // job. Four letters per property would not fit on a drawing.
      expect(variationValueCode('Brass'), 'BRAS');
      expect(partPropertyCode('Brass'), 'B');
    });
  });
}

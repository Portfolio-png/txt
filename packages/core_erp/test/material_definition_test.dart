import 'dart:io';

import 'package:core_erp/features/materials/domain/material_definition.dart';
import 'package:flutter_test/flutter_test.dart';

/// The material master exists for one sum, and one join.
///
/// The sum is volume × density = weight. The join is name → swatch file, which
/// is made twice — once in Dart here, once in the Python generator — and a
/// mismatch shows up as a grid of broken images rather than as an error.
void main() {
  MaterialDefinition steel({
    double density = 7.85,
    String name = 'Steel / MS',
  }) {
    return MaterialDefinition(id: 1, name: name, densityGCm3: density);
  }

  group('weight', () {
    test('volume times density is weight', () {
      // A 1219 × 2438 × 1.6 mm sheet is 4756 cm³; in mild steel that is 37 kg,
      // which is what two people lifting it would tell you.
      expect(steel().weightKg(4755), closeTo(37.33, 0.01));
      // Water is the reference: a litre weighs a kilogram.
      expect(
        const MaterialDefinition(
          id: 1,
          name: 'Water',
          densityGCm3: 1,
        ).weightKg(1000),
        1,
      );
    });

    test('nothing weighs nothing, and never a negative', () {
      expect(steel().weightKg(0), 0);
      expect(steel().weightKg(-100), 0);
      expect(steel(density: 0).weightKg(4755), 0);
    });
  });

  group('swatch slugs', () {
    test('a name becomes the same slug the generator writes', () {
      expect(MaterialDefinition.slugFor('Steel / MS'), 'steel-ms');
      expect(MaterialDefinition.slugFor('PB / Gunmetal'), 'pb-gunmetal');
      expect(MaterialDefinition.slugFor('PVDF'), 'pvdf');
      expect(MaterialDefinition.slugFor('Stainless Steel'), 'stainless-steel');
      // Leading and trailing punctuation is trimmed, not left as a dash.
      expect(MaterialDefinition.slugFor('  Brass!  '), 'brass');
    });

    test('every seeded material has a swatch on disk', () {
      // The names come from the migration; the files from the generator. This
      // is the only place the two are checked against each other.
      final migration = File(
        '../../backend/migrations/034-material-master.sql',
      );
      if (!migration.existsSync()) {
        // The Dart package can be tested without the backend checked out.
        return;
      }
      final names = RegExp(r"^\s*\('([^']+)',", multiLine: true)
          .allMatches(migration.readAsStringSync())
          .map((match) => match.group(1)!)
          .toList();
      expect(names.length, greaterThanOrEqualTo(36), reason: 'seed parsed');

      final missing = <String>[];
      for (final name in names) {
        final file = File(
          '../../backend/public/${MaterialDefinition(id: 0, name: name, densityGCm3: 1).imagePath}',
        );
        if (!file.existsSync()) missing.add(name);
      }
      expect(
        missing,
        isEmpty,
        reason: 'these materials would show a broken card',
      );
    });
  });

  group('search', () {
    test('matches on name, category and note', () {
      const nylon = MaterialDefinition(
        id: 1,
        name: 'Nylon',
        densityGCm3: 1.15,
        category: 'plastic',
        notes: 'Nylon 6/6',
      );
      expect(nylon.matches('nyl'), isTrue);
      expect(nylon.matches('PLASTIC'), isTrue);
      expect(nylon.matches('6/6'), isTrue);
      expect(
        nylon.matches(''),
        isTrue,
        reason: 'an empty search hides nothing',
      );
      expect(nylon.matches('brass'), isFalse);
    });
  });

  test('a density reads to two places, the precision a handbook quotes', () {
    expect(steel().densityLabel, '7.85 g/cm³');
    expect(steel(density: 2.7).densityLabel, '2.70 g/cm³');
  });
}

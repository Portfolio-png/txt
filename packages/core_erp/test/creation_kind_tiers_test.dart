import 'package:core_erp/features/groups/presentation/screens/creation_wizard_kinds.dart';
import 'package:flutter_test/flutter_test.dart';

/// The chooser's four groups, checked against the catalogue they come from.
///
/// The chooser draws a tier by filtering the catalogue
/// (`catalog.where((spec) => spec.tier == tier)`), so a kind whose tier nobody
/// thought about would simply never appear on screen — no error, no blank card,
/// just a master you cannot reach from the empty bench. `tier` is required on
/// `CreationKindSpec` to make that impossible to write, and these guard the
/// rest: that the four groups still cover everything, and that the catalogue's
/// order agrees with them.
void main() {
  group('every kind has a place in the chooser', () {
    test('the four tiers cover the catalogue, once each', () {
      final counted = <String>[];
      for (final tier in CreationTier.values) {
        counted.addAll(
          CreationKinds.catalog
              .where((spec) => spec.tier == tier)
              .map((spec) => spec.key),
        );
      }

      expect(
        counted.toSet(),
        CreationKinds.catalog.map((spec) => spec.key).toSet(),
        reason: 'a kind in no tier is a card the chooser never draws',
      );
      expect(
        counted.length,
        CreationKinds.catalog.length,
        reason: 'and one in two tiers would be drawn twice',
      );
    });

    test('no tier is empty', () {
      // An empty tier draws a label and a reason over nothing at all.
      for (final tier in CreationTier.values) {
        expect(
          CreationKinds.catalog.where((spec) => spec.tier == tier),
          isNotEmpty,
          reason: tier.label,
        );
      }
    });

    test('every tier says what it is and why it comes there', () {
      for (final tier in CreationTier.values) {
        expect(tier.label, isNotEmpty, reason: tier.name);
        expect(tier.reason, isNotEmpty, reason: tier.name);
      }
    });
  });

  group('the catalogue is in tier order', () {
    test('each tier is one contiguous run, in CreationTier order', () {
      // Three surfaces read this one list — the chooser's groups, the + menu in
      // the lineup column, and the order "Add them all" fills the bench. If the
      // list interleaved tiers, the chooser would still look right (it filters)
      // while the other two disagreed with it.
      final runs = <CreationTier>[];
      for (final spec in CreationKinds.catalog) {
        if (runs.isEmpty || runs.last != spec.tier) runs.add(spec.tier);
      }

      expect(runs, CreationTier.values);
    });

    test('a client comes before its sub-contractor', () {
      // `sub_contractors.client_id` is NOT NULL and the only create route is
      // nested under a client, so this is the one ordering inside a tier that
      // is a real dependency rather than a reading order.
      final keys = CreationKinds.catalog.map((spec) => spec.key).toList();
      expect(
        keys.indexOf('client'),
        lessThan(keys.indexOf('sub_contractor')),
      );
    });

    test('a unit and a group come before the item that needs them', () {
      // `groupId` and `unitId` are both required on an item write.
      final keys = CreationKinds.catalog.map((spec) => spec.key).toList();
      expect(keys.indexOf('unit'), lessThan(keys.indexOf(CreationKinds.item)));
      expect(
        keys.indexOf('item_group'),
        lessThan(keys.indexOf(CreationKinds.item)),
      );
    });

    test('items come before the set built out of them', () {
      final keys = CreationKinds.catalog.map((spec) => spec.key).toList();
      expect(keys.indexOf(CreationKinds.item), lessThan(keys.indexOf('set')));
    });
  });

  group('what the reorder must not have broken', () {
    test('the three defaults still name kinds the catalogue knows', () {
      for (final key in CreationKinds.defaults) {
        expect(CreationKinds.knows(key), isTrue, reason: key);
      }
    });

    test('every kind is still reachable by key', () {
      // byKey is a firstWhere with no fallback: reordering must not have lost
      // or renamed anything.
      for (final spec in CreationKinds.catalog) {
        expect(CreationKinds.byKey(spec.key).label, spec.label);
      }
    });
  });
}

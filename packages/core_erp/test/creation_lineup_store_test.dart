import 'package:core_erp/features/groups/presentation/screens/creation_sessions.dart';
import 'package:core_erp/features/groups/presentation/screens/creation_wizard_kinds.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The tiles the Express window opens with.
///
/// Its own file, not a group inside `creation_sessions_test.dart`: a top-level
/// `setUp` applies to every test in a file, and sharing one has cost a round of
/// phantom failures before.
///
/// The split under test is deliberate — the store round-trips strings and knows
/// nothing about the catalogue, and `CreationKinds.sanitizeLineup` decides what
/// still names something. That keeps the prefs file free of any path back into
/// the widget tree.
void main() {
  group('CreationLineupStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('nothing stored is no lineup, not an empty one', () async {
      expect(await CreationLineupStore().load(), isEmpty);
    });

    test('the kinds come back in the order they were left', () async {
      final store = CreationLineupStore();
      await store.save(<String>[
        CreationKinds.machine,
        CreationKinds.item,
        'unit',
      ]);

      expect(await CreationLineupStore().load(), <String>[
        CreationKinds.machine,
        CreationKinds.item,
        'unit',
      ]);
    });

    test('a later save replaces the earlier one', () async {
      final store = CreationLineupStore();
      await store.save(<String>[CreationKinds.item, CreationKinds.die]);
      await store.save(<String>['vendor']);

      expect(await store.load(), <String>['vendor']);
    });

    test('a store that cannot be read is empty, never a throw', () async {
      // The real one swallows a missing plugin the same way; a convenience
      // must not be the reason the window will not open.
      SharedPreferences.setMockInitialValues(<String, Object>{
        CreationLineupStore.prefsKey: 'not a list',
      });

      expect(await CreationLineupStore().load(), isEmpty);
    });
  });

  group('sanitizeLineup', () {
    test('keeps what the catalogue still knows, in order', () {
      expect(
        CreationKinds.sanitizeLineup(<String>[
          'unit',
          CreationKinds.item,
          'material',
        ]),
        <String>['unit', CreationKinds.item, 'material'],
      );
    });

    test('drops a kind that has left the catalogue', () {
      // byKey has no fallback, so an unknown key reaching the lineup would
      // throw while the window was being built.
      expect(
        CreationKinds.sanitizeLineup(<String>[
          CreationKinds.item,
          'conveyor_belt',
        ]),
        <String>[CreationKinds.item],
      );
    });

    test('empty stays empty, and so does all-unknown', () {
      // This used to substitute the three defaults. An empty bench is a real
      // state now — the window puts a chooser in the middle — and the fallback
      // to the defaults lives in the workspace's `initialKinds ?? defaults`,
      // which only the Add Item door reaches.
      expect(CreationKinds.sanitizeLineup(<String>[]), isEmpty);
      expect(CreationKinds.sanitizeLineup(<String>['conveyor_belt']), isEmpty);
    });
  });
}

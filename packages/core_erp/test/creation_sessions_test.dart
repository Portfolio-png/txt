import 'package:core_erp/features/groups/presentation/screens/creation_sessions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The recents list behind the creation window's title-bar search.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  CreationSession session(String id, List<(String, String)> records) =>
      CreationSession(
        id: id,
        savedAt: DateTime.now(),
        records: [
          for (final (kind, title) in records)
            CreationSessionRecord(kind: kind, id: '$kind-$title', title: title),
        ],
      );

  test('a sitting survives the window being closed and opened again', () async {
    final first = CreationSessionController();
    await first.load();
    await first.remember(
      session('s1', [('item', 'Cone Top'), ('die', 'DIE-100')]),
    );

    final reopened = CreationSessionController();
    await reopened.load();
    expect(reopened.recent.single.label, 'Cone Top · DIE-100');
    expect(reopened.recent.single.records.length, 2);
  });

  test('a sitting grows as more is saved, keeping one entry', () async {
    final controller = CreationSessionController();
    await controller.load();
    var sitting = session('s1', [('item', 'Cone Top')]);
    await controller.remember(sitting);
    sitting = sitting.plus(
      const CreationSessionRecord(kind: 'die', id: 'd1', title: 'DIE-100'),
    );
    await controller.remember(sitting);

    expect(controller.recent, hasLength(1));
    expect(controller.recent.single.label, 'Cone Top · DIE-100');
  });

  test('saving the same record twice does not list it twice', () {
    final grown = session('s1', [('item', 'Cone Top')]).plus(
      const CreationSessionRecord(
        kind: 'item',
        id: 'item-Cone Top',
        title: 'Cone Top',
      ),
    );
    expect(grown.records, hasLength(1));
  });

  test('only the most recent sittings are kept', () async {
    final controller = CreationSessionController();
    await controller.load();
    for (var i = 0; i < CreationSessionController.keep + 5; i++) {
      await controller.remember(session('s$i', [('item', 'Item $i')]));
    }
    expect(controller.recent, hasLength(CreationSessionController.keep));
    // Newest first.
    expect(
      controller.recent.first.label,
      'Item ${CreationSessionController.keep + 4}',
    );
  });

  test('search matches a record name or its kind', () {
    final sitting = session('s1', [('item', 'Cone Top'), ('die', 'DIE-100')]);
    expect(sitting.matches(''), isTrue);
    expect(sitting.matches('cone'), isTrue);
    expect(sitting.matches('die'), isTrue);
    expect(sitting.matches('press'), isFalse);
  });

  test(
    'an unreadable stored entry does not cost the rest of the list',
    () async {
      SharedPreferences.setMockInitialValues({
        CreationSessionController.prefsKey: <String>[
          'not json at all',
          '{"id":"s2","savedAt":"2026-09-29T10:00:00.000","records":'
              '[{"kind":"item","id":"1","title":"Cone Top"}]}',
        ],
      });
      final controller = CreationSessionController();
      await controller.load();
      expect(controller.recent.single.label, 'Cone Top');
    },
  );
}

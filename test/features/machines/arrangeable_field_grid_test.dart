import 'package:core_erp/features/groups/data/repositories/group_repository.dart';
import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paper/features/machines/data/machine_repository.dart';
import 'package:paper/features/machines/domain/machine.dart';
import 'package:paper/features/machines/presentation/providers/machine_provider.dart';
import 'package:paper/features/machines/presentation/screens/machine_form_screen.dart';
import 'package:paper/features/machines/presentation/widgets/arrangeable_field_grid.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The Create Machine dialog's fields move in place (owner, 2026-11-27: "give
// an option for each field to jumble their places in-place" — "here, not
// there": on this dialog, not the item sheet). Each card is one
// ArrangeableFieldGrid; the order is the person's own, kept on the computer.

ArrangeableField _field(String id, {bool wide = false}) => ArrangeableField(
  id: id,
  label: id.toUpperCase(),
  wide: wide,
  child: SizedBox(height: 48, child: Text('box $id')),
);

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            ArrangeableFieldGrid(
              storeKey: 'plant',
              fields: [
                _field('make'),
                _field('dom'),
                _field('hours'),
                _field('capacity', wide: true),
                _field('feed'),
              ],
            ),
            const SizedBox(height: 40),
            ArrangeableFieldGrid(
              storeKey: 'identity',
              fields: [_field('name'), _field('asset')],
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _cell(String grid, String id) =>
    find.byKey(ValueKey<String>('arrange_${grid}_$id'));
Finder _handle(String grid, String id) =>
    find.byKey(ValueKey<String>('arrange_handle_${grid}_$id'));

bool _before(WidgetTester tester, Finder a, Finder b) {
  final pa = tester.getTopLeft(a);
  final pb = tester.getTopLeft(b);
  if ((pa.dy - pb.dy).abs() > 4) return pa.dy < pb.dy;
  return pa.dx < pb.dx;
}

Future<void> _drag(WidgetTester tester, Finder handle, Finder onto) async {
  final gesture = await tester.startGesture(tester.getCenter(handle));
  await tester.pump();
  await gesture.moveBy(const Offset(10, 10));
  await tester.pump();
  await gesture.moveTo(tester.getCenter(onto));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  dialogMain();

  testWidgets('two to a row, every field with a handle, the usual order', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester);
    for (final id in ['make', 'dom', 'hours', 'capacity', 'feed']) {
      expect(_handle('plant', id), findsOneWidget, reason: id);
    }
    // make | dom on one row; capacity on its own.
    expect(
      tester.getTopLeft(_cell('plant', 'make')).dy,
      tester.getTopLeft(_cell('plant', 'dom')).dy,
    );
    expect(
      tester.getSize(_cell('plant', 'capacity')).width,
      greaterThan(tester.getSize(_cell('plant', 'make')).width * 1.5),
    );
    expect(find.byKey(const ValueKey('arrange_reset_plant')), findsNothing);
  });

  testWidgets('a field dropped on another takes its place, and is kept', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester);
    await _drag(tester, _handle('plant', 'feed'), _cell('plant', 'make'));
    expect(_before(tester, _cell('plant', 'feed'), _cell('plant', 'make')), isTrue);
    expect(tester.takeException(), isNull);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('field_order.plant.local')!.first, 'feed');

    final reset = find.byKey(const ValueKey('arrange_reset_plant'));
    expect(reset, findsOneWidget);
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(_before(tester, _cell('plant', 'make'), _cell('plant', 'feed')), isTrue);
    expect(prefs.getStringList('field_order.plant.local'), isNull);
  });

  testWidgets('a field does not cross into another card', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester);
    await _drag(tester, _handle('plant', 'make'), _cell('identity', 'name'));
    expect(_before(tester, _cell('identity', 'name'), _cell('identity', 'asset')), isTrue);
    expect(_before(tester, _cell('plant', 'make'), _cell('plant', 'dom')), isTrue);
    expect(find.text('box make'), findsOneWidget);
  });

  testWidgets('a kept order opens as it was left', (tester) async {
    SharedPreferences.setMockInitialValues({
      'field_order.identity.local': <String>['asset', 'name'],
    });
    await _pump(tester);
    expect(_before(tester, _cell('identity', 'asset'), _cell('identity', 'name')), isTrue);
    expect(find.byKey(const ValueKey('arrange_reset_identity')), findsOneWidget);
  });
}

// --- the real Create Machine dialog, with its three cards arrangeable -------

class _NoGroups implements GroupRepository {
  @override
  Future<void> init() async {}

  @override
  Future<List<GroupDefinition>> getGroups({bool withCovers = false}) async => [
    GroupDefinition(
      id: 60,
      name: 'Power Press',
      groupType: 'machine',
      groupStructure: 'hierarchical',
      parentGroupId: null,
      unitId: 1,
      isArchived: false,
      usageCount: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoMachines implements MachineRepository {
  final List<Machine> saved = [];

  @override
  Future<void> init() async {}

  @override
  Future<List<Machine>> fetchMachines() async => List.of(saved);

  @override
  Future<Machine> saveMachine(Machine machine) async {
    final made = machine.copyWith(id: '${saved.length + 1}');
    saved.add(made);
    return made;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void dialogMain() {
  testWidgets('the Create Machine dialog: each card\'s fields move in place', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1700, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final groups = GroupsProvider(repository: _NoGroups());
    final repo = _NoMachines();
    await groups.initialize();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GroupsProvider>.value(value: groups),
          ChangeNotifierProvider<MachinesProvider>(
            create: (_) => MachinesProvider(repository: repo),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showMachineFormDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Create Machine'), findsWidgets);
    // No Machine Name (owner, 2026-11-27): the Asset ID names a new one.
    expect(find.text('Machine Name'), findsNothing);
    // Nor Feeder make (owner, 2026-11-27).
    expect(find.text('Feeder make'), findsNothing);

    for (final (grid, id) in [
      ('machine_dialog.identity', 'asset'),
      ('machine_dialog.identity', 'status'),
      ('machine_dialog.plant', 'make'),
      ('machine_dialog.plant', 'capacity'),
      ('machine_dialog.plant', 'feed'),
    ]) {
      expect(_handle(grid, id), findsOneWidget, reason: '$grid $id');
    }
    expect(tester.takeException(), isNull);

    // Die Type dropped on Machine Make: first in its card.
    await tester.ensureVisible(_handle('machine_dialog.plant', 'feed'));
    await tester.pumpAndSettle();
    // Make Machine Make the field in view, then drop on its lower part.
    await tester.ensureVisible(_cell('machine_dialog.plant', 'make'));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      tester.getCenter(_handle('machine_dialog.plant', 'feed')),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(10, 10));
    await tester.pump();
    await gesture.moveTo(
      tester.getBottomLeft(_cell('machine_dialog.plant', 'make')) +
          const Offset(40, -12),
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      _before(
        tester,
        _cell('machine_dialog.plant', 'feed'),
        _cell('machine_dialog.plant', 'make'),
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);

    // Saved, a new machine is named by its Asset ID.
    await tester.ensureVisible(find.byType(TextFormField).first);
    await tester.enterText(
      find.descendant(
        of: _cell('machine_dialog.identity', 'asset'),
        matching: find.byType(TextFormField),
      ),
      'PP-7',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('machine-group-field')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('machine-group-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Power Press').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Machine').last);
    await tester.pumpAndSettle();
    expect(repo.saved.single.assetId, 'PP-7');
    expect(repo.saved.single.name, 'PP-7');
  });
}

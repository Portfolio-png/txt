import 'package:core_erp/core/widgets/soft_master_data.dart';
import 'package:core_erp/core/widgets/soft_primitives.dart';
import 'package:core_erp/features/groups/data/repositories/api_group_repository.dart';
import 'package:core_erp/features/groups/data/repositories/group_repository.dart';
import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/groups/presentation/screens/groups_screen.dart';
import 'package:core_erp/features/inventory/data/repositories/inventory_repository.dart';
import 'package:core_erp/features/inventory/domain/material_record.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:core_erp/features/items/data/repositories/item_repository.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/features/units/data/repositories/unit_repository.dart';
import 'package:core_erp/features/units/domain/unit_definition.dart';
import 'package:core_erp/features/units/presentation/providers/units_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Archiving a group.
///
/// The endpoint existed and nothing called it, so the only way to get a group
/// out of the way was Delete — which cascades through the group's items. The
/// status column, meanwhile, printed "Active" for every row, archived ones
/// included, which is the kind of lie that makes people stop trusting a screen.

final _unit = UnitDefinition(
  id: 1,
  name: 'gross',
  symbol: 'gr',
  notes: '',
  unitGroupId: null,
  unitGroupName: null,
  conversionFactor: 1,
  conversionBaseUnitId: null,
  conversionBaseUnitName: null,
  conversionType: 'linear',
  precision: 2,
  unitGroupDimension: null,
  unitGroupBaseUnitId: null,
  isArchived: false,
  usageCount: 0,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

GroupDefinition _group(
  int id,
  String name, {
  int? parentGroupId,
  bool isArchived = false,
  int itemCount = 0,
}) {
  return GroupDefinition(
    id: id,
    name: name,
    groupStructure: 'hierarchical',
    parentGroupId: parentGroupId,
    unitId: 1,
    itemCount: itemCount,
    isArchived: isArchived,
    usageCount: 0,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

class _ArchivingGroupRepository implements GroupRepository {
  _ArchivingGroupRepository();

  List<GroupDefinition> groups = <GroupDefinition>[
    _group(1, 'Primary Group'),
    _group(2, 'Spare Parts', parentGroupId: 1),
    _group(3, 'Discontinued', parentGroupId: 1, isArchived: true),
  ];

  final List<int> archived = <int>[];
  final List<int> restored = <int>[];

  /// What the server says when something is still in the group.
  String? refusal;

  @override
  Future<void> init() async {}

  @override
  Future<List<GroupDefinition>> getGroups({bool withCovers = false}) async =>
      groups;

  GroupDefinition _setArchived(int id, bool value) {
    final index = groups.indexWhere((group) => group.id == id);
    final current = groups[index];
    final updated = _group(
      current.id,
      current.name,
      parentGroupId: current.parentGroupId,
      isArchived: value,
      itemCount: current.itemCount,
    );
    groups = <GroupDefinition>[...groups]..[index] = updated;
    return updated;
  }

  @override
  Future<GroupDefinition> archiveGroup(int id) async {
    if (refusal != null) {
      throw GroupApiException(refusal!);
    }
    archived.add(id);
    return _setArchived(id, true);
  }

  @override
  Future<GroupDefinition> restoreGroup(int id) async {
    restored.add(id);
    return _setArchived(id, false);
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeItemRepository implements ItemRepository {
  @override
  Future<void> init() async {}

  @override
  Future<List<ItemDefinition>> getItems() async => const <ItemDefinition>[];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUnitRepository implements UnitRepository {
  @override
  Future<void> init() async {}

  @override
  Future<List<UnitDefinition>> getUnits() async => <UnitDefinition>[_unit];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeInventoryRepository implements InventoryRepository {
  @override
  Future<void> init() async {}

  @override
  Future<void> seedIfEmpty() async {}

  @override
  Future<List<MaterialRecord>> getAllMaterials() async =>
      const <MaterialRecord>[];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_ArchivingGroupRepository> _openGroups(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1700, 1300);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final repository = _ArchivingGroupRepository();
  final groupsProvider = GroupsProvider(repository: repository);
  final itemsProvider = ItemsProvider(repository: _FakeItemRepository());
  final unitsProvider = UnitsProvider(repository: _FakeUnitRepository());
  await groupsProvider.initialize();
  await itemsProvider.initialize();
  await unitsProvider.initialize();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<GroupsProvider>.value(value: groupsProvider),
        ChangeNotifierProvider<ItemsProvider>.value(value: itemsProvider),
        ChangeNotifierProvider<UnitsProvider>.value(value: unitsProvider),
        ChangeNotifierProvider<InventoryProvider>(
          create: (_) =>
              InventoryProvider(repository: _FakeInventoryRepository()),
        ),
      ],
      child: const MaterialApp(home: GroupsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

Future<void> _unfold(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> _tapAction(WidgetTester tester, String label) async {
  final finder = find.widgetWithText(SoftActionLink, label);
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

void main() {
  group('the status filter', () {
    testWidgets('opens on the live groups and keeps the archived back', (
      tester,
    ) async {
      await _openGroups(tester);
      await _unfold(tester, 'Primary Group');

      expect(find.text('Spare Parts'), findsOneWidget);
      expect(
        find.text('Discontinued'),
        findsNothing,
        reason: 'an archived group used to sit in the live list, labelled '
            '"Active"',
      );
    });

    testWidgets('shows the archived ones when asked, labelled honestly', (
      tester,
    ) async {
      await _openGroups(tester);

      await tester.tap(find.text('Archived'));
      await tester.pumpAndSettle();

      expect(find.text('Discontinued'), findsOneWidget);
      expect(find.text('Spare Parts'), findsNothing);
      // The column reads from the group now, instead of printing "Active".
      expect(find.widgetWithText(SoftStatusPill, 'Archived'), findsWidgets);
    });

    testWidgets('All shows both', (tester) async {
      await _openGroups(tester);

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      await _unfold(tester, 'Primary Group');

      expect(find.text('Spare Parts'), findsOneWidget);
      expect(find.text('Discontinued'), findsOneWidget);
    });
  });

  group('archiving from the row', () {
    testWidgets('asks first, and says nothing is deleted', (tester) async {
      final repository = await _openGroups(tester);
      await _unfold(tester, 'Primary Group');

      // The child row, not the root: the root has a child and could not be
      // archived anyway.
      final rows = find.widgetWithText(SoftActionLink, 'Archive');
      await tester.ensureVisible(rows.last);
      await tester.pumpAndSettle();
      await tester.tap(rows.last);
      await tester.pumpAndSettle();

      expect(find.textContaining('Archive "Spare Parts"?'), findsOneWidget);
      expect(
        find.textContaining('Nothing is deleted'),
        findsOneWidget,
        reason: '"archive" reads as "destroy" to most people, and this one '
            'does not',
      );
      expect(repository.archived, isEmpty, reason: 'not until it is confirmed');

      await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
      await tester.pumpAndSettle();
      expect(repository.archived, <int>[2]);
    });

    testWidgets('an archived row offers Restore instead', (tester) async {
      final repository = await _openGroups(tester);

      await tester.tap(find.text('Archived'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(SoftActionLink, 'Archive'), findsNothing);
      await _tapAction(tester, 'Restore');

      expect(repository.restored, <int>[3]);
      // Restoring needs no confirmation: it puts something back.
      expect(find.textContaining('?'), findsNothing);
    });

    testWidgets('a refusal says what is still in the group', (tester) async {
      final repository = await _openGroups(tester);
      repository.refusal =
          '"Spare Parts" still holds 2 active items. Move or archive them '
          'first.';
      await _unfold(tester, 'Primary Group');

      final rows = find.widgetWithText(SoftActionLink, 'Archive');
      await tester.ensureVisible(rows.last);
      await tester.pumpAndSettle();
      await tester.tap(rows.last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
      await tester.pumpAndSettle();

      // The server's sentence, which names the thing to go and fix.
      expect(find.textContaining('still holds 2 active items'), findsOneWidget);
      expect(find.text('Spare Parts'), findsWidgets, reason: 'and it stayed');
    });
  });
}

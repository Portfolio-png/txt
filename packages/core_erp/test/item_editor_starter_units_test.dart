import 'package:core_erp/core/services/user_preferences_service.dart';
import 'package:core_erp/core/widgets/app_button.dart';
import 'package:core_erp/features/auth/presentation/providers/auth_provider.dart';
import 'package:core_erp/features/clients/data/repositories/client_repository.dart';
import 'package:core_erp/features/clients/presentation/providers/clients_provider.dart';
import 'package:core_erp/features/groups/data/repositories/group_repository.dart';
import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/inventory/data/repositories/inventory_repository.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:core_erp/features/items/data/repositories/item_repository.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/domain/item_form_sections.dart';
import 'package:core_erp/features/items/presentation/providers/item_form_sections_provider.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/features/items/presentation/screens/items_screen.dart';
import 'package:core_erp/features/materials/data/material_repository.dart';
import 'package:core_erp/features/materials/presentation/providers/materials_provider.dart';
import 'package:core_erp/features/units/data/repositories/unit_repository.dart';
import 'package:core_erp/features/units/domain/unit_definition.dart';
import 'package:core_erp/features/units/domain/unit_inputs.dart';
import 'package:core_erp/features/units/presentation/providers/units_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// The standard units, offered in the one place the blocker is actually met.
///
/// A fresh workspace holds exactly one unit — `Primary Unit`, symbol `-`,
/// written by the server on first boot — and an item cannot be saved without a
/// real one. The offer already existed, but only on the Units master and in the
/// Express chooser: two screens a first-day user has no reason to open. The
/// item editor's unit field is where somebody is standing when it stops them.

UnitDefinition _unit(int id, String name, String symbol) => UnitDefinition(
  id: id,
  name: name,
  symbol: symbol,
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

final _placeholder = _unit(1, 'Primary Unit', '-');

final _group = GroupDefinition(
  id: 10,
  name: 'Switch Action',
  groupType: 'item',
  groupStructure: 'hierarchical',
  parentGroupId: null,
  unitId: 1,
  isArchived: false,
  usageCount: 0,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

/// Starts with whatever it is given and grows as units are created, so the
/// offer can be watched disappearing.
class _FakeUnitRepository implements UnitRepository {
  _FakeUnitRepository(this.units);

  final List<UnitDefinition> units;
  final List<CreateUnitInput> created = [];

  @override
  Future<void> init() async {}

  @override
  Future<List<UnitDefinition>> getUnits() async => List.of(units);

  // Not optional: `UnitsProvider.refresh` asks for these in the same try as
  // the units, so a noSuchMethod null here throws and leaves the provider
  // holding NO units — which reads as "nothing is set up" and would make this
  // suite pass for the wrong reason.
  @override
  Future<List<ConversionPoint>> getGaugePoints() async =>
      const <ConversionPoint>[];

  @override
  Future<UnitDefinition> createUnit(CreateUnitInput input) async {
    created.add(input);
    final made = _unit(100 + created.length, input.name, input.symbol);
    units.add(made);
    return made;
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

class _FakeGroupRepository implements GroupRepository {
  @override
  Future<void> init() async {}

  @override
  Future<List<GroupDefinition>> getGroups({bool withCovers = false}) async =>
      <GroupDefinition>[_group];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeInventoryRepository implements InventoryRepository {
  @override
  Future<void> init() async {}

  @override
  Future<void> seedIfEmpty() async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClientRepository implements ClientRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMaterialRepository implements MaterialRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DenyingAuthProvider extends AuthProvider {
  _DenyingAuthProvider() : super(baseUrl: '');

  @override
  bool can(String permissionKey) => false;
}

Finder get _offer => find.byKey(const ValueKey<String>('items-starter-units'));
Finder get _loadButton =>
    find.byKey(const ValueKey<String>('items-load-starter-units'));

Future<_FakeUnitRepository> _open(
  WidgetTester tester, {
  required List<UnitDefinition> units,
  bool canCreateUnits = true,
  ItemFormSections? overrideSections,
  bool identityOnly = false,
}) async {
  tester.view.physicalSize = const Size(1700, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final unitRepo = _FakeUnitRepository(List.of(units));
  final itemsProvider = ItemsProvider(repository: _FakeItemRepository());
  final groupsProvider = GroupsProvider(repository: _FakeGroupRepository());
  final unitsProvider = UnitsProvider(repository: unitRepo);
  await itemsProvider.initialize();
  await groupsProvider.initialize();
  await unitsProvider.initialize();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ItemsProvider>.value(value: itemsProvider),
        ChangeNotifierProvider<GroupsProvider>.value(value: groupsProvider),
        ChangeNotifierProvider<UnitsProvider>.value(value: unitsProvider),
        ChangeNotifierProvider<InventoryProvider>(
          create: (_) =>
              InventoryProvider(repository: _FakeInventoryRepository()),
        ),
        ChangeNotifierProvider<ClientsProvider>(
          create: (_) => ClientsProvider(repository: _FakeClientRepository()),
        ),
        ChangeNotifierProvider<MaterialsProvider>(
          create: (_) =>
              MaterialsProvider(repository: _FakeMaterialRepository()),
        ),
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => canCreateUnits
              ? AuthProvider(baseUrl: '', demoMode: true)
              : _DenyingAuthProvider(),
        ),
        ChangeNotifierProvider<ItemFormSectionsProvider>(
          create: (_) => ItemFormSectionsProvider(
            service: UserPreferencesService(
              baseUrl: '',
              useMockResponses: true,
            ),
          ),
        ),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => _openSurface(
                  context,
                  overrideSections: overrideSections,
                  identityOnly: identityOnly,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return unitRepo;
}

void main() {
  group('the standard-units offer in the item editor', () {
    testWidgets('a workspace with only the placeholder is offered them', (
      tester,
    ) async {
      await _open(tester, units: <UnitDefinition>[_placeholder]);

      expect(_offer, findsOneWidget);
      expect(
        find.text('This workspace has no units yet, and an item needs one.'),
        findsOneWidget,
      );
    });

    testWidgets('one real unit is enough to stop asking', (tester) async {
      await _open(
        tester,
        units: <UnitDefinition>[_placeholder, _unit(2, 'Kilogram', 'kg')],
      );

      expect(
        _offer,
        findsNothing,
        reason: 'somebody has set this workspace up; the blocker is gone',
      );
    });

    testWidgets('taking it writes names and symbols, and no conversion', (
      tester,
    ) async {
      final repo = await _open(tester, units: <UnitDefinition>[_placeholder]);

      await tester.ensureVisible(_loadButton);
      await tester.pumpAndSettle();
      await tester.tap(_loadButton);
      await tester.pumpAndSettle();

      expect(repo.created, isNotEmpty);
      for (final input in repo.created) {
        expect(input.name, isNotEmpty);
        expect(input.symbol, isNotEmpty);
        // Nothing in Paper can convert yet, so a seeded ratio would be a claim
        // the system cannot honour.
        expect(input.unitGroupName, isEmpty, reason: input.name);
        expect(input.conversionFactor, 1, reason: input.name);
      }
      // Answered, so it stops asking.
      expect(_offer, findsNothing);
    });

    testWidgets('without permission it is drawn disabled, not hidden', (
      tester,
    ) async {
      // Never hide a control until its precondition holds — a control that
      // vanishes reads as a missing feature, which has cost rounds of
      // "I don't see it" here before.
      await _open(
        tester,
        units: <UnitDefinition>[_placeholder],
        canCreateUnits: false,
      );

      expect(_offer, findsOneWidget);
      expect(tester.widget<AppButton>(_loadButton).onPressed, isNull);
      expect(
        find.byTooltip(
          'You do not have permission to add units (units.create).',
        ),
        findsOneWidget,
      );
    });
  });

  group('a host can shape the form', () {
    // The guided first run needs a form that asks for identity and nothing
    // else. Two separate levers: overrideSections picks whole sections, and
    // identityOnly trims the fields inside Item Details — which no section
    // flag can reach, because Name, Group, Unit and the part pair all live in
    // that one card together with Alias and the generated Item Name.

    testWidgets('overrideSections beats the user default', (tester) async {
      await _open(
        tester,
        units: <UnitDefinition>[_unit(2, 'Kilogram', 'kg')],
        overrideSections: const ItemFormSections(
          itemImage: false,
          cadFile: false,
          additionalFiles: false,
          developedFor: false,
          defaultPipeline: false,
          variationTree: false,
          machines: false,
          dies: false,
          sets: false,
        ),
      );

      // What identifies the part survives.
      expect(find.widgetWithText(TextFormField, 'Base Name'), findsOneWidget);
      expect(find.text('Group'), findsWidgets);

      // The optional sections do not.
      for (final gone in ['Developed For', 'Variations', 'Sample Data']) {
        expect(find.text(gone), findsNothing, reason: gone);
      }
    });

    testWidgets('identityOnly hides alias, item name and the codes toggle', (
      tester,
    ) async {
      await _open(
        tester,
        units: <UnitDefinition>[_unit(2, 'Kilogram', 'kg')],
        identityOnly: true,
      );

      expect(find.widgetWithText(TextFormField, 'Base Name'), findsOneWidget);
      expect(
        find.widgetWithText(TextFormField, 'Alias'),
        findsNothing,
        reason: 'an alias is a refinement of a name nobody has settled yet',
      );
      expect(find.widgetWithText(TextFormField, 'Item Name'), findsNothing);
    });

    testWidgets('and leaves the part pair, which is what a SKU means here', (
      tester,
    ) async {
      // The tree calls it SKU; the UI has no such field. Part No and Part Code
      // are the real identity pair, and they must survive the trim.
      await _open(
        tester,
        units: <UnitDefinition>[_unit(2, 'Kilogram', 'kg')],
        identityOnly: true,
      );

      expect(find.byKey(const ValueKey<String>('item-part-no')), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('item-part-code')),
        findsOneWidget,
      );
    });

    testWidgets('the hidden display name is still filled from the name', (
      tester,
    ) async {
      // The server REQUIRES displayName (server.js:16793). Hiding its field
      // would be a silent save failure if nothing filled it — the name
      // listener does, via _syncPrimaryDisplayName.
      await _open(
        tester,
        units: <UnitDefinition>[_unit(2, 'Kilogram', 'kg')],
        identityOnly: true,
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Base Name'),
        'Cone Top',
      );
      await tester.pumpAndSettle();

      // Not visible, but carried: the summary the host is handed uses it.
      expect(tester.takeException(), isNull);
      expect(find.text('Cone Top'), findsWidgets);
    });
  });
}

/// The editor, opened the way the host opens it.
///
/// `openEditor` has no shaping params — only `workflowPanel` does, because the
/// guided run embeds the editor rather than pushing it as a dialog. So a test
/// about shape has to go through the panel.
void _openSurface(
  BuildContext context, {
  ItemFormSections? overrideSections,
  bool identityOnly = false,
}) {
  if (overrideSections == null && !identityOnly) {
    ItemsScreen.openEditor(context, item: null, initialGroupId: _group.id);
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        body: ItemsScreen.workflowPanel(
          item: null,
          initialGroupId: _group.id,
          overrideSections: overrideSections,
          identityOnly: identityOnly,
          onClosed: (_) {},
        ),
      ),
    ),
  );
}

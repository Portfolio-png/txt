import 'package:core_erp/features/items/presentation/providers/item_form_sections_provider.dart';
import 'package:core_erp/features/process_routes/data/process_route_service.dart';
import 'package:core_erp/core/app_flow_hooks.dart';
import 'package:core_erp/core/services/user_preferences_service.dart';
import 'package:core_erp/features/auth/presentation/providers/auth_provider.dart';
import 'package:core_erp/features/clients/data/repositories/client_repository.dart';
import 'package:core_erp/features/clients/data/repositories/sub_contractor_repository.dart';
import 'package:core_erp/features/clients/presentation/providers/clients_provider.dart';
import 'package:core_erp/features/clients/presentation/providers/sub_contractors_provider.dart';
import 'package:core_erp/features/departments/data/repositories/departments_repository.dart';
import 'package:core_erp/features/departments/presentation/providers/departments_provider.dart';
import 'package:core_erp/features/groups/presentation/screens/component_creation_screen.dart';
import 'package:core_erp/features/groups/presentation/screens/creation_wizard_kinds.dart';
import 'package:core_erp/features/inventory/data/repositories/inventory_repository.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:core_erp/features/items/data/repositories/item_repository.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/features/groups/data/repositories/group_repository.dart';
import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/materials/data/material_repository.dart';
import 'package:core_erp/features/materials/presentation/providers/materials_provider.dart';
import 'package:core_erp/features/units/data/repositories/unit_repository.dart';
import 'package:core_erp/features/units/domain/unit_definition.dart';
import 'package:core_erp/features/units/presentation/providers/units_provider.dart';
import 'package:core_erp/features/vendors/data/repositories/vendor_repository.dart';
import 'package:core_erp/features/vendors/presentation/providers/vendors_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Every kind the creation window can put in its middle column, rendered once.
///
/// Until now only `item` and a stubbed `die` were ever exercised: eleven of the
/// thirteen kinds had never been built in a test at all, and
/// `AppFlowHooks.machineEditor` was registered nowhere. That was survivable
/// while the window had one door, on the items master, where nobody reaches for
/// a department. The Masters header's Express button makes all thirteen a
/// click away, so each one needs to be known to render.
///
/// This asserts the modest thing worth asserting automatically — the editor
/// builds, and it is not the "can only be created inside the app" fallback.
/// How each one *looks* in the middle tile is still a question for eyes.

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

final _group = GroupDefinition(
  id: 1,
  name: 'Primary Group',
  groupType: 'item',
  groupStructure: 'hierarchical',
  parentGroupId: null,
  unitId: 1,
  isArchived: false,
  usageCount: 0,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

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
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMaterialRepository implements MaterialRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClientRepository implements ClientRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSubContractorRepository implements SubContractorRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeVendorRepository implements VendorRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDepartmentsRepository implements DepartmentsRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Stands in for the host app's die and machine editors, which are registered
/// by the shell and so are never present in a test by themselves.
Widget _stubEditor(
  String label,
  BuildContext context, {
  required ValueChanged<CreatedRecord> onSaved,
  required VoidCallback onCancel,
}) {
  return Center(child: Text('Stub $label editor'));
}

Future<void> pumpKind(WidgetTester tester, String kind) async {
  tester.view.physicalSize = const Size(1800, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ItemsProvider>(
          create: (_) => ItemsProvider(repository: _FakeItemRepository()),
        ),
        ChangeNotifierProvider<GroupsProvider>(
          create: (_) => GroupsProvider(repository: _FakeGroupRepository()),
        ),
        ChangeNotifierProvider<UnitsProvider>(
          create: (_) => UnitsProvider(repository: _FakeUnitRepository()),
        ),
        ChangeNotifierProvider<InventoryProvider>(
          create: (_) =>
              InventoryProvider(repository: _FakeInventoryRepository()),
        ),
        ChangeNotifierProvider<MaterialsProvider>(
          create: (_) =>
              MaterialsProvider(repository: _FakeMaterialRepository()),
        ),
        ChangeNotifierProvider<ClientsProvider>(
          create: (_) =>
              ClientsProvider(repository: _FakeClientRepository()),
        ),
        ChangeNotifierProvider<SubContractorsProvider>(
          create: (_) => SubContractorsProvider(
            repository: _FakeSubContractorRepository(),
          ),
        ),
        ChangeNotifierProvider<VendorsProvider>(
          create: (_) =>
              VendorsProvider(repository: _FakeVendorRepository()),
        ),
        ChangeNotifierProvider<DepartmentsProvider>(
          create: (_) =>
              DepartmentsProvider(repository: _FakeDepartmentsRepository()),
        ),
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(baseUrl: '', demoMode: true),
        ),
        ChangeNotifierProvider<ItemFormSectionsProvider>(
          create: (_) => ItemFormSectionsProvider(
            service: UserPreferencesService(
              baseUrl: '',
              useMockResponses: true,
            ),
          ),
        ),
        // The Route card needs this, and without it the panel degrades to
        // "Routing is not available in this build." — which this test would
        // happily pass, having rendered nothing of the real card.
        Provider<ProcessRouteService>(
          create: (_) =>
              ProcessRouteService(baseUrl: '', useMockResponses: true),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ComponentCreationDialog(
            itemsOnly: true,
            title: 'Express entry',
            // The kind under test is the only tile, so it is the active
            // one and its editor is what the middle column builds.
            initialKinds: <String>[kind],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('every kind in the catalogue renders', () {
    setUp(() {
      AppFlowHooks.dieEditor = (context, {required onSaved, required onCancel}) =>
          _stubEditor('die', context, onSaved: onSaved, onCancel: onCancel);
      AppFlowHooks.machineEditor =
          (context, {required onSaved, required onCancel}) => _stubEditor(
            'machine',
            context,
            onSaved: onSaved,
            onCancel: onCancel,
          );
    });

    tearDown(() {
      AppFlowHooks.dieEditor = null;
      AppFlowHooks.machineEditor = null;
    });

    for (final spec in CreationKinds.catalog) {
      testWidgets('${spec.label} (${spec.key})', (tester) async {
        await pumpKind(tester, spec.key);

        expect(
          tester.takeException(),
          isNull,
          reason: '${spec.label} threw while building',
        );
        expect(
          find.text('${spec.label}s can only be created inside the app.'),
          findsNothing,
          reason: '${spec.label} has no editor here — a hook is unregistered',
        );
        // Its own tile is in the lineup, so the window did open on it.
        expect(
          find.byKey(ValueKey('creation_kind_${spec.key}')),
          findsOneWidget,
        );
      });
    }
  });
}

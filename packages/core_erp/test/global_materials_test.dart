import 'package:core_erp/features/materials/data/material_repository.dart';
import 'package:core_erp/features/materials/domain/global_materials.dart';
import 'package:core_erp/features/materials/domain/material_definition.dart';
import 'package:core_erp/features/materials/presentation/providers/materials_provider.dart';
import 'package:core_erp/features/materials/presentation/widgets/global_materials_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// The global materials catalogue and the dialog that shows it.

/// The master a shop might have: a few of the catalogue's entries, so the
/// dialog has both ticked and unticked rows to show. Its own list rather than
/// the repository's demo data, which is free to change with the catalogue.
class _FakeMaterialRepository extends MaterialRepository {
  _FakeMaterialRepository() : super(useMockResponses: true);

  static const List<MaterialDefinition> _master = <MaterialDefinition>[
    MaterialDefinition(id: 1, name: 'MS', densityGCm3: 7.85),
    MaterialDefinition(id: 2, name: 'Aluminium', densityGCm3: 2.70),
    MaterialDefinition(id: 3, name: 'Brass', densityGCm3: 8.50),
    MaterialDefinition(id: 4, name: 'Copper', densityGCm3: 8.96),
    MaterialDefinition(
      id: 5,
      name: 'Nylon',
      densityGCm3: 1.15,
      category: 'plastic',
    ),
  ];

  @override
  Future<List<MaterialDefinition>> list({bool includeArchived = false}) async =>
      _master;
}

void main() {
  group('catalogue', () {
    test('mirrors the seed migration: 36 materials, no duplicate names', () {
      expect(globalMaterials.length, 36);
      final names = globalMaterials.map((m) => m.name.toLowerCase()).toSet();
      expect(names.length, globalMaterials.length);
    });

    test('every density is a real one, in g/cm³ not kg/m³', () {
      for (final material in globalMaterials) {
        expect(material.densityGCm3, greaterThanOrEqualTo(0.01));
        expect(material.densityGCm3, lessThanOrEqualTo(30));
        expect(globalMaterialCategories, contains(material.category));
      }
    });

    test('groups by category in display order, common metals first', () {
      final grouped = globalMaterialsByCategory;
      expect(grouped.keys.toList(), globalMaterialCategories);
      expect(grouped['metal']!.first.name, 'MS');
      expect(
        grouped.values.fold<int>(0, (n, list) => n + list.length),
        globalMaterials.length,
      );
    });

    test('export rows carry name, density and whether it is in the master', () {
      final rows = globalMaterialExportRows(masterNames: ['brass', 'Gold ']);
      expect(rows.length, globalMaterials.length);
      final brass = rows.firstWhere((r) => r['Material'] == 'Brass');
      expect(brass['Density (g/cm³)'], '8.50');
      expect(brass['Category'], 'Metals');
      expect(brass['In your master'], 'Yes');
      expect(
        rows.firstWhere((r) => r['Material'] == 'Gold')['In your master'],
        'Yes',
      );
      expect(
        rows.firstWhere((r) => r['Material'] == 'Copper')['In your master'],
        'No',
      );
    });
  });

  group('dialog', () {
    Future<MaterialsProvider> loadedProvider() async {
      final provider = MaterialsProvider(repository: _FakeMaterialRepository());
      await provider.load();
      return provider;
    }

    Future<void> pumpDialog(WidgetTester tester, MaterialsProvider p) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ChangeNotifierProvider<MaterialsProvider>.value(
          value: p,
          child: const MaterialApp(
            home: Scaffold(body: GlobalMaterialsLibraryDialog()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    CheckboxListTile tileFor(WidgetTester tester, String name) =>
        tester.widget<CheckboxListTile>(
          find.byKey(ValueKey('global-material-$name')),
        );

    testWidgets('materials already in the master show ticked and locked', (
      tester,
    ) async {
      final provider = await loadedProvider();
      await pumpDialog(tester, provider);

      expect(find.text('Global Materials Library'), findsOneWidget);
      expect(find.textContaining('5 of 36 are in your master'), findsOneWidget);

      final steel = tileFor(tester, 'MS');
      expect(steel.value, isTrue);
      expect(steel.onChanged, isNull);

      final gold = tileFor(tester, 'Gold');
      expect(gold.value, isFalse);
      expect(gold.onChanged, isNotNull);
      expect(find.text('19.32 g/cm³'), findsOneWidget);
    });

    testWidgets('ticking a material adds it to the master', (tester) async {
      final provider = await loadedProvider();
      await pumpDialog(tester, provider);

      final gold = find.byKey(const ValueKey('global-material-Gold'));
      await tester.ensureVisible(gold);
      await tester.pumpAndSettle();
      await tester.tap(gold);
      await tester.pumpAndSettle();

      expect(provider.materials.any((m) => m.name == 'Gold'), isTrue);
      expect(tileFor(tester, 'Gold').value, isTrue);
      expect(find.textContaining('6 of 36 are in your master'), findsOneWidget);
    });

    testWidgets('Download opens the export dialog for the whole list', (
      tester,
    ) async {
      final provider = await loadedProvider();
      await pumpDialog(tester, provider);

      await tester.tap(find.byKey(const ValueKey('global-materials-download')));
      await tester.pumpAndSettle();

      expect(find.text('Export Materials'), findsOneWidget);
      expect(find.text('CSV'), findsOneWidget);
      expect(find.text('Excel'), findsOneWidget);
    });
  });
}

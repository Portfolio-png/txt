import 'package:core_erp/features/materials/domain/material_definition.dart';
import 'package:core_erp/features/production_pipelines/domain/pen_paper_baseline.dart';
import 'package:core_erp/features/production_pipelines/presentation/widgets/master_data_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The join between the two features: sheet planning knows the volume, the
/// material master knows the density, and the plan is only worth costing if the
/// window actually puts them together on screen.
void main() {
  const materials = <MaterialDefinition>[
    MaterialDefinition(id: 1, name: 'Steel / MS', densityGCm3: 7.85),
    MaterialDefinition(id: 2, name: 'Aluminium', densityGCm3: 2.70),
  ];

  // A 4' x 8' sheet at 1.6 mm, sheared into four 300 mm strips.
  const planned = PenPaperBaseline(
    sheetWidthInches: 48,
    sheetHeightInches: 96,
    sheetThicknessMm: 1.6,
    bands: [SheetCutGroup(sizeMm: 300, count: 4)],
    kerfMm: 3,
  );

  Future<PenPaperBaseline?> open(
    WidgetTester tester, {
    PenPaperBaseline baseline = planned,
    List<MaterialDefinition> master = materials,
  }) async {
    PenPaperBaseline? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showMasterDataDialog(
                    context,
                    baseline: baseline,
                    materials: master,
                    pipelineName: 'Shear → Press',
                    itemName: 'MS Bracket',
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  /// Open the picker and take the material with this id.
  Future<void> choose(WidgetTester tester, int id) async {
    await tester.tap(find.byKey(const ValueKey<String>('sheet-material')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey<String>('material-option-$id')));
    await tester.pumpAndSettle();
  }

  void bigScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('with no master, the window asks for no material', (
    tester,
  ) async {
    bigScreen(tester);
    await open(tester, master: const []);
    // A shop that has not filled in densities plans in millimetres, and the
    // window says nothing about weight rather than guessing one.
    expect(find.text('MATERIAL'), findsNothing);
    expect(find.textContaining('kg'), findsNothing);
  });

  testWidgets('choosing a material puts a weight on the plan', (tester) async {
    bigScreen(tester);
    await open(tester);

    expect(find.text('MATERIAL'), findsOneWidget);
    // Nothing chosen yet, so no weight is claimed.
    expect(find.text('Sheet in'), findsNothing);

    await choose(tester, 1);

    // 4' x 8' x 1.6 mm of mild steel is 37.3 kg, and the breakdown has to
    // account for where every kilo of it goes.
    expect(find.text('IN STEEL / MS'), findsOneWidget);
    expect(find.text('Sheet in'), findsOneWidget);
    expect(find.text('37.3 kg'), findsOneWidget);
    expect(find.text('Parts out'), findsOneWidget);
    // Three 3 mm cuts is real weight that reaches neither parts nor rack.
    expect(find.text('Blade and trim'), findsOneWidget);
  });

  testWidgets('the same plan in aluminium weighs a third as much', (
    tester,
  ) async {
    bigScreen(tester);
    await open(tester);

    await choose(tester, 2);

    expect(find.text('IN ALUMINIUM'), findsOneWidget);
    expect(find.text('12.8 kg'), findsOneWidget);
    // And the steel figure is gone, not left beside it.
    expect(find.text('37.3 kg'), findsNothing);
  });

  testWidgets('the chosen material comes back on the saved baseline', (
    tester,
  ) async {
    bigScreen(tester);
    PenPaperBaseline? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  saved = await showMasterDataDialog(
                    context,
                    baseline: planned,
                    materials: materials,
                    pipelineName: 'Shear → Press',
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await choose(tester, 1);

    await tester.tap(find.text('Save Master Data'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.materialName, 'Steel / MS');
  });

  testWidgets('a material the master no longer has is still named', (
    tester,
  ) async {
    bigScreen(tester);
    // An old plan cut from something since archived. The record still says
    // what it was, it just cannot be weighed any more.
    await open(tester, baseline: planned.copyWith(materialName: 'Inconel 625'));
    expect(find.textContaining('Inconel 625'), findsOneWidget);
    expect(find.text('Sheet in'), findsNothing);
  });

  testWidgets('the list stays inside the window instead of covering it', (
    tester,
  ) async {
    bigScreen(tester);
    // The whole catalogue, which is what made a plain dropdown unusable: it
    // opened a menu taller than the dialog, over the controls beside it.
    await open(
      tester,
      master: List<MaterialDefinition>.generate(
        36,
        (index) => MaterialDefinition(
          id: index + 1,
          name: 'Material ${index + 1}',
          densityGCm3: 1 + index * 0.5,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('sheet-material')));
    await tester.pumpAndSettle();

    final menu = tester.getRect(
      find.byKey(const ValueKey<String>('material-search')),
    );
    final window = tester.getRect(find.byType(MaterialApp));
    expect(menu.right, lessThanOrEqualTo(window.right));
    expect(menu.left, greaterThanOrEqualTo(window.left));
    expect(menu.top, greaterThanOrEqualTo(window.top));

    // Bounded, not as tall as the catalogue: the last material is not painted.
    expect(find.text('Material 1'), findsOneWidget);
    expect(find.text('Material 36'), findsNothing);
  });

  testWidgets('searching narrows the list instead of scrolling it', (
    tester,
  ) async {
    bigScreen(tester);
    await open(tester);

    await tester.tap(find.byKey(const ValueKey<String>('sheet-material')));
    await tester.pumpAndSettle();
    expect(find.text('Steel / MS'), findsOneWidget);
    expect(find.text('Aluminium'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('material-search')),
      'alum',
    );
    await tester.pumpAndSettle();
    expect(find.text('Aluminium'), findsOneWidget);
    expect(find.text('Steel / MS'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey<String>('material-search')),
      'inconel',
    );
    await tester.pumpAndSettle();
    expect(find.text('No material by that name.'), findsOneWidget);
  });

  testWidgets('a chosen material can be unset again', (tester) async {
    bigScreen(tester);
    await open(tester);
    await choose(tester, 1);
    expect(find.text('Sheet in'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('sheet-material')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('material-option-none')),
    );
    await tester.pumpAndSettle();

    // Back to planning in millimetres, with no weight claimed.
    expect(find.text('Sheet in'), findsNothing);
    expect(find.text('37.3 kg'), findsNothing);
  });
}

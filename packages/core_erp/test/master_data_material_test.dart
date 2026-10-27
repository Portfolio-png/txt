import 'package:core_erp/features/materials/domain/material_definition.dart';
import 'package:core_erp/features/production_pipelines/domain/pen_paper_baseline.dart';
import 'package:core_erp/features/production_pipelines/presentation/widgets/master_data_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The alloy, picked from the material master in a host with no Alloy column
/// of its own (the item screen's dialog). By name only: what an alloy weighs
/// depends on its grade, so no weight is ever worked out from it.
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

  testWidgets('with no master, the window asks for no alloy', (tester) async {
    bigScreen(tester);
    await open(tester, master: const []);
    expect(find.text('ALLOY'), findsNothing);
    expect(find.textContaining('kg'), findsNothing);
  });

  testWidgets('choosing an alloy names it, and claims no weight', (
    tester,
  ) async {
    bigScreen(tester);
    await open(tester);
    expect(find.text('ALLOY'), findsOneWidget);

    await choose(tester, 2);
    expect(find.text('Aluminium'), findsWidgets);
    // The density-made breakdown is gone for good.
    expect(find.text('Sheet in'), findsNothing);
    expect(find.text('IN ALUMINIUM'), findsNothing);
    expect(find.textContaining('g/cm³'), findsNothing);
  });

  testWidgets('the alloy and its grade come back on the saved baseline', (
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
    await tester.tap(find.byKey(const ValueKey<String>('sheet-grade')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second grade').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save Master Data'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.materialName, 'Steel / MS');
    expect(saved!.materialGrade, 'Second');
  });

  testWidgets('a material the master no longer has is still named', (
    tester,
  ) async {
    bigScreen(tester);
    // An old plan cut from something since archived still says what it was.
    await open(tester, baseline: planned.copyWith(materialName: 'Inconel 625'));
    expect(find.textContaining('Inconel 625'), findsOneWidget);
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

  testWidgets('a chosen alloy can be unset again', (tester) async {
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
                    baseline: planned.copyWith(materialName: 'Aluminium'),
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

    await tester.tap(find.byKey(const ValueKey<String>('sheet-material')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('material-option-none')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Master Data'));
    await tester.pumpAndSettle();
    expect(saved!.materialName, '');
  });
}

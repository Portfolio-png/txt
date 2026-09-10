import 'package:core_erp/core/widgets/searchable_select.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The picker had no way to offer a richer answer than picking a row without
/// stacking a second dialog on top of itself. These pin the contract the
/// inline panel adds.
Future<String?> _open(
  WidgetTester tester, {
  required SearchableSelectInlinePanelBuilder<String> panel,
}) async {
  tester.view.physicalSize = const Size(900, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  String? picked;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final result = await showSearchableSelectDialog<String>(
                context: context,
                options: const [
                  SearchableSelectOption(value: 'a', label: 'Bulb'),
                  SearchableSelectOption(value: 'b', label: 'Cone'),
                ],
                inlinePanelBuilder: panel,
              );
              picked = result?.value;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return picked;
}

void main() {
  testWidgets('a null panel leaves the picker exactly as it was', (
    tester,
  ) async {
    await _open(tester, panel: (context, panel) => null);

    expect(find.text('Bulb'), findsOneWidget);
    expect(find.text('Cone'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the panel renders inside the picker, above the options', (
    tester,
  ) async {
    await _open(
      tester,
      panel: (context, panel) => const Text('PANEL'),
    );

    // Both are on screen at once — no second dialog was pushed.
    expect(find.text('PANEL'), findsOneWidget);
    expect(find.text('Bulb'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the panel sees the query and can react to it', (tester) async {
    await _open(
      tester,
      panel: (context, panel) =>
          panel.query.contains('+') ? const Text('EXPRESSION') : null,
    );

    expect(find.text('EXPRESSION'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Bulb + Red');
    await tester.pumpAndSettle();
    expect(find.text('EXPRESSION'), findsOneWidget);
  });

  testWidgets('selecting from the panel closes the picker with that option', (
    tester,
  ) async {
    late void Function(SearchableSelectOption<String>) capturedSelect;
    late void Function(String) capturedSetQuery;
    await _open(
      tester,
      panel: (context, panel) {
        capturedSelect = panel.select;
        capturedSetQuery = panel.setQuery;
        return const Text('PANEL');
      },
    );

    capturedSelect(
      const SearchableSelectOption(value: 'made-here', label: 'Made here'),
    );
    await tester.pumpAndSettle();

    // The picker is gone and it answered with the panel's option.
    expect(find.text('PANEL'), findsNothing);
    expect(find.text('Bulb'), findsNothing);
    expect(capturedSetQuery, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('setQuery writes back into the picker\'s own search box', (
    tester,
  ) async {
    late void Function(String) setQuery;
    await _open(
      tester,
      panel: (context, panel) {
        setQuery = panel.setQuery;
        // Echoing the query proves the panel reads the one field, and does
        // not keep a copy that can drift.
        return Text('Q:${panel.query}');
      },
    );

    await tester.enterText(find.byType(TextField), 'Bul');
    await tester.pumpAndSettle();
    expect(find.text('Q:Bul'), findsOneWidget);

    setQuery('Bulb + Red');
    await tester.pumpAndSettle();

    // Both the field and the panel moved, together.
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'Bulb + Red',
    );
    expect(find.text('Q:Bulb + Red'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

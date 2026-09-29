import 'package:core_erp/features/materials/data/material_repository.dart';
import 'package:core_erp/features/materials/domain/material_definition.dart';
import 'package:core_erp/features/materials/presentation/providers/materials_provider.dart';
import 'package:core_erp/features/materials/presentation/screens/materials_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// A master editor embedded in a host (the creation wizard) hands its result
/// to callbacks instead of popping the route it sits in.
void main() {
  Future<void> pumpPanel(
    WidgetTester tester, {
    required ValueChanged<MaterialDefinition> onSaved,
    required VoidCallback onCancel,
  }) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => MaterialsProvider(
          repository: MaterialRepository(useMockResponses: true),
        ),
        child: MaterialApp(
          home: Scaffold(
            body: MaterialsScreen.editorPanel(
              onSaved: onSaved,
              onCancel: onCancel,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('material panel hands the saved material to the host', (
    tester,
  ) async {
    MaterialDefinition? saved;
    await pumpPanel(tester, onSaved: (m) => saved = m, onCancel: () {});

    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Brass');
    await tester.enterText(find.widgetWithText(TextField, 'Density'), '8.5');
    await tester.tap(find.text('Add Material').last);
    await tester.pumpAndSettle();

    expect(saved?.name, 'Brass');
    // Still on screen: nothing was popped.
    expect(find.widgetWithText(TextField, 'Name'), findsOneWidget);
  });

  testWidgets('material panel cancel calls the host, not the navigator', (
    tester,
  ) async {
    var cancelled = 0;
    await pumpPanel(tester, onSaved: (_) {}, onCancel: () => cancelled++);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();

    expect(cancelled, 2);
    expect(find.widgetWithText(TextField, 'Name'), findsOneWidget);
  });
}

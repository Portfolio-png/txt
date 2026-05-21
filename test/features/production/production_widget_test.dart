import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paper/features/production/providers/production_provider.dart';
import 'package:paper/features/production/providers/production_run_provider.dart';
import 'package:paper/features/production/screens/pipeline_builder_screen.dart';
import 'package:paper/features/production/screens/shop_floor_kiosk_screen.dart';
import 'package:paper/features/production/widgets/lock_key_setup_modal.dart';
import 'package:paper/features/production/widgets/material_ledger_closure_dialog.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('builder inspector keeps draft state when switching stages', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    final provider = ProductionProvider.seeded();
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      _ProductionHarness(
        provider: provider,
        child: const PipelineBuilderScreen(),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Reel Slitting'),
      'Edited Slitting',
    );
    await tester.tap(find.textContaining('Die Punching'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Reel Slitting').first);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Edited Slitting'), findsOneWidget);
  });

  testWidgets('N adds a stage and Delete removes selected stage with undo', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    final provider = ProductionProvider.seeded();
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      _ProductionHarness(
        provider: provider,
        child: const PipelineBuilderScreen(),
      ),
    );
    final initialCount = provider.blueprint.stages.length;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();
    expect(provider.blueprint.stages.length, initialCount + 1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.delete);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(provider.blueprint.stages.length, initialCount);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(provider.blueprint.stages.length, initialCount + 1);
  });

  testWidgets('kiosk macro buttons keep 64dp minimum target height', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    final provider = ProductionProvider.seeded();
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      _ProductionHarness(
        provider: provider,
        child: const ShopFloorKioskScreen(),
      ),
    );

    expect(
      tester.getSize(find.byKey(const Key('verify_start_button'))).height,
      64,
    );
    expect(
      tester.getSize(find.byKey(const Key('pause_resume_button'))).height,
      64,
    );
    expect(tester.getSize(find.byKey(const Key('closure_button'))).height, 64);
  });

  testWidgets('kiosk setup sheet keeps route-scoped production provider', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    final provider = ProductionProvider.seeded();
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<ProductionProvider>.value(value: provider),
            ChangeNotifierProvider<ProductionRunProvider>(
              create: (_) => ProductionRunProvider(),
            ),
          ],
          child: const Scaffold(body: ShopFloorKioskScreen()),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('verify_start_button')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('LOCK-KEY ASSET VERIFICATION'), findsOneWidget);
  });

  testWidgets('lock-key modal autofocuses machine scanner input', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    final provider = ProductionProvider.seeded();
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      _ProductionHarness(
        provider: provider,
        child: Builder(
          builder: (context) {
            return FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const LockKeySetupModal(),
              ),
              child: const Text('Open setup'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open setup'));
    await tester.pumpAndSettle();

    final scanner = find.descendant(
      of: find.byKey(const Key('machine_scanner_field')),
      matching: find.byType(TextField),
    );
    final machineField = tester.widget<TextField>(scanner);
    expect(machineField.focusNode?.hasFocus, isTrue);
  });

  testWidgets('lock-key modal sequential scanning logic', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    final provider = ProductionProvider.seeded();
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      _ProductionHarness(
        provider: provider,
        child: Builder(
          builder: (context) {
            return FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const LockKeySetupModal(),
              ),
              child: const Text('Open setup'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open setup'));
    await tester.pumpAndSettle();

    final scanner = find.descendant(
      of: find.byKey(const Key('machine_scanner_field')),
      matching: find.byType(TextField),
    );

    // 1. Initially, we should be prompted to scan machine
    expect(find.text('Scan Machine Barcode...'), findsOneWidget);

    // 2. Scan correct machine
    await tester.enterText(scanner, 'MC-SLIT-01');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // 3. Prompt should change to scan die
    expect(find.text('Scan Die Barcode...'), findsOneWidget);

    // 4. Scan WRONG die to trigger mismatch
    await tester.enterText(scanner, 'DIE-WRONG');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // 5. Warning chip should show mismatch error, and Start button is disabled
    expect(find.textContaining('MISMATCH'), findsOneWidget);
    final startButtonFinder = find.byKey(const Key('confirm_start_button'));
    if (startButtonFinder.evaluate().isNotEmpty) {
      final startButton = tester.widget<ElevatedButton>(startButtonFinder);
      expect(startButton.onPressed, isNull);
    }

    // 6. Reset scanner
    await tester.tap(find.byTooltip('Reset Scanner'));
    await tester.pumpAndSettle();

    // 7. Prompt is back to scan machine
    expect(find.text('Scan Machine Barcode...'), findsOneWidget);

    // 8. Scan correct machine and correct die
    await tester.enterText(scanner, 'MC-SLIT-01');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    await tester.enterText(scanner, 'DIE-1450-A');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // 9. Start button should be enabled
    final startButtonFinder2 = find.byKey(const Key('confirm_start_button'));
    final startButton2 = tester.widget<ElevatedButton>(startButtonFinder2);
    expect(startButton2.onPressed, isNotNull);
  });

  testWidgets('ledger closure dialog tactile buttons and balanced sliders', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    final provider = ProductionProvider.seeded();
    addTearDown(provider.dispose);

    // Setup run to be able to open ledger closure
    provider.verifyAssetSetup('MC-SLIT-01', 'DIE-1450-A');
    provider.startRun();
    provider.beginClosure();

    await tester.pumpWidget(
      _ProductionHarness(
        provider: provider,
        child: const MaterialLedgerClosureDialog(),
      ),
    );

    // Verify initial values
    expect(find.textContaining('510.00 Kg'), findsWidgets);

    // Tap Produced (+100) increment button (at index 1)
    await tester.tap(find.byIcon(Icons.add_rounded).at(1));
    await tester.pumpAndSettle();

    // Verify yield units changed
    expect(provider.goodYieldCount, 4950); // 4850 + 100

    // Drag the Good Yield slider
    final slider = find.byType(Slider).at(0);
    await tester.drag(slider, const Offset(-50, 0));
    await tester.pumpAndSettle();

    // Verify that the preview updates reactively
    expect(find.textContaining('STOCK_REEL_8821'), findsWidgets);
  });

  testWidgets('operator switcher dialog updates activeOperator in provider', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    final provider = ProductionProvider.seeded();
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      _ProductionHarness(
        provider: provider,
        child: const ShopFloorKioskScreen(),
      ),
    );

    // Find the profile switcher button and tap it
    await tester.tap(find.text('FL'));
    await tester.pumpAndSettle();

    // Verify that Operator Switcher Dialog is visible
    expect(find.text('OPERATOR SWITCHER'), findsOneWidget);

    // Press PIN digits 1, 2, 3, 4
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4'));
    await tester.pumpAndSettle();

    // Dialog should dismiss and active operator updates to OPERATOR-A
    expect(find.text('OPERATOR SWITCHER'), findsNothing);
    expect(provider.activeOperator, 'OPERATOR-A');
  });
}

class _ProductionHarness extends StatelessWidget {
  const _ProductionHarness({required this.provider, required this.child});

  final ProductionProvider provider;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ProductionProvider>.value(value: provider),
        ChangeNotifierProvider<ProductionRunProvider>(
          create: (_) => ProductionRunProvider(),
        ),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }
}

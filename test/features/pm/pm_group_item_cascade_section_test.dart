import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:paper/features/pm/presentation/widgets/pm_group_item_cascade_section.dart';

void main() {
  testWidgets('PMGroupItemCascadeSection renders screenshot fidelity grid and handles progressive versions', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PMGroupItemCascadeSection(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Assert Title and Screenshot Fidelity Elements
    expect(find.text('Hierarchy & Progressive Variation Matrix (PM Lab)'), findsOneWidget);
    expect(find.text('Group\nItem'), findsOneWidget); // Black side block from screenshot
    expect(find.text('Group'), findsWidgets);
    expect(find.text('Type (Sub Group)'), findsOneWidget);
    expect(find.text('Part Name (Item)'), findsOneWidget);
    expect(find.text('Part No'), findsWidgets);
    expect(find.text('Part Code'), findsWidgets);
    expect(find.text('Date'), findsWidgets);
    expect(find.text('Time'), findsWidgets);

    // 2. Assert Initial Active Values (from Screenshot)
    expect(find.text('Switch Action'), findsWidgets);
    expect(find.text('Dolly'), findsWidgets);
    expect(find.text('Patti'), findsWidgets);
    expect(find.text('48'), findsWidgets);
    expect(find.text('SADBP48'), findsWidgets);
    expect(find.text('15/05/2026'), findsWidgets);
    expect(find.text('10.05 AM'), findsWidgets);

    // 3. Assert Action Pills (Auto, Edit, Okey)
    expect(find.text('Auto'), findsWidgets);
    expect(find.text('Edit'), findsWidgets);
    expect(find.text('Okey'), findsWidgets);

    // 4. Assert Photo and CAD attachments for active variation
    expect(find.text('Variation Photo'), findsOneWidget);
    expect(find.text('CAD Drawing'), findsOneWidget);
    expect(find.text('Noting Timestamp'), findsOneWidget);
    expect(find.textContaining('SADBP48_RevA.step'), findsOneWidget);

    // 5. Stamp next progressive version
    final stampBtn = find.text('+ Progressive Stamp (#51)');
    expect(stampBtn, findsOneWidget);
    await tester.ensureVisible(stampBtn);
    await tester.tap(stampBtn);
    await tester.pump();
    // Dismiss toast by tapping it directly
    final toastFinder = find.textContaining('Stamped progressive version');
    if (toastFinder.evaluate().isNotEmpty) {
      await tester.tap(toastFinder);
      await tester.pumpAndSettle();
    }

    // New version 51 is created with SADBP51
    expect(find.text('#51 (SADBP51)'), findsWidgets);
    expect(find.text('SADBP51'), findsWidgets);

    // 6. Test Mode Switching: Miller Columns
    final millerBtn = find.byKey(const ValueKey('mode_btn_millerColumns'));
    expect(millerBtn, findsOneWidget);
    await tester.ensureVisible(millerBtn);
    await tester.tap(millerBtn);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('miller_columns_mode')), findsOneWidget);
    expect(find.text('1. Group'), findsOneWidget);
    expect(find.text('2. Sub Group'), findsOneWidget);
    expect(find.text('3. Item'), findsOneWidget);
    expect(find.text('4. Variations'), findsOneWidget);

    // 7. Test Mode Switching: Progressive Ledger
    final ledgerBtn = find.byKey(const ValueKey('mode_btn_progressiveLedger'));
    expect(ledgerBtn, findsOneWidget);
    await tester.ensureVisible(ledgerBtn);
    await tester.tap(ledgerBtn);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('progressive_ledger_mode')), findsOneWidget);
    expect(find.textContaining('#48'), findsWidgets);
    expect(find.textContaining('#49'), findsWidgets);
    expect(find.textContaining('#50'), findsWidgets);
    expect(find.textContaining('#51'), findsWidgets);

    // 8. Test Mode Switching: Fast-Entry Bar
    final fastBarBtn = find.byKey(const ValueKey('mode_btn_quickMatrixBar'));
    expect(fastBarBtn, findsOneWidget);
    await tester.ensureVisible(fastBarBtn);
    await tester.tap(fastBarBtn);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('quick_matrix_bar_mode')), findsOneWidget);
    expect(find.text('Stamp #Patti'), findsOneWidget);
  });
}

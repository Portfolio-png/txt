import 'package:core_erp/features/groups/data/repositories/group_repository.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/inventory/data/repositories/inventory_repository.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paper/features/produce/data/produce_sandbox_repository.dart';
import 'package:paper/features/produce/screens/produce_screen.dart';
import 'package:provider/provider.dart';

/// Every call fails, the way an unreachable backend would — the point is that
/// Produce never needs one.
class _OfflineInventoryRepository implements InventoryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<dynamic>.error(StateError('backend not available in tests'));
}

class _OfflineGroupRepository implements GroupRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<dynamic>.error(StateError('backend not available in tests'));
}

void main() {
  testWidgets('tapping a Produce run opens the sandbox live monitor', (tester) async {
    ProduceSandboxRepository.instance.reset();
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // The test font is far wider than the real one, so desktop-width rows
    // overflow here and nowhere else. Layout is not what this test is about.
    final defaultOnError = FlutterError.onError!;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      defaultOnError(details);
    };
    addTearDown(() => FlutterError.onError = defaultOnError);

    final inventoryRepo = _OfflineInventoryRepository();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<InventoryRepository>.value(value: inventoryRepo),
          ChangeNotifierProvider(
            create: (_) => InventoryProvider(repository: inventoryRepo),
          ),
          ChangeNotifierProvider(
            create: (_) => GroupsProvider(repository: _OfflineGroupRepository()),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: ProduceScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Order: ORD-2041'), findsOneWidget);

    await tester.tap(find.text('Order: ORD-2041'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Produce preview'), findsOneWidget);
    expect(find.text('ORDER'), findsOneWidget);
    expect(find.text('Complete Order'), findsOneWidget);

    // The canvas resolved the run and its template out of the sandbox: the
    // stage nodes of the carton line are on screen.
    expect(find.text('Cutting'), findsWidgets);
    expect(find.text('Printing'), findsWidgets);
  });

  test('sandbox run writes stay in memory', () async {
    final sandbox = ProduceSandboxRepository.instance..reset();
    final before = sandbox.runsNow.length;

    final run = await sandbox.createRun('tpl-carton', name: 'Test run');
    expect(sandbox.runsNow.length, before + 1);

    await sandbox.updateNodeMetrics(
      runId: run.id,
      nodeId: 'carton-cut',
      metrics: {'outputQty': 12.0},
    );
    final reloaded = await sandbox.getRun(run.id);
    expect(reloaded!.nodeMetrics['carton-cut']!['outputQty'], 12.0);

    await sandbox.deleteRun(run.id);
    expect(sandbox.runsNow.length, before);
  });
}

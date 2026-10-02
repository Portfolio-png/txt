import 'package:core_erp/features/links/data/entity_link_service.dart';
import 'package:core_erp/features/links/domain/entity_link.dart';
import 'package:core_erp/features/links/presentation/widgets/link_columns.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The column view over the link graph. Driven against the service's own demo
// graph, which is symmetric exactly as the store is — so a link made from the
// item's column has to show up in the die's, and that is the assertion that
// matters most here.

Widget _host(EntityLinkService service, {LinkColumnsController? controller}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 1400,
        height: 800,
        child: LinkColumns(
          service: service,
          controller: controller,
          columnWidth: 320,
        ),
      ),
    ),
  );
}

/// A link raises a toast, which sits across the TOP of the screen — exactly
/// where the next column's + button is. Waiting it out keeps the taps that
/// follow landing on the columns rather than on the notice.
Future<void> _settleToast(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

/// Opens the + menu of the column headed by [subjectKey] and picks a master.
Future<void> _addVia(
  WidgetTester tester,
  String subjectKey,
  String master,
) async {
  await tester.tap(find.byKey(ValueKey('link_columns_add_$subjectKey')));
  await tester.pumpAndSettle();
  // Scoped to the menu: a column that already has a Dies heading shows the
  // same word, and tapping that would open nothing.
  await tester.tap(
    find.descendant(
      of: find.byType(PopupMenuItem<String>),
      matching: find.text(master),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the first column lists a master and a pick opens its links', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(EntityLinkService(baseUrl: '', useMockResponses: true)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Items'), findsOneWidget);
    expect(find.text('Hinge Plate'), findsOneWidget);
    expect(find.text('Latch Body'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('link_row_item:1')));
    await tester.pumpAndSettle();

    // A second column, headed by the item, offering the + that links.
    expect(
      find.byKey(const ValueKey('link_columns_add_item:1')),
      findsOneWidget,
    );
    expect(
      find.textContaining('Nothing linked to Hinge Plate yet'),
      findsOneWidget,
    );
  });

  testWidgets('a die linked from the item column lists the item from its own', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(EntityLinkService(baseUrl: '', useMockResponses: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('link_row_item:1')));
    await tester.pumpAndSettle();

    // + on the item's column -> Die -> pick one from the picker.
    await _addVia(tester, 'item:1', 'Die');
    expect(find.text('Link a die'), findsOneWidget);
    expect(find.text('to Hinge Plate'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('link_row_die:1')));
    await tester.pumpAndSettle();
    await _settleToast(tester);

    // The item's column now has a Dies heading with the die under it.
    expect(find.text('Die'), findsOneWidget, reason: 'one die reads singular');
    expect(find.byKey(const ValueKey('link_row_die:1')), findsOneWidget);

    // More than one die on the same item, which is the point of a column
    // rather than a single field.
    await _addVia(tester, 'item:1', 'Die');
    await tester.tap(find.byKey(const ValueKey('link_row_die:2')));
    await tester.pumpAndSettle();
    await _settleToast(tester);
    expect(find.text('Dies'), findsOneWidget);
    expect(find.byKey(const ValueKey('link_row_die:1')), findsOneWidget);
    expect(find.byKey(const ValueKey('link_row_die:2')), findsOneWidget);

    // Down the chain: the die's own column answers the reverse question.
    await tester.tap(find.byKey(const ValueKey('link_row_die:1')));
    await tester.pumpAndSettle();
    expect(find.text('DIE-100'), findsWidgets);
    expect(
      find.byKey(const ValueKey('link_columns_add_die:1')),
      findsOneWidget,
    );
    // Twice over: once in the first column's listing of items, and once as a
    // link under the die — which is the reverse read the item's own table
    // could never answer.
    expect(
      find.byKey(const ValueKey('link_row_item:1')),
      findsNWidgets(2),
      reason: 'the die lists the item it makes, from the same link',
    );

    // And a machine onto the die, from the die's own column: a pair with no
    // table of its own, made in the same gesture as one that has.
    await _addVia(tester, 'die:1', 'Machine');
    await tester.tap(find.byKey(const ValueKey('link_row_machine:1')));
    await tester.pumpAndSettle();
    await _settleToast(tester);
    expect(find.text('Machine'), findsOneWidget);
    expect(find.byKey(const ValueKey('link_row_machine:1')), findsOneWidget);
  });

  testWidgets('unlinking closes the columns that hung off the link', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final service = EntityLinkService(baseUrl: '', useMockResponses: true);
    await service.link(
      fromType: 'item',
      fromId: '1',
      toType: 'die',
      toId: '1',
    );
    await service.link(
      fromType: 'die',
      fromId: '1',
      toType: 'machine',
      toId: '1',
    );

    await tester.pumpWidget(_host(service));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('link_row_item:1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('link_row_die:1')));
    await tester.pumpAndSettle();

    // The die's column is open, and the machine is visible in it.
    expect(find.byKey(const ValueKey('link_row_machine:1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('link_unlink_die:1')));
    await tester.pumpAndSettle();
    expect(find.text('Unlink?'), findsOneWidget);
    await tester.tap(find.text('Unlink'));
    await tester.pumpAndSettle();

    // The die is gone from the item, and so is the column it had opened —
    // nothing to its right can still be reached through a link that is gone.
    expect(find.byKey(const ValueKey('link_row_die:1')), findsNothing);
    expect(find.byKey(const ValueKey('link_row_machine:1')), findsNothing);
    expect(
      find.textContaining('Nothing linked to Hinge Plate yet'),
      findsOneWidget,
    );
  });

  testWidgets('the first column switches which master it lists', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final service = EntityLinkService(baseUrl: '', useMockResponses: true);
    await service.link(
      fromType: 'item',
      fromId: '1',
      toType: 'die',
      toId: '1',
    );

    await tester.pumpWidget(_host(service));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('link_columns_root_type')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(PopupMenuItem<String>),
        matching: find.text('Dies'),
      ),
    );
    await tester.pumpAndSettle();

    // Starting from the die instead: the same link, approached from the end
    // the old item editor could not reach.
    expect(find.text('Dies'), findsOneWidget);
    expect(find.text('DIE-100'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('link_row_die:1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('link_row_item:1')), findsOneWidget);
  });

  testWidgets('the + menu can make a record and link it in one gesture', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final service = EntityLinkService(baseUrl: '', useMockResponses: true);
    var opened = '';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1400,
            height: 800,
            child: LinkColumns(
              service: service,
              columnWidth: 320,
              onCreate: (context, type) async {
                opened = type;
                // Stands in for the master's real editor, which the host owns.
                return const LinkRef(
                  type: 'die',
                  id: '3',
                  label: 'DIE-300',
                  subtitle: 'Rack 7',
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('link_row_item:2')));
    await tester.pumpAndSettle();

    await _addVia(tester, 'item:2', 'Die');
    await tester.tap(find.byKey(const ValueKey('link_attach_create')));
    await tester.pumpAndSettle();

    await _settleToast(tester);
    expect(opened, 'die', reason: 'the host is asked for that master’s editor');
    expect(
      find.byKey(const ValueKey('link_row_die:3')),
      findsOneWidget,
      reason: 'the record the editor saved is linked without a second step',
    );
  });

  testWidgets('an anchor replaces the browse column and + moves to the foot', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final service = EntityLinkService(baseUrl: '', useMockResponses: true);
    await service.link(
      fromType: 'item',
      fromId: '1',
      toType: 'die',
      toId: '1',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 700,
            height: 800,
            child: LinkColumns(
              service: service,
              anchor: const LinkRef(
                type: 'item',
                id: '1',
                label: 'Hinge Plate',
              ),
              columnWidth: 300,
              addAtBottom: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // No second listing of records: the host's own column is the root.
    expect(find.byKey(const ValueKey('link_columns_root_search')), findsNothing);
    expect(find.byKey(const ValueKey('link_columns_root_type')), findsNothing);

    // Straight to the anchor's links, with the + at the foot.
    expect(find.text('Hinge Plate'), findsOneWidget);
    expect(find.byKey(const ValueKey('link_row_die:1')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('link_columns_add_item:1')),
      findsOneWidget,
    );

    // The chain still grows rightwards from there.
    await tester.tap(find.byKey(const ValueKey('link_row_die:1')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('link_columns_add_die:1')),
      findsOneWidget,
    );
  });

  testWidgets('a new anchor starts a new chain', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final service = EntityLinkService(baseUrl: '', useMockResponses: true);
    await service.link(
      fromType: 'item',
      fromId: '1',
      toType: 'die',
      toId: '1',
    );
    final anchor = ValueNotifier<LinkRef>(
      const LinkRef(type: 'item', id: '1', label: 'Hinge Plate'),
    );
    addTearDown(anchor.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<LinkRef>(
            valueListenable: anchor,
            builder: (context, value, _) => SizedBox(
              width: 700,
              height: 800,
              child: LinkColumns(
                service: service,
                anchor: value,
                columnWidth: 300,
                addAtBottom: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('link_row_die:1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('link_columns_add_die:1')), findsOneWidget);

    // Selecting another tile in the host's column: the old chain answered
    // about a different record, so it does not linger as a stale tail.
    anchor.value = const LinkRef(
      type: 'item',
      id: '2',
      label: 'Latch Body',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('link_columns_add_die:1')), findsNothing);
    expect(
      find.byKey(const ValueKey('link_columns_add_item:2')),
      findsOneWidget,
    );
  });

  testWidgets('minColumns keeps the next column open and empty', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final service = EntityLinkService(baseUrl: '', useMockResponses: true);
    await service.link(
      fromType: 'item',
      fromId: '1',
      toType: 'die',
      toId: '1',
    );
    await service.link(
      fromType: 'die',
      fromId: '1',
      toType: 'machine',
      toId: '2',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 700,
            height: 800,
            child: LinkColumns(
              service: service,
              anchor: const LinkRef(
                type: 'item',
                id: '1',
                label: 'Hinge Plate',
              ),
              columnWidth: 288,
              minColumns: 2,
              addAtBottom: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // One link deep, two columns: the second says what picking in the first
    // would put in it, rather than being absent until it is used.
    expect(find.byKey(const ValueKey('link_row_die:1')), findsOneWidget);
    expect(find.text('Nothing picked'), findsOneWidget);
    expect(
      find.textContaining("Hinge Plate's links"),
      findsOneWidget,
      reason: 'the empty column names what fills it',
    );

    await tester.tap(find.byKey(const ValueKey('link_row_die:1')));
    await tester.pumpAndSettle();

    // Filled, so no column is waiting any more — and the chain is still two
    // deep rather than having grown a third empty one.
    expect(find.text('Nothing picked'), findsNothing);
    expect(find.byKey(const ValueKey('link_row_machine:2')), findsOneWidget);
    expect(find.byKey(const ValueKey('link_columns_add_die:1')), findsOneWidget);
  });

  testWidgets('the controller re-reads what is on screen', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final service = EntityLinkService(baseUrl: '', useMockResponses: true);
    final controller = LinkColumnsController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(service, controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('link_row_item:1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('link_row_machine:2')), findsNothing);

    // The graph changes by some other route — the host's own editor saving a
    // machine against this item, as the creation window does.
    await service.link(
      fromType: 'item',
      fromId: '1',
      toType: 'machine',
      toId: '2',
    );
    controller.refresh();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('link_row_machine:2')), findsOneWidget);
  });
}

import 'package:core_erp/core/app_flow_hooks.dart';
import 'package:core_erp/features/links/data/entity_link_service.dart';
import 'package:core_erp/features/links/domain/entity_link.dart';
import 'package:core_erp/features/links/presentation/widgets/ecosystem_inspector.dart';
import 'package:core_erp/features/links/presentation/widgets/linked_ecosystem_ribbon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The ecosystem ribbon: what a record works with, and walking to it.
///
/// The link graph answers from either end, so one strip serves every master.
/// Two things it must never do: imply "nothing is linked" when the real answer
/// is "you may not see it", and open a neighbour for editing when somebody only
/// asked to look.

LinkRef _ref(String type, String id, String label, [String subtitle = '']) =>
    LinkRef(type: type, id: id, label: label, subtitle: subtitle);

EntityLinks _links({List<LinkGroup> groups = const []}) => EntityLinks(
  entity: _ref('item', '42', 'Cone Top'),
  groups: groups,
);

/// Answers with a fixed payload, or throws.
class _StubLinks extends EntityLinkService {
  _StubLinks({this.payload, this.failure}) : super(baseUrl: '');

  final EntityLinks? payload;
  final Object? failure;
  int calls = 0;

  @override
  Future<EntityLinks> fetchLinks(String type, String id) async {
    calls += 1;
    if (failure != null) throw failure!;
    return payload ?? _links();
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required EntityLinkService service,
  ValueChanged<LinkRef>? onOpen,
  String type = 'item',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LinkedEcosystemRibbon(
          type: type,
          id: '42',
          service: service,
          onOpen: onOpen,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the ribbon names what a record works with', () {
    testWidgets('every group the payload returns, not a chosen two', (
      tester,
    ) async {
      // Sets, groups, pipelines and materials are linkable too. Filtering to
      // dies and machines here would hide a real attachment.
      await _pump(
        tester,
        service: _StubLinks(
          payload: _links(
            groups: [
              LinkGroup(
                type: 'die',
                label: 'Die',
                plural: 'Dies',
                links: [_ref('die', '1', 'TD-12', 'Rack 4')],
              ),
              LinkGroup(
                type: 'set',
                label: 'Set',
                plural: 'Sets',
                links: [_ref('set', '7', 'Cone Kit')],
              ),
            ],
          ),
        ),
      );

      expect(find.text('Works with'), findsOneWidget);
      expect(find.text('TD-12'), findsOneWidget);
      expect(find.text('Rack 4'), findsOneWidget);
      expect(
        find.text('Cone Kit'),
        findsOneWidget,
        reason: 'a set is linkable and must not be filtered out',
      );
    });

    testWidgets('an empty payload says so', (tester) async {
      await _pump(tester, service: _StubLinks(payload: _links()));
      expect(
        find.byKey(const ValueKey('linked_ecosystem_empty')),
        findsOneWidget,
      );
    });

    testWidgets('a refused read shows NOTHING, not "nothing linked"', (
      tester,
    ) async {
      // The endpoint drops groups the caller cannot read and can refuse the
      // subject outright. Claiming "nothing linked" on a refusal would be a
      // statement this widget has no evidence for.
      await _pump(tester, service: _StubLinks(failure: Exception('403')));

      expect(find.byKey(const ValueKey('linked_ecosystem_ribbon')), findsNothing);
      expect(
        find.byKey(const ValueKey('linked_ecosystem_empty')),
        findsNothing,
      );
    });

    testWidgets('with no service at all it is hidden, not broken', (
      tester,
    ) async {
      // main.dart is the only Provider registration, so a host or test tree
      // without it must degrade rather than throw.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LinkedEcosystemRibbon(type: 'item', id: '42'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('linked_ecosystem_ribbon')), findsNothing);
    });

    testWidgets('a changed subject refetches', (tester) async {
      // A panel that pivots in place swaps the subject under the ribbon.
      final service = _StubLinks(payload: _links());
      await _pump(tester, service: service);
      expect(service.calls, 1);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LinkedEcosystemRibbon(
              type: 'die',
              id: '9',
              service: service,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(service.calls, 2);
    });
  });

  group('walking to a neighbour', () {
    tearDown(() {
      AppFlowHooks.dieInspector = null;
      AppFlowHooks.machineInspector = null;
      AppFlowHooks.itemInspector = null;
    });

    testWidgets('a chip is inert where nothing can be opened', (tester) async {
      // No inspector registered: the chip stays a label. Honest, and the
      // documented degrade for this seam.
      expect(AppFlowHooks.canInspect('die'), isFalse);

      LinkRef? opened;
      await _pump(
        tester,
        service: _StubLinks(
          payload: _links(
            groups: [
              LinkGroup(
                type: 'die',
                label: 'Die',
                plural: 'Dies',
                links: [_ref('die', '1', 'TD-12')],
              ),
            ],
          ),
        ),
        onOpen: (ref) => opened = ref,
      );

      await tester.tap(find.byKey(const ValueKey('ribbon_chip_die:1')));
      await tester.pumpAndSettle();

      // The callback still fires — it is the panel that declines to open an
      // inspector that does not exist, which keeps that rule in one place.
      expect(opened?.id, '1');
    });

    testWidgets('canInspect follows what the host registered', (tester) async {
      expect(AppFlowHooks.canInspect('die'), isFalse);
      AppFlowHooks.dieInspector = (context, id) => const SizedBox.shrink();
      expect(AppFlowHooks.canInspect('die'), isTrue);
      expect(
        AppFlowHooks.canInspect('item'),
        isFalse,
        reason: 'an item has its own panel; it is not inspected this way',
      );
    });

    testWidgets('the inspector opens read-only, with one way to edit', (
      tester,
    ) async {
      var edits = 0;
      AppFlowHooks.dieInspector = (context, id) => EcosystemInspectorSheet(
        title: 'TD-12',
        subtitle: 'Die',
        facts: const [('Tool code', 'TD-12'), ('Status', 'Ready')],
        ribbon: const SizedBox.shrink(),
        onEdit: () async => edits += 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showEcosystemInspector(
                  context,
                  subject: _ref('die', '1', 'TD-12'),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('TD-12'), findsWidgets);
      expect(find.text('TOOL CODE'), findsOneWidget);
      // Reading has not written anything.
      expect(edits, 0);

      await tester.tap(find.byKey(const ValueKey('inspector_edit')));
      await tester.pumpAndSettle();
      expect(edits, 1, reason: 'editing is the explicit second step');
    });

    testWidgets('a record that has gone says so rather than showing blanks', (
      tester,
    ) async {
      AppFlowHooks.dieInspector = (context, id) =>
          const EcosystemInspectorSheet(
            title: 'Die',
            subtitle: 'Not found',
            facts: <(String, String)>[],
            ribbon: SizedBox.shrink(),
            missing: true,
          );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showEcosystemInspector(
                  context,
                  subject: _ref('die', '404', 'Gone'),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('This record is no longer there.'), findsOneWidget);
      // No Edit for a record that is not there.
      expect(find.byKey(const ValueKey('inspector_edit')), findsNothing);
    });

    testWidgets('pivoting walks between linked inspector sheets', (
      tester,
    ) async {
      String? seenItem;
      AppFlowHooks.itemInspector = (context, id) {
        seenItem = id;
        return EcosystemInspectorSheet(
          title: 'Cone Part',
          subtitle: 'Part',
          facts: const [('Part code', 'CP-01')],
          ribbon: const SizedBox.shrink(),
        );
      };

      AppFlowHooks.dieInspector = (context, id) => EcosystemInspectorSheet(
        title: 'TD-12',
        subtitle: 'Die',
        facts: const [('Tool code', 'TD-12')],
        ribbon: Builder(
          builder: (context) => TextButton(
            key: const ValueKey('pivot_to_part'),
            onPressed: () => pivotEcosystemInspector(
              context,
              _ref('item', '99', 'Cone Part'),
            ),
            child: const Text('pivot to part'),
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showEcosystemInspector(
                  context,
                  subject: _ref('die', '1', 'TD-12'),
                ),
                child: const Text('open die'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open die'));
      await tester.pumpAndSettle();
      expect(find.text('TD-12'), findsWidgets);

      // Now tap pivot button on the die's ribbon to walk to the part.
      await tester.tap(find.byKey(const ValueKey('pivot_to_part')));
      await tester.pumpAndSettle();

      expect(seenItem, '99');
      expect(find.text('Cone Part'), findsOneWidget);
      expect(find.text('PART CODE'), findsOneWidget);
    });
  });
}

import 'package:core_erp/features/process_routes/domain/part_route.dart';
import 'package:core_erp/features/process_routes/domain/process_stage.dart';
import 'package:core_erp/features/process_routes/presentation/widgets/route_editor.dart';
import 'package:core_erp/features/process_routes/presentation/widgets/route_ribbon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The two lenses on a route, and the read-only ribbon.
//
// Doc 10: "Each view produces the same payload: a list of stage ids in order.
// The view a client sees is a per-client setting, not a code branch." The load-
// bearing assertion in this file is that both lenses, driven differently,
// hand back the same list — because the moment they do not, the rules stop
// being inheritable and a second view can route around them.

const _stages = <ProcessStage>[
  ProcessStage(id: 1, code: 'die', name: 'Die', position: 1),
  ProcessStage(id: 2, code: 'shearing', name: 'Shearing', position: 2),
  ProcessStage(id: 3, code: 'cutting', name: 'Cutting', position: 3, repeatable: true),
  ProcessStage(id: 9, code: 'delivery', name: 'Delivery', position: 9),
  ProcessStage(id: 7, code: 'lapping', name: 'Hand Lapping', position: 7, active: false),
];

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('RouteEditor', () {
    testWidgets('both lenses produce the same ordered stage ids', (tester) async {
      // Classic: add three steps and set each dropdown.
      List<RouteStep> classic = const [];
      await tester.pumpWidget(_host(RouteEditor(
        // A distinct key per lens: pumping two RouteEditors of the same type
        // into one tester otherwise reuses the State, and the draft built in
        // the first lens would still be there in the second.
        key: const ValueKey('classic'),
        stages: _stages,
        steps: const [],
        lens: RouteLens.classic,
        onChanged: (steps) => classic = steps,
      )));

      for (var i = 0; i < 3; i += 1) {
        await tester.tap(find.byKey(const ValueKey('route_add_step')));
        await tester.pumpAndSettle();
      }
      // Appending takes the first still-available stage each time, which with
      // this master is die, shearing, cutting.
      expect(classic.map((s) => s.stageId), [1, 2, 3]);

      // List: tap the same three chips, in the same order.
      List<RouteStep> list = const [];
      await tester.pumpWidget(_host(RouteEditor(
        key: const ValueKey('list'),
        stages: _stages,
        steps: const [],
        lens: RouteLens.list,
        onChanged: (steps) => list = steps,
      )));
      for (final code in ['die', 'shearing', 'cutting']) {
        await tester.tap(find.byKey(ValueKey('route_palette_$code')));
        await tester.pumpAndSettle();
      }

      expect(
        list.map((s) => s.stageId),
        classic.map((s) => s.stageId),
        reason: 'one payload, whichever gesture produced it',
      );
      expect(list.map((s) => s.seq), [1, 2, 3]);
    });

    testWidgets('classic draws the steps as boxes in one row, not stacked rows',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(RouteEditor(
        stages: _stages,
        steps: const [
          RouteStep(stageId: 1, seq: 1),
          RouteStep(stageId: 2, seq: 2),
          RouteStep(stageId: 3, seq: 3),
        ],
        lens: RouteLens.classic,
        onChanged: (_) {},
      )));

      final first = tester.getRect(find.byKey(const ValueKey('route_step_0')));
      final third = tester.getRect(find.byKey(const ValueKey('route_step_2')));
      expect(third.top, first.top, reason: 'a short route fits on one line');
      expect(third.left, greaterThan(first.right));
      expect(first.width, lessThan(260), reason: 'a box, not a full-width row');
      expect(find.byIcon(Icons.chevron_right), findsNWidgets(3));
    });

    testWidgets('the stage box finds an existing stage as you type', (tester) async {
      List<RouteStep> steps = const [];
      await tester.pumpWidget(_host(RouteEditor(
        stages: _stages,
        steps: const [RouteStep(stageId: 1, seq: 1)],
        lens: RouteLens.classic,
        onChanged: (next) => steps = next,
        onCreateStage: (_) async => fail('nothing new was asked for'),
      )));

      await tester.tap(find.byKey(const ValueKey('route_new_stage')));
      await tester.pumpAndSettle();
      // Die is in the route already and Hand Lapping is retired: neither is offered.
      expect(find.text('Shearing'), findsOneWidget);
      expect(find.text('Hand Lapping'), findsNothing);

      await tester.enterText(find.byType(TextField).last, 'deliv');
      await tester.pumpAndSettle();
      expect(find.text('Shearing'), findsNothing, reason: 'the list filters');
      await tester.tap(find.text('Delivery'));
      await tester.pumpAndSettle();

      expect(steps.map((s) => s.stageId), [1, 9]);
    });

    testWidgets('a name nobody has made is offered as a new stage, and added',
        (tester) async {
      final asked = <String>[];
      List<RouteStep> steps = const [];
      var stages = [..._stages];
      await tester.pumpWidget(_host(StatefulBuilder(
        builder: (context, setState) => RouteEditor(
          stages: stages,
          steps: const [RouteStep(stageId: 1, seq: 1)],
          lens: RouteLens.classic,
          onChanged: (next) => steps = next,
          onCreateStage: (name) async {
            asked.add(name);
            const made = ProcessStage(id: 40, code: 'bending', name: 'Bending', position: 10);
            setState(() => stages = [...stages, made]);
            return made;
          },
        ),
      )));

      await tester.tap(find.byKey(const ValueKey('route_new_stage')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Bending');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add “Bending” as a new stage'));
      await tester.pumpAndSettle();

      expect(asked, ['Bending']);
      expect(steps.map((s) => s.stageId), [1, 40]);
      expect(steps.map((s) => s.seq), [1, 2]);
      expect(find.text('Bending'), findsOneWidget, reason: 'the second box shows it');
    });

    testWidgets('a stage already in this route is neither listed nor offered as new',
        (tester) async {
      await tester.pumpWidget(_host(RouteEditor(
        stages: _stages,
        steps: const [RouteStep(stageId: 1, seq: 1)],
        lens: RouteLens.classic,
        onChanged: (_) {},
        onCreateStage: (_) async => fail('Die exists; it must not be made again'),
      )));
      await tester.tap(find.byKey(const ValueKey('route_new_stage')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'die');
      await tester.pumpAndSettle();

      expect(find.textContaining('as a new stage'), findsNothing);
      expect(find.textContaining('Already in this route'), findsOneWidget);
    });

    testWidgets('a locked route draws New stage disabled, saying why',
        (tester) async {
      await tester.pumpWidget(_host(RouteEditor(
        stages: _stages,
        steps: const [RouteStep(stageId: 1, seq: 1)],
        lens: RouteLens.classic,
        locked: true,
        lockedVersion: 2,
        onChanged: (_) {},
        onCreateStage: (_) async => null,
      )));
      final button = tester.widget<ButtonStyleButton>(
        find.byKey(const ValueKey('route_new_stage')),
      );
      expect(button.onPressed, isNull);
      final tip = tester.widget<Tooltip>(find.ancestor(
        of: find.byKey(const ValueKey('route_new_stage')),
        matching: find.byType(Tooltip),
      ).first);
      expect(tip.message, contains('declare a new version'));
    });

    testWidgets('seq is renumbered from 1 on every change', (tester) async {
      // Contiguity is a property of the structure, not something a user has to
      // maintain — the backend refuses a gap, so the editor cannot make one.
      List<RouteStep> steps = const [];
      await tester.pumpWidget(_host(RouteEditor(
        stages: _stages,
        steps: const [
          RouteStep(stageId: 1, seq: 1, stageName: 'Die'),
          RouteStep(stageId: 2, seq: 2, stageName: 'Shearing'),
          RouteStep(stageId: 9, seq: 3, stageName: 'Delivery'),
        ],
        lens: RouteLens.classic,
        onChanged: (next) => steps = next,
      )));

      await tester.tap(find.byKey(const ValueKey('route_step_remove_0')));
      await tester.pumpAndSettle();

      expect(steps.map((s) => s.stageId), [2, 9]);
      expect(steps.map((s) => s.seq), [1, 2], reason: 'renumbered, not 2 and 3');
    });

    testWidgets('a non-repeatable stage already used is not offered again', (tester) async {
      await tester.pumpWidget(_host(RouteEditor(
        stages: _stages,
        steps: const [RouteStep(stageId: 1, seq: 1, stageName: 'Die')],
        lens: RouteLens.list,
        onChanged: (_) {},
      )));

      // Die is used and is not repeatable, so its chip is gone; Cutting is
      // flagged repeatable and stays offered even once used.
      expect(find.byKey(const ValueKey('route_palette_die')), findsNothing);
      expect(find.byKey(const ValueKey('route_palette_shearing')), findsOneWidget);
      expect(find.byKey(const ValueKey('route_palette_cutting')), findsOneWidget);
      // An inactive stage is never offered at all.
      expect(find.byKey(const ValueKey('route_palette_lapping')), findsNothing);
    });

    testWidgets('a repeatable stage can be added twice', (tester) async {
      List<RouteStep> steps = const [];
      await tester.pumpWidget(_host(RouteEditor(
        stages: _stages,
        steps: const [],
        lens: RouteLens.list,
        onChanged: (next) => steps = next,
      )));
      await tester.tap(find.byKey(const ValueKey('route_palette_cutting')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('route_palette_cutting')));
      await tester.pumpAndSettle();
      expect(steps.map((s) => s.stageId), [3, 3]);
    });

    testWidgets('an active route is locked, drawn disabled, and offers a version', (tester) async {
      // Never hide a control until its precondition holds: draw it disabled
      // with something that explains why.
      var declared = false;
      await tester.pumpWidget(_host(RouteEditor(
        stages: _stages,
        steps: const [RouteStep(stageId: 1, seq: 1, stageName: 'Die')],
        lens: RouteLens.classic,
        locked: true,
        lockedVersion: 2,
        onDeclareVersion: () async => declared = true,
        onChanged: (_) {},
      )));

      expect(find.textContaining('Version 2 is active'), findsOneWidget);

      final add = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Add step'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(add.onPressed, isNull, reason: 'drawn, but disabled');

      final remove = tester.widget<IconButton>(
        find.byKey(const ValueKey('route_step_remove_0')),
      );
      expect(remove.onPressed, isNull);
      expect(remove.tooltip, contains('declare a new version'));

      await tester.tap(find.byKey(const ValueKey('route_declare_version')));
      await tester.pumpAndSettle();
      expect(declared, isTrue);
    });

    testWidgets('Add step is disabled, not hidden, when every stage is used', (tester) async {
      await tester.pumpWidget(_host(RouteEditor(
        stages: const [ProcessStage(id: 1, code: 'die', name: 'Die')],
        steps: const [RouteStep(stageId: 1, seq: 1, stageName: 'Die')],
        lens: RouteLens.classic,
        onChanged: (_) {},
      )));
      expect(find.text('Add step'), findsOneWidget);
      final add = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Add step'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(add.onPressed, isNull);
    });

    testWidgets('the list lens is not wrapped in a LayoutBuilder', (tester) async {
      // A LayoutBuilder over a reorderable list crashes mid-layout when the
      // drag overlay appears, and that crash will NOT reproduce in a widget
      // test — so the guard has to be structural rather than behavioural.
      await tester.pumpWidget(_host(RouteEditor(
        stages: _stages,
        steps: const [
          RouteStep(stageId: 1, seq: 1, stageName: 'Die'),
          RouteStep(stageId: 2, seq: 2, stageName: 'Shearing'),
        ],
        lens: RouteLens.list,
        onChanged: (_) {},
      )));
      expect(find.byType(ReorderableListView), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(ReorderableListView),
          matching: find.byType(LayoutBuilder),
        ),
        findsNothing,
      );
    });
  });

  group('RouteRibbon', () {
    testWidgets('renders the stages in order with the version', (tester) async {
      await tester.pumpWidget(_host(const RouteRibbon(
        route: PartRoute(
          id: 1,
          partId: 48,
          version: 2,
          status: RouteStatus.active,
          steps: [
            RouteStep(stageId: 1, seq: 1, stageName: 'Die'),
            RouteStep(stageId: 2, seq: 2, stageName: 'Shearing'),
          ],
        ),
      )));
      expect(find.text('Goes through'), findsOneWidget);
      expect(find.text('v2'), findsOneWidget);
      expect(find.text('Die'), findsOneWidget);
      expect(find.text('Shearing'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('no route renders nothing at all, not an empty heading', (tester) async {
      // A refusal and an absence must not look alike, and a heading over
      // nothing reads as "this part has no route" — which a refused read does
      // not establish.
      await tester.pumpWidget(_host(const RouteRibbon(route: null)));
      expect(find.text('Goes through'), findsNothing);

      await tester.pumpWidget(_host(const RouteRibbon(
        route: PartRoute(
          id: 1, partId: 48, version: 1, status: RouteStatus.draft, steps: [],
        ),
      )));
      expect(find.text('Goes through'), findsNothing);
    });

    testWidgets('a draft and a retired route say so', (tester) async {
      await tester.pumpWidget(_host(const RouteRibbon(
        route: PartRoute(
          id: 1, partId: 48, version: 3, status: RouteStatus.draft,
          steps: [RouteStep(stageId: 1, seq: 1, stageName: 'Die')],
        ),
      )));
      expect(find.text('v3 draft'), findsOneWidget);

      await tester.pumpWidget(_host(const RouteRibbon(
        route: PartRoute(
          id: 1, partId: 48, version: 1, status: RouteStatus.retired,
          steps: [RouteStep(stageId: 1, seq: 1, stageName: 'Die')],
        ),
      )));
      expect(find.text('v1 retired'), findsOneWidget);
    });

    testWidgets('names a step from the stage master when the step did not carry one', (tester) async {
      await tester.pumpWidget(_host(const RouteRibbon(
        route: PartRoute(
          id: 1, partId: 48, version: 1, status: RouteStatus.active,
          steps: [RouteStep(stageId: 9, seq: 1)],
        ),
        stages: _stages,
      )));
      expect(find.text('Delivery'), findsOneWidget);
    });
  });
}

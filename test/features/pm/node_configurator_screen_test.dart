import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paper/features/pm/presentation/node_configurator/domain/node_blueprint.dart';
import 'package:paper/features/pm/presentation/node_configurator/node_configurator_screen.dart';

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(home: NodeConfiguratorScreen()));
  await tester.pumpAndSettle();
}

void main() {
  // The configurator pane is a ListView, so lower sections start below the
  // fold. A TextField carries its own Scrollable, hence `.first`.
  final configuratorPane = find
      .descendant(
        of: find.byKey(const PageStorageKey<String>('node_configurator_pane')),
        matching: find.byType(Scrollable),
      )
      .first;

  group('NodeConfiguratorScreen renders', () {
    testWidgets('at desktop width, with both panes', (tester) async {
      await _pumpAt(tester, const Size(1600, 1000));

      expect(find.text('Node Configurator'), findsOneWidget);
      expect(find.text('Identity'), findsOneWidget);

      // "Machine"/"Die"/"Loss" label both a preview row and a section, so the
      // sections are identified by content unique to them.
      final markers = <Finder>[
        find.byKey(ValueKey('slot_mode_${MachineSlotMode.group}')),
        find.byKey(ValueKey('slot_mode_${DieSlotMode.open}')),
        find.byKey(const Key('add_loss_scrap')),
      ];
      for (final marker in markers) {
        await tester.scrollUntilVisible(
          marker,
          300,
          scrollable: configuratorPane,
        );
        expect(marker, findsOneWidget);
      }

      // The removed sections stay removed.
      expect(find.text('Checks'), findsNothing);
      expect(find.text('Shelf'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('at narrow width, one pane at a time', (tester) async {
      await _pumpAt(tester, const Size(760, 1100));

      final libraryList = find.byKey(
        const PageStorageKey<String>('node_configurator_library'),
      );
      expect(libraryList, findsOneWidget);
      expect(find.text('Identity'), findsNothing);

      await tester.tap(find.text('Configure'));
      await tester.pumpAndSettle();

      expect(find.text('Identity'), findsOneWidget);
      expect(libraryList, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('through every machine and die mode', (tester) async {
      await _pumpAt(tester, const Size(1600, 1400));

      for (final mode in [...MachineSlotMode.values, ...DieSlotMode.values]) {
        final pill = find.byKey(ValueKey('slot_mode_$mode'));
        await tester.scrollUntilVisible(pill, 300, scrollable: configuratorPane);
        await tester.tap(pill);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$mode');
      }
    });

    testWidgets('creates a process the seeded list does not name', (
      tester,
    ) async {
      await _pumpAt(tester, const Size(1600, 1400));

      final field = find.byKey(const Key('process_type_field'));
      await tester.scrollUntilVisible(field, 300, scrollable: configuratorPane);
      await tester.tap(field);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, 'Deburring');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create process "Deburring"'));
      await tester.pumpAndSettle();

      // The preview pill carries the new process immediately.
      expect(find.text('DEBURRING'), findsOneWidget);

      // And it is on the list from then on — offered as an option, and no
      // longer offered for creation, so it cannot be duplicated.
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(find.text('Deburring'), findsWidgets);
      expect(find.textContaining('Create process'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('DEBURRING'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('changes a loss route unit to gross', (tester) async {
      await _pumpAt(tester, const Size(1600, 1400));

      // Reel Slitting has one scrap route, defaulted to kg.
      final picker = find.byTooltip('Unit');
      await tester.scrollUntilVisible(picker, 300, scrollable: configuratorPane);
      expect(picker, findsOneWidget);

      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gross — 144'));
      await tester.pumpAndSettle();

      expect(find.text('gross'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('adds a rejection route alongside the seeded scrap', (
      tester,
    ) async {
      await _pumpAt(tester, const Size(1600, 1400));

      // Reel Slitting seeds one scrap route and no rejections. The name shows
      // in the library card, the preview, the section chip and the dropdown.
      expect(find.text('Paper Waste'), findsWidgets);

      final addRejection = find.byKey(const Key('add_loss_rejection'));
      await tester.scrollUntilVisible(
        addRejection,
        300,
        scrollable: configuratorPane,
      );
      await tester.tap(addRejection);
      await tester.pumpAndSettle();

      // Both kinds now route, and the summary chips say so.
      expect(find.text('1 scrap · 1 rejection'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('binding rules', () {
    const punchNode = NodeBlueprint(
      id: 't1',
      name: 'Punch',
      processType: 'Punching',
      machineMode: MachineSlotMode.specific,
      machineId: 'm_pn07',
      dieMode: DieSlotMode.specific,
      dieId: 'd_c90',
    );

    test('a compatible machine and die pair is saveable and asks nothing', () {
      expect(NodeBindingRules.isSaveable(punchNode), isTrue);
      expect(NodeBindingRules.runtimePrompts(punchNode), isEmpty);
    });

    test('a die that does not fit the machine group blocks the save', () {
      // D-HDL fits Presses; PN-07 is a Punch.
      final mismatched = punchNode.copyWith(dieId: 'd_handle');
      expect(NodeBindingRules.isSaveable(mismatched), isFalse);
    });

    test('"no die" asks nothing; "at run time" asks for a die', () {
      final noDie = punchNode.copyWith(dieMode: DieSlotMode.none, dieId: null);
      final openDie = punchNode.copyWith(dieMode: DieSlotMode.open, dieId: null);

      expect(NodeBindingRules.runtimePrompts(noDie), isEmpty);
      expect(
        NodeBindingRules.runtimePrompts(openDie).map((p) => p.slot),
        contains('Die'),
      );
      // Both are legitimate; neither blocks a save.
      expect(NodeBindingRules.isSaveable(noDie), isTrue);
      expect(NodeBindingRules.isSaveable(openDie), isTrue);
    });

    test('a pooled machine still asks which one, fenced to the group', () {
      const pooled = NodeBlueprint(
        id: 't2',
        name: 'Slit',
        processType: 'Slitting',
        machineMode: MachineSlotMode.group,
        machineGroupId: 'mg_slit',
        dieMode: DieSlotMode.none,
      );

      final prompts = NodeBindingRules.runtimePrompts(pooled);
      expect(prompts, hasLength(1));
      expect(prompts.single.kind, PromptKind.constrained);
      expect(prompts.single.detail, contains('Slitters'));
    });

    test('a pinned die fences an open machine slot to its groups', () {
      const openMachine = NodeBlueprint(
        id: 't3',
        name: 'Press cut',
        processType: 'Pressing',
        machineMode: MachineSlotMode.open,
        dieMode: DieSlotMode.specific,
        dieId: 'd_handle',
      );

      expect(
        NodeBindingRules.groupsAllowedByDie(openMachine).map((g) => g.name),
        ['Presses'],
      );
      expect(
        NodeBindingRules.runtimePrompts(openMachine).single.detail,
        contains('Presses'),
      );
    });

    test('a half-made slot blocks the save', () {
      const noSubject = NodeBlueprint(
        id: 't4',
        name: 'Half made',
        processType: 'Punching',
        machineMode: MachineSlotMode.specific,
        dieMode: DieSlotMode.none,
      );
      expect(NodeBindingRules.isSaveable(noSubject), isFalse);
    });
  });

  group('loss routing', () {
    const base = NodeBlueprint(
      id: 'l0',
      name: 'Cut',
      processType: 'Punching',
      machineMode: MachineSlotMode.none,
      dieMode: DieSlotMode.none,
    );

    test('no route is legal, but reads as nothing routed', () {
      expect(NodeBindingRules.isSaveable(base), isTrue);
      expect(NodeBindingRules.lossSummary(base), 'Nothing routed');
      expect(NodeBindingRules.lossTone(base), SlotTone.absent);
    });

    test('a scrap route with no destination blocks the save', () {
      final incomplete = base.copyWith(
        lossRoutes: const [LossRoute(id: 'a', kind: LossKind.scrap)],
      );
      expect(incomplete.lossRoutes.single.isComplete, isFalse);
      expect(NodeBindingRules.isSaveable(incomplete), isFalse);
      expect(NodeBindingRules.lossTone(incomplete), SlotTone.deferred);
    });

    test('two scrap routes to the same item block the save', () {
      final duplicated = base.copyWith(
        lossRoutes: const [
          LossRoute(id: 'a', kind: LossKind.scrap, scrapItemId: 'sc_brass'),
          LossRoute(id: 'b', kind: LossKind.scrap, scrapItemId: 'sc_brass'),
        ],
      );
      expect(NodeBindingRules.isSaveable(duplicated), isFalse);
    });

    test('one cut can yield two different scrap items', () {
      final twoMetals = base.copyWith(
        lossRoutes: const [
          LossRoute(id: 'a', kind: LossKind.scrap, scrapItemId: 'sc_brass'),
          LossRoute(id: 'b', kind: LossKind.scrap, scrapItemId: 'sc_alu'),
        ],
      );
      expect(NodeBindingRules.isSaveable(twoMetals), isTrue);
      expect(NodeBindingRules.lossSummary(twoMetals), '2 scrap items');
      expect(NodeBindingRules.lossTone(twoMetals), SlotTone.bound);
    });

    test('a route defaults its unit by kind but is not locked to it', () {
      const scrap = LossRoute(
        id: 'a',
        kind: LossKind.scrap,
        scrapItemId: 'sc_brass',
      );
      expect(scrap.effectiveUnitId, 'kg');

      const rejects = LossRoute(
        id: 'b',
        kind: LossKind.rejection,
        rejection: RejectionRoute.rework,
      );
      expect(rejects.effectiveUnitId, 'pcs');

      // Cones come off the floor counted in gross, not pieces.
      expect(rejects.copyWith(unitId: 'gross').unitSymbol, 'gross');
      expect(
        NodeConfiguratorCatalog.unitById('gross')?.family,
        UnitFamily.quantity,
      );
    });

    test('a unit from another family is allowed, not a validation failure', () {
      // Reel trim measured in running metres rather than weight.
      final trim = base.copyWith(
        lossRoutes: const [
          LossRoute(
            id: 'c',
            kind: LossKind.scrap,
            scrapItemId: 'sc_paper',
            unitId: 'm',
          ),
        ],
      );
      expect(trim.lossRoutes.single.unitSymbol, 'm');
      expect(NodeBindingRules.isSaveable(trim), isTrue);
    });

    test('a mixed node summarises both kinds', () {
      final mixed = base.copyWith(
        lossRoutes: const [
          LossRoute(id: 'a', kind: LossKind.scrap, scrapItemId: 'sc_brass'),
          LossRoute(
            id: 'b',
            kind: LossKind.rejection,
            rejection: RejectionRoute.rework,
          ),
        ],
      );
      expect(NodeBindingRules.lossSummary(mixed), '1 scrap · 1 rejection');
      expect(NodeBindingRules.isSaveable(mixed), isTrue);
    });
  });
}

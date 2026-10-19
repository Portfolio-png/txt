import 'package:core_erp/core/app_flow_hooks.dart';
import 'package:core_erp/core/widgets/app_button.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/data/repositories/item_repository.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/features/process_routes/data/process_route_service.dart';
import 'package:core_erp/features/process_routes/domain/part_route.dart';
import 'package:core_erp/features/process_routes/presentation/widgets/route_creation_panel.dart';
import 'package:core_erp/features/process_routes/presentation/widgets/route_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

// Authoring a route from the creation bench.
//
// A route is the one card on that bench which is not a master of its own:
// `process_routes.part_id` is a foreign key, so the card always needs a part.
// Most of what is worth asserting here is about that — what the card does
// before it has one, and that it asks the server for the right thing once it
// does.

ItemDefinition _item(int id, String name, {int? baseItemId, String partCode = ''}) {
  return ItemDefinition(
    id: id,
    name: name,
    displayName: name,
    alias: '',
    partCode: partCode,
    groupId: 1,
    unitId: 1,
    baseItemId: baseItemId,
    quantity: 0,
    namingFormat: const <String>[],
    variationTree: const <ItemVariationNodeDefinition>[],
    usageCount: 0,
    isArchived: false,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

/// Records what the panel asked for. Extends the real service so the panel is
/// exercised through its real type rather than an interface written for a test.
class _SpyRouteService extends ProcessRouteService {
  _SpyRouteService({this.activeFor, this.throwActive = false})
      : super(baseUrl: '', useMockResponses: true);

  /// A part that already has an active route.
  final PartRoute? activeFor;
  final bool throwActive;

  final List<(String, int, List<int>)> calls = [];

  @override
  Future<PartRoute?> activeRoute(int partId) async =>
      activeFor?.partId == partId ? activeFor : null;

  @override
  Future<List<PartRoute>> save(
    int partId,
    List<RouteStep> steps, {
    String status = 'active',
    String note = '',
  }) async {
    calls.add(('save', partId, [for (final s in steps) s.stageId]));
    if (throwActive) {
      throw RouteActiveException('already active', routeId: 9, version: 3);
    }
    return [
      PartRoute(
        id: 11,
        partId: partId,
        version: 1,
        status: RouteStatus.active,
        steps: steps,
      ),
    ];
  }

  @override
  Future<List<PartRoute>> declareVersion(
    int partId,
    List<RouteStep> steps, {
    String note = '',
  }) async {
    calls.add(('declareVersion', partId, [for (final s in steps) s.stageId]));
    return [
      PartRoute(
        id: 12,
        partId: partId,
        version: 2,
        status: RouteStatus.active,
        steps: steps,
      ),
    ];
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required List<ItemDefinition> items,
  ProcessRouteService? service,
  int? initialPartId,
  Set<int> madeHere = const <int>{},
  ValueChanged<CreatedRecord>? onSaved,
  VoidCallback? onCancel,
}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final providers = <SingleChildWidget>[
    ChangeNotifierProvider<ItemsProvider>.value(value: _FakeItems(items)),
    if (service != null) Provider<ProcessRouteService>.value(value: service),
  ];

  await tester.pumpWidget(
    MultiProvider(
      providers: providers,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RouteCreationPanel(
              initialPartId: initialPartId,
              madeHereItemIds: madeHere,
              onSaved: onSaved ?? (_) {},
              onCancel: onCancel ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeItems extends ItemsProvider {
  _FakeItems(this._items) : super(repository: _NullRepo());

  final List<ItemDefinition> _items;

  @override
  List<ItemDefinition> get items => _items;
}

/// The panel never calls the repository — it reads `items` and writes through
/// `ProcessRouteService`. noSuchMethod keeps this free as the interface grows.
class _NullRepo implements ItemRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Adds one step through the CLASSIC lens — one dropdown per step, which is
/// what the default `routes.listLens: false` gives and therefore what these
/// tests must drive. `dev_config.dart` wins over a fetched config whenever
/// `useDevConfig` is true, which it is in a debug test binary, so the flag
/// cannot be flipped from here. Both lenses are covered in
/// route_editor_test.dart; what matters here is the panel around them.
Future<void> _addStep(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('route_add_step')));
  await tester.pumpAndSettle();
}

AppButton _saveButton(WidgetTester tester) {
  return tester.widget<AppButton>(
    find.ancestor(
      of: find.textContaining('Save'),
      matching: find.byType(AppButton),
    ),
  );
}

void main() {
  group('RouteCreationPanel', () {
    testWidgets('without a part, Save is drawn disabled and says why', (tester) async {
      // Never hide a control until its precondition holds: a Save that
      // disappears until a part is picked reads as a broken card.
      await _pump(
        tester,
        items: [_item(1, 'Patti')],
        service: _SpyRouteService(),
      );

      expect(find.byKey(const ValueKey('route_part_field')), findsOneWidget);
      expect(_saveButton(tester).onPressed, isNull);

      final tooltip = tester.widget<Tooltip>(
        find.ancestor(
          of: find.textContaining('Save'),
          matching: find.byType(Tooltip),
        ),
      );
      expect(tooltip.message, contains('part'));
    });

    testWidgets('with a part but no stages, Save stays disabled', (tester) async {
      await _pump(
        tester,
        items: [_item(1, 'Patti')],
        service: _SpyRouteService(),
        initialPartId: 1,
      );
      expect(_saveButton(tester).onPressed, isNull);
      final tooltip = tester.widget<Tooltip>(
        find.ancestor(
          of: find.textContaining('Save'),
          matching: find.byType(Tooltip),
        ),
      );
      expect(tooltip.message, contains('stage'));
    });

    testWidgets('sends the ordered stage ids and hands back a record', (tester) async {
      final service = _SpyRouteService();
      CreatedRecord? saved;
      await _pump(
        tester,
        items: [_item(1, 'Patti', partCode: 'SADP48')],
        service: service,
        initialPartId: 1,
        onSaved: (record) => saved = record,
      );

      // Three stages. Add step appends the first stage still available, so
      // this is die, then shearing, then cutting.
      await _addStep(tester);
      await _addStep(tester);
      await _addStep(tester);
      expect(_saveButton(tester).onPressed, isNotNull);

      await tester.tap(find.textContaining('Save'));
      await tester.pumpAndSettle();

      expect(service.calls, hasLength(1));
      expect(service.calls.single.$1, 'save');
      expect(service.calls.single.$2, 1);
      expect(service.calls.single.$3, [1, 2, 3]);

      // Hands the record to the host and does NOT pop — the host owns the
      // window, which is what the embedded-editor contract requires.
      expect(saved, isNotNull);
      expect(saved!.title, contains('Patti'));
      expect(saved!.subtitle, '3 stages');
      expect(find.byType(RouteCreationPanel), findsOneWidget);
    });

    testWidgets('an authored stage list survives picking the part afterwards', (tester) async {
      // "Held until there is a part to attach it to": somebody can lay out the
      // stages first and name the part second without losing their work.
      final service = _SpyRouteService();
      await _pump(
        tester,
        items: [_item(1, 'Patti'), _item(2, 'Cover')],
        service: service,
      );

      await _addStep(tester);
      await _addStep(tester);
      expect(find.text('Die'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('route_part_field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cover').last);
      await tester.pumpAndSettle();

      // Still there, and now saveable.
      expect(find.text('Die'), findsOneWidget);
      expect(find.text('Shearing'), findsOneWidget);
      expect(_saveButton(tester).onPressed, isNotNull);

      await tester.tap(find.textContaining('Save'));
      await tester.pumpAndSettle();
      expect(service.calls.single.$2, 2, reason: 'the part picked second');
      expect(service.calls.single.$3, [1, 2]);
    });

    testWidgets('a part with an active route is locked, and a change versions it', (tester) async {
      // An active route is never edited in place. The panel asks for a version
      // rather than letting the server refuse a save.
      final service = _SpyRouteService(
        activeFor: const PartRoute(
          id: 7,
          partId: 1,
          version: 3,
          status: RouteStatus.active,
          steps: [
            RouteStep(stageId: 1, seq: 1, stageName: 'Die'),
            RouteStep(stageId: 2, seq: 2, stageName: 'Shearing'),
          ],
        ),
      );
      await _pump(
        tester,
        items: [_item(1, 'Patti')],
        service: service,
        initialPartId: 1,
      );

      // It adopts the live route's steps, so a version starts from what it
      // changes rather than from nothing.
      expect(find.textContaining('Version 3 is active'), findsOneWidget);
      expect(find.text('Die'), findsOneWidget);
      expect(find.text('Shearing'), findsOneWidget);
      expect(_saveButton(tester).label, 'Save as new version');

      await tester.tap(find.byKey(const ValueKey('route_declare_version')));
      await tester.pumpAndSettle();

      // Unlocked for editing, and the bar is gone.
      expect(find.textContaining('Version 3 is active'), findsNothing);
      await _addStep(tester);

      await tester.tap(find.textContaining('Save'));
      await tester.pumpAndSettle();

      // declareVersion, NOT save — pressing New version clears the locked
      // state, so only the pending-version marker keeps this right.
      expect(service.calls.single.$1, 'declareVersion');
      expect(service.calls.single.$3, [1, 2, 3]);
    });

    testWidgets('a route activated elsewhere mid-edit is reported, not swallowed', (tester) async {
      final service = _SpyRouteService(throwActive: true);
      CreatedRecord? saved;
      await _pump(
        tester,
        items: [_item(1, 'Patti')],
        service: service,
        initialPartId: 1,
        onSaved: (r) => saved = r,
      );
      await _addStep(tester);
      await tester.tap(find.textContaining('Save'));
      await tester.pumpAndSettle();

      expect(find.textContaining('already active'), findsOneWidget);
      expect(saved, isNull, reason: 'nothing was saved, so nothing is reported as saved');
    });

    testWidgets('the picker names variants by their code and puts this sitting first', (tester) async {
      // "Patti Brass 22" and "Patti MS 22" read alike in a list; SADPB2248 and
      // SADPMS2248 do not, which is the whole point of a variant code.
      await _pump(
        tester,
        items: [
          _item(1, 'Patti', partCode: 'SADP48'),
          _item(2, 'Patti Brass 22', baseItemId: 1, partCode: 'SADPB2248'),
          _item(3, 'Patti MS 22', baseItemId: 1, partCode: 'SADPMS2248'),
        ],
        service: _SpyRouteService(),
        madeHere: const {3},
      );

      await tester.tap(find.byKey(const ValueKey('route_part_field')));
      await tester.pumpAndSettle();

      expect(find.textContaining('SADPB2248'), findsOneWidget);
      expect(find.textContaining('SADPMS2248'), findsOneWidget);
      expect(find.textContaining('variant'), findsWidgets);
      // Made in this sitting is said out loud, because that is the part
      // somebody is almost always routing.
      expect(find.textContaining('made just now'), findsOneWidget);
    });

    testWidgets('no service renders a line instead of throwing', (tester) async {
      // The same degradation the part inspector makes for a provider that is
      // not in the tree. A build that cannot route is not a crash.
      await _pump(tester, items: [_item(1, 'Patti')]);
      expect(find.text('Routing is not available in this build.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Cancel hands back to the host rather than popping', (tester) async {
      var cancelled = false;
      await _pump(
        tester,
        items: [_item(1, 'Patti')],
        service: _SpyRouteService(),
        onCancel: () => cancelled = true,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(cancelled, isTrue);
      expect(find.byType(RouteCreationPanel), findsOneWidget);
    });

    testWidgets('the embedded seam builds the panel and passes its arguments on', (tester) async {
      // The bench reaches a route through this seam, so it has to return the
      // panel — and carry the part it was opened for, which is what lets a
      // caller point the card at a part instead of making someone search.
      Widget? built;
      final builder = routeEditorPanel(
        initialPartId: 5,
        madeHereItemIds: const {5},
      );
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) {
            built = builder(context, onSaved: (_) {}, onCancel: () {});
            return const SizedBox.shrink();
          },
        ),
      ));

      expect(built, isA<RouteCreationPanel>());
      final panel = built! as RouteCreationPanel;
      expect(panel.initialPartId, 5);
      expect(panel.madeHereItemIds, const {5});
    });
  });
}

import 'package:core_erp/features/variations/data/variation_tree_service.dart';
import 'package:core_erp/features/variations/domain/variation_node.dart';
import 'package:core_erp/features/variations/presentation/widgets/variation_tree_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The variation tree editor, and the rule it exists to make visible: what is
// already in a version is fixed, adding to it is not. Driven against the
// service's own in-memory store, which stamps ids and versions exactly as the
// backend does — so the lock is observable here without a server.

Widget _host(VariationTreeController controller, {VoidCallback? onVersion}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: SizedBox(
          width: 720,
          child: VariationTreeEditor(
            controller: controller,
            onDeclareVersion: onVersion,
          ),
        ),
      ),
    ),
  );
}

void main() {
  late VariationTreeService service;
  late VariationTreeController controller;

  setUp(() {
    service = VariationTreeService(baseUrl: '', useMockResponses: true);
    controller = VariationTreeController(service: service, type: 'die');
  });

  tearDown(() => controller.dispose());

  testWidgets('properties and values are built and saved', (tester) async {
    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    expect(find.textContaining('No variations yet'), findsOneWidget);
    expect(find.text('Version 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('variation_add_property')));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Property, e.g. Cavity').first, 'Cavity');
    await tester.pumpAndSettle();

    final addValue = find.byWidgetPredicate(
      (widget) =>
          widget is TextButton &&
          widget.key.toString().contains('variation_add_value'),
    );
    await tester.tap(addValue);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Value').first, '2');
    await tester.pumpAndSettle();

    expect(controller.nodes.length, 1);
    expect(controller.nodes.first.name, 'Cavity');
    expect(controller.nodes.first.children.single.name, '2');

    expect(await controller.save('7'), isNull);
    final stored = await service.fetch('die', '7');
    expect(stored.nodes.single.name, 'Cavity');
    expect(stored.nodes.single.children.single.name, '2');
  });

  testWidgets('what is saved locks, and the editor says so', (tester) async {
    await service.save('die', '7', [
      VariationNode(
        kind: 'property',
        name: 'Cavity',
        children: [VariationNode(kind: 'value', name: '2')],
      ),
    ]);
    await controller.load('7');
    var versionAsked = 0;
    await tester.pumpWidget(_host(controller, onVersion: () => versionAsked++));
    await tester.pumpAndSettle();

    expect(controller.locked, isTrue);
    expect(find.textContaining('Fixed in this version'), findsOneWidget);

    // The stored property cannot be retyped or removed...
    final property = controller.nodes.single;
    expect(controller.canEdit(property), isFalse);
    final nameField = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Property, e.g. Cavity').first,
    );
    expect(nameField.enabled, isFalse);
    final removeKey = ValueKey('variation_remove_${property.id}');
    expect(tester.widget<IconButton>(find.byKey(removeKey)).onPressed, isNull);

    // ...but a value can still be added to it, which is the edit the shop
    // floor actually makes.
    await tester.tap(
      find.byKey(ValueKey('variation_add_value_${property.id}')),
    );
    await tester.pumpAndSettle();
    expect(property.children.length, 2);
    expect(
      controller.canEdit(property.children.last),
      isTrue,
      reason: 'a value added now is new, so it is not fixed by the old version',
    );
    expect(await controller.save('7'), isNull);

    // And the way out is offered, not hidden.
    await tester.tap(find.byKey(const ValueKey('variation_new_version')));
    await tester.pumpAndSettle();
    expect(versionAsked, 1);
  });

  testWidgets('a declared version unlocks what was fixed', (tester) async {
    await service.save('die', '7', [
      VariationNode(
        kind: 'property',
        name: 'Cavity',
        children: [VariationNode(kind: 'value', name: '2')],
      ),
    ]);
    await controller.load('7');
    expect(controller.locked, isTrue);

    expect(await controller.declareVersion('7', label: 'Rev B'), isNull);
    expect(controller.version, 2);
    expect(
      controller.locked,
      isFalse,
      reason: 'declaring a version is what opens the tree for changes',
    );

    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();
    expect(find.text('Version 2 · Rev B'), findsOneWidget);
    expect(find.textContaining('Open for changes'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.widgetWithText(TextField, 'Property, e.g. Cavity').first,
          )
          .enabled,
      isTrue,
    );
  });

  testWidgets('a locked save is reported, not swallowed', (tester) async {
    // The service refuses nothing in demo mode, so this drives the exception
    // path directly — what the editor must do with a 409 is show it.
    final failing = _RefusingService();
    final locked = VariationTreeController(service: failing, type: 'die');
    addTearDown(locked.dispose);
    locked.addProperty();
    locked.nodes.single.name = 'Cavity';

    final failure = await locked.save('7');
    expect(failure, isNotNull);
    expect(failure, contains('new version'));
    expect(
      failure,
      contains("Cavity: name 'Cavity' -> 'Cav'"),
      reason: 'the message carries what would have changed, so it can be read',
    );
  });

  testWidgets('richer input types: Numeric bounds, Gauge, and Material', (tester) async {
    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    // 1. Add property and switch to Numeric
    await tester.tap(find.byKey(const ValueKey('variation_add_property')));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Property, e.g. Cavity').first, 'Thickness');
    await tester.pumpAndSettle();

    // Open input type popup and select Numeric
    final property = controller.nodes.first;
    await tester.tap(find.byKey(ValueKey('variation_type_${property.id ?? identityHashCode(property)}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('variation_type_opt_Numeric')));
    await tester.pumpAndSettle();

    expect(property.inputType, 'Numeric');
    expect(find.text('Range: '), findsOneWidget);

    // Enter Min and Max bounds
    final minField = find.byKey(ValueKey('variation_min_${property.id ?? identityHashCode(property)}'));
    final maxField = find.byKey(ValueKey('variation_max_${property.id ?? identityHashCode(property)}'));
    expect(minField, findsOneWidget);
    expect(maxField, findsOneWidget);

    await tester.enterText(minField, '1.5');
    await tester.enterText(maxField, '10');
    await tester.pumpAndSettle();

    expect(property.numericMin, 1.5);
    expect(property.numericMax, 10.0);

    // Save and verify persistence
    expect(await controller.save('7'), isNull);
    final stored = await service.fetch('die', '7');
    expect(stored.nodes.first.inputType, 'Numeric');
    expect(stored.nodes.first.numericMin, 1.5);
    expect(stored.nodes.first.numericMax, 10.0);

    // 2. Switch to Gauge
    // It's locked because it was saved! Let's declare a new version to unlock:
    expect(await controller.declareVersion('7', label: 'Rev B'), isNull);
    await tester.pumpAndSettle();

    final savedId = controller.nodes.first.id;
    await tester.tap(find.byKey(ValueKey('variation_type_$savedId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('variation_type_opt_Gauge')));
    await tester.pumpAndSettle();

    expect(find.textContaining('SWG Gauge input'), findsOneWidget);

    // 3. Switch to Material
    await tester.tap(find.byKey(ValueKey('variation_type_$savedId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('variation_type_opt_Material')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Material values linked to materials master'), findsOneWidget);
  });
}

class _RefusingService extends VariationTreeService {
  _RefusingService() : super(baseUrl: '', useMockResponses: true);

  @override
  Future<VariationTree> save(
    String type,
    String id,
    List<VariationNode> nodes,
  ) async {
    throw VariationLockedException(
      'This die is on version 1. Adding is fine; changing or removing needs a '
      'new version.',
      ["Cavity: name 'Cavity' -> 'Cav'"],
    );
  }
}

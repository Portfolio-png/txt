import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/shared/widgets/exact_item_variation_select_field.dart';
import 'package:core_erp/shared/widgets/output_variation_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A run started to build stock has no order line to say which variation it
/// produces, so the operator is the only one who knows. What is pinned here is
/// mostly about *when not to ask*, and about the escape hatch: an operator who
/// cannot start work without answering will learn to answer falsely, and a
/// false variation goes into an append-only ledger and stays there.

final DateTime _when = DateTime(2026, 1, 1);

ItemVariationNodeDefinition node({
  required int id,
  required int itemId,
  int? parentNodeId,
  required ItemVariationNodeKind kind,
  required String name,
  List<ItemVariationNodeDefinition> children = const <ItemVariationNodeDefinition>[],
}) {
  return ItemVariationNodeDefinition(
    id: id,
    itemId: itemId,
    parentNodeId: parentNodeId,
    kind: kind,
    name: name,
    displayName: name,
    position: 0,
    isArchived: false,
    createdAt: _when,
    updatedAt: _when,
    children: children,
  );
}

ItemDefinition item({
  required int id,
  required String name,
  List<ItemVariationNodeDefinition> tree = const <ItemVariationNodeDefinition>[],
}) {
  return ItemDefinition(
    id: id,
    name: name,
    alias: '',
    displayName: name,
    quantity: 0,
    groupId: 1,
    unitId: 1,
    isArchived: false,
    usageCount: 0,
    createdAt: _when,
    updatedAt: _when,
    variationTree: tree,
  );
}

/// An item with one property carrying two values — the ordinary case where a
/// question genuinely needs asking.
ItemDefinition itemWithVariations() {
  return item(
    id: 7,
    name: 'Socket 10A',
    tree: <ItemVariationNodeDefinition>[
      node(
        id: 100,
        itemId: 7,
        kind: ItemVariationNodeKind.property,
        name: 'Finish',
        children: <ItemVariationNodeDefinition>[
          node(id: 101, itemId: 7, parentNodeId: 100, kind: ItemVariationNodeKind.value, name: 'Matte'),
          node(id: 102, itemId: 7, parentNodeId: 100, kind: ItemVariationNodeKind.value, name: 'Gloss'),
        ],
      ),
    ],
  );
}

Widget host(void Function(BuildContext) onTap) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => onTap(context),
          child: const Text('open'),
        ),
      ),
    ),
  );
}

void main() {
  group('deciding whether there is a question at all', () {
    test('an item with variations offers each of them', () {
      final choices = outputVariationChoices(
        outputName: 'Socket 10A',
        items: <ItemDefinition>[itemWithVariations()],
      );
      expect(choices, hasLength(2));
      expect(choices.map((choice) => choice.variationLeafNodeId), <int>[101, 102]);
    });

    test('a base item has nothing to choose between', () {
      // Not an error, and not a dialog: there is exactly one thing this run can
      // be making, so interrupting the operator would be noise.
      //
      // The trap this pins: buildExactItemVariationReferences represents a base
      // item as ONE reference with leaf id 0, not as an empty list. Testing for
      // emptiness alone opened a dialog offering a single meaningless option —
      // and leaf 0 is what the server reads as "not stated", so picking it would
      // have said nothing at all.
      final choices = outputVariationChoices(
        outputName: 'Plain Bracket',
        items: <ItemDefinition>[item(id: 8, name: 'Plain Bracket')],
      );
      expect(choices, isEmpty);
    });

    test('an output this workspace does not carry is not a question either', () {
      // A template can name an output that was never created as an item. That
      // is a data gap, but it is not something the operator can answer.
      final choices = outputVariationChoices(
        outputName: 'Something Else',
        items: <ItemDefinition>[itemWithVariations()],
      );
      expect(choices, isEmpty);
    });

    test('the name is matched forgivingly, because templates are typed by hand', () {
      expect(
        outputVariationChoices(
          outputName: '  socket 10a  ',
          items: <ItemDefinition>[itemWithVariations()],
        ),
        hasLength(2),
      );
    });

    test('an empty output name asks nothing', () {
      expect(
        outputVariationChoices(
          outputName: '   ',
          items: <ItemDefinition>[itemWithVariations()],
        ),
        isEmpty,
      );
    });
  });

  group('the prompt', () {
    testWidgets('does not open a dialog when there is nothing to ask', (
      tester,
    ) async {
      ExactItemVariationReference? result;
      var returned = false;
      await tester.pumpWidget(host((context) async {
        result = await promptStandaloneRunOutputVariation(
          context,
          outputName: 'Plain Bracket',
          items: <ItemDefinition>[item(id: 8, name: 'Plain Bracket')],
        );
        returned = true;
      }));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(returned, isTrue, reason: 'it returns rather than hanging');
      expect(result, isNull);
    });

    testWidgets('asks when the output could be one of several things', (
      tester,
    ) async {
      await tester.pumpWidget(host((context) {
        promptStandaloneRunOutputVariation(
          context,
          outputName: 'Socket 10A',
          items: <ItemDefinition>[itemWithVariations()],
        );
      }));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('What is this run making?'), findsOneWidget);
      // Says what happens if they do not answer, rather than implying the run
      // is blocked.
      expect(find.textContaining('still finishes'), findsOneWidget);
    });
  });

  group('the dialog', () {
    Future<ExactItemVariationReference?> show(WidgetTester tester) async {
      ExactItemVariationReference? captured;
      await tester.pumpWidget(host((context) async {
        captured = await showDialog<ExactItemVariationReference>(
          context: context,
          builder: (context) => OutputVariationDialog(
            outputName: 'Socket 10A',
            references: outputVariationChoices(
              outputName: 'Socket 10A',
              items: <ItemDefinition>[itemWithVariations()],
            ),
          ),
        );
      }));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return captured;
    }

    testWidgets('cannot be confirmed until something is chosen', (tester) async {
      await show(tester);
      final confirm = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Use this'),
      );
      expect(
        confirm.onPressed,
        isNull,
        reason: 'the confirming button must not be the one that returns nothing',
      );
    });

    testWidgets('"Not sure yet" lets the work start anyway', (tester) async {
      // The whole point of the escape hatch. An operator who cannot begin
      // without answering learns to answer falsely to get past the dialog, and
      // a false variation is permanent — where an unattributed lot is not.
      ExactItemVariationReference? captured;
      await tester.pumpWidget(host((context) async {
        captured = await showDialog<ExactItemVariationReference>(
          context: context,
          builder: (context) => OutputVariationDialog(
            outputName: 'Socket 10A',
            references: outputVariationChoices(
              outputName: 'Socket 10A',
              items: <ItemDefinition>[itemWithVariations()],
            ),
          ),
        );
      }));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Not sure yet'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(captured, isNull, reason: 'not stated — and the caller proceeds');
    });

    testWidgets('a chosen variation comes back to the caller', (tester) async {
      ExactItemVariationReference? captured;
      await tester.pumpWidget(host((context) async {
        captured = await showDialog<ExactItemVariationReference>(
          context: context,
          builder: (context) => OutputVariationDialog(
            outputName: 'Socket 10A',
            references: outputVariationChoices(
              outputName: 'Socket 10A',
              items: <ItemDefinition>[itemWithVariations()],
            ),
          ),
        );
      }));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Open the searchable picker and take the second value, so a passing test
      // cannot be explained by whatever happens to be first.
      await tester.tap(find.byKey(const Key('run-output-variation')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Gloss').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Use this'));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.variationLeafNodeId, 102);
      expect(captured!.itemId, 7);
    });
  });
}

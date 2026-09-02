import 'package:flutter/material.dart';

import '../../features/items/domain/item_definition.dart';
import 'exact_item_variation_select_field.dart';

/// Asking a standalone production run what it is about to make.
///
/// A run tied to an order line needs no answer — the line says which variation
/// was promised, and that always wins. A run started to build stock has nobody
/// to ask but the person starting it, and before this there was nowhere to
/// write the answer down, so completing such a run had to either guess a
/// variation or decline to mint anything.
///
/// Lives here, in the package, rather than beside the console that calls it:
/// the app's own test directory does not compile, so anything left there is
/// untestable in practice. Split into a pure choice function and a widget so
/// the decision — *is there even a question to ask?* — can be checked without
/// pumping a frame.

/// The variations [outputName] could refer to, or empty when there is no
/// question worth asking.
///
/// Empty covers two different situations that both mean "do not interrupt
/// anyone": the output is a base item with no variations to choose between, or
/// this workspace does not carry it as an item at all. Neither is an error.
List<ExactItemVariationReference> outputVariationChoices({
  required String outputName,
  required List<ItemDefinition> items,
}) {
  final wanted = outputName.trim().toLowerCase();
  if (wanted.isEmpty) return const <ExactItemVariationReference>[];

  final matches = items
      .where((item) => item.name.trim().toLowerCase() == wanted)
      .toList(growable: false);
  if (matches.isEmpty) return const <ExactItemVariationReference>[];

  // Only real choices. `buildExactItemVariationReferences` represents a base
  // item as a single reference with leaf id 0 rather than as an empty list, so
  // checking for emptiness alone would open a dialog offering one meaningless
  // option — and 0 is exactly what the server reads as "not stated" anyway, so
  // choosing it would say nothing.
  return buildExactItemVariationReferences(matches)
      .where((reference) => reference.variationLeafNodeId > 0)
      .toList(growable: false);
}

/// Asks, when there is something to ask.
///
/// Returns null both when the question does not arise and when the operator
/// declines it. The caller must treat both the same way — as "not stated" — and
/// start the run regardless. Blocking here would stop someone beginning
/// physical work over an attribution they can make later.
Future<ExactItemVariationReference?> promptStandaloneRunOutputVariation(
  BuildContext context, {
  required String outputName,
  required List<ItemDefinition> items,
}) async {
  final choices = outputVariationChoices(outputName: outputName, items: items);
  if (choices.isEmpty) return null;
  if (!context.mounted) return null;

  return showDialog<ExactItemVariationReference>(
    context: context,
    builder: (context) => OutputVariationDialog(
      outputName: outputName,
      references: choices,
    ),
  );
}

class OutputVariationDialog extends StatefulWidget {
  const OutputVariationDialog({
    super.key,
    required this.outputName,
    required this.references,
  });

  final String outputName;
  final List<ExactItemVariationReference> references;

  @override
  State<OutputVariationDialog> createState() => _OutputVariationDialogState();
}

class _OutputVariationDialogState extends State<OutputVariationDialog> {
  ExactItemVariationReference? _selected;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('What is this run making?'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'This run is not tied to an order, so nothing else can say which '
              'variation of ${widget.outputName} it produces. Without it the run '
              'still finishes — it just will not put finished goods into '
              'inventory, because guessing would be worse.',
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            ExactItemVariationSelectField(
              fieldKey: const Key('run-output-variation'),
              value: _selected?.key,
              references: widget.references,
              enabled: true,
              labelText: 'Output variation',
              dialogTitle: 'Select output variation',
              onChanged: (reference) => setState(() => _selected = reference),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          // Deliberately not a cancel: the run still deploys. An operator who
          // genuinely does not know yet must not be stopped from starting work
          // — that is how people learn to type something false to get past a
          // dialog, and a false variation is permanent.
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Not sure yet'),
        ),
        FilledButton(
          // Disabled until something is chosen, so the confirming button cannot
          // be the one that returns nothing.
          onPressed: _selected == null
              ? null
              : () => Navigator.of(context).pop(_selected),
          child: const Text('Use this'),
        ),
      ],
    );
  }
}

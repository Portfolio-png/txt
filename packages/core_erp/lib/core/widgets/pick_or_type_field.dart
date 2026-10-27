import 'package:flutter/material.dart';

import 'searchable_select.dart';

/// A searchable dropdown over the values already used, that also takes a new
/// one — for a free-text answer that repeats ("Mayank", "Progressive", 110).
///
/// Backed by a [TextEditingController] so a form that reads and resets its
/// fields through controllers keeps doing so. The options are whatever the
/// caller has seen used before; a value typed here becomes one of them the
/// next time, because it is saved with the record it was typed for.
class PickOrTypeField extends StatelessWidget {
  const PickOrTypeField({
    super.key,
    this.fieldKey,
    required this.controller,
    required this.label,
    required this.options,
    this.enabled = true,
    this.onChanged,
    this.errorText,
    this.searchKeyboardType,
  });

  /// On the field itself, for finding it in a test.
  final Key? fieldKey;
  final TextEditingController controller;
  final String label;
  final List<String> options;
  final bool enabled;
  final VoidCallback? onChanged;
  final String? errorText;

  /// The keyboard for the search box — a number pad for a figure.
  final TextInputType? searchKeyboardType;

  @override
  Widget build(BuildContext context) {
    final current = controller.text.trim();
    // The value on the form is always one of the choices, typed or not, so
    // the field shows it and the list marks it.
    final values = <String>[
      if (current.isNotEmpty) current,
      for (final option in options)
        if (option.trim().isNotEmpty &&
            option.trim().toLowerCase() != current.toLowerCase())
          option.trim(),
    ];
    bool known(String query) =>
        values.any((v) => v.toLowerCase() == query.trim().toLowerCase());

    return SearchableSelectField<String>(
      key: fieldKey,
      value: current.isEmpty ? null : current,
      fieldEnabled: enabled,
      dialogTitle: label,
      searchHintText: 'Search or type a new $label',
      keyboardType: searchKeyboardType,
      emptyText: 'Nothing used yet — type one',
      options: [
        for (final value in values)
          SearchableSelectOption<String>(value: value, label: value),
      ],
      canCreateOption: (query, _) =>
          query.trim().isNotEmpty && !known(query),
      createOptionLabelBuilder: (query) => 'Use "${query.trim()}"',
      onCreateOption: (query) async => SearchableSelectOption<String>(
        value: query.trim(),
        label: query.trim(),
      ),
      decoration: InputDecoration(
        labelText: label,
        errorText: errorText,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      onChanged: (value) {
        final next = value ?? '';
        controller.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
        onChanged?.call();
      },
    );
  }
}

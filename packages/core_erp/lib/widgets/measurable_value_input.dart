import 'package:flutter/material.dart';

import '../features/units/domain/unit_definition.dart';

/// A compact unit picker rendered as a small "symbol ▼" affordance.
///
/// Tapping it opens a [PopupMenuButton] listing the allowed units. It is used
/// both as the suffix of [MeasurableValueInput] and standalone wherever a
/// measurable value only needs its unit changed (e.g. dense variation tables),
/// replacing the wider [DropdownButton] those layouts previously used.
class UnitSuffixButton extends StatelessWidget {
  const UnitSuffixButton({
    super.key,
    required this.allowedUnits,
    required this.selectedUnitId,
    required this.onUnitChanged,
    this.enabled = true,
    this.placeholder = 'Unit',
  });

  /// Units offered in the popup menu.
  final List<UnitDefinition> allowedUnits;

  /// Currently selected unit, or null when none is chosen yet.
  final int? selectedUnitId;

  /// Invoked with the newly selected unit id.
  final ValueChanged<int?> onUnitChanged;

  /// Disables interaction (read-only contexts).
  final bool enabled;

  /// Shown when no unit is selected.
  final String placeholder;

  /// Short label for a unit: its symbol, falling back to its name.
  String _shortLabel(UnitDefinition unit) =>
      unit.symbol.trim().isEmpty ? unit.name : unit.symbol.trim();

  @override
  Widget build(BuildContext context) {
    final selected = allowedUnits
        .where((unit) => unit.id == selectedUnitId)
        .firstOrNull;
    final label = selected == null ? placeholder : _shortLabel(selected);
    final theme = Theme.of(context);

    return PopupMenuButton<int>(
      enabled: enabled,
      tooltip: 'Change unit',
      // Keep the affordance tight so it sits cleanly inside a field suffix.
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        for (final unit in allowedUnits)
          PopupMenuItem<int>(
            value: unit.id,
            child: Text(
              unit.symbol.trim().isEmpty
                  ? unit.name
                  : '${unit.name} (${unit.symbol.trim()})',
            ),
          ),
      ],
      onSelected: onUnitChanged,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: selected == null
                    ? theme.hintColor
                    : theme.textTheme.bodyMedium?.color,
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 20),
          ],
        ),
      ),
    );
  }
}

/// A space-efficient measurable-value control: a single quantity [TextField]
/// whose unit lives in the suffix as a tappable [UnitSuffixButton].
///
/// This replaces the older wide `Row(TextField + DropdownButton)` layouts so a
/// measurable value occupies roughly the width of a normal text field.
class MeasurableValueInput extends StatelessWidget {
  const MeasurableValueInput({
    super.key,
    required this.controller,
    required this.allowedUnits,
    required this.selectedUnitId,
    required this.onUnitChanged,
    this.decoration,
    this.autofocus = false,
    this.enabled = true,
    this.onSubmitted,
  });

  /// Holds the quantity entered in the main field.
  final TextEditingController controller;

  /// Units offered in the unit popup.
  final List<UnitDefinition> allowedUnits;

  /// Currently selected unit id, or null.
  final int? selectedUnitId;

  /// Invoked when the user picks a different unit.
  final ValueChanged<int?> onUnitChanged;

  /// Optional decoration overrides (label, border, etc.). The unit suffix is
  /// always applied on top of whatever is provided here.
  final InputDecoration? decoration;

  final bool autofocus;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final base = decoration ?? const InputDecoration();
    return TextField(
      controller: controller,
      autofocus: autofocus,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onSubmitted: onSubmitted,
      decoration: base.copyWith(
        suffixIcon: UnitSuffixButton(
          allowedUnits: allowedUnits,
          selectedUnitId: selectedUnitId,
          onUnitChanged: onUnitChanged,
          enabled: enabled,
        ),
        // Keep the suffix from forcing an oversized minimum width.
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      ),
    );
  }
}

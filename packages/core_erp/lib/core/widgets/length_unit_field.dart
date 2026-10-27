/// A measurement: a number, and the unit it was read in.
///
/// Stored as an integer count of **nanometres**, which is what the units
/// contract asks for and not an arbitrary choice: it forbids floats for a
/// quantity and wants an integer count of a base small enough that every unit
/// offered is a whole multiple of it. Micrometres would not do — 1 thou is
/// 25.4 µm — while in nanometres mm, cm, inch, thou and every SWG gauge row
/// land exactly.
///
/// The unit travels beside the value because it is how the measurement was
/// *read*, not what it *is*: a drawing quoted in thou stays quoted in thou.
/// It never takes part in arithmetic.
library;

import 'package:flutter/material.dart';

import '../../features/units/domain/global_length_units.dart';
import '../theme/soft_erp_theme.dart';
import 'pick_or_type_field.dart';
import 'searchable_select.dart';

/// Nanometres in one millimetre.
const int nanometresPerMillimetre = 1000000;

/// What a typed number and a unit come to, in whole nanometres.
///
/// Null when the field is empty, which is a different answer from zero.
/// [LengthParseResult.error] is set when the value cannot be expressed in
/// whole nanometres, which the contract says to refuse rather than round away.
class LengthParseResult {
  const LengthParseResult.empty() : nanometres = null, error = null;
  const LengthParseResult.value(int this.nanometres) : error = null;
  const LengthParseResult.failed(String this.error) : nanometres = null;

  final int? nanometres;
  final String? error;

  bool get isFailure => error != null;
}

LengthParseResult parseLengthToNanometres(String? raw, String unitSymbol) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return const LengthParseResult.empty();
  final typed = double.tryParse(text);
  if (typed == null || typed.isNaN || typed.isInfinite || typed < 0) {
    return const LengthParseResult.failed('Not a measurement');
  }

  final unit = lengthUnitBySymbol(unitSymbol);
  final millimetres = unit.toMm(typed);
  if (millimetres <= 0) {
    return LengthParseResult.failed(
      unit.isGauge ? 'No such gauge in the table' : 'Not a measurement',
    );
  }

  final exact = millimetres * nanometresPerMillimetre;
  final rounded = exact.roundToDouble();
  // The slack is floating-point noise at a scale of millions, not rounding of
  // what was typed: a value that genuinely falls between nanometres misses by
  // far more than this and is refused, as I6 requires.
  if ((exact - rounded).abs() > 0.001) {
    return LengthParseResult.failed(
      'That is not a whole number of nanometres — type it in mm',
    );
  }
  return LengthParseResult.value(rounded.toInt());
}

/// Nanometres back to a number in [unitSymbol], for putting in a field.
String formatLengthFromNanometres(int? nanometres, String unitSymbol) {
  if (nanometres == null) return '';
  final unit = lengthUnitBySymbol(unitSymbol);
  final millimetres = nanometres / nanometresPerMillimetre;
  if (unit.isGauge) {
    // A gauge is a lookup, not a ratio, so there is nothing to divide by.
    // Showing the millimetres is more honest than inventing a gauge number.
    return millimetres.toString();
  }
  final value = millimetres / unit.millimetres;
  // Trailing zeros off: 94.50 and 94.5 are the same measurement, and a field
  // that rewrites what someone typed as they type is maddening.
  final text = value.toStringAsFixed(4);
  return text.contains('.')
      ? text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
      : text;
}

/// The number and its unit, side by side.
class LengthUnitField extends StatelessWidget {
  const LengthUnitField({
    super.key,
    required this.controller,
    required this.unitSymbol,
    required this.onUnitChanged,
    this.label = 'Size',
    this.helperText,
    this.errorText,
    this.enabled = true,
    this.onChanged,
    this.fieldKey,
    this.unitKey,
    this.suggestions,
  });

  final TextEditingController controller;
  final String unitSymbol;
  final ValueChanged<String> onUnitChanged;
  final String label;
  final String? helperText;
  final String? errorText;
  final bool enabled;
  final VoidCallback? onChanged;
  final Key? fieldKey;

  /// On the unit picker, for finding it in a test.
  final Key? unitKey;

  /// Sizes used before, already in [unitSymbol]. Given, the number is a
  /// searchable dropdown of them that also takes a new one; null keeps a
  /// plain field.
  final List<String>? suggestions;

  @override
  Widget build(BuildContext context) {
    final number = suggestions != null
        ? PickOrTypeField(
            fieldKey: fieldKey,
            controller: controller,
            label: label,
            options: suggestions!,
            enabled: enabled,
            errorText: errorText,
            searchKeyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
            onChanged: onChanged,
          )
        : TextField(
            key: fieldKey,
            controller: controller,
            enabled: enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => onChanged?.call(),
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              labelText: label,
              helperText: helperText,
              errorText: errorText,
              border: const OutlineInputBorder(),
            ),
          );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: suggestions != null && helperText != null && errorText == null
              // The dropdown has no helper line of its own.
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    number,
                    Padding(
                      padding: const EdgeInsets.only(left: 12, top: 4),
                      child: Text(
                        helperText!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: SoftErpTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                )
              : number,
        ),
        const SizedBox(width: 8),
        // The same searchable dropdown as every other pick on the sheet, so
        // "thou" is found by typing it rather than scrolling for it.
        SizedBox(
          width: 104,
          child: SearchableSelectField<String>(
            key: unitKey,
            value: unitSymbol,
            fieldEnabled: enabled,
            dialogTitle: 'Unit',
            searchHintText: 'Search units',
            options: [
              for (final unit in globalLengthUnits)
                SearchableSelectOption<String>(
                  value: unit.symbol,
                  label: unit.symbol,
                  subtitle: unit.name,
                  searchText: '${unit.name} ${unit.symbol}',
                ),
            ],
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (symbol) {
              if (symbol != null && symbol != unitSymbol) onUnitChanged(symbol);
            },
          ),
        ),
      ],
    );
  }
}

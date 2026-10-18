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

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
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
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: PopupMenuButton<String>(
            enabled: enabled,
            tooltip: 'Read this in another unit',
            initialValue: unitSymbol,
            onSelected: onUnitChanged,
            itemBuilder: (context) => [
              for (final unit in globalLengthUnits)
                PopupMenuItem<String>(
                  value: unit.symbol,
                  child: Text(
                    '${unit.name} (${unit.symbol})',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
                border: Border.all(color: SoftErpTheme.border),
                color: SoftErpTheme.sectionSurface,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    unitSymbol,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: SoftErpTheme.textPrimary,
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down_rounded, size: 18),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

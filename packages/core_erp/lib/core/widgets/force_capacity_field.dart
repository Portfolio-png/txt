/// What a machine can press, and whether it is rated at all.
///
/// Stored as an integer count of **kilograms-force**, which is what the units
/// contract asks for rather than an arbitrary choice: it forbids floats for a
/// quantity and wants an integer count of a base small enough that every unit
/// offered is a whole multiple of it. A press quoted at 35 Ton is 35,000 kgf
/// and a 1.5 Ton press is 1,500 — both exact.
///
/// "Free hand" is not a capacity of zero and not a blank: a bench with no
/// rated tonnage is a fact someone recorded, which is why the kind travels
/// beside the figure.
library;

import 'package:flutter/material.dart';

import '../theme/soft_erp_theme.dart';

/// Kilograms-force in one metric ton-force.
const int kgfPerTon = 1000;

/// What a machine's capacity says.
enum CapacityKind {
  /// Nobody has filled it in.
  unknown(''),

  /// [MachineCapacity.kgf] holds it.
  rated('rated'),

  /// The machine has no rated capacity at all.
  freeHand('free_hand');

  const CapacityKind(this.wire);

  /// What `machines.capacity_kind` holds.
  final String wire;

  static CapacityKind fromWire(String? value) {
    final raw = (value ?? '').trim();
    for (final kind in CapacityKind.values) {
      if (kind.wire == raw) return kind;
    }
    // An unknown kind reads as "nobody said" rather than throwing: a client one
    // version behind the server still has to open the machine.
    return CapacityKind.unknown;
  }
}

/// The units a capacity can be read in. Both are whole multiples of a
/// kilogram-force, so nothing the field accepts has to be rounded.
const Map<String, int> capacityUnitsKgf = <String, int>{'Ton': kgfPerTon, 'kgf': 1};

/// A typed number and a unit, in whole kilograms-force.
///
/// Null when the field is empty, which is a different answer from zero.
/// [CapacityParseResult.error] is set when the value cannot be expressed in
/// whole kilograms-force, which the contract says to refuse rather than round
/// away.
class CapacityParseResult {
  const CapacityParseResult.empty() : kgf = null, error = null;
  const CapacityParseResult.value(int this.kgf) : error = null;
  const CapacityParseResult.failed(String this.error) : kgf = null;

  final int? kgf;
  final String? error;

  bool get isFailure => error != null;
}

CapacityParseResult parseCapacityToKgf(String? raw, String unitSymbol) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return const CapacityParseResult.empty();
  final typed = double.tryParse(text);
  if (typed == null || typed.isNaN || typed.isInfinite || typed < 0) {
    return const CapacityParseResult.failed('Not a capacity');
  }
  final factor = capacityUnitsKgf[unitSymbol] ?? kgfPerTon;
  final exact = typed * factor;
  final rounded = exact.roundToDouble();
  // The slack is floating-point noise at a scale of thousands, not rounding of
  // what was typed: a value that genuinely falls between kilograms-force
  // misses by far more than this and is refused.
  if ((exact - rounded).abs() > 0.001) {
    return const CapacityParseResult.failed(
      'That is not a whole number of kgf — type it in kgf',
    );
  }
  return CapacityParseResult.value(rounded.toInt());
}

/// Kilograms-force back to a number in [unitSymbol], for putting in a field.
String formatCapacityFromKgf(int? kgf, String unitSymbol) {
  if (kgf == null) return '';
  final factor = capacityUnitsKgf[unitSymbol] ?? kgfPerTon;
  final value = kgf / factor;
  // Trailing zeros off: 35 and 35.00 are the same press.
  final text = value.toStringAsFixed(3);
  return text.contains('.')
      ? text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
      : text;
}

/// `35 Ton`, or what a free-hand machine says instead. Empty when nobody said.
String capacityLabel(CapacityKind kind, int? kgf, String unitSymbol) {
  switch (kind) {
    case CapacityKind.freeHand:
      return 'Free hand';
    case CapacityKind.rated:
      if (kgf == null) return '';
      return '${formatCapacityFromKgf(kgf, unitSymbol)} $unitSymbol';
    case CapacityKind.unknown:
      return '';
  }
}

/// The capacity: a number, its unit, and the free-hand answer beside them.
class ForceCapacityField extends StatelessWidget {
  const ForceCapacityField({
    super.key,
    required this.controller,
    required this.unitSymbol,
    required this.kind,
    required this.onUnitChanged,
    required this.onKindChanged,
    this.label = 'Capacity',
    this.errorText,
    this.enabled = true,
    this.onChanged,
    this.fieldKey,
    this.freeHandKey,
  });

  final TextEditingController controller;
  final String unitSymbol;
  final CapacityKind kind;
  final ValueChanged<String> onUnitChanged;
  final ValueChanged<CapacityKind> onKindChanged;
  final String label;
  final String? errorText;
  final bool enabled;
  final VoidCallback? onChanged;
  final Key? fieldKey;
  final Key? freeHandKey;

  @override
  Widget build(BuildContext context) {
    final freeHand = kind == CapacityKind.freeHand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: fieldKey,
                controller: controller,
                // Greyed rather than hidden while free hand is ticked: the
                // field is still the answer to the same question, and hiding
                // it would make the tick look like it had deleted something.
                enabled: enabled && !freeHand,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => onChanged?.call(),
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  labelText: label,
                  helperText: freeHand ? 'No rated capacity' : 'Optional',
                  errorText: errorText,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: PopupMenuButton<String>(
                enabled: enabled && !freeHand,
                tooltip: 'Read this in another unit',
                initialValue: unitSymbol,
                onSelected: onUnitChanged,
                itemBuilder: (context) => [
                  for (final symbol in capacityUnitsKgf.keys)
                    PopupMenuItem<String>(
                      value: symbol,
                      child: Text(symbol, style: const TextStyle(fontSize: 14)),
                    ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
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
        ),
        InkWell(
          key: freeHandKey,
          onTap: enabled
              ? () => onKindChanged(
                  freeHand ? CapacityKind.unknown : CapacityKind.freeHand,
                )
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: freeHand,
                  onChanged: enabled
                      ? (value) => onKindChanged(
                          value == true
                              ? CapacityKind.freeHand
                              : CapacityKind.unknown,
                        )
                      : null,
                ),
                const Text(
                  'Free hand — no rated capacity',
                  style: TextStyle(fontSize: 13.5),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

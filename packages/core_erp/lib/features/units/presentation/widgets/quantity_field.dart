import 'package:flutter/material.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/searchable_select.dart';
import '../../domain/quantity.dart';
import '../../domain/unit_family.dart';
import '../../domain/units.dart';

/// A count and the unit it is typed in — pieces, dozens, gross — with the
/// count spelt out down the ladder beneath it ("20 gro · 1 doz · 8 Pc").
///
/// The units contract's field (.claude/skills/units/SKILL.md): the stored
/// value is whole base units, typed text goes through [Units.parse] (which
/// refuses a fraction of a piece rather than rounding it), and every display
/// goes through the units module. Switching the unit re-renders the same
/// stored count; it never changes it.
///
/// With no [family] (the Count family not seeded yet) it takes whole pieces
/// with no unit picker and no breakdown, rather than refusing to work.
class QuantityField extends StatefulWidget {
  const QuantityField({
    super.key,
    required this.family,
    required this.baseValue,
    required this.onChanged,
    this.unitId,
    this.label = 'Qty',
    this.enabled = true,
    this.fieldKey,
    this.unitKey,
    this.dense = false,
  });

  /// The family offered (Count). Null falls back to whole pieces.
  final UnitFamily? family;

  /// The stored count in base units, or null for none.
  final int? baseValue;

  /// The unit it was last typed in; null means the family's base.
  final int? unitId;

  /// The new count (null when cleared) and the unit it was typed in.
  final void Function(int? base, int? unitId) onChanged;

  final String label;
  final bool enabled;
  final Key? fieldKey;
  final Key? unitKey;

  /// Tight, for a table cell.
  final bool dense;

  @override
  State<QuantityField> createState() => _QuantityFieldState();
}

class _QuantityFieldState extends State<QuantityField> {
  late final TextEditingController _text = TextEditingController();
  String? _error;

  /// What the field last wrote itself. A rebuild that would write the same
  /// leaves the cursor alone; only a change from outside re-renders.
  String _rendered = '';

  Unit? get _unit {
    final family = widget.family;
    if (family == null) return null;
    return family.units.where((u) => u.id == widget.unitId).firstOrNull ??
        family.base;
  }

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void didUpdateWidget(covariant QuantityField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedFromOutside =
        widget.unitId != oldWidget.unitId ||
        widget.family != oldWidget.family ||
        (widget.baseValue != oldWidget.baseValue && _text.text == _rendered);
    if (changedFromOutside) _render();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// The stored count in the chosen unit, exactly when it divides, else to
  /// the unit's decimals — display only; it is never parsed back.
  void _render() {
    final base = widget.baseValue;
    final unit = _unit;
    final family = widget.family;
    String text;
    if (base == null) {
      text = '';
    } else if (unit == null || family == null) {
      text = '$base';
    } else {
      final parts = Units.inUnit(Quantity(base, family), unit);
      text = parts.remainder == 0
          ? '${parts.whole}'
          : Units.format(
              Quantity(base, family),
              display: QtyDisplay.pinned(unit),
            ).replaceAll(' ${unit.symbol}', '').trim();
    }
    _rendered = text;
    if (_text.text != text) _text.text = text;
    _error = null;
  }

  void _typed(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      setState(() => _error = null);
      widget.onChanged(null, widget.unitId);
      return;
    }
    final unit = _unit;
    final family = widget.family;
    if (unit == null || family == null) {
      final whole = int.tryParse(text.replaceAll(',', ''));
      setState(() => _error = whole == null ? 'A whole number of pieces' : null);
      if (whole != null) widget.onChanged(whole, null);
      return;
    }
    try {
      final q = Units.parse(text, unit, family);
      setState(() => _error = null);
      widget.onChanged(q.base, unit.id);
    } on UnitParseError catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final family = widget.family;
    final unit = _unit;
    final base = widget.baseValue;
    final breakdown = family != null && base != null && base.abs() >= 12
        ? Units.formatBreakdown(Quantity(base, family))
        : null;

    final number = TextField(
      key: widget.fieldKey,
      controller: _text,
      enabled: widget.enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: _typed,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: widget.dense ? null : widget.label,
        hintText: '0',
        errorText: _error,
        isDense: true,
        suffixText: family == null ? 'pcs' : null,
        border: const OutlineInputBorder(),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: number),
            if (family != null && unit != null) ...[
              const SizedBox(width: 6),
              SizedBox(
                width: 92,
                child: SearchableSelectField<int>(
                  key: widget.unitKey,
                  value: unit.id,
                  fieldEnabled: widget.enabled,
                  dialogTitle: 'Unit',
                  searchHintText: 'Search units',
                  options: [
                    for (final u in family.units)
                      SearchableSelectOption<int>(
                        value: u.id,
                        label: u.symbol,
                        subtitle: u.label,
                        searchText: '${u.label} ${u.symbol}',
                      ),
                  ],
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (id) {
                    if (id == null) return;
                    widget.onChanged(widget.baseValue, id);
                  },
                ),
              ),
            ],
          ],
        ),
        if (breakdown != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 2),
            child: Text(
              '= $breakdown',
              key: widget.fieldKey == null
                  ? null
                  : ValueKey('${widget.fieldKey}_breakdown'),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: SoftErpTheme.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}

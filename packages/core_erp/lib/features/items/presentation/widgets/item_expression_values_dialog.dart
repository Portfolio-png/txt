import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/erp_form_dialog.dart';
import '../../domain/item_expression.dart';
import 'item_expression_view.dart';

/// Collects the values for properties the expression declared but did not fill.
///
/// `Sheet + number + material` says what the properties *are* without saying
/// what they hold, and neither of those two can be typed as free text — a
/// number is a number, and a material has to come from the material master. So
/// the line is confirmed first, and the blanks are asked for after.
///
/// The material list is passed in rather than read from a provider, so the
/// dialog stays testable and a caller without a material master degrades to a
/// plain field instead of failing.
class ItemExpressionValuesDialog extends StatefulWidget {
  const ItemExpressionValuesDialog({
    super.key,
    required this.plan,
    this.materialNames = const <String>[],
  });

  final ItemExpressionPlan plan;
  final List<String> materialNames;

  /// Resolves to the collected values keyed by segment index, or null if the
  /// user backed out — in which case nothing should be written.
  static Future<Map<int, String>?> open(
    BuildContext context, {
    required ItemExpressionPlan plan,
    List<String> materialNames = const <String>[],
  }) {
    return showErpFormDialog<Map<int, String>>(
      context,
      maxWidth: 620,
      maxHeight: 620,
      child: ItemExpressionValuesDialog(
        plan: plan,
        materialNames: materialNames,
      ),
    );
  }

  @override
  State<ItemExpressionValuesDialog> createState() =>
      _ItemExpressionValuesDialogState();
}

class _ItemExpressionValuesDialogState
    extends State<ItemExpressionValuesDialog> {
  final Map<int, String> _values = <int, String>{};
  final Map<int, TextEditingController> _controllers =
      <int, TextEditingController>{};

  late final List<MapEntry<int, ItemExpressionSegment>> _pending =
      ItemExpression.pendingValues(widget.plan);

  @override
  void initState() {
    super.initState();
    // One per pending value, whatever its type: a Material or Gauge field
    // falls back to typing when there is nothing to pick from, and creating
    // that controller lazily inside build would be making state during a
    // build.
    for (final entry in _pending) {
      final controller = TextEditingController();
      controller.addListener(
        () => setState(() => _values[entry.key] = controller.text),
      );
      _controllers[entry.key] = controller;
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Every declared property has to be answered — a property with no value is
  /// the half-made state this whole flow exists to avoid.
  bool get _isComplete => _pending.every(
    (entry) => (_values[entry.key] ?? '').trim().isNotEmpty,
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _pending.length == 1
                    ? 'One value to fill in'
                    : '${_pending.length} values to fill in',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: SoftErpTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'The line said what these properties are. It could not say what '
                'they hold.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: SoftErpTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              // The line stays on screen: these fields only make sense as part
              // of the expression they came from.
              ItemExpressionView(plan: widget.plan, dense: true),
            ],
          ),
        ),
        const Divider(height: 1, color: SoftErpTheme.border),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
            itemCount: _pending.length,
            separatorBuilder: (_, _) => const SizedBox(height: 16),
            itemBuilder: (context, index) => _fieldFor(_pending[index]),
          ),
        ),
        const Divider(height: 1, color: SoftErpTheme.border),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Spacer(),
              AppButton(
                label: 'Back',
                variant: AppButtonVariant.secondary,
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 12),
              AppButton(
                label: 'Confirm values',
                icon: Icons.check,
                onPressed: _isComplete
                    ? () => Navigator.of(context).pop(Map<int, String>.from(_values))
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _fieldFor(MapEntry<int, ItemExpressionSegment> entry) {
    final segment = entry.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              segment.propertyName,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: SoftErpTheme.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: SoftErpTheme.accentSoft,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                segment.inputType,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: SoftErpTheme.accentDeeper,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        switch (segment.inputType) {
          'Material' => _picker(
            key: 'material-${entry.key}',
            hint: widget.materialNames.isEmpty
                ? 'No material master available — type one'
                : 'Pick a material',
            options: widget.materialNames,
            index: entry.key,
          ),
          'Gauge' => _picker(
            key: 'gauge-${entry.key}',
            hint: 'Pick an SWG',
            options: ItemExpression.swgValues,
            index: entry.key,
            optionLabel: (value) => 'SWG $value',
          ),
          'Numeric' => _text(
            index: entry.key,
            hint: 'A number',
            numeric: true,
          ),
          _ => _text(index: entry.key, hint: 'A value'),
        },
      ],
    );
  }

  Widget _text({
    required int index,
    required String hint,
    bool numeric = false,
  }) {
    return TextField(
      controller: _controllers[index],
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      inputFormatters: numeric
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
          : null,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        filled: true,
        fillColor: SoftErpTheme.sectionSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _picker({
    required String key,
    required String hint,
    required List<String> options,
    required int index,
    String Function(String value)? optionLabel,
  }) {
    // Nothing to pick from is still an answerable question — fall back to
    // typing rather than blocking the whole line.
    if (options.isEmpty) {
      return _text(index: index, hint: hint);
    }

    return Container(
      key: ValueKey<String>(key),
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: SoftErpTheme.sectionSurface,
        borderRadius: BorderRadius.circular(11),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _values[index],
          hint: Text(
            hint,
            style: const TextStyle(
              fontSize: 13,
              color: SoftErpTheme.textSecondary,
            ),
          ),
          isExpanded: true,
          icon: const Icon(Icons.expand_more, size: 18),
          onChanged: (value) {
            if (value != null) setState(() => _values[index] = value);
          },
          items: [
            for (final option in options)
              DropdownMenuItem<String>(
                value: option,
                child: Text(
                  optionLabel?.call(option) ?? option,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/utils/quantity_shorthand.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/erp_form_dialog.dart';
import '../../../../widgets/variation_path_selector_dialog.dart';
import '../../../inventory/domain/inventory_set_definition.dart';
import '../../../items/domain/item_definition.dart';

/// What the user chose in the "order a set" dialog: which set, and how many of
/// it. Every member line is multiplied by [multiplier].
class SetOrderChoice {
  const SetOrderChoice({required this.set, required this.multiplier});

  final InventorySetDefinition set;
  final int multiplier;
}

/// Picks a set and how many of it to order.
///
/// A set is a kit — a fixed list of item/variation lines with per-line
/// quantities — so ordering "3 of Starter Kit" means every line times three.
class SetOrderPickerDialog extends StatefulWidget {
  const SetOrderPickerDialog({super.key, required this.sets});

  final List<InventorySetDefinition> sets;

  @override
  State<SetOrderPickerDialog> createState() => _SetOrderPickerDialogState();
}

class _SetOrderPickerDialogState extends State<SetOrderPickerDialog> {
  final TextEditingController _search = TextEditingController();
  final TextEditingController _multiplier = TextEditingController(text: '1');
  int? _selectedSetId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _multiplier.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    _multiplier.dispose();
    super.dispose();
  }

  List<InventorySetDefinition> get _visible {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return widget.sets;
    return widget.sets
        .where((set) => set.name.toLowerCase().contains(query))
        .toList(growable: false);
  }

  void _submit() {
    final set = widget.sets
        .where((candidate) => candidate.id == _selectedSetId)
        .firstOrNull;
    if (set == null) {
      setState(() => _error = 'Pick a set to order.');
      return;
    }
    final parsed = parseQuantityShorthand(_multiplier.text);
    if (parsed == null || parsed <= 0 || parsed != parsed.roundToDouble()) {
      setState(() => _error = 'Enter how many sets, as a whole number.');
      return;
    }
    if (set.lines.isEmpty) {
      setState(() => _error = 'That set has no lines to order.');
      return;
    }
    Navigator.of(
      context,
    ).pop(SetOrderChoice(set: set, multiplier: parsed.round()));
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final selected = widget.sets
        .where((candidate) => candidate.id == _selectedSetId)
        .firstOrNull;
    final multiplier = parseQuantityShorthand(_multiplier.text)?.round() ?? 0;

    return ErpFormScaffold(
      title: 'Order a set',
      subtitle:
          'Every line in the set is added to the order, multiplied by how '
          'many sets you order.',
      errorBanner: _error == null
          ? null
          : ErpFormMessageBanner(message: _error!),
      bodyScrollable: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Search sets',
              isDense: true,
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              filled: true,
              fillColor: SoftErpTheme.cardSurfaceAlt,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: SoftErpTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: SoftErpTheme.border),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: visible.isEmpty
                ? const Center(
                    child: Text(
                      'No sets match.',
                      style: TextStyle(color: SoftErpTheme.textSecondary),
                    ),
                  )
                : ListView.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final set = visible[index];
                      final isSelected = set.id == _selectedSetId;
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => setState(() {
                            _error = null;
                            _selectedSetId = set.id;
                          }),
                          borderRadius: BorderRadius.circular(
                            SoftErpTheme.radiusSm,
                          ),
                          child: Ink(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? SoftErpTheme.accentSoft
                                  : SoftErpTheme.cardSurface,
                              borderRadius: BorderRadius.circular(
                                SoftErpTheme.radiusSm,
                              ),
                              border: Border.all(
                                color: isSelected
                                    ? SoftErpTheme.accent
                                    : SoftErpTheme.border,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected
                                      ? Icons.check_circle_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  size: 17,
                                  color: isSelected
                                      ? SoftErpTheme.accent
                                      : SoftErpTheme.textSecondary,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    set.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isSelected
                                          ? SoftErpTheme.accentDeeper
                                          : SoftErpTheme.textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${set.lines.length} line'
                                  '${set.lines.length == 1 ? '' : 's'} · '
                                  '${set.totalItemCount} units',
                                  style: const TextStyle(
                                    color: SoftErpTheme.textSecondary,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _multiplier,
                  keyboardType: TextInputType.text,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'[0-9.,kKlLcCrR ]'),
                    ),
                  ],
                  decoration: InputDecoration(
                    labelText: 'How many sets',
                    isDense: true,
                    filled: true,
                    fillColor: SoftErpTheme.cardSurfaceAlt,
                    helperText: multiplier <= 0
                        ? null
                        : formatIndianNumber(multiplier),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: SoftErpTheme.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: SoftErpTheme.border),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              if (selected != null && multiplier > 0)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Adds ${selected.lines.length} order line'
                      '${selected.lines.length == 1 ? '' : 's'}, '
                      '${formatIndianNumber(selected.totalItemCount * multiplier)} '
                      'units in total.',
                      style: const TextStyle(
                        color: SoftErpTheme.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 12),
          AppButton(label: 'Add to order', onPressed: _submit),
        ],
      ),
    );
  }
}

/// One set member that still needs its variation properties supplied before it
/// can become an order line.
class SetLinePropertyRequest {
  SetLinePropertyRequest({
    required this.line,
    required this.item,
    required this.quantity,
  });

  final InventorySetLineDefinition line;
  final ItemDefinition item;
  final int quantity;

  /// Filled in by the dialog.
  VariationPathSelectionResult? result;

  bool get isResolved => result != null;
}

/// Collects the variation properties for the members of a set that cannot be
/// ordered as-is.
///
/// A set line pins a variation *leaf*, but Numeric and Gauge properties carry
/// no value nodes — they are typed per order — so a set containing a
/// hierarchical item still has to be asked about at order time. The user works
/// down the list; nothing is added to the order until every row is answered.
class SetLinePropertiesDialog extends StatefulWidget {
  const SetLinePropertiesDialog({
    super.key,
    required this.setName,
    required this.requests,
  });

  final String setName;
  final List<SetLinePropertyRequest> requests;

  @override
  State<SetLinePropertiesDialog> createState() =>
      _SetLinePropertiesDialogState();
}

class _SetLinePropertiesDialogState extends State<SetLinePropertiesDialog> {
  String? _error;

  bool get _allResolved =>
      widget.requests.every((request) => request.isResolved);

  Future<void> _resolve(SetLinePropertyRequest request) async {
    final result = await showDialog<VariationPathSelectionResult>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
          child: VariationPathSelectorDialog(
            item: request.item,
            initialRootPropertyId: null,
            initialValueNodeIds: request.result?.valueNodeIds ?? const <int>[],
            initialCustomVariationValues:
                request.result?.customVariationValues ?? const {},
            // Ordering is data entry: it must not write new values back into
            // the item master.
            allowCustomValues: false,
          ),
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      request.result = result;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pending = widget.requests.where((r) => !r.isResolved).length;
    return ErpFormScaffold(
      title: 'Properties for ${widget.setName}',
      subtitle:
          'These members are ordered by property rather than a fixed variation, '
          'so each one needs its values before the order lines can be created.',
      errorBanner: _error == null
          ? null
          : ErpFormMessageBanner(message: _error!),
      bodyScrollable: false,
      body: ListView.separated(
        itemCount: widget.requests.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final request = widget.requests[index];
          final resolved = request.isResolved;
          return Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              color: resolved
                  ? SoftErpTheme.successBg
                  : SoftErpTheme.cardSurface,
              borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
              border: Border.all(
                color: resolved
                    ? SoftErpTheme.successText.withValues(alpha: 0.3)
                    : SoftErpTheme.border,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  resolved
                      ? Icons.check_circle_rounded
                      : Icons.error_outline_rounded,
                  size: 18,
                  color: resolved
                      ? SoftErpTheme.successText
                      : SoftErpTheme.warningText,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.item.displayName.trim().isEmpty
                            ? request.item.name
                            : request.item.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SoftErpTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        resolved
                            ? request.result!.summaryLabel
                            : 'Properties not set',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: resolved
                              ? SoftErpTheme.successText
                              : SoftErpTheme.textSecondary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '×${request.quantity}',
                  style: const TextStyle(
                    color: SoftErpTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 10),
                AppButton(
                  label: resolved ? 'Change' : 'Set properties',
                  variant: AppButtonVariant.secondary,
                  onPressed: () => _resolve(request),
                ),
              ],
            ),
          );
        },
      ),
      footer: Row(
        children: [
          Expanded(
            child: Text(
              pending == 0
                  ? 'All members ready.'
                  : '$pending member${pending == 1 ? '' : 's'} still need '
                        'properties.',
              style: TextStyle(
                color: pending == 0
                    ? SoftErpTheme.successText
                    : SoftErpTheme.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          const SizedBox(width: 12),
          AppButton(
            label: 'Add to order',
            onPressed: _allResolved
                ? () => Navigator.of(context).pop(true)
                : null,
          ),
        ],
      ),
    );
  }
}

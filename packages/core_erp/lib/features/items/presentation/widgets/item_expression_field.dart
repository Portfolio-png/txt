import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../domain/item_definition.dart';
import '../../domain/item_expression.dart';
import '../../domain/item_expression_executor.dart';
import '../providers/items_provider.dart';
import 'item_expression_values_dialog.dart';
import 'item_expression_view.dart';

/// Turns an [ItemsProvider] into the two writes the executor needs.
class ItemsProviderExpressionSink implements ItemExpressionSink {
  ItemsProviderExpressionSink(this._provider);

  final ItemsProvider _provider;

  @override
  String? get lastError => _provider.errorMessage;

  @override
  Future<int?> findProperty({
    required int itemId,
    required String name,
  }) async {
    final needle = name.trim().toLowerCase();
    final item = _provider.items
        .where((candidate) => candidate.id == itemId)
        .firstOrNull;
    if (item == null) return null;
    for (final property in item.topLevelProperties) {
      if (property.name.trim().toLowerCase() == needle) return property.id;
    }
    return null;
  }

  @override
  bool isDataEntry(String inputType) =>
      ItemsProvider.isDataEntryInputType(inputType);

  @override
  Future<int?> appendPropertyWithValue({
    required int itemId,
    required String name,
    required String inputType,
    required String value,
  }) async {
    final result = await _provider.appendTopLevelPropertyWithValue(
      itemId: itemId,
      propertyName: name,
      inputType: inputType,
      valueName: value,
    );
    return result?.createdPropertyNode.id;
  }

  @override
  Future<bool> appendValue({
    required int itemId,
    required int propertyNodeId,
    required String value,
  }) async {
    final result = await _provider.appendVariationValue(
      itemId: itemId,
      propertyNodeId: propertyNodeId,
      valueName: value,
    );
    return result != null;
  }
}

/// Reads the item master as the expression grammar needs to see it: items,
/// their top-level properties, and the values each property already holds.
List<ExpressionItem> expressionCatalogFrom(List<ItemDefinition> items) {
  return [
    for (final item in items)
      if (!item.isArchived)
        ExpressionItem(
          id: item.id,
          name: item.displayName.trim().isEmpty
              ? item.name
              : item.displayName,
          properties: [
            for (final property in item.topLevelProperties)
              ExpressionProperty(
                id: property.id,
                name: property.name,
                inputType: property.inputType,
                values: [
                  for (final child in property.children)
                    if (child.kind == ItemVariationNodeKind.value &&
                        !child.isArchived)
                      ExpressionValue(id: child.id, name: child.name),
                ],
              ),
          ],
        ),
  ];
}

/// One line instead of three screens, droppable anywhere an item is picked.
///
/// Deliberately has **no text field of its own**. It is meant to sit inside a
/// picker that already has a search box, and a second box below the first is
/// both redundant and a bug waiting to happen — the two copies drift, and the
/// panel starts describing text the user is no longer looking at.
///
/// So the text is passed in and completions are written back out. Everything
/// shown is derived from the item master as it stands: what it suggests, what
/// it reports as already-there, and what it will actually write.
class ItemExpressionField extends StatefulWidget {
  const ItemExpressionField({
    super.key,
    required this.text,
    required this.onTextChanged,
    this.onApplied,
    this.materialNames = const <String>[],
  });

  /// The line as it currently reads, owned by whoever hosts this.
  final String text;
  final ValueChanged<String> onTextChanged;

  /// Called after a successful apply, with the item the line landed on.
  final void Function(int itemId)? onApplied;
  final List<String> materialNames;

  @override
  State<ItemExpressionField> createState() => _ItemExpressionFieldState();
}

class _ItemExpressionFieldState extends State<ItemExpressionField> {
  ItemExpressionOutcome? _outcome;
  bool _busy = false;

  @override
  void didUpdateWidget(ItemExpressionField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A changed line means the last result is about something else now.
    if (oldWidget.text != widget.text) _outcome = null;
  }

  void _accept(ExpressionSuggestion suggestion) {
    widget.onTextChanged(
      ItemExpression.applySuggestion(widget.text, suggestion.insertText),
    );
  }

  Future<void> _apply(ItemExpressionPlan plan) async {
    final provider = context.read<ItemsProvider>();
    var effective = plan;

    // A declared property still owes a value, and it cannot be typed inline —
    // a number is a number and a material comes from the master.
    final pending = ItemExpression.pendingValues(plan);
    if (pending.isNotEmpty) {
      final values = await ItemExpressionValuesDialog.open(
        context,
        plan: plan,
        materialNames: widget.materialNames,
      );
      if (values == null || !mounted) return;
      effective = ItemExpression.applyCollectedValues(plan, values);
    }

    setState(() => _busy = true);
    final outcome = await ItemExpressionExecutor.apply(
      effective,
      ItemsProviderExpressionSink(provider),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _outcome = outcome;
    });
    if (outcome.isClean && effective.itemId != null) {
      widget.onApplied?.call(effective.itemId!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = context.watch<ItemsProvider>().items;
    final catalog = expressionCatalogFrom(items);
    final plan = ItemExpression.parseWithCatalog(widget.text, catalog);
    final suggestions = ItemExpression.suggest(widget.text, catalog);
    final progress = ItemExpression.propertyProgress(widget.text, catalog);
    final nextProperty = ItemExpression.propertyForNextSegment(
      widget.text,
      catalog,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // First, not last: a refusal that renders under a scrolled-off button
        // reads as "nothing happened".
        if (_outcome != null) ...[
          _OutcomeBanner(outcome: _outcome!),
          const SizedBox(height: 10),
        ],
        if (progress != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Property ${progress.$1} of ${progress.$2}'
              ' · ${nextProperty?.name ?? ''}',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: SoftErpTheme.textPrimary,
              ),
            ),
          ),
        if (suggestions.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 150),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: SoftErpTheme.border),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: suggestions.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: SoftErpTheme.border),
                itemBuilder: (context, index) => _SuggestionTile(
                  suggestion: suggestions[index],
                  onTap: () => _accept(suggestions[index]),
                ),
              ),
            ),
          ),
        if (!plan.isEmpty) ...[
          const SizedBox(height: 10),
          ItemExpressionView(plan: plan, dense: true),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _busy || plan.itemId == null || plan.writeCount == 0
                  ? null
                  : () => _apply(plan),
              icon: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check, size: 16),
              label: Text(
                plan.itemId == null
                    ? 'Pick an existing item to add to'
                    : plan.writeCount == 0
                    ? 'Nothing new to add'
                    : 'Add ${plan.writeCount} to ${plan.headText}',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: SoftErpTheme.accent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({required this.suggestion, required this.onTap});

  final ExpressionSuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color colour) = switch (suggestion.kind) {
      SuggestionKind.item => (
        Icons.inventory_2_outlined,
        SoftErpTheme.entityItem,
      ),
      SuggestionKind.existingValue => (
        Icons.check_circle_outline,
        SoftErpTheme.successText,
      ),
      SuggestionKind.newValue => (
        Icons.add_circle_outline,
        SoftErpTheme.warningText,
      ),
      SuggestionKind.inputType => (
        Icons.category_outlined,
        SoftErpTheme.accentDeeper,
      ),
    };

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 14, color: colour),
            const SizedBox(width: 9),
            Text(
              suggestion.label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: SoftErpTheme.textPrimary,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                suggestion.detail,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: SoftErpTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutcomeBanner extends StatelessWidget {
  const _OutcomeBanner({required this.outcome});

  final ItemExpressionOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final failed = !outcome.isClean;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: failed ? SoftErpTheme.dangerBg : SoftErpTheme.successBg,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            outcome.summary,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: failed
                  ? SoftErpTheme.dangerText
                  : SoftErpTheme.successText,
            ),
          ),
          for (final failure in outcome.failures)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                failure,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: SoftErpTheme.dangerText,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

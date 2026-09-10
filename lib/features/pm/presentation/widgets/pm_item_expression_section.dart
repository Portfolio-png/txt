import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/core/widgets/app_card.dart';
import 'package:core_erp/core/widgets/app_section_title.dart';
import 'package:core_erp/features/items/domain/item_expression.dart';
import 'package:core_erp/features/items/presentation/widgets/item_expression_values_dialog.dart';
import 'package:core_erp/features/items/presentation/widgets/item_expression_view.dart';
import 'package:flutter/material.dart';

/// Live bench for the `+` entry grammar.
///
/// The grammar's whole risk is that it reads a line differently from how the
/// person typing it meant it. So this is a place to type and watch it parse
/// against a stand-in item, before it is wired to anything that writes.
class PMItemExpressionSection extends StatefulWidget {
  const PMItemExpressionSection({super.key});

  @override
  State<PMItemExpressionSection> createState() =>
      _PMItemExpressionSectionState();
}

class _PMItemExpressionSectionState extends State<PMItemExpressionSection> {
  final _controller = TextEditingController(text: 'Bulb + Red + 60 + Brass');

  /// Stands in for the item master until this is wired to one. Values matter
  /// as much as properties here: reuse can only be shown against values that
  /// already exist.
  static const _catalog = <ExpressionItem>[
    ExpressionItem(
      id: 5,
      name: 'Bulb',
      properties: [
        ExpressionProperty(
          id: 11,
          name: 'Colour',
          values: [
            ExpressionValue(id: 101, name: 'Red'),
            ExpressionValue(id: 102, name: 'Warm White'),
            ExpressionValue(id: 103, name: 'Blue'),
          ],
        ),
        ExpressionProperty(
          id: 12,
          name: 'Wattage',
          inputType: 'Numeric',
          values: [
            ExpressionValue(id: 111, name: '9'),
            ExpressionValue(id: 112, name: '12'),
          ],
        ),
      ],
    ),
    ExpressionItem(
      id: 6,
      name: 'Cone',
      properties: [
        ExpressionProperty(
          id: 21,
          name: 'Size',
          inputType: 'Numeric',
          values: [ExpressionValue(id: 201, name: '90')],
        ),
      ],
    ),
    ExpressionItem(id: 7, name: 'Ferrule'),
  ];

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  ItemExpressionPlan? _completed;

  /// Stands in for the material master until this is wired to one.
  static const _materials = <String>[
    'Brass',
    'Aluminium',
    'Mild Steel',
    'Copper',
  ];

  void _accept(ExpressionSuggestion suggestion) {
    final next = ItemExpression.applySuggestion(
      _controller.text,
      suggestion.insertText,
    );
    _controller.text = next;
    _controller.selection = TextSelection.collapsed(offset: next.length);
  }

  Future<void> _confirm(ItemExpressionPlan plan) async {
    setState(() => _completed = null);
    final pending = ItemExpression.pendingValues(plan);
    if (pending.isEmpty) {
      setState(() => _completed = plan);
      return;
    }
    final values = await ItemExpressionValuesDialog.open(
      context,
      plan: plan,
      materialNames: _materials,
    );
    if (values == null || !mounted) return;
    setState(
      () => _completed = ItemExpression.applyCollectedValues(plan, values),
    );
  }


  @override
  Widget build(BuildContext context) {
    final plan = ItemExpression.parseWithCatalog(_controller.text, _catalog);
    final suggestions = ItemExpression.suggest(_controller.text, _catalog);
    final progress = ItemExpression.propertyProgress(
      _controller.text,
      _catalog,
    );
    final nextProperty = ItemExpression.propertyForNextSegment(
      _controller.text,
      _catalog,
    );

    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionTitle(
            title: 'Item expression (+)',
            subtitle:
                'One line instead of three screens. The first segment is the '
                'item; each + adds a value. Values fill the properties the item '
                'already has, then start inventing them.',
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _controller,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            decoration: InputDecoration(
              labelText: 'Expression',
              hintText: 'Bulb + Red + 60 + Brass',
              filled: true,
              fillColor: SoftErpTheme.sectionSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // What the caret can accept right now. Before the first + these are
          // items; after it they are the values the property at that position
          // already holds, so picking one reuses it instead of minting a
          // near-duplicate.
          if (nextProperty != null || progress != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.subdirectory_arrow_right,
                    size: 15,
                    color: SoftErpTheme.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    progress == null
                        ? 'Next value'
                        : 'Property ${progress.$1} of ${progress.$2}'
                              ' · ${nextProperty?.name ?? ''}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: SoftErpTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          if (suggestions.isEmpty)
            const Text(
              'No matches — what you type becomes a new value.',
              style: TextStyle(
                fontSize: 11.5,
                fontStyle: FontStyle.italic,
                color: SoftErpTheme.textSecondary,
              ),
            )
          else
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 190),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: SoftErpTheme.border),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: suggestions.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: SoftErpTheme.border),
                itemBuilder: (context, index) =>
                    _SuggestionRow(
                      suggestion: suggestions[index],
                      onTap: () => _accept(suggestions[index]),
                    ),
              ),
            ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFBFAFF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: SoftErpTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'HOW IT READS',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: SoftErpTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                ItemExpressionView(plan: plan),
                if (plan.warnings.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  for (final warning in plan.warnings)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 13,
                          color: SoftErpTheme.warningText,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            warning,
                            style: const TextStyle(
                              fontSize: 12,
                              color: SoftErpTheme.warningText,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
                const SizedBox(height: 14),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: plan.headText.isEmpty
                        ? null
                        : () => _confirm(plan),
                    icon: const Icon(Icons.check, size: 17),
                    label: Text(
                      ItemExpression.pendingValues(plan).isEmpty
                          ? 'Confirm item'
                          : 'Confirm item · '
                                '${ItemExpression.pendingValues(plan).length} '
                                'to fill in',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: SoftErpTheme.accent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                      ),
                    ),
                  ),
                ),
                if (_completed != null) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'READY TO WRITE',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: SoftErpTheme.successText,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ItemExpressionView(plan: _completed!),
                ],
                const SizedBox(height: 14),
                Text(
                  plan.writeCount == 0
                      ? '${plan.existingValueCount} reused · nothing new to '
                            'create'
                      : '${plan.existingValueCount} reused · '
                            '${plan.boundValueCount} new value'
                            '${plan.boundValueCount == 1 ? '' : 's'} · '
                            '${plan.newPropertyCount} new '
                            'propert${plan.newPropertyCount == 1 ? 'y' : 'ies'}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: SoftErpTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({required this.suggestion, required this.onTap});

  final ExpressionSuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color colour) = switch (suggestion.kind) {
      SuggestionKind.item => (Icons.inventory_2_outlined, SoftErpTheme.entityItem),
      SuggestionKind.existingValue => (Icons.check_circle_outline, SoftErpTheme.successText),
      SuggestionKind.newValue => (Icons.add_circle_outline, SoftErpTheme.warningText),
      SuggestionKind.inputType => (Icons.category_outlined, SoftErpTheme.accentDeeper),
    };

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            Icon(icon, size: 15, color: colour),
            const SizedBox(width: 10),
            Text(
              suggestion.label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: SoftErpTheme.textPrimary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                suggestion.detail,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
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

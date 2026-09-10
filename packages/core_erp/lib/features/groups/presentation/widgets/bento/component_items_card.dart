import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../core/theme/soft_erp_theme.dart';
import '../../../../../core/app_flow_hooks.dart';
import '../../../../items/presentation/widgets/item_expression_field.dart';
import '../../../domain/group_definition.dart';
import '../../../../items/domain/item_definition.dart';
import '../../../../items/domain/item_expression.dart';
import '../../../../items/presentation/providers/items_provider.dart';
import '../../../../items/presentation/screens/items_screen.dart';

class ComponentItemsCard extends StatefulWidget {
  const ComponentItemsCard({
    super.key,
    required this.component,
    required this.selectedItemId,
    required this.onSelect,
    required this.onSave,
  });

  final GroupDefinition component;
  final int? selectedItemId;
  final ValueChanged<int?> onSelect;
  final VoidCallback onSave;

  @override
  State<ComponentItemsCard> createState() => _ComponentItemsCardState();
}

class _ComponentItemsCardState extends State<ComponentItemsCard> {
  final TextEditingController _itemQuery = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _itemQuery.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _itemQuery.dispose();
    super.dispose();
  }

  List<ItemDefinition> get _members => context
      .watch<ItemsProvider>()
      .items
      .where((item) => item.groupId == widget.component.id && !item.isArchived)
      .toList(growable: false);

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addExistingItem(int itemId) async {
    final provider = context.read<ItemsProvider>();
    await _run(() async {
      final moved = await provider.reassignItemGroup(itemId, widget.component.id);
      if (!mounted) return;
      if (moved == null) {
        final reason = provider.errorMessage ?? 'Could not add that item.';
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(reason)));
        return;
      }
      widget.onSelect(itemId);
      _itemQuery.clear();
    });
  }

  Future<void> _createItem({String initialName = ''}) async {
    final created = await ItemsScreen.openWorkflow(
      context,
      initialName: initialName,
      initialGroupId: widget.component.id,
      onCreatePipeline: AppFlowHooks.createPipelineFor(context),
    );
    if (created == null || !mounted) return;
    widget.onSelect(created.id);
    _itemQuery.clear();
  }

  @override
  Widget build(BuildContext context) {
    final members = _members;
    final query = _itemQuery.text.trim();
    final lower = query.toLowerCase();
    
    final candidates = context
        .watch<ItemsProvider>()
        .items
        .where((item) => item.groupId != widget.component.id && !item.isArchived)
        .where((item) => lower.isNotEmpty && '${item.name} ${item.alias} ${item.displayName}'.toLowerCase().contains(lower))
        .take(6)
        .toList(growable: false);

    final exactExists = context.watch<ItemsProvider>().items.any(
      (item) => item.displayName.trim().toLowerCase() == lower,
    );
    final isExpression = query.contains(ItemExpression.separator);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final item in members) ...[
          _ItemSelectableCard(
            item: item,
            selected: item.id == widget.selectedItemId,
            onTap: () => widget.onSelect(item.id),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        TextField(
          controller: _itemQuery,
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search, size: 17),
            prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            hintText: 'Search items, or type a new name',
            hintStyle: const TextStyle(fontSize: 12),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
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
        const SizedBox(height: 8),
        if (isExpression)
          ItemExpressionField(
            text: _itemQuery.text,
            onTextChanged: (next) => _itemQuery.text = next,
          )
        else ...[
          for (final item in candidates) ...[
            InkWell(
              onTap: () => _addExistingItem(item.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined, size: 16, color: SoftErpTheme.textSecondary),
                    const SizedBox(width: 8),
                    Text(item.displayName.trim().isEmpty ? item.name : item.displayName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ],
          if (query.isNotEmpty && !exactExists)
            InkWell(
              onTap: () => _createItem(initialName: query),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.add_circle_outline, size: 16, color: SoftErpTheme.accent),
                    const SizedBox(width: 8),
                    Text('Create item "$query"', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: SoftErpTheme.accent)),
                  ],
                ),
              ),
            )
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton(
            onPressed: widget.onSave,
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }
}

class _ItemSelectableCard extends StatefulWidget {
  const _ItemSelectableCard({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final ItemDefinition item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ItemSelectableCard> createState() => _ItemSelectableCardState();
}

class _ItemSelectableCardState extends State<_ItemSelectableCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.selected ? SoftErpTheme.accentSoft : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: widget.selected ? SoftErpTheme.accent : SoftErpTheme.border,
          width: widget.selected ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () {
              if (widget.selected) {
                setState(() => _expanded = !_expanded);
              } else {
                widget.onTap();
              }
            },
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.item.displayName.trim().isEmpty ? widget.item.name : widget.item.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: SoftErpTheme.textPrimary,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: SoftErpTheme.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 16),
                  _buildDetailRow('Pipeline', widget.item.defaultPipelineName ?? 'None'),
                  const SizedBox(height: 4),
                  _buildDetailRow('Machines', widget.item.machines.isNotEmpty ? widget.item.machines.map((e) => e.name).join(', ') : 'None'),
                  const SizedBox(height: 4),
                  _buildDetailRow('Dies', widget.item.dies.isNotEmpty ? widget.item.dies.map((e) => e.toolCode).join(', ') : 'None'),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: SoftErpTheme.textSecondary),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12, color: SoftErpTheme.textPrimary, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

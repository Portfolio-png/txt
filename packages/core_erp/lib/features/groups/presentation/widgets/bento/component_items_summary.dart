import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../core/theme/soft_erp_theme.dart';
import '../../../domain/group_definition.dart';
import '../../../../items/domain/item_definition.dart';
import '../../../../items/presentation/providers/items_provider.dart';

class ComponentItemsSummary extends StatelessWidget {
  const ComponentItemsSummary({
    super.key,
    required this.component,
  });

  final GroupDefinition component;

  @override
  Widget build(BuildContext context) {
    final members = context
        .watch<ItemsProvider>()
        .items
        .where((item) => item.groupId == component.id && !item.isArchived)
        .toList(growable: false);

    if (members.isEmpty) {
      return const Text(
        'No items added yet.',
        style: TextStyle(fontSize: 12, color: SoftErpTheme.textSecondary),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final item in members)
          _ItemSummaryTile(item: item),
      ],
    );
  }
}

class _ItemSummaryTile extends StatefulWidget {
  const _ItemSummaryTile({required this.item});
  final ItemDefinition item;

  @override
  State<_ItemSummaryTile> createState() => _ItemSummaryTileState();
}

class _ItemSummaryTileState extends State<_ItemSummaryTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.item.displayName.trim().isEmpty ? widget.item.name : widget.item.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: SoftErpTheme.textPrimary,
                    ),
                  ),
                ),
                Icon(
                  _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  size: 16,
                  color: SoftErpTheme.textSecondary,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 8, bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildRow('Pipeline:', widget.item.defaultPipelineName ?? widget.item.defaultPipelineId ?? 'None'),
                _buildRow('Machines:', widget.item.machines.map((e) => e.name).join(', ').isNotEmpty ? widget.item.machines.map((e) => e.name).join(', ') : 'None'),
                _buildRow('Dies:', widget.item.dies.map((e) => e.toolCode).join(', ').isNotEmpty ? widget.item.dies.map((e) => e.toolCode).join(', ') : 'None'),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: SoftErpTheme.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 11, color: SoftErpTheme.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

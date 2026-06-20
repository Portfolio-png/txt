import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:core_erp/core/widgets/app_button.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/shared/widgets/exact_item_variation_select_field.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';

class OutputItemPickerDialog extends StatefulWidget {
  const OutputItemPickerDialog({super.key});

  @override
  State<OutputItemPickerDialog> createState() => _OutputItemPickerDialogState();
}

class _OutputItemPickerDialogState extends State<OutputItemPickerDialog> {
  String _searchQuery = '';
  ExactItemVariationReference? _selected;

  @override
  Widget build(BuildContext context) {
    final itemsProvider = context.watch<ItemsProvider>();
    final allItems = itemsProvider.items;
    
    final filteredItems = _searchQuery.isEmpty 
      ? allItems 
      : allItems.where((i) => i.displayName.toLowerCase().contains(_searchQuery.toLowerCase()) || i.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_rounded, color: Color(0xFF3B82F6)),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Select Output Item',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search items...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: itemsProvider.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: filteredItems.length,
                      itemBuilder: (context, index) {
                        final item = filteredItems[index];
                        final variations = _getLeafVariations(item.variationTree);
                        
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.grey.shade200),
                          ),
                          child: ExpansionTile(
                            title: Text(
                              item.displayName.isNotEmpty ? item.displayName : item.name,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            children: variations.isEmpty
                              ? [
                                  ListTile(
                                    contentPadding: const EdgeInsets.only(left: 32, right: 16),
                                    title: const Text('Default Item (No Variations)'),
                                    trailing: _selected?.itemId == item.id 
                                      ? const Icon(Icons.check_circle, color: Colors.green)
                                      : null,
                                    onTap: () {
                                      setState(() {
                                        _selected = ExactItemVariationReference(
                                          itemId: item.id,
                                          variationLeafNodeId: 0,
                                          itemLabel: item.displayName,
                                          variationPathLabel: '',
                                        );
                                      });
                                    },
                                  )
                                ]
                              : variations.map((v) {
                                  final isSelected = _selected?.variationLeafNodeId == v.id;
                                  return ListTile(
                                    contentPadding: const EdgeInsets.only(left: 32, right: 16),
                                    title: Text(v.pathLabel),
                                    trailing: isSelected 
                                      ? const Icon(Icons.check_circle, color: Colors.green)
                                      : null,
                                    onTap: () {
                                      setState(() {
                                        _selected = ExactItemVariationReference(
                                          itemId: item.id,
                                          variationLeafNodeId: v.id,
                                          itemLabel: item.displayName,
                                          variationPathLabel: v.pathLabel,
                                        );
                                      });
                                    },
                                  );
                                }).toList(),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    label: 'Cancel',
                    variant: AppButtonVariant.secondary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  AppButton(
                    label: 'Confirm Selection',
                    onPressed: _selected == null 
                      ? null 
                      : () => Navigator.of(context).pop(_selected),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  List<_VariationLeaf> _getLeafVariations(List<ItemVariationNodeDefinition> nodes, [String currentPath = '']) {
    final leaves = <_VariationLeaf>[];
    for (final node in nodes) {
      final newPath = currentPath.isEmpty ? node.name : '$currentPath - ${node.name}';
      if (node.children.isEmpty) {
        leaves.add(_VariationLeaf(id: node.id, pathLabel: newPath));
      } else {
        leaves.addAll(_getLeafVariations(node.children, newPath));
      }
    }
    return leaves;
  }
}

class _VariationLeaf {
  _VariationLeaf({required this.id, required this.pathLabel});
  final int id;
  final String pathLabel;
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/erp_form_dialog.dart';
import '../../../../core/widgets/searchable_select.dart';
import '../../../items/domain/item_definition.dart';
import '../../../items/presentation/providers/items_provider.dart';
import '../../domain/inventory_set_definition.dart';
import '../providers/inventory_provider.dart';

class InventorySetEditorDialog extends StatefulWidget {
  const InventorySetEditorDialog({super.key, this.setDefinition});

  final InventorySetDefinition? setDefinition;

  static Future<void> open(
    BuildContext context, {
    InventorySetDefinition? setDefinition,
  }) {
    return showErpFormDialog<void>(
      context,
      maxWidth: 1120,
      maxHeight: 780,
      child: InventorySetEditorDialog(setDefinition: setDefinition),
    );
  }

  @override
  State<InventorySetEditorDialog> createState() =>
      _InventorySetEditorDialogState();
}

class _InventorySetEditorDialogState extends State<InventorySetEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final List<_EditableInventorySetLine> _lines;

  bool get _isEditMode => widget.setDefinition != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.setDefinition?.name ?? '',
    );
    _lines =
        widget.setDefinition?.lines
            .map(
              (line) => _EditableInventorySetLine(
                itemId: line.itemId,
                variationLeafNodeId: line.variationLeafNodeId,
                selectionKey: '${line.itemId}::${line.variationLeafNodeId}',
                itemLabel: line.itemDisplayName.trim().isEmpty
                    ? line.itemName
                    : line.itemDisplayName,
                variationPathLabel: line.variationPathLabel,
                variationPathNodeIds: line.variationPathNodeIds,
                quantity: line.quantity.toString(),
              ),
            )
            .toList(growable: true) ??
        <_EditableInventorySetLine>[_EditableInventorySetLine()];
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final items =
        context
            .watch<ItemsProvider>()
            .items
            .where((item) => !item.isArchived)
            .toList(growable: false)
          ..sort(
            (a, b) => a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            ),
          );
    final selectableReferences = _buildSelectableReferences(items);
    final selectableReferenceByKey = {
      for (final reference in selectableReferences) reference.key: reference,
    };

    final isNarrow = MediaQuery.of(context).size.width < 900;

    final header = Container(
      height: 76,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Color(0xFFFBFBFB),
        border: Border(bottom: BorderSide(color: Color(0xFFE7EBF0))),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isEditMode ? 'Edit Set' : 'Create Set',
                  style: _inventoryInterStyle(
                    color: const Color(0xFF111827),
                    size: 22,
                    weight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Build a named composition of exact item variations and quantities.',
                  style: _inventoryInterStyle(
                    color: const Color(0xFF6B7280),
                    size: 13,
                    weight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );

    final footer = Container(
      height: 76,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Color(0xFFFBFBFB),
        border: Border(top: BorderSide(color: Color(0xFFE7EBF0))),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
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
            label: _isEditMode ? 'Save Changes' : 'Create Set',
            isLoading: inventory.isSaving,
            onPressed: _save,
          ),
        ],
      ),
    );

    final detailsCard = _CreateGroupSurfaceCard(
      title: 'Set Details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _nameController,
            style: _inventoryInterStyle(
              color: const Color(0xFF0F172A),
              size: 14,
              weight: FontWeight.w500,
            ),
            decoration: _editorFieldDecoration(
              label: 'Set Name',
              helper:
                  'Use a clear operational name like Starter Pack or Marketing Kit.',
            ),
            validator: (value) =>
                value == null || value.trim().isEmpty ? 'Required' : null,
          ),
        ],
      ),
    );

    final compositionCard = _CreateGroupSurfaceCard(
      title: 'Composition',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Each row must point to an exact item variation instance.',
            style: _inventoryInterStyle(
              color: const Color(0xFF64748B),
              size: 12,
              weight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 16),
          for (var index = 0; index < _lines.length; index++) ...[
            _buildLineRow(
              index: index,
              line: _lines[index],
              selectableReferences: selectableReferences,
              selectableReferenceByKey: selectableReferenceByKey,
            ),
            if (index != _lines.length - 1) const SizedBox(height: 12),
          ],
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              label: 'Add Row',
              variant: AppButtonVariant.secondary,
              onPressed: _addLine,
            ),
          ),
        ],
      ),
    );

    final content = Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: isNarrow
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        detailsCard,
                        const SizedBox(height: 24),
                        compositionCard,
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 4, child: detailsCard),
                        const SizedBox(width: 24),
                        Expanded(flex: 6, child: compositionCard),
                      ],
                    ),
            ),
          ),
          footer,
        ],
      ),
    );

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: isNarrow
          ? content
          : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1140, maxHeight: 740),
              child: content,
            ),
    );
  }

  Widget _buildLineRow({
    required int index,
    required _EditableInventorySetLine line,
    required List<_SelectableSetReference> selectableReferences,
    required Map<String, _SelectableSetReference> selectableReferenceByKey,
  }) {
    final selectedReference = line.selectionKey == null
        ? null
        : selectableReferenceByKey[line.selectionKey!];
    final itemLabel =
        selectedReference?.itemLabel ??
        (line.itemLabel.trim().isEmpty ? null : line.itemLabel);
    final variationLabel =
        selectedReference?.variationPathLabel ??
        (line.variationPathLabel.trim().isEmpty
            ? null
            : line.variationPathLabel);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: SearchableSelectField<String?>(
                  tapTargetKey: ValueKey<String>('inventory-set-item-$index'),
                  value: line.selectionKey,
                  decoration: _editorFieldDecoration(
                    label: 'Item',
                    helper:
                        'Search by item name, alias, or variation-path terms.',
                  ),
                  dialogTitle: 'Select Item',
                  searchHintText: 'Search item or variation path',
                  options: selectableReferences
                      .map(
                        (reference) => SearchableSelectOption<String?>(
                          value: reference.key,
                          label: reference.optionLabel,
                          searchText: reference.searchText,
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) => _handleReferenceSelection(
                    index,
                    value,
                    selectableReferenceByKey,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: line.quantityController,
                  focusNode: line.quantityFocusNode,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: _inventoryInterStyle(
                    color: const Color(0xFF0F172A),
                    size: 14,
                    weight: FontWeight.w600,
                  ),
                  decoration: _editorFieldDecoration(
                    label: 'Qty',
                    helper: 'Required',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: IconButton(
                  onPressed: _lines.length == 1
                      ? null
                      : () => _removeLine(index),
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD8E0EA)),
            ),
            child: itemLabel == null
                ? Row(
                    children: [
                      const Icon(
                        Icons.link_off_rounded,
                        size: 16,
                        color: Color(0xFF94A3B8),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Pick an exact item reference.',
                        style: _inventoryInterStyle(
                          color: const Color(0xFF94A3B8),
                          size: 12,
                          weight: FontWeight.w500,
                        ),
                      ),
                    ],
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _ReadOnlyReferenceChip(
                        icon: Icons.inventory_2_outlined,
                        label: itemLabel,
                      ),
                      _ReadOnlyReferenceChip(
                        icon: selectedReference?.variationLeafNodeId == 0
                            ? Icons.layers_clear_outlined
                            : Icons.account_tree_outlined,
                        label: variationLabel ?? 'Base item',
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  void _addLine() {
    setState(() {
      _lines.add(_EditableInventorySetLine());
    });
  }

  void _removeLine(int index) {
    final line = _lines.removeAt(index);
    line.dispose();
    setState(() {});
  }

  Future<void> _handleReferenceSelection(
    int index,
    String? selectionKey,
    Map<String, _SelectableSetReference> selectableReferenceByKey,
  ) async {
    if (selectionKey == null) {
      setState(() {
        final line = _lines[index];
        line.itemId = null;
        line.variationLeafNodeId = null;
        line.itemLabel = '';
        line.variationPathLabel = '';
        line.variationPathNodeIds = const <int>[];
        line.selectionKey = null;
      });
      return;
    }
    final reference = selectableReferenceByKey[selectionKey];
    if (reference == null) {
      return;
    }
    setState(() {
      final line = _lines[index];
      line.selectionKey = reference.key;
      line.itemId = reference.itemId;
      line.variationLeafNodeId = reference.variationLeafNodeId;
      line.itemLabel = reference.itemLabel;
      line.variationPathLabel = reference.variationPathLabel;
      line.variationPathNodeIds = reference.variationPathNodeIds;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final line = _lines[index];
      line.quantityFocusNode.requestFocus();
      line.quantityController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: line.quantityController.text.length,
      );
    });
  }

  List<_SelectableSetReference> _buildSelectableReferences(
    List<ItemDefinition> items,
  ) {
    final references = <_SelectableSetReference>[];
    for (final item in items) {
      final itemLabel = item.displayName.trim().isEmpty
          ? item.name
          : item.displayName;
      final propertyNames = item.topLevelProperties
          .map(
            (property) => property.displayName.trim().isEmpty
                ? property.name
                : property.displayName,
          )
          .where((name) => name.trim().isNotEmpty)
          .join(' ');
      final baseSearchPrefix =
          '$itemLabel ${item.name} ${item.alias} ${item.displayName} $propertyNames';
      if (item.leafVariationNodes.isEmpty) {
        references.add(
          _SelectableSetReference(
            itemId: item.id,
            variationLeafNodeId: 0,
            itemLabel: itemLabel,
            variationPathLabel: 'Base item',
            variationPathNodeIds: const <int>[],
            optionLabel: '$itemLabel • Base item',
            searchText: '$baseSearchPrefix base item no variation',
          ),
        );
        continue;
      }

      final leafPaths = _leafPathNodeIdsByLeafId(item);
      for (final leaf in item.leafVariationNodes) {
        references.add(
          _SelectableSetReference(
            itemId: item.id,
            variationLeafNodeId: leaf.id,
            itemLabel: itemLabel,
            variationPathLabel: leaf.displayName,
            variationPathNodeIds: leafPaths[leaf.id] ?? const <int>[],
            optionLabel: '$itemLabel • ${leaf.displayName}',
            searchText: '$baseSearchPrefix ${leaf.displayName}',
          ),
        );
      }
    }
    references.sort(
      (a, b) =>
          a.optionLabel.toLowerCase().compareTo(b.optionLabel.toLowerCase()),
    );
    return references;
  }

  Map<int, List<int>> _leafPathNodeIdsByLeafId(ItemDefinition item) {
    final byLeafId = <int, List<int>>{};

    void visit(ItemVariationNodeDefinition node, List<int> activeValuePath) {
      if (node.kind == ItemVariationNodeKind.value) {
        final nextPath = [...activeValuePath, node.id];
        if (node.activeChildren.isEmpty) {
          byLeafId[node.id] = nextPath;
          return;
        }
        for (final child in node.activeChildren) {
          visit(child, nextPath);
        }
        return;
      }
      for (final child in node.activeChildren) {
        visit(child, activeValuePath);
      }
    }

    for (final root in item.topLevelProperties) {
      visit(root, const <int>[]);
    }
    return byLeafId;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      return;
    }

    final parsedLines = <SaveInventorySetLineInput>[];
    for (var index = 0; index < _lines.length; index++) {
      final line = _lines[index];
      final quantity = int.tryParse(line.quantityController.text.trim());
      if (line.itemId == null ||
          line.variationLeafNodeId == null ||
          quantity == null ||
          quantity <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Complete row ${index + 1} with an item reference and quantity.',
            ),
          ),
        );
        return;
      }
      parsedLines.add(
        SaveInventorySetLineInput(
          itemId: line.itemId!,
          variationLeafNodeId: line.variationLeafNodeId!,
          quantity: quantity,
          position: index,
          itemName: line.itemLabel,
          itemDisplayName: line.itemLabel,
          variationPathLabel: line.variationPathLabel,
          variationPathNodeIds: line.variationPathNodeIds,
        ),
      );
    }
    if (parsedLines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one composition row.')),
      );
      return;
    }

    final merged = <String, SaveInventorySetLineInput>{};
    for (final line in parsedLines) {
      final key = '${line.itemId}::${line.variationLeafNodeId}';
      final current = merged[key];
      if (current == null) {
        merged[key] = line;
      } else {
        merged[key] = SaveInventorySetLineInput(
          itemId: line.itemId,
          variationLeafNodeId: line.variationLeafNodeId,
          quantity: current.quantity + line.quantity,
          position: current.position,
          itemName: current.itemName,
          itemDisplayName: current.itemDisplayName,
          variationPathLabel: current.variationPathLabel,
          variationPathNodeIds: current.variationPathNodeIds,
        );
      }
    }

    await context.read<InventoryProvider>().saveSet(
      SaveInventorySetInput(
        id: widget.setDefinition?.id,
        name: name,
        lines: merged.values.toList(growable: false)
          ..sort((a, b) => a.position.compareTo(b.position)),
      ),
    );

    if (!mounted) {
      return;
    }
    final provider = context.read<InventoryProvider>();
    if (provider.errorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.errorMessage!)));
      return;
    }
    Navigator.of(context).pop();
  }

  InputDecoration _editorFieldDecoration({
    required String label,
    required String helper,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helper,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD8E0EA)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD8E0EA)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF6049E3)),
      ),
      helperStyle: _inventoryInterStyle(
        color: const Color(0xFF6B7280),
        size: 12,
        weight: FontWeight.w400,
      ),
    );
  }
}

class _EditableInventorySetLine {
  _EditableInventorySetLine({
    this.itemId,
    this.variationLeafNodeId,
    this.selectionKey,
    this.itemLabel = '',
    this.variationPathLabel = '',
    this.variationPathNodeIds = const <int>[],
    String quantity = '1',
  }) : quantityController = TextEditingController(text: quantity),
       quantityFocusNode = FocusNode(debugLabel: 'set_line_quantity');

  int? itemId;
  int? variationLeafNodeId;
  String? selectionKey;
  String itemLabel;
  String variationPathLabel;
  List<int> variationPathNodeIds;
  final TextEditingController quantityController;
  final FocusNode quantityFocusNode;

  void dispose() {
    quantityController.dispose();
    quantityFocusNode.dispose();
  }
}

class _SelectableSetReference {
  const _SelectableSetReference({
    required this.itemId,
    required this.variationLeafNodeId,
    required this.itemLabel,
    required this.variationPathLabel,
    required this.variationPathNodeIds,
    required this.optionLabel,
    required this.searchText,
  });

  final int itemId;
  final int variationLeafNodeId;
  final String itemLabel;
  final String variationPathLabel;
  final List<int> variationPathNodeIds;
  final String optionLabel;
  final String searchText;

  String get key => '$itemId::$variationLeafNodeId';
}

class _ReadOnlyReferenceChip extends StatelessWidget {
  const _ReadOnlyReferenceChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF64748B)),
          const SizedBox(width: 6),
          Text(
            label,
            style: _inventoryInterStyle(
              color: const Color(0xFF475569),
              size: 12,
              weight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateGroupSurfaceCard extends StatelessWidget {
  const _CreateGroupSurfaceCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: _inventoryInterStyle(
              color: const Color(0xFF1E293B),
              size: 16,
              weight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

TextStyle _inventoryInterStyle({
  required Color color,
  required double size,
  required FontWeight weight,
}) {
  return TextStyle(
    fontFamily: 'Inter',
    color: color,
    fontSize: size,
    fontWeight: weight,
    height: 1.3,
  );
}

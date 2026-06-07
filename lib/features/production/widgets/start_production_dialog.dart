import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:core_erp/core/widgets/app_button.dart';
import 'package:core_erp/features/orders/domain/order_entry.dart';
import '../../production_pipelines/data/repositories/pipeline_run_repository.dart';
import '../../production_pipelines/domain/pipeline_template.dart';

Future<void> showStartProductionDialog(BuildContext context, OrderGroup orderGroup, {OrderEntry? preselectedItem}) async {
  final repo = context.read<PipelineRunRepository>();
  
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => const Center(child: CircularProgressIndicator()),
  );
  
  final templates = await repo.getTemplates();
  final existingRuns = await repo.getRunsForOrder(orderGroup.orderNo);
  if (!context.mounted) return;
  Navigator.of(context).pop(); // remove loading
  
  final assignedItemIds = existingRuns.map((r) => r.orderItemId).whereType<int>().toSet();
  final unassignedItems = orderGroup.items.where((i) => !assignedItemIds.contains(i.id)).toList();

  if (unassignedItems.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All items for this order are already in production.')),
    );
    return;
  }
  
  await showDialog<void>(
    context: context,
    builder: (context) => _StartProductionDialog(
      templates: templates,
      unassignedItems: unassignedItems,
      orderGroup: orderGroup,
      preselectedItem: preselectedItem,
    ),
  );
}

class _StartProductionDialog extends StatefulWidget {
  const _StartProductionDialog({
    required this.templates,
    required this.unassignedItems,
    required this.orderGroup,
    this.preselectedItem,
  });

  final List<PipelineTemplate> templates;
  final List<OrderEntry> unassignedItems;
  final OrderGroup orderGroup;
  final OrderEntry? preselectedItem;

  @override
  State<_StartProductionDialog> createState() => _StartProductionDialogState();
}

class _StartProductionDialogState extends State<_StartProductionDialog> {
  late List<OrderEntry> _currentItems;
  PipelineTemplate? _selectedTemplate;
  OrderEntry? _selectedItem;
  bool _showConfirmation = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _currentItems = List.from(widget.unassignedItems);
    if (widget.templates.isNotEmpty) _selectedTemplate = widget.templates.first;
    if (_currentItems.isNotEmpty) {
      if (widget.preselectedItem != null && _currentItems.any((i) => i.id == widget.preselectedItem!.id)) {
        _selectedItem = _currentItems.firstWhere((i) => i.id == widget.preselectedItem!.id);
      } else {
        _selectedItem = _currentItems.first;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_currentItems.isEmpty 
          ? 'All Assigned' 
          : (_showConfirmation ? 'Confirm Production Assignment' : 'Start Production Line')),
      content: SizedBox(
        width: 400,
        child: _currentItems.isEmpty
            ? _buildAllAssignedContent()
            : (_showConfirmation ? _buildConfirmationContent() : _buildSelectionContent()),
      ),
      actions: _currentItems.isEmpty
          ? [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))]
          : (_showConfirmation ? _buildConfirmationActions() : _buildSelectionActions()),
    );
  }

  Widget _buildAllAssignedContent() {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 16),
        Icon(Icons.check_circle, color: Colors.green, size: 48),
        SizedBox(height: 16),
        Text('All items from this order have been successfully assigned to production!'),
        SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSelectionContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Which item are you putting into production?'),
        const SizedBox(height: 8),
        DropdownButton<OrderEntry>(
          value: _selectedItem,
          isExpanded: true,
          items: _currentItems.map((item) {
            return DropdownMenuItem(
              value: item,
              child: Text(
                '${item.itemName} (${item.variationPathLabel}) - ${item.quantity} ${item.unitSymbol}',
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: (val) => setState(() => _selectedItem = val),
        ),
        const SizedBox(height: 24),
        const Text('Which production pipeline template?'),
        const SizedBox(height: 8),
        DropdownButton<PipelineTemplate>(
          value: _selectedTemplate,
          isExpanded: true,
          items: widget.templates.map((t) {
            return DropdownMenuItem(
              value: t,
              child: Text(
                '${t.name} (${t.nodes.length} stages)',
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: (val) => setState(() => _selectedTemplate = val),
        ),
      ],
    );
  }

  Widget _buildConfirmationContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Please confirm the following production assignment:', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        const Text('Item:', style: TextStyle(color: Colors.black54)),
        Text('${_selectedItem?.itemName} (${_selectedItem?.variationPathLabel})', style: const TextStyle(fontWeight: FontWeight.w500)),
        Text('Quantity: ${_selectedItem?.quantity} ${_selectedItem?.unitSymbol}'),
        const SizedBox(height: 16),
        const Text('Pipeline Template:', style: TextStyle(color: Colors.black54)),
        Text('${_selectedTemplate?.name}', style: const TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 24),
        const Text('A new active pipeline run will be created for this item. Are you sure you want to proceed?'),
      ],
    );
  }

  List<Widget> _buildSelectionActions() {
    return [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      AppButton(
        onPressed: (_selectedTemplate != null && _selectedItem != null)
            ? () => setState(() => _showConfirmation = true)
            : null,
        label: 'Next',
      ),
    ];
  }

  List<Widget> _buildConfirmationActions() {
    return [
      TextButton(
        onPressed: _isLoading ? null : () => setState(() => _showConfirmation = false),
        child: const Text('Back'),
      ),
      AppButton(
        isLoading: _isLoading,
        onPressed: () async {
          setState(() => _isLoading = true);
          try {
            final repo = context.read<PipelineRunRepository>();
            await repo.createRun(
              _selectedTemplate!.id,
              orderNo: widget.orderGroup.orderNo,
              orderItemId: _selectedItem!.id,
            );
            
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              _showConfirmation = false;
              _currentItems.remove(_selectedItem);
              _selectedItem = _currentItems.isNotEmpty ? _currentItems.first : null;
            });
            
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Item successfully assigned to production!')),
            );
          } catch (e) {
            if (!mounted) return;
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to start production: $e')),
            );
          }
        },
        label: 'Confirm & Start',
      ),
    ];
  }
}

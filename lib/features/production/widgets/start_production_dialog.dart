import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:core_erp/core/widgets/app_button.dart';
import 'package:core_erp/features/orders/domain/order_entry.dart';
import '../../production_pipelines/data/repositories/pipeline_run_repository.dart';
import '../../production_pipelines/domain/pipeline_run.dart';
import '../../production_pipelines/domain/pipeline_template.dart';
import '../providers/production_provider.dart';
import '../screens/live_production_monitor_screen.dart';

Future<void> showStartProductionDialog(BuildContext context, OrderGroup orderGroup) async {
  final repo = context.read<PipelineRunRepository>();
  
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => const Center(child: CircularProgressIndicator()),
  );
  
  final templates = await repo.getTemplates();
  final existingRuns = await repo.getRunsForOrder(orderGroup.orderNo);
  Navigator.of(context).pop(); // remove loading
  
  if (!context.mounted) return;

  final assignedItemIds = existingRuns.map((r) => r.orderItemId).whereType<int>().toSet();
  final unassignedItems = orderGroup.items.where((i) => !assignedItemIds.contains(i.id)).toList();

  print('Existing runs: ${existingRuns.length}');
  print('Assigned item IDs: $assignedItemIds');
  print('Unassigned items: ${unassignedItems.length}');

  if (unassignedItems.isEmpty && existingRuns.isNotEmpty) {
    // All items are already in production! Jump directly to the first active run
    final runToOpen = existingRuns.first;
    final template = templates.firstWhere(
      (t) => t.id == runToOpen.templateId, 
      orElse: () => templates.first,
    );

    context.read<ProductionProvider>().loadTemplate(
      template,
      orderId: runToOpen.orderItemId,
      orderNo: orderGroup.orderNo,
      clientName: orderGroup.clientName,
    );

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LiveProductionMonitorScreen()),
    );
    return;
  }
  
  final result = await showDialog<({PipelineTemplate template, OrderEntry item})>(
    context: context,
    builder: (context) => _StartProductionDialog(
      templates: templates,
      items: unassignedItems,
    ),
  );

  print('Dialog closed with result: $result');
  print('Is context mounted? ${context.mounted}');
  
  if (result != null && context.mounted) {
    print('Proceeding to create run');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await repo.createRun(
        result.template.id, 
        orderNo: orderGroup.orderNo,
        orderItemId: result.item.id,
      );

      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // remove loading dialog first

        context.read<ProductionProvider>().loadTemplate(
          result.template,
          orderId: result.item.id,
          orderNo: orderGroup.orderNo,
          clientName: orderGroup.clientName,
        );

        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(builder: (_) => const LiveProductionMonitorScreen()),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // remove loading dialog on error
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start production: $e')),
        );
      }
    }
  }
}

class _StartProductionDialog extends StatefulWidget {
  const _StartProductionDialog({
    required this.templates,
    required this.items,
  });

  final List<PipelineTemplate> templates;
  final List<OrderEntry> items;

  @override
  State<_StartProductionDialog> createState() => _StartProductionDialogState();
}

class _StartProductionDialogState extends State<_StartProductionDialog> {
  PipelineTemplate? _selectedTemplate;
  OrderEntry? _selectedItem;
  bool _showConfirmation = false;

  @override
  void initState() {
    super.initState();
    if (widget.templates.isNotEmpty) _selectedTemplate = widget.templates.first;
    if (widget.items.isNotEmpty) _selectedItem = widget.items.first;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_showConfirmation ? 'Confirm Production Assignment' : 'Start Production Line'),
      content: SizedBox(
        width: 400,
        child: _showConfirmation ? _buildConfirmationContent() : _buildSelectionContent(),
      ),
      actions: _showConfirmation ? _buildConfirmationActions() : _buildSelectionActions(),
    );
  }

  Widget _buildSelectionContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Which item are you putting into production?'),
        const SizedBox(height: 8),
        DropdownButtonFormField<OrderEntry>(
          value: _selectedItem,
          isExpanded: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: widget.items.map((item) {
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
        DropdownButtonFormField<PipelineTemplate>(
          value: _selectedTemplate,
          isExpanded: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
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
        onPressed: () => setState(() => _showConfirmation = false),
        child: const Text('Back'),
      ),
      AppButton(
        onPressed: () => Navigator.of(context).pop((template: _selectedTemplate!, item: _selectedItem!)),
        label: 'Confirm & Start',
      ),
    ];
  }
}

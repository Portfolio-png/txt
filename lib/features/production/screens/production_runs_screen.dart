import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/features/orders/domain/order_entry.dart';
import 'package:core_erp/features/orders/presentation/providers/orders_provider.dart';

import '../../production_pipelines/data/repositories/pipeline_run_repository.dart';
import '../../production_pipelines/domain/pipeline_run.dart';
import '../../production_pipelines/domain/pipeline_template.dart';
import '../../production_pipelines/domain/process_node.dart';
import '../../production_pipelines/domain/node_run_status.dart';
import '../providers/production_provider.dart';
import '../providers/production_run_provider.dart';
import 'live_production_monitor_screen.dart';
import '../widgets/order_picker_dialog.dart';
import 'package:collection/collection.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';

class ProductionRunsScreen extends StatefulWidget {
  const ProductionRunsScreen({super.key});

  @override
  State<ProductionRunsScreen> createState() => _ProductionRunsScreenState();
}

class _ProductionRunsScreenState extends State<ProductionRunsScreen> {
  bool _isLoading = true;
  List<PipelineRun> _runs = [];
  List<PipelineTemplate> _templates = [];

  @override
  void initState() {
    super.initState();
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<InventoryProvider>().initialize();
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final repo = context.read<PipelineRunRepository>();
      final futures = await Future.wait([
        repo.getRuns(),
        repo.getTemplates(),
      ]);
      if (!mounted) return;
      
      final runs = futures[0] as List<PipelineRun>;
      final templates = futures[1] as List<PipelineTemplate>;
      
      // Sort runs: active at the top, completed at the bottom, then by createdAt desc
      runs.sort((a, b) {
        final aActive = a.status != 'completed';
        final bActive = b.status != 'completed';
        if (aActive && !bActive) return -1;
        if (!aActive && bActive) return 1;
        return b.createdAt.compareTo(a.createdAt);
      });

      setState(() {
        _runs = runs;
        _templates = templates;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _startProduction() async {
    // 1. Show template picker
    final activeTemplates = _templates.where((t) => t.status != PipelineTemplateStatus.archived).toList();
    if (activeTemplates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active templates available to start production.')),
      );
      return;
    }

    final template = await showDialog<PipelineTemplate>(
      context: context,
      builder: (context) => _TemplateSelectionDialog(templates: activeTemplates),
    );

    if (template == null || !mounted) return;

    // 2. Show order picker
    final order = await showDialog<OrderEntry?>(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<OrdersProvider>(),
        child: const OrderPickerDialog(),
      ),
    );

    if (order == null || !mounted) return;

    // 3. Create run and navigate
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final repo = context.read<PipelineRunRepository>();
      final newRun = await repo.createRun(
        template.id, 
        orderNo: order.orderNo,
        orderItemId: order.id,
      );

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // remove loading dialog

      context.read<ProductionProvider>().loadTemplate(
        template,
        orderId: order.id,
        orderNo: order.orderNo,
        clientName: order.clientName,
      );
      context.read<ProductionRunProvider>().initializeIdleRun(newRun.id);

      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LiveProductionMonitorScreen()),
      );
      
      // Refresh runs in the background so it's updated when we come back
      _loadData();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // remove loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start production: $e')),
      );
    }
  }

  void _monitorRun(PipelineRun run) {
    final template = _templates.firstWhere((t) => t.id == run.templateId, orElse: () => _templates.first);
    context.read<ProductionProvider>().loadTemplate(
      template,
      orderId: run.orderItemId,
      orderNo: run.orderNo,
      clientName: run.clientName,
    );
    context.read<ProductionRunProvider>().initializeIdleRun(run.id);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LiveProductionMonitorScreen()),
    );
  }

  Future<void> _deleteRun(PipelineRun run) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Production Run', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to delete the production run for "${run.orderNo != null ? 'Order: ' + run.orderNo! : 'Ad-hoc Run'}"?\nThis will permanently delete this run history.',
          style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final repo = context.read<PipelineRunRepository>();
      await repo.deleteRun(run.id);
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete run: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inventoryProvider = context.watch<InventoryProvider>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
      child: Column(
        children: [
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Production',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        color: SoftErpTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Monitor active production runs and start new pipelines.',
                      style: TextStyle(
                        fontSize: 14,
                        color: SoftErpTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _startProduction,
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: const Text('Start Production'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Content
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _runs.isEmpty
                      ? Center(
                          child: Text(
                            'No production runs found.',
                            style: TextStyle(color: SoftErpTheme.textSecondary),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: _runs.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final run = _runs[index];
                            final template = _templates.where((t) => t.id == run.templateId).firstOrNull;
                            final isActive = run.status != 'completed';
                            
                            String? stalledMessage;
                            if (isActive && template != null) {
                              final inputNode = template.nodes.firstWhereOrNull((n) {
                                final pType = n.processType.trim().toLowerCase();
                                final name = n.name.trim().toLowerCase();
                                return pType == 'input' || pType == 'input stage' || name == 'input' || name == 'input stage' || name.endsWith(' input');
                              });
                              
                              if (inputNode != null && inputNode.inputItem != null) {
                                final itemId = inputNode.inputItem!.itemId;
                                final materials = inventoryProvider.materials.where((m) => m.linkedItemId == itemId).toList();
                                final stock = materials.fold<double>(0.0, (sum, m) => sum + m.onHand);
                                if (stock <= 0) {
                                  stalledMessage = '${inputNode.name} stalled due to insufficient material';
                                }
                              }
                            }
                            
                            return _RunCard(
                              run: run,
                              templateName: template?.name ?? 'Unknown Pipeline',
                              template: template,
                              isActive: isActive,
                              stalledMessage: stalledMessage,
                              onMonitor: () => _monitorRun(run),
                              onDelete: () => _deleteRun(run),
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RunCard extends StatelessWidget {
  const _RunCard({
    required this.run,
    required this.templateName,
    this.template,
    required this.isActive,
    this.stalledMessage,
    required this.onMonitor,
    required this.onDelete,
  });

  final PipelineRun run;
  final String templateName;
  final PipelineTemplate? template;
  final bool isActive;
  final String? stalledMessage;
  final VoidCallback onMonitor;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isStalled = stalledMessage != null;
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onMonitor,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: isStalled ? Colors.amber.shade50 : SoftErpTheme.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isStalled ? Colors.amber.shade400 : SoftErpTheme.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Info section
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            run.orderNo != null ? 'Order: ${run.orderNo}' : 'Ad-hoc Run',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: SoftErpTheme.textPrimary,
                            ),
                          ),
                          if (run.clientName != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              '• ${run.clientName}',
                              style: TextStyle(
                                fontSize: 14,
                                color: SoftErpTheme.textSecondary,
                              ),
                            ),
                          ],
                          const SizedBox(width: 12),
                          _StatusBadge(status: run.status, isActive: isActive),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Pipeline: $templateName',
                        style: const TextStyle(
                          fontSize: 14,
                          color: SoftErpTheme.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Started: ${run.createdAt.toIso8601String().split('T').first}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: SoftErpTheme.textSecondary,
                        ),
                      ),
                      _buildTimeline(context),
                      if (isStalled) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange),
                              const SizedBox(width: 6),
                              Text(
                                stalledMessage!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                
                // Actions
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                  tooltip: 'Delete production run',
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeline(BuildContext context) {
    if (template == null || template!.nodes.isEmpty) {
      return const SizedBox.shrink();
    }

    final sortedNodes = List<ProcessNode>.from(template!.nodes)
      ..sort((a, b) => a.stageIndex.compareTo(b.stageIndex));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Text(
          'Pipeline Progress:',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              for (var i = 0; i < sortedNodes.length; i++) ...[
                _RunTimelineStep(
                  label: sortedNodes[i].name,
                  status: run.nodeStatuses[sortedNodes[i].id] ?? NodeRunStatus.pending,
                ),
                if (i != sortedNodes.length - 1)
                  _RunTimelineConnector(
                    isComplete: (run.nodeStatuses[sortedNodes[i].id] ?? NodeRunStatus.pending) == NodeRunStatus.done,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.isActive});
  final String status;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? SoftErpTheme.accent : Colors.grey.shade600;
    final bgColor = isActive ? SoftErpTheme.accent.withValues(alpha: 0.1) : Colors.grey.shade200;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

class _TemplateSelectionDialog extends StatelessWidget {
  const _TemplateSelectionDialog({required this.templates});
  final List<PipelineTemplate> templates;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Pipeline Template'),
      content: SizedBox(
        width: 400,
        height: 300,
        child: ListView.builder(
          itemCount: templates.length,
          itemBuilder: (context, index) {
            final t = templates[index];
            return ListTile(
              title: Text(t.name),
              subtitle: Text('${t.nodes.length} stages'),
              onTap: () => Navigator.of(context).pop(t),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _RunTimelineStep extends StatelessWidget {
  const _RunTimelineStep({
    required this.label,
    required this.status,
  });

  final String label;
  final NodeRunStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      NodeRunStatus.done => const Color(0xFF48C7A4),
      NodeRunStatus.active => SoftErpTheme.accent,
      NodeRunStatus.skipped => const Color(0xFF94A3B8),
      NodeRunStatus.pending => const Color(0xFFCBD5E1),
    };

    final isComplete = status == NodeRunStatus.done;
    final isActive = status == NodeRunStatus.active;
    final isSkipped = status == NodeRunStatus.skipped;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
            color: isComplete
                ? color
                : isSkipped
                    ? const Color(0xFFF1F5F9)
                    : isActive
                        ? Colors.white
                        : const Color(0xFFF8FAFC),
          ),
          child: isComplete
              ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
              : isSkipped
                  ? const Icon(Icons.redo_rounded, size: 12, color: Color(0xFF94A3B8))
                  : Center(
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: isActive ? color : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: const Color(0xFF475569),
            fontSize: 11,
            fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _RunTimelineConnector extends StatelessWidget {
  const _RunTimelineConnector({required this.isComplete});

  final bool isComplete;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: isComplete ? const Color(0xFF48C7A4) : const Color(0xFFE2DFEA),
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }
}

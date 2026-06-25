import 'package:flutter/foundation.dart' show listEquals;
import 'package:core_erp/core/widgets/app_button.dart';
import 'package:core_erp/core/widgets/app_empty_state.dart';
import 'package:core_erp/core/widgets/app_toast.dart';
import 'package:core_erp/core/widgets/erp_form_dialog.dart';
import 'package:core_erp/core/widgets/soft_master_data.dart';
import 'package:core_erp/core/widgets/soft_primitives.dart';
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
      showAppSnack(
        const SnackBar(content: Text('No active templates available to start production.')),
      );
      return;
    }

    final template = await showErpFormDialog<PipelineTemplate>(
      context,
      maxWidth: 520,
      maxHeight: 560,
      child: _TemplateSelectionDialog(templates: activeTemplates),
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
      showAppSnack(
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
    final confirmed = await showErpFormDialog<bool>(
      context,
      maxWidth: 460,
      maxHeight: 300,
      child: _DeleteRunConfirm(run: run),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final repo = context.read<PipelineRunRepository>();
      await repo.deleteRun(run.id);
      await _loadData();
    } catch (e) {
      if (mounted) {
        showAppSnack(
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

    return SoftMasterDataPage(
      title: 'Production',
      subtitle: 'Monitor active production runs and start new pipelines.',
      action: AppButton(
        label: 'Start Production',
        icon: Icons.play_arrow_rounded,
        onPressed: _startProduction,
      ),
      toolbar: const SizedBox.shrink(),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _runs.isEmpty
                ? const AppEmptyState(
                    title: 'No production runs found',
                    message: 'Start a new pipeline to see it here.',
                    icon: Icons.precision_manufacturing_outlined,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Identity
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  run.orderNo != null
                                      ? 'Order: ${run.orderNo}'
                                      : 'Ad-hoc Run',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: SoftErpTheme.textPrimary,
                                  ),
                                ),
                              ),
                              if (run.clientName != null) ...[
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    '• ${run.clientName}',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: SoftErpTheme.textSecondary,
                                    ),
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
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              color: SoftErpTheme.textPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: _LabeledField(
                        label: 'Started',
                        value: run.createdAt.toIso8601String().split('T').first,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Progress + flow dots fill the remaining width.
                    Expanded(flex: 4, child: _buildTimeline(context)),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: Colors.redAccent),
                      tooltip: 'Delete production run',
                      onPressed: onDelete,
                    ),
                  ],
                ),
                if (isStalled) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            size: 14, color: Colors.orange),
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
    final statuses = [
      for (final n in sortedNodes)
        run.nodeStatuses[n.id] ?? NodeRunStatus.pending,
    ];
    final doneCount =
        statuses.where((s) => s == NodeRunStatus.done).length;
    // Full names on hover so the compact dots don't lose stage info.
    final flow = sortedNodes.map((n) => n.name).join('  ➔  ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Text(
              'Pipeline Progress:',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$doneCount/${statuses.length}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Tooltip(
          message: flow,
          child: SizedBox(
            height: 26,
            width: _RunFlowPainter.inset * 2 +
                (statuses.length - 1).clamp(0, 999) * _RunFlowPainter.gap,
            child: CustomPaint(painter: _RunFlowPainter(statuses: statuses)),
          ),
        ),
      ],
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            color: SoftErpTheme.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Compact dot-flow of a run's stages, coloured by live node status. Replaces
/// the old full-width labelled timeline so long pipelines stay readable.
class _RunFlowPainter extends CustomPainter {
  const _RunFlowPainter({required this.statuses});

  final List<NodeRunStatus> statuses;

  static const double inset = 8.0;
  static const double gap = 22.0;

  static Color _statusColor(NodeRunStatus status) => switch (status) {
        NodeRunStatus.done => const Color(0xFF48C7A4),
        NodeRunStatus.active => SoftErpTheme.accent,
        NodeRunStatus.skipped => const Color(0xFF94A3B8),
        NodeRunStatus.pending => const Color(0xFFCBD5E1),
      };

  @override
  void paint(Canvas canvas, Size size) {
    if (statuses.isEmpty) return;
    final y = size.height / 2;
    Offset dotAt(int i) => Offset(inset + gap * i, y);

    // Connectors: green once the upstream stage is done, otherwise faint.
    for (var i = 0; i < statuses.length - 1; i++) {
      final done = statuses[i] == NodeRunStatus.done;
      canvas.drawLine(
        dotAt(i),
        dotAt(i + 1),
        Paint()
          ..color = done ? const Color(0xFF48C7A4) : const Color(0xFFE2DFEA)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }

    final ringPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var i = 0; i < statuses.length; i++) {
      final center = dotAt(i);
      final color = _statusColor(statuses[i]);
      if (statuses[i] == NodeRunStatus.active) {
        canvas.drawCircle(
          center,
          9,
          Paint()..color = color.withValues(alpha: 0.22),
        );
      }
      canvas.drawCircle(center, 5, Paint()..color = color);
      canvas.drawCircle(center, 5, ringPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RunFlowPainter oldDelegate) {
    return !listEquals(oldDelegate.statuses, statuses);
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
    return ErpFormScaffold(
      title: 'Select Pipeline Template',
      subtitle: 'Choose the pipeline this production run will follow.',
      bodyScrollable: false,
      footer: Align(
        alignment: Alignment.centerRight,
        child: AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView.separated(
        itemCount: templates.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final t = templates[index];
          return SoftRowCard(
            onTap: () => Navigator.of(context).pop(t),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: SoftErpTheme.cardSurfaceAlt,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: SoftErpTheme.border),
                    ),
                    child: const Icon(Icons.account_tree_outlined,
                        size: 20, color: SoftErpTheme.accent),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          t.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: SoftErpTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${t.nodes.length} stages',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: SoftErpTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: SoftErpTheme.textSecondary),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DeleteRunConfirm extends StatelessWidget {
  const _DeleteRunConfirm({required this.run});
  final PipelineRun run;

  @override
  Widget build(BuildContext context) {
    final label = run.orderNo != null ? 'Order: ${run.orderNo}' : 'Ad-hoc Run';
    return ErpFormScaffold(
      title: 'Delete Production Run',
      subtitle: 'This permanently removes the run history and cannot be undone.',
      bodyScrollable: false,
      body: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Delete the production run for "$label"?',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: SoftErpTheme.textPrimary,
          ),
        ),
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 44,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                elevation: 1.5,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              child: const Text('Delete',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }
}


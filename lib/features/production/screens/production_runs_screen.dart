import 'package:collection/collection.dart';
import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/core/widgets/app_button.dart';
import 'package:core_erp/core/widgets/app_toast.dart';
import 'package:core_erp/core/widgets/soft_master_data.dart';
import 'package:core_erp/core/widgets/soft_primitives.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:core_erp/features/orders/domain/order_entry.dart';
import 'package:core_erp/features/orders/presentation/providers/orders_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../production_pipelines/data/repositories/pipeline_run_repository.dart';
import '../../production_pipelines/domain/node_run_status.dart';
import '../../production_pipelines/domain/pipeline_run.dart';
import '../../production_pipelines/domain/pipeline_template.dart';
import '../providers/production_provider.dart';
import '../providers/production_run_provider.dart';
import '../widgets/order_picker_dialog.dart';
import 'live_production_monitor_screen.dart';

enum _RunFilter { all, active, stalled, completed }

class ProductionRunsScreen extends StatefulWidget {
  const ProductionRunsScreen({super.key});

  @override
  State<ProductionRunsScreen> createState() => _ProductionRunsScreenState();
}

class _ProductionRunsScreenState extends State<ProductionRunsScreen> {
  bool _isLoading = true;
  String? _error;
  List<PipelineRun> _runs = <PipelineRun>[];
  List<PipelineTemplate> _templates = <PipelineTemplate>[];
  final TextEditingController _searchController = TextEditingController();
  _RunFilter _filter = _RunFilter.all;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<InventoryProvider>().initialize();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final repository = context.read<PipelineRunRepository>();
      final results = await Future.wait([
        repository.getRuns(),
        repository.getTemplates(),
      ]);
      if (!mounted) return;

      final runs = results[0] as List<PipelineRun>;
      final templates = results[1] as List<PipelineTemplate>;
      runs.sort((first, second) {
        final firstActive = !_isCompleted(first.status);
        final secondActive = !_isCompleted(second.status);
        if (firstActive && !secondActive) return -1;
        if (!firstActive && secondActive) return 1;
        return second.createdAt.compareTo(first.createdAt);
      });

      setState(() {
        _runs = runs;
        _templates = templates;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _startProduction() async {
    final activeTemplates = _templates
        .where((template) => template.status != PipelineTemplateStatus.archived)
        .toList(growable: false);
    if (activeTemplates.isEmpty) {
      showAppSnack(
        const SnackBar(
          content: Text(
            'Create an active pipeline template before starting production.',
          ),
        ),
      );
      return;
    }

    final template = await showDialog<PipelineTemplate>(
      context: context,
      builder: (_) => _TemplateSelectionDialog(templates: activeTemplates),
    );
    if (template == null || !mounted) return;

    final order = await showDialog<OrderEntry?>(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<OrdersProvider>(),
        child: const OrderPickerDialog(),
      ),
    );
    if (order == null || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CreatingRunDialog(),
    );
    var loadingDialogVisible = true;

    try {
      final repository = context.read<PipelineRunRepository>();
      final newRun = await repository.createRun(
        template.id,
        orderNo: order.orderNo,
        orderItemId: order.id,
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      loadingDialogVisible = false;

      context.read<ProductionProvider>().loadTemplate(
        template,
        orderId: order.id,
        orderNo: order.orderNo,
        clientName: order.clientName,
      );
      context.read<ProductionRunProvider>().initializeIdleRun(newRun.id);
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LiveProductionMonitorScreen()),
      );
      if (mounted) await _loadData();
    } catch (error) {
      if (!mounted) return;
      if (loadingDialogVisible) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      showAppSnack(
        SnackBar(content: Text('Failed to start production: $error')),
      );
    }
  }

  void _monitorRun(PipelineRun run) {
    final template = _templates.firstWhereOrNull(
      (value) => value.id == run.templateId,
    );
    if (template == null) {
      showAppSnack(
        const SnackBar(
          content: Text('The pipeline template for this run is unavailable.'),
        ),
      );
      return;
    }
    context.read<ProductionProvider>().loadTemplate(
      template,
      orderId: run.orderItemId,
      orderNo: run.orderNo,
      clientName: run.clientName,
    );
    context.read<ProductionRunProvider>().initializeIdleRun(run.id);
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => const LiveProductionMonitorScreen(),
          ),
        )
        .then((_) {
          if (mounted) _loadData();
        });
  }

  Future<void> _deleteRun(PipelineRun run) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: SoftErpTheme.dangerBg,
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Icons.delete_outline_rounded,
                color: SoftErpTheme.dangerText,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Delete production run?')),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Text(
            'This permanently removes ${_runLabel(run)} and its production history. This action cannot be undone.',
            style: const TextStyle(
              color: SoftErpTheme.textSecondary,
              height: 1.45,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: SoftErpTheme.dangerText,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Delete run'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isLoading = true);
    try {
      await context.read<PipelineRunRepository>().deleteRun(run.id);
      await _loadData();
    } catch (error) {
      if (mounted) {
        showAppSnack(SnackBar(content: Text('Failed to delete run: $error')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final presentations = _runs
        .map((run) {
          final template = _templates.firstWhereOrNull(
            (value) => value.id == run.templateId,
          );
          return _RunPresentation(
            run: run,
            template: template,
            stalledMessage: _stalledMessage(run, template, inventory),
          );
        })
        .toList(growable: false);
    final visibleRuns = presentations.where(_matchesCurrentView).toList();

    return SoftMasterDataPage(
      title: 'Production',
      subtitle:
          'Monitor live production, identify blocked work, and launch orders into pipelines.',
      action: AppButton(
        label: 'Start production',
        icon: Icons.play_arrow_rounded,
        onPressed: _startProduction,
      ),
      toolbar: _ProductionToolbar(
        filter: _filter,
        searchController: _searchController,
        allCount: presentations.length,
        activeCount: presentations
            .where((item) => !_isCompleted(item.run.status))
            .length,
        stalledCount: presentations
            .where((item) => item.stalledMessage != null)
            .length,
        completedCount: presentations
            .where((item) => _isCompleted(item.run.status))
            .length,
        onFilterChanged: (value) => setState(() => _filter = value),
        onQueryChanged: (value) => setState(() => _query = value.trim()),
        onRefresh: _loadData,
      ),
      messages: [
        if (_error != null)
          _ProductionError(message: _error!, onRetry: _loadData),
      ],
      body: _isLoading
          ? const _ProductionLoadingState()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ProductionSummary(
                  presentations: presentations,
                  activeTemplateCount: _templates
                      .where(
                        (template) =>
                            template.status != PipelineTemplateStatus.archived,
                      )
                      .length,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: visibleRuns.isEmpty
                      ? _ProductionEmptyState(
                          hasRuns: presentations.isNotEmpty,
                          onStart: _startProduction,
                          onClearFilters: () {
                            _searchController.clear();
                            setState(() {
                              _filter = _RunFilter.all;
                              _query = '';
                            });
                          },
                        )
                      : RefreshIndicator(
                          color: SoftErpTheme.accent,
                          onRefresh: _loadData,
                          child: ListView.separated(
                            padding: const EdgeInsets.only(bottom: 24),
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: visibleRuns.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 12),
                            itemBuilder: (_, index) {
                              final item = visibleRuns[index];
                              return _RunCard(
                                run: item.run,
                                template: item.template,
                                stalledMessage: item.stalledMessage,
                                onMonitor: () => _monitorRun(item.run),
                                onDelete: () => _deleteRun(item.run),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  bool _matchesCurrentView(_RunPresentation presentation) {
    final run = presentation.run;
    final matchesFilter = switch (_filter) {
      _RunFilter.all => true,
      _RunFilter.active => !_isCompleted(run.status),
      _RunFilter.stalled => presentation.stalledMessage != null,
      _RunFilter.completed => _isCompleted(run.status),
    };
    if (!matchesFilter) return false;
    if (_query.isEmpty) return true;
    final haystack = [
      run.id,
      run.name,
      run.orderNo ?? '',
      run.clientName ?? '',
      run.status,
      presentation.template?.name ?? '',
    ].join(' ').toLowerCase();
    return haystack.contains(_query.toLowerCase());
  }

  String? _stalledMessage(
    PipelineRun run,
    PipelineTemplate? template,
    InventoryProvider inventory,
  ) {
    if (_isCompleted(run.status) ||
        template == null ||
        inventory.isLoading ||
        inventory.errorMessage != null) {
      return null;
    }
    final inputNode = template.nodes.firstWhereOrNull((node) {
      final processType = node.processType.trim().toLowerCase();
      final name = node.name.trim().toLowerCase();
      return processType == 'input' ||
          processType == 'input stage' ||
          name == 'input' ||
          name == 'input stage' ||
          name.endsWith(' input');
    });
    if (inputNode?.inputItem == null) return null;
    final materials = inventory.materials.where(
      (material) => material.linkedItemId == inputNode!.inputItem!.itemId,
    );
    final stock = materials.fold<double>(
      0,
      (sum, material) => sum + material.onHand,
    );
    if (stock > 0) return null;
    return '${inputNode!.name} is blocked by insufficient material';
  }
}

class _RunPresentation {
  const _RunPresentation({
    required this.run,
    required this.template,
    required this.stalledMessage,
  });

  final PipelineRun run;
  final PipelineTemplate? template;
  final String? stalledMessage;
}

class _ProductionToolbar extends StatelessWidget {
  const _ProductionToolbar({
    required this.filter,
    required this.searchController,
    required this.allCount,
    required this.activeCount,
    required this.stalledCount,
    required this.completedCount,
    required this.onFilterChanged,
    required this.onQueryChanged,
    required this.onRefresh,
  });

  final _RunFilter filter;
  final TextEditingController searchController;
  final int allCount;
  final int activeCount;
  final int stalledCount;
  final int completedCount;
  final ValueChanged<_RunFilter> onFilterChanged;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return SoftMasterToolbar(
      children: [
        SizedBox(
          width: 290,
          height: 42,
          child: TextField(
            controller: searchController,
            onChanged: onQueryChanged,
            decoration: const InputDecoration(
              hintText: 'Search order, client, or pipeline',
              prefixIcon: Icon(Icons.search_rounded, size: 20),
              contentPadding: EdgeInsets.symmetric(horizontal: 14),
            ),
          ),
        ),
        SoftSegmentedFilter<_RunFilter>(
          selected: filter,
          onChanged: onFilterChanged,
          options: [
            SoftSegmentOption(
              value: _RunFilter.all,
              label: 'All runs',
              count: allCount,
            ),
            SoftSegmentOption(
              value: _RunFilter.active,
              label: 'Active',
              count: activeCount,
            ),
            SoftSegmentOption(
              value: _RunFilter.stalled,
              label: 'Blocked',
              count: stalledCount,
            ),
            SoftSegmentOption(
              value: _RunFilter.completed,
              label: 'Completed',
              count: completedCount,
            ),
          ],
        ),
        SoftIconButton(
          icon: Icons.refresh_rounded,
          tooltip: 'Refresh production runs',
          onTap: onRefresh,
        ),
      ],
    );
  }
}

class _ProductionSummary extends StatelessWidget {
  const _ProductionSummary({
    required this.presentations,
    required this.activeTemplateCount,
  });

  final List<_RunPresentation> presentations;
  final int activeTemplateCount;

  @override
  Widget build(BuildContext context) {
    final active = presentations
        .where((item) => !_isCompleted(item.run.status))
        .length;
    final blocked = presentations
        .where((item) => item.stalledMessage != null)
        .length;
    final completed = presentations
        .where((item) => _isCompleted(item.run.status))
        .length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < 760
            ? (constraints.maxWidth - 10) / 2
            : (constraints.maxWidth - 30) / 4;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _ProductionStat(
              width: width,
              label: 'Active runs',
              value: '$active',
              icon: Icons.play_circle_outline_rounded,
              background: SoftErpTheme.infoBg,
              foreground: SoftErpTheme.infoText,
            ),
            _ProductionStat(
              width: width,
              label: 'Blocked runs',
              value: '$blocked',
              icon: Icons.report_problem_outlined,
              background: SoftErpTheme.warningBg,
              foreground: SoftErpTheme.warningText,
            ),
            _ProductionStat(
              width: width,
              label: 'Completed runs',
              value: '$completed',
              icon: Icons.task_alt_rounded,
              background: SoftErpTheme.successBg,
              foreground: SoftErpTheme.successText,
            ),
            _ProductionStat(
              width: width,
              label: 'Pipeline templates',
              value: '$activeTemplateCount',
              icon: Icons.account_tree_outlined,
              background: SoftErpTheme.accentSoft,
              foreground: SoftErpTheme.accentDark,
            ),
          ],
        );
      },
    );
  }
}

class _ProductionStat extends StatelessWidget {
  const _ProductionStat({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final double width;
  final String label;
  final String value;
  final IconData icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return SoftSurface(
      width: width,
      radius: 18,
      elevated: false,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, size: 20, color: foreground),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: SoftErpTheme.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SoftErpTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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

class _RunCard extends StatelessWidget {
  const _RunCard({
    required this.run,
    required this.template,
    required this.stalledMessage,
    required this.onMonitor,
    required this.onDelete,
  });

  final PipelineRun run;
  final PipelineTemplate? template;
  final String? stalledMessage;
  final VoidCallback onMonitor;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final progress = _progressFor(run, template);
    final stageSummary = _stageSummary(run, template);
    final completed = _isCompleted(run.status);
    final statusColors = _statusColors(run.status, stalledMessage != null);
    return SoftRowCard(
      onTap: onMonitor,
      baseColor: stalledMessage == null
          ? SoftErpTheme.cardSurface
          : const Color(0xFFFFFCF4),
      hoverColor: stalledMessage == null
          ? const Color(0xFFFDFDFF)
          : const Color(0xFFFFF9E9),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: statusColors.$1,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    completed
                        ? Icons.task_alt_rounded
                        : Icons.precision_manufacturing_outlined,
                    color: statusColors.$2,
                    size: 23,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _runLabel(run),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: SoftErpTheme.textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _RunStatusBadge(
                            status: run.status,
                            blocked: stalledMessage != null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (run.clientName?.trim().isNotEmpty == true)
                            run.clientName!.trim(),
                          template?.name ?? 'Pipeline unavailable',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SoftErpTheme.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SoftIconButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: 'Delete production run',
                  iconColor: SoftErpTheme.dangerText,
                  background: SoftErpTheme.dangerBg,
                  borderColor: SoftErpTheme.dangerBg,
                  onTap: onDelete,
                ),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 720;
                final details = Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  children: [
                    _RunDetailPill(
                      icon: Icons.account_tree_outlined,
                      label: '${template?.nodes.length ?? 0} stages',
                    ),
                    _RunDetailPill(
                      icon: Icons.layers_outlined,
                      label: '${run.batches.length} batches',
                    ),
                    _RunDetailPill(
                      icon: Icons.calendar_today_outlined,
                      label: _shortDate(run.startedAt ?? run.createdAt),
                    ),
                  ],
                );
                final action = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      completed ? 'View run' : 'Open monitor',
                      style: const TextStyle(
                        color: SoftErpTheme.accentDark,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      color: SoftErpTheme.accentDark,
                      size: 17,
                    ),
                  ],
                );
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      details,
                      const SizedBox(height: 12),
                      Align(alignment: Alignment.centerRight, child: action),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: details),
                    const SizedBox(width: 12),
                    action,
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    stageSummary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SoftErpTheme.textSecondary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${(progress * 100).round()}%',
                  style: const TextStyle(
                    color: SoftErpTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: SoftErpTheme.border,
                valueColor: AlwaysStoppedAnimation<Color>(
                  completed ? SoftErpTheme.successText : SoftErpTheme.accent,
                ),
              ),
            ),
            if (stalledMessage != null) ...[
              const SizedBox(height: 13),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: SoftErpTheme.warningBg,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.report_problem_outlined,
                      size: 18,
                      color: SoftErpTheme.warningText,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        stalledMessage!,
                        style: const TextStyle(
                          color: SoftErpTheme.warningText,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RunDetailPill extends StatelessWidget {
  const _RunDetailPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SoftPill(
      label: label,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      leading: Icon(icon, size: 14, color: SoftErpTheme.textSecondary),
    );
  }
}

class _RunStatusBadge extends StatelessWidget {
  const _RunStatusBadge({required this.status, required this.blocked});

  final String status;
  final bool blocked;

  @override
  Widget build(BuildContext context) {
    final colors = _statusColors(status, blocked);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: colors.$2, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            blocked ? 'Blocked' : _statusLabel(status),
            style: TextStyle(
              color: colors.$2,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductionEmptyState extends StatelessWidget {
  const _ProductionEmptyState({
    required this.hasRuns,
    required this.onStart,
    required this.onClearFilters,
  });

  final bool hasRuns;
  final VoidCallback onStart;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    return SoftSurface(
      radius: SoftErpTheme.radiusLg,
      padding: const EdgeInsets.all(30),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 470),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: hasRuns
                      ? SoftErpTheme.infoBg
                      : SoftErpTheme.accentSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  hasRuns
                      ? Icons.filter_alt_off_outlined
                      : Icons.precision_manufacturing_outlined,
                  size: 36,
                  color: hasRuns
                      ? SoftErpTheme.infoText
                      : SoftErpTheme.accentDark,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                hasRuns
                    ? 'No runs match this view'
                    : 'Ready to start production',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: SoftErpTheme.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hasRuns
                    ? 'Clear the search or change the run status filter.'
                    : 'Choose a pipeline and sales order to create the first production run.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: SoftErpTheme.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              AppButton(
                label: hasRuns ? 'Clear filters' : 'Start production',
                icon: hasRuns
                    ? Icons.filter_alt_off_outlined
                    : Icons.play_arrow_rounded,
                onPressed: hasRuns ? onClearFilters : onStart,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductionError extends StatelessWidget {
  const _ProductionError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SoftSurface(
      color: SoftErpTheme.dangerBg,
      radius: 14,
      elevated: false,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: SoftErpTheme.dangerText,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: SoftErpTheme.dangerText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _ProductionLoadingState extends StatelessWidget {
  const _ProductionLoadingState();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: List.generate(
            4,
            (index) => Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: index == 3 ? 0 : 10),
                child: const _ProductionSkeleton(height: 70),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const _ProductionSkeleton(height: 168),
        const SizedBox(height: 12),
        const _ProductionSkeleton(height: 168),
      ],
    );
  }
}

class _ProductionSkeleton extends StatelessWidget {
  const _ProductionSkeleton({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFEFF0F6),
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusLg),
        border: Border.all(color: SoftErpTheme.border),
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
      titlePadding: const EdgeInsets.fromLTRB(22, 20, 16, 12),
      contentPadding: const EdgeInsets.fromLTRB(22, 4, 22, 16),
      title: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: SoftErpTheme.accentSoft,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.account_tree_outlined,
              color: SoftErpTheme.accentDark,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Choose a pipeline'),
                SizedBox(height: 3),
                Text(
                  'Select the process this order should follow.',
                  style: TextStyle(
                    color: SoftErpTheme.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          SoftIconButton(
            icon: Icons.close_rounded,
            tooltip: 'Close',
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        height: 350,
        child: ListView.separated(
          itemCount: templates.length,
          separatorBuilder: (_, _) => const SizedBox(height: 9),
          itemBuilder: (_, index) {
            final template = templates[index];
            return SoftRowCard(
              onTap: () => Navigator.pop(context, template),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: SoftErpTheme.infoBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.schema_outlined,
                        color: SoftErpTheme.infoText,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            template.name,
                            style: const TextStyle(
                              color: SoftErpTheme.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${template.nodes.length} stages · ${_statusLabel(template.status.name)}',
                            style: const TextStyle(
                              color: SoftErpTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      color: SoftErpTheme.accentDark,
                      size: 19,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CreatingRunDialog extends StatelessWidget {
  const _CreatingRunDialog();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SoftSurface(
        width: 320,
        radius: 22,
        padding: const EdgeInsets.all(24),
        child: const Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Starting production',
                    style: TextStyle(
                      color: SoftErpTheme.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Creating the run and preparing its stages…',
                    style: TextStyle(
                      color: SoftErpTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

double _progressFor(PipelineRun run, PipelineTemplate? template) {
  if (template == null || template.nodes.isEmpty) {
    return _isCompleted(run.status) ? 1 : 0;
  }
  final complete = template.nodes.where((node) {
    final status = run.nodeStatuses[node.id] ?? NodeRunStatus.pending;
    return status == NodeRunStatus.done || status == NodeRunStatus.skipped;
  }).length;
  return complete / template.nodes.length;
}

String _stageSummary(PipelineRun run, PipelineTemplate? template) {
  if (template == null || template.nodes.isEmpty) {
    return 'No stage data available';
  }
  final activeNode = template.nodes.firstWhereOrNull(
    (node) => run.nodeStatuses[node.id] == NodeRunStatus.active,
  );
  if (activeNode != null) return 'Current stage: ${activeNode.name}';
  final complete = template.nodes.where((node) {
    final status = run.nodeStatuses[node.id] ?? NodeRunStatus.pending;
    return status == NodeRunStatus.done || status == NodeRunStatus.skipped;
  }).length;
  if (complete == template.nodes.length) return 'All stages completed';
  return '$complete of ${template.nodes.length} stages completed';
}

(Color, Color) _statusColors(String status, bool blocked) {
  if (blocked) return (SoftErpTheme.warningBg, SoftErpTheme.warningText);
  final normalized = status.toLowerCase().replaceAll('-', '_');
  if (_isCompleted(normalized)) {
    return (SoftErpTheme.successBg, SoftErpTheme.successText);
  }
  if (normalized == 'in_progress' ||
      normalized == 'running' ||
      normalized == 'active') {
    return (SoftErpTheme.infoBg, SoftErpTheme.infoText);
  }
  if (normalized == 'paused' || normalized == 'delayed') {
    return (SoftErpTheme.warningBg, SoftErpTheme.warningText);
  }
  return (SoftErpTheme.accentSoft, SoftErpTheme.accentDark);
}

bool _isCompleted(String status) {
  final normalized = status.toLowerCase().replaceAll('-', '_');
  return normalized == 'completed' || normalized == 'done';
}

String _statusLabel(String status) {
  final normalized = status.trim().replaceAll('-', ' ').replaceAll('_', ' ');
  if (normalized.isEmpty) return 'Unknown';
  return normalized
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map(
        (part) => '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
      )
      .join(' ');
}

String _runLabel(PipelineRun run) {
  final orderNo = run.orderNo?.trim();
  if (orderNo != null && orderNo.isNotEmpty) return 'Order $orderNo';
  if (run.name.trim().isNotEmpty) return run.name.trim();
  final suffix = run.id.split('-').lastOrNull ?? run.id;
  return 'Production run $suffix';
}

String _shortDate(DateTime date) {
  final local = date.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day-$month-${local.year}';
}

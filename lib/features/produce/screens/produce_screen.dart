import 'package:collection/collection.dart';
import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/core/widgets/app_button.dart';
import 'package:core_erp/core/widgets/app_empty_state.dart';
import 'package:core_erp/core/widgets/app_toast.dart';
import 'package:core_erp/core/widgets/erp_form_dialog.dart';
import 'package:core_erp/core/widgets/searchable_select.dart';
import 'package:core_erp/core/widgets/soft_master_data.dart';
import 'package:core_erp/core/widgets/soft_primitives.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../production_pipelines/domain/node_run_status.dart';
import '../../production_pipelines/domain/pipeline_run.dart';
import '../../production_pipelines/domain/pipeline_template.dart';
import '../../production_pipelines/domain/process_node.dart';
import '../data/produce_sample_data.dart';
import '../data/produce_sandbox_repository.dart';
import 'produce_monitor_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Produce — a UI-only duplicate of the Production tab.
//
// Same chrome, same cards, same filters, and the same live monitor behind a
// card tap. Every row comes from ProduceSandboxRepository, an in-memory store
// seeded from produce_sample_data.dart: no server call is made from this tab,
// and nothing it does outlives the session.
// ─────────────────────────────────────────────────────────────────────────────

class ProduceScreen extends StatefulWidget {
  const ProduceScreen({
    super.key,
    this.initialTab = 'runs',
    this.showTabs = true,
  });

  final String initialTab;
  final bool showTabs;

  @override
  State<ProduceScreen> createState() => _ProduceScreenState();
}

class _ProduceScreenState extends State<ProduceScreen> {
  final ProduceSandboxRepository _sandbox = ProduceSandboxRepository.instance;

  late String _activeTab = widget.initialTab;
  late List<PipelineTemplate> _templates = _sandbox.templatesNow;
  late List<PipelineRun> _runs = _sandbox.sortedRunsNow;
  final Set<String> _stalledRunIds = <String>{...produceSampleStalledRunIds};

  void _reload() {
    setState(() {
      _templates = _sandbox.templatesNow;
      _runs = _sandbox.sortedRunsNow;
    });
  }

  Future<void> _startProduction() async {
    final activeTemplates = _templates
        .where((t) => t.status != PipelineTemplateStatus.archived)
        .toList();
    if (activeTemplates.isEmpty) {
      showAppSnack(
        const SnackBar(
          content: Text('No active templates available to start production.'),
        ),
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

    final draft = await _sandbox.createRun(template.id);
    if (!mounted) return;

    _reload();
    showAppSnack(
      SnackBar(
        content: Text(
          'Preview only — "${template.name}" was added to this list and is not saved.',
        ),
      ),
    );
    await _openMonitor(draft);
  }

  /// Opens the sandbox live monitor for [run]. The monitor writes back into the
  /// same in-memory store, so the list reflects whatever happened in there.
  Future<void> _openMonitor(PipelineRun run) async {
    final template = _templates.where((t) => t.id == run.templateId).firstOrNull;
    if (template == null) {
      showAppSnack(
        const SnackBar(content: Text('That run has no pipeline to monitor.')),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProduceMonitorScreen(run: run, template: template),
      ),
    );
    if (!mounted) return;
    _reload();
  }

  Future<void> _deleteRun(PipelineRun run) async {
    final confirmed = await showErpFormDialog<bool>(
      context,
      maxWidth: 460,
      maxHeight: 300,
      child: _DeleteRunConfirm(run: run),
    );

    if (confirmed != true || !mounted) return;

    await _sandbox.deleteRun(run.id);
    if (!mounted) return;
    _stalledRunIds.remove(run.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return SoftMasterDataPage(
      title: 'Produce',
      action: AppButton(
        label: 'Start Production',
        icon: Icons.play_arrow_rounded,
        onPressed: _startProduction,
      ),
      toolbar: widget.showTabs
          ? SoftMasterToolbar(
              children: [
                SoftSegmentedFilter<String>(
                  selected: _activeTab,
                  onChanged: (val) => setState(() => _activeTab = val),
                  options: const [
                    SoftSegmentOption<String>(value: 'runs', label: 'Runs'),
                    SoftSegmentOption<String>(value: 'insights', label: 'Insights'),
                  ],
                ),
              ],
            )
          : const SizedBox.shrink(),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: _activeTab == 'runs'
            ? _RunsTab(
                key: const ValueKey('produce_runs_tab'),
                runs: _runs,
                templates: _templates,
                stalledRunIds: _stalledRunIds,
                onMonitor: _openMonitor,
                onDelete: _deleteRun,
              )
            : _InsightsTab(
                key: const ValueKey('produce_insights_tab'),
                runs: _runs,
                templates: _templates,
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 0 – Runs list
// ─────────────────────────────────────────────────────────────────────────────

class _RunsTab extends StatelessWidget {
  const _RunsTab({
    super.key,
    required this.runs,
    required this.templates,
    required this.stalledRunIds,
    required this.onMonitor,
    required this.onDelete,
  });

  final List<PipelineRun> runs;
  final List<PipelineTemplate> templates;
  final Set<String> stalledRunIds;
  final void Function(PipelineRun) onMonitor;
  final void Function(PipelineRun) onDelete;

  @override
  Widget build(BuildContext context) {
    if (runs.isEmpty) {
      return const AppEmptyState(
        title: 'No production runs found',
        message: 'Start a new pipeline to see it here.',
        icon: Icons.precision_manufacturing_outlined,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: runs.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final run = runs[index];
        final template = templates.where((t) => t.id == run.templateId).firstOrNull;
        final isActive = run.status != 'completed';

        // The real tab derives this from live inventory; here it is sample state.
        String? stalledMessage;
        if (isActive && template != null && stalledRunIds.contains(run.id)) {
          final inputNode = template.nodes.firstWhereOrNull((n) {
            final pType = n.processType.trim().toLowerCase();
            final name = n.name.trim().toLowerCase();
            return pType == 'input' ||
                pType == 'input stage' ||
                name == 'input' ||
                name == 'input stage' ||
                name.endsWith(' input');
          });
          if (inputNode != null) {
            stalledMessage = '${inputNode.name} stalled due to insufficient material';
          }
        }

        return _RunCard(
          run: run,
          templateName: template?.name ?? 'Unknown Pipeline',
          template: template,
          isActive: isActive,
          stalledMessage: stalledMessage,
          onMonitor: () => onMonitor(run),
          onDelete: () => onDelete(run),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 1 – Insights: filter chips → KPI cards → filtered run cards
// ─────────────────────────────────────────────────────────────────────────────

class _InsightsTab extends StatefulWidget {
  const _InsightsTab({
    super.key,
    required this.runs,
    required this.templates,
  });

  final List<PipelineRun> runs;
  final List<PipelineTemplate> templates;

  @override
  State<_InsightsTab> createState() => _InsightsTabState();
}

class _InsightsTabState extends State<_InsightsTab> {
  String? _filterPipeline; // template id
  String? _filterStatus; // 'active' | 'completed'
  String? _filterClient;
  ProduceDateFilter _filterDate = ProduceDateFilter.allTime;

  List<PipelineRun> get _filtered {
    return widget.runs.where((r) {
      if (_filterPipeline != null && r.templateId != _filterPipeline) return false;
      if (_filterStatus == 'active' && r.status == 'completed') return false;
      if (_filterStatus == 'completed' && r.status != 'completed') return false;
      if (_filterClient != null && r.clientName != _filterClient) return false;
      if (!_filterDate.matches(r.createdAt)) return false;
      return true;
    }).toList();
  }

  _KpiSet get _kpis => _KpiSet.from(_filtered, widget.templates);

  // Clients come from the sample runs only — no clients provider behind this.
  List<String> get _clients {
    final clientSet = <String>{};
    for (final r in widget.runs) {
      if (r.clientName != null && r.clientName!.trim().isNotEmpty) {
        clientSet.add(r.clientName!.trim());
      }
    }
    final list = clientSet.toList()..sort();
    return list;
  }

  bool get _hasFilters =>
      _filterPipeline != null ||
      _filterStatus != null ||
      _filterClient != null ||
      !_filterDate.isAllTime;

  void _clearFilters() => setState(() {
        _filterPipeline = null;
        _filterStatus = null;
        _filterClient = null;
        _filterDate = ProduceDateFilter.allTime;
      });

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final kpis = _kpis;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _InsightsToolbar(
                  templates: widget.templates,
                  clients: _clients,
                  selectedPipeline: _filterPipeline,
                  selectedStatus: _filterStatus,
                  selectedClient: _filterClient,
                  selectedDate: _filterDate,
                  hasFilters: _hasFilters,
                  onPipeline: (v) => setState(() => _filterPipeline = v),
                  onStatus: (v) => setState(() => _filterStatus = v),
                  onClient: (v) => setState(() => _filterClient = v),
                  onDate: (v) => setState(() => _filterDate = v),
                  onClear: _clearFilters,
                ),
              ],
            ),
          ),
        ),

        SliverToBoxAdapter(
          child: _KpiRow(
            kpis: kpis,
            total: filtered.length,
            hasFilters: _hasFilters,
          ),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 20, 0, 10),
            child: Row(
              children: [
                Text(
                  'Runs (${filtered.length})',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: SoftErpTheme.textPrimary,
                    letterSpacing: 0.5,
                  ),
                ),
                if (_hasFilters) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: SoftErpTheme.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Filtered',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: SoftErpTheme.accent,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        if (filtered.isEmpty)
          const SliverFillRemaining(
            child: AppEmptyState(
              title: 'No runs match your filters',
              message: 'Adjust or clear the filters above to see results.',
              icon: Icons.filter_list_off_rounded,
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index.isOdd) return const SizedBox(height: 12);
                final run = filtered[index ~/ 2];
                final template =
                    widget.templates.where((t) => t.id == run.templateId).firstOrNull;
                return _InsightRunCard(
                  run: run,
                  templateName: template?.name ?? 'Unknown Pipeline',
                  template: template,
                );
              },
              childCount: filtered.length * 2 - 1,
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Date filter model (presets & relative shorthand: 12d, -12d, 2w, 1m)
// ─────────────────────────────────────────────────────────────────────────────

class ProduceDateFilter {
  const ProduceDateFilter({
    required this.label,
    this.cutoffDate,
    this.exactDate,
    this.isAllTime = false,
  });

  final String label;
  final DateTime? cutoffDate;
  final DateTime? exactDate;
  final bool isAllTime;

  static const allTime = ProduceDateFilter(label: 'All Time', isAllTime: true);

  bool matches(DateTime date) {
    if (isAllTime) return true;
    if (cutoffDate != null) {
      return date.isAfter(cutoffDate!) || date.isAtSameMomentAs(cutoffDate!);
    }
    if (exactDate != null) {
      return date.year == exactDate!.year &&
          date.month == exactDate!.month &&
          date.day == exactDate!.day;
    }
    return true;
  }

  static ProduceDateFilter? tryParse(String input) {
    final trimmed = input.trim().toLowerCase();
    if (trimmed.isEmpty || trimmed == 'all' || trimmed == 'all time') {
      return allTime;
    }

    final now = DateTime.now();

    final relMatch =
        RegExp(r'^([+-]?\d+(?:\.\d+)?)\s*([dwmyDWMY])(?:\s*ago)?$').firstMatch(trimmed);
    if (relMatch != null) {
      final numStr = relMatch.group(1) ?? '0';
      final unit = (relMatch.group(2) ?? 'd').toLowerCase();
      final numVal = double.tryParse(numStr)?.abs() ?? 0.0;
      if (numVal > 0) {
        final days = switch (unit) {
          'd' => numVal.round(),
          'w' => (numVal * 7).round(),
          'm' => (numVal * 30).round(),
          'y' => (numVal * 365).round(),
          _ => numVal.round(),
        };
        final cutoff = now.subtract(Duration(days: days));
        final unitLabel = switch (unit) {
          'd' => '$days days',
          'w' => '${numVal.round()} weeks',
          'm' => '${numVal.round()} months',
          'y' => '${numVal.round()} years',
          _ => '$days days',
        };
        return ProduceDateFilter(
          label: 'Last $unitLabel (-${numVal.round()}$unit)',
          cutoffDate: cutoff,
        );
      }
    }

    final justNumMatch = RegExp(r'^([+-]?\d+)$').firstMatch(trimmed);
    if (justNumMatch != null) {
      final days = int.tryParse(justNumMatch.group(1) ?? '0')?.abs() ?? 0;
      if (days > 0) {
        final cutoff = now.subtract(Duration(days: days));
        return ProduceDateFilter(
          label: 'Last $days days (-${days}d)',
          cutoffDate: cutoff,
        );
      }
    }

    final dmyMatch = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})$').firstMatch(trimmed);
    if (dmyMatch != null) {
      final day = int.tryParse(dmyMatch.group(1) ?? '');
      final month = int.tryParse(dmyMatch.group(2) ?? '');
      final year = int.tryParse(dmyMatch.group(3) ?? '');
      if (day != null && month != null && year != null) {
        final date = DateTime(year, month, day);
        return ProduceDateFilter(
          label: 'Since $day/$month/$year',
          cutoffDate: date,
        );
      }
    }

    final ymdMatch = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$').firstMatch(trimmed);
    if (ymdMatch != null) {
      final year = int.tryParse(ymdMatch.group(1) ?? '');
      final month = int.tryParse(ymdMatch.group(2) ?? '');
      final day = int.tryParse(ymdMatch.group(3) ?? '');
      if (day != null && month != null && year != null) {
        final date = DateTime(year, month, day);
        return ProduceDateFilter(
          label: 'Since $day/$month/$year',
          cutoffDate: date,
        );
      }
    }

    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Compact filter toolbar — Pipeline, Status, Client, Date
// ─────────────────────────────────────────────────────────────────────────────

class _InsightsToolbar extends StatelessWidget {
  const _InsightsToolbar({
    required this.templates,
    required this.clients,
    required this.selectedPipeline,
    required this.selectedStatus,
    required this.selectedClient,
    required this.selectedDate,
    required this.hasFilters,
    required this.onPipeline,
    required this.onStatus,
    required this.onClient,
    required this.onDate,
    required this.onClear,
  });

  final List<PipelineTemplate> templates;
  final List<String> clients;
  final String? selectedPipeline;
  final String? selectedStatus;
  final String? selectedClient;
  final ProduceDateFilter selectedDate;
  final bool hasFilters;
  final ValueChanged<String?> onPipeline;
  final ValueChanged<String?> onStatus;
  final ValueChanged<String?> onClient;
  final ValueChanged<ProduceDateFilter> onDate;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final selectedPipelineTemplate =
        templates.where((t) => t.id == selectedPipeline).firstOrNull;
    final pipelineLabel =
        selectedPipelineTemplate != null ? selectedPipelineTemplate.name : 'Pipeline';

    final statusLabel = switch (selectedStatus) {
      'active' => 'Active',
      'completed' => 'Completed',
      _ => 'Status',
    };

    final clientLabel = selectedClient ?? 'Client';
    final dateLabel = selectedDate.isAllTime ? 'Date' : selectedDate.label;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SearchFilterButton(
          label: pipelineLabel,
          icon: Icons.account_tree_outlined,
          isActive: selectedPipeline != null,
          onTap: () async {
            final selected = await showSearchableSelectDialog<String?>(
              context: context,
              title: 'Filter by Pipeline',
              searchHintText: 'Search pipeline name...',
              selectedValue: selectedPipeline,
              options: [
                const SearchableSelectOption(value: null, label: 'All pipelines'),
                for (final t in templates)
                  SearchableSelectOption(value: t.id, label: t.name),
              ],
            );
            if (selected != null) {
              onPipeline(selected.value);
            }
          },
        ),
        const SizedBox(width: 8),

        _SearchFilterButton(
          label: statusLabel,
          icon: Icons.circle_outlined,
          isActive: selectedStatus != null,
          onTap: () async {
            final selected = await showSearchableSelectDialog<String?>(
              context: context,
              title: 'Filter by Status',
              searchHintText: 'Search status...',
              selectedValue: selectedStatus,
              options: const [
                SearchableSelectOption(value: null, label: 'All statuses'),
                SearchableSelectOption(value: 'active', label: 'Active'),
                SearchableSelectOption(value: 'completed', label: 'Completed'),
              ],
            );
            if (selected != null) {
              onStatus(selected.value);
            }
          },
        ),
        const SizedBox(width: 8),

        _SearchFilterButton(
          label: clientLabel,
          icon: Icons.person_outline_rounded,
          isActive: selectedClient != null,
          onTap: () async {
            final selected = await showSearchableSelectDialog<String?>(
              context: context,
              title: 'Filter by Client',
              searchHintText: 'Search client name...',
              selectedValue: selectedClient,
              options: [
                const SearchableSelectOption(value: null, label: 'All clients'),
                for (final c in clients)
                  SearchableSelectOption(value: c, label: c),
              ],
            );
            if (selected != null) {
              onClient(selected.value);
            }
          },
        ),
        const SizedBox(width: 8),

        _SearchFilterButton(
          label: dateLabel,
          icon: Icons.calendar_today_outlined,
          isActive: !selectedDate.isAllTime,
          onTap: () async {
            final picked = await _showDateSearchFilterDialog(
              context,
              current: selectedDate,
            );
            if (picked != null) {
              onDate(picked);
            }
          },
        ),

        if (hasFilters) ...[
          const SizedBox(width: 6),
          Tooltip(
            message: 'Clear all filters',
            child: GestureDetector(
              onTap: onClear,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: SoftErpTheme.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.close_rounded, size: 14, color: SoftErpTheme.accent),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SearchFilterButton extends StatelessWidget {
  const _SearchFilterButton({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: isActive
                ? SoftErpTheme.accent.withValues(alpha: 0.08)
                : SoftErpTheme.cardSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive
                  ? SoftErpTheme.accent.withValues(alpha: 0.5)
                  : SoftErpTheme.border,
              width: isActive ? 1.4 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: isActive ? SoftErpTheme.accent : SoftErpTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 130),
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                    color: isActive ? SoftErpTheme.accent : SoftErpTheme.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 14,
                color: isActive ? SoftErpTheme.accent : SoftErpTheme.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Date search filter dialog with shorthand support
// ─────────────────────────────────────────────────────────────────────────────

Future<ProduceDateFilter?> _showDateSearchFilterDialog(
  BuildContext context, {
  required ProduceDateFilter current,
}) {
  return showErpFormDialog<ProduceDateFilter>(
    context,
    maxWidth: 480,
    maxHeight: 520,
    child: _DateSearchFilterDialog(current: current),
  );
}

class _DateSearchFilterDialog extends StatefulWidget {
  const _DateSearchFilterDialog({required this.current});
  final ProduceDateFilter current;

  @override
  State<_DateSearchFilterDialog> createState() => _DateSearchFilterDialogState();
}

class _DateSearchFilterDialogState extends State<_DateSearchFilterDialog> {
  final TextEditingController _controller = TextEditingController();
  ProduceDateFilter? _liveResolved;

  static final List<ProduceDateFilter> _presets = [
    ProduceDateFilter.allTime,
    ProduceDateFilter(
      label: 'Today',
      cutoffDate: DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      ),
    ),
    ProduceDateFilter(
      label: 'Last 7 days (-7d)',
      cutoffDate: DateTime.now().subtract(const Duration(days: 7)),
    ),
    ProduceDateFilter(
      label: 'Last 12 days (-12d)',
      cutoffDate: DateTime.now().subtract(const Duration(days: 12)),
    ),
    ProduceDateFilter(
      label: 'Last 30 days (-30d)',
      cutoffDate: DateTime.now().subtract(const Duration(days: 30)),
    ),
    ProduceDateFilter(
      label: 'Last 3 months (-90d)',
      cutoffDate: DateTime.now().subtract(const Duration(days: 90)),
    ),
    ProduceDateFilter(
      label: 'Last 6 months (-180d)',
      cutoffDate: DateTime.now().subtract(const Duration(days: 180)),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _liveResolved = null);
    } else {
      final parsed = ProduceDateFilter.tryParse(text);
      setState(() => _liveResolved = parsed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = _controller.text.trim();
    final filteredPresets = text.isEmpty
        ? _presets
        : _presets
            .where((p) => p.label.toLowerCase().contains(text.toLowerCase()))
            .toList();

    return ErpFormScaffold(
      title: 'Filter by Date / Relative Time',
      subtitle:
          'Type a shorthand like -12d (12 days ago), 7d, 2w, 1m, or pick a preset.',
      bodyScrollable: false,
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
          if (_liveResolved != null) ...[
            const SizedBox(width: 10),
            AppButton(
              label: 'Apply "${_liveResolved!.label}"',
              onPressed: () => Navigator.of(context).pop(_liveResolved),
            ),
          ],
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: SoftErpTheme.cardSurfaceAlt,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: SoftErpTheme.border),
            ),
            child: TextField(
              controller: _controller,
              autofocus: true,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                icon: const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: SoftErpTheme.textSecondary,
                ),
                hintText: 'Type shorthand (e.g. -12d, 14d, 1m, 15/08/2026)...',
                hintStyle: const TextStyle(
                  fontSize: 13,
                  color: SoftErpTheme.textSecondary,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 16),
                        onPressed: () => _controller.clear(),
                      )
                    : null,
              ),
              onSubmitted: (_) {
                if (_liveResolved != null) {
                  Navigator.of(context).pop(_liveResolved);
                }
              },
            ),
          ),
          const SizedBox(height: 10),

          if (_liveResolved != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF10B981).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: Color(0xFF10B981),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Resolved: ${_liveResolved!.label}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF065F46),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(_liveResolved),
                    child: const Text(
                      'Select ➔',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF047857),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          const Text(
            'Presets & Shortcuts',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: SoftErpTheme.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: ListView.separated(
              itemCount: filteredPresets.length,
              separatorBuilder: (context, index) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final preset = filteredPresets[index];
                final isSelected = widget.current.label == preset.label;
                return SoftRowCard(
                  isSelected: isSelected,
                  onTap: () => Navigator.of(context).pop(preset),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Icon(
                          preset.isAllTime
                              ? Icons.all_inclusive_rounded
                              : Icons.date_range_outlined,
                          size: 16,
                          color: isSelected
                              ? SoftErpTheme.accent
                              : SoftErpTheme.textSecondary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            preset.label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight:
                                  isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isSelected
                                  ? SoftErpTheme.accent
                                  : SoftErpTheme.textPrimary,
                            ),
                          ),
                        ),
                        if (isSelected)
                          const Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: SoftErpTheme.accent,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KPI aggregation model
// ─────────────────────────────────────────────────────────────────────────────

class _KpiSet {
  const _KpiSet({
    required this.totalRuns,
    required this.completedRuns,
    required this.activeRuns,
    required this.avgRecoveryPct,
    required this.totalRawInput,
    required this.totalGoodOutput,
    required this.totalScrap,
    required this.totalRejection,
  });

  final int totalRuns;
  final int completedRuns;
  final int activeRuns;
  final double avgRecoveryPct;
  final double totalRawInput;
  final double totalGoodOutput;
  final double totalScrap;
  final double totalRejection;

  static _KpiSet from(List<PipelineRun> runs, List<PipelineTemplate> templates) {
    int completed = 0, active = 0;
    double rawTotal = 0, goodTotal = 0, scrapTotal = 0, rejTotal = 0;
    int metricsCount = 0;
    double recoverySum = 0;

    for (final run in runs) {
      if (run.status == 'completed') {
        completed++;
      } else {
        active++;
      }

      for (final m in run.nodeMetrics.values) {
        rawTotal += _d(m['inputQty']);
        goodTotal += _d(m['outputQty']);
        scrapTotal += _d(m['scrapQty']);
        rejTotal += _d(m['rejectionQty']);
      }

      final ov = run.overrides;
      final ovIn = _d(ov.toJson()['inputQty']);
      final ovOut = _d(ov.toJson()['goodOutputQty']);
      if (ovIn > 0) {
        rawTotal += ovIn;
        goodTotal += ovOut;
        final rec = ovIn > 0 ? (ovOut / ovIn * 100) : 0.0;
        recoverySum += rec;
        metricsCount++;
      }
    }

    final avgRecovery = metricsCount > 0 ? recoverySum / metricsCount : 0.0;

    return _KpiSet(
      totalRuns: runs.length,
      completedRuns: completed,
      activeRuns: active,
      avgRecoveryPct: avgRecovery,
      totalRawInput: rawTotal,
      totalGoodOutput: goodTotal,
      totalScrap: scrapTotal,
      totalRejection: rejTotal,
    );
  }

  static double _d(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KPI row
// ─────────────────────────────────────────────────────────────────────────────

class _KpiRow extends StatelessWidget {
  const _KpiRow({
    required this.kpis,
    required this.total,
    required this.hasFilters,
  });

  final _KpiSet kpis;
  final int total;
  final bool hasFilters;

  @override
  Widget build(BuildContext context) {
    final recoveryLabel = kpis.totalRawInput > 0
        ? '${(kpis.totalGoodOutput / kpis.totalRawInput * 100).toStringAsFixed(1)}%'
        : '—';

    final filterSub = hasFilters ? 'Across filtered runs' : 'All recorded runs';

    return LayoutBuilder(
      builder: (context, constraints) {
        final tileW = (constraints.maxWidth - 24) / 4;
        return Row(
          children: [
            SizedBox(
              width: tileW,
              child: _KpiCard(
                label: 'Total Runs',
                value: '$total',
                sub: '${kpis.activeRuns} active · ${kpis.completedRuns} done',
                icon: Icons.precision_manufacturing_outlined,
                color: SoftErpTheme.accent,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: tileW,
              child: _KpiCard(
                label: 'Net Recovery',
                value: recoveryLabel,
                sub: 'Good out / raw in',
                icon: Icons.recycling_rounded,
                color: const Color(0xFF10B981),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: tileW,
              child: _KpiCard(
                label: 'Total Scrap',
                value: kpis.totalScrap > 0
                    ? '${kpis.totalScrap.toStringAsFixed(1)} kg'
                    : '—',
                sub: filterSub,
                icon: Icons.delete_sweep_outlined,
                color: const Color(0xFFF59E0B),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: tileW,
              child: _KpiCard(
                label: 'Total Rejection',
                value: kpis.totalRejection > 0
                    ? '${kpis.totalRejection.toStringAsFixed(1)} kg'
                    : '—',
                sub: filterSub,
                icon: Icons.block_rounded,
                color: const Color(0xFFEF4444),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String sub;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: child,
            ),
            child: Text(
              value,
              key: ValueKey('val_$value'),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: SoftErpTheme.textPrimary,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: SoftErpTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: child,
            ),
            child: Text(
              sub,
              key: ValueKey('sub_$sub'),
              style: TextStyle(
                fontSize: 10.5,
                color: SoftErpTheme.textSecondary.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Insight run card (compact, read-only)
// ─────────────────────────────────────────────────────────────────────────────

class _InsightRunCard extends StatelessWidget {
  const _InsightRunCard({
    required this.run,
    required this.templateName,
    this.template,
  });

  final PipelineRun run;
  final String templateName;
  final PipelineTemplate? template;

  @override
  Widget build(BuildContext context) {
    final isCompleted = run.status == 'completed';
    final completedAt = run.completedAt;

    double rawIn = 0, goodOut = 0, scrapOut = 0, rejOut = 0;
    for (final m in run.nodeMetrics.values) {
      rawIn += _d(m['inputQty']);
      goodOut += _d(m['outputQty']);
      scrapOut += _d(m['scrapQty']);
      rejOut += _d(m['rejectionQty']);
    }
    final recovery = rawIn > 0 ? (goodOut / rawIn * 100) : 0.0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCompleted ? Colors.grey.shade400 : SoftErpTheme.accent,
            ),
          ),
          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        run.orderNo != null ? 'Order: ${run.orderNo}' : 'Ad-hoc Run',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: SoftErpTheme.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _StatusBadge(status: run.status, isActive: !isCompleted),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Pipeline: $templateName${run.clientName != null ? '  ·  ${run.clientName}' : ''}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: SoftErpTheme.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),

                Row(
                  children: [
                    if (rawIn > 0) ...[
                      _MetricChip(
                        label: 'Raw In',
                        value: '${rawIn.toStringAsFixed(1)} kg',
                        color: const Color(0xFF6366F1),
                      ),
                      const SizedBox(width: 6),
                      _MetricChip(
                        label: 'Good Out',
                        value: '${goodOut.toStringAsFixed(1)} kg',
                        color: const Color(0xFF10B981),
                      ),
                      const SizedBox(width: 6),
                      if (scrapOut > 0)
                        _MetricChip(
                          label: 'Scrap',
                          value: '${scrapOut.toStringAsFixed(1)} kg',
                          color: const Color(0xFFF59E0B),
                        ),
                      if (scrapOut > 0) const SizedBox(width: 6),
                      if (rejOut > 0)
                        _MetricChip(
                          label: 'Rejection',
                          value: '${rejOut.toStringAsFixed(1)} kg',
                          color: const Color(0xFFEF4444),
                        ),
                      if (rejOut > 0) const SizedBox(width: 6),
                      _MetricChip(
                        label: 'Recovery',
                        value: '${recovery.toStringAsFixed(1)}%',
                        color: recovery >= 80
                            ? const Color(0xFF10B981)
                            : recovery >= 60
                                ? const Color(0xFFF59E0B)
                                : const Color(0xFFEF4444),
                      ),
                    ] else
                      Text(
                        'No mass balance recorded yet',
                        style: TextStyle(
                          fontSize: 11,
                          color: SoftErpTheme.textSecondary.withValues(alpha: 0.7),
                        ),
                      ),
                    const Spacer(),
                    Text(
                      _fmtDate(isCompleted ? completedAt : run.createdAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: SoftErpTheme.textSecondary.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),

                if (template != null && template!.nodes.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _StageDots(run: run, template: template!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static double _d(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  static String _fmtDate(DateTime? dt) {
    if (dt == null) return '—';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: color.withValues(alpha: 0.8),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _StageDots extends StatelessWidget {
  const _StageDots({required this.run, required this.template});
  final PipelineRun run;
  final PipelineTemplate template;

  @override
  Widget build(BuildContext context) {
    final sortedNodes = List<ProcessNode>.from(template.nodes)
      ..sort((a, b) => a.stageIndex.compareTo(b.stageIndex));
    final statuses = [
      for (final n in sortedNodes) run.nodeStatuses[n.id] ?? NodeRunStatus.pending,
    ];
    final doneCount = statuses.where((s) => s == NodeRunStatus.done).length;
    final flow = sortedNodes.map((n) => n.name).join('  ➔  ');

    return Row(
      children: [
        Text(
          'Stages $doneCount/${statuses.length}:',
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Tooltip(
            message: flow,
            child: SizedBox(
              height: 22,
              width: _RunFlowPainter.inset * 2 +
                  (statuses.length - 1).clamp(0, 999) * _RunFlowPainter.gap,
              child: CustomPaint(painter: _RunFlowPainter(statuses: statuses)),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Run card
// ─────────────────────────────────────────────────────────────────────────────

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
    final doneCount = statuses.where((s) => s == NodeRunStatus.done).length;
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

/// Compact dot-flow of a run's stages, coloured by node status.
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
        canvas.drawCircle(center, 9, Paint()..color = color.withValues(alpha: 0.22));
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
    final bgColor =
        isActive ? SoftErpTheme.accent.withValues(alpha: 0.1) : Colors.grey.shade200;

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
        separatorBuilder: (context, index) => const SizedBox(height: 12),
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
      subtitle: 'Preview only — this removes the card from the list, nothing else.',
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

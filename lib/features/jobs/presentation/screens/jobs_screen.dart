import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/core/widgets/app_button.dart';
import 'package:core_erp/core/widgets/app_empty_state.dart';
import 'package:core_erp/core/widgets/soft_master_data.dart';
import 'package:core_erp/core/widgets/soft_primitives.dart';
import 'package:core_erp/features/departments/domain/employee_definition.dart';
import 'package:core_erp/features/departments/presentation/providers/departments_provider.dart';
import 'package:core_erp/shared/widgets/exact_item_variation_select_field.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/freelancer_job.dart';
import '../../../production/widgets/output_item_picker_dialog.dart';
import '../providers/jobs_provider.dart';
import '../utils/job_card_printer.dart';

enum _JobsView { spreadsheet, batches }

enum _JobFilter { all, unassigned, active, completed }

class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key});

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  _JobsView _view = _JobsView.spreadsheet;
  _JobFilter _filter = _JobFilter.all;
  final Set<int> _selectedJobIds = <int>{};
  final TextEditingController _searchController = TextEditingController();
  int? _selectedFreelancerId;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    await Future.wait<void>([
      context.read<JobsProvider>().fetchJobsData(),
      context.read<DepartmentsProvider>().load(),
    ]);
    if (!mounted) return;
    final validUnassigned = context
        .read<JobsProvider>()
        .jobs
        .where((job) => job.batchId == null)
        .map((job) => job.id)
        .toSet();
    setState(() => _selectedJobIds.retainAll(validUnassigned));
  }

  Future<void> _assignBatch() async {
    final freelancerId = _selectedFreelancerId;
    if (freelancerId == null || _selectedJobIds.isEmpty) {
      _showMessage('Choose a freelancer and at least one unassigned job.');
      return;
    }

    try {
      await context.read<JobsProvider>().createBatchAndAssign(
        freelancerId,
        _selectedJobIds.toList(growable: false),
      );
      if (!mounted) return;
      setState(() {
        _selectedJobIds.clear();
        _selectedFreelancerId = null;
      });
      _showMessage('Batch assigned successfully.');
    } catch (error) {
      if (mounted) {
        _showMessage('Could not assign batch: $error', isError: true);
      }
    }
  }

  Future<void> _createManualJob() async {
    final selected = await showDialog<ExactItemVariationReference>(
      context: context,
      builder: (_) => const OutputItemPickerDialog(),
    );
    if (selected == null || !mounted) return;

    final quantityController = TextEditingController(text: '1');
    final quantity = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create assembly job'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Set the number of finished units required from this item.',
                style: TextStyle(
                  color: SoftErpTheme.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: quantityController,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Quantity',
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                  suffixText: 'units',
                ),
                onSubmitted: (value) =>
                    Navigator.pop(dialogContext, int.tryParse(value)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(
              dialogContext,
              int.tryParse(quantityController.text),
            ),
            icon: const Icon(Icons.add_task_rounded, size: 18),
            label: const Text('Create job'),
          ),
        ],
      ),
    );
    quantityController.dispose();

    if (quantity == null || quantity <= 0 || !mounted) return;
    try {
      await context.read<JobsProvider>().createJob(selected.itemId, quantity);
      if (mounted) _showMessage('Assembly job created.');
    } catch (error) {
      if (mounted) _showMessage('Could not create job: $error', isError: true);
    }
  }

  Future<void> _updateStatus(FreelancerJob job, String status) async {
    if (job.status == status) return;
    try {
      await context.read<JobsProvider>().updateJobStatus(job.id, status);
      if (mounted) {
        _showMessage('Job #${job.id} marked ${_statusLabel(status)}.');
      }
    } catch (error) {
      if (mounted) _showMessage('Could not update job: $error', isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError
              ? SoftErpTheme.dangerText
              : SoftErpTheme.textPrimary,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final jobsProvider = context.watch<JobsProvider>();
    final departmentsProvider = context.watch<DepartmentsProvider>();
    final freelancers = departmentsProvider.employees
        .where((employee) => employee.employmentType == 'freelancer')
        .toList(growable: false);
    final jobs = jobsProvider.jobs;
    final visibleJobs = _filterJobs(jobs);

    return SoftMasterDataPage(
      title: 'Freelancer jobs',
      subtitle:
          'Bundle assembly work into batches, assign it to freelancers, and track progress and payouts.',
      action: AppButton(
        label: 'Create job',
        icon: Icons.add_rounded,
        onPressed: _createManualJob,
      ),
      toolbar: _JobsToolbar(
        view: _view,
        filter: _filter,
        queryController: _searchController,
        allCount: jobs.length,
        unassignedCount: jobs.where((job) => job.batchId == null).length,
        activeCount: jobs.where((job) => !_isComplete(job.status)).length,
        completedCount: jobs.where((job) => _isComplete(job.status)).length,
        onViewChanged: (value) => setState(() => _view = value),
        onFilterChanged: (value) => setState(() => _filter = value),
        onQueryChanged: (value) => setState(() => _query = value.trim()),
        onRefresh: _refresh,
      ),
      messages: [
        if (jobsProvider.error != null)
          _ErrorBanner(message: jobsProvider.error!, onRetry: _refresh),
        if (departmentsProvider.errorMessage != null)
          _ErrorBanner(
            message: departmentsProvider.errorMessage!,
            onRetry: _refresh,
          ),
      ],
      body: jobsProvider.isLoading || departmentsProvider.isLoading
          ? const _JobsLoadingState()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SummaryStrip(
                  jobs: jobs,
                  batches: jobsProvider.batches,
                  freelancers: freelancers,
                ),
                const SizedBox(height: 14),
                _AssignmentBar(
                  selectedCount: _selectedJobIds.length,
                  selectedFreelancerId: _selectedFreelancerId,
                  freelancers: freelancers,
                  onFreelancerChanged: (value) =>
                      setState(() => _selectedFreelancerId = value),
                  onAssign: _assignBatch,
                  onClear: () => setState(_selectedJobIds.clear),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: _view == _JobsView.spreadsheet
                      ? _SpreadsheetView(
                          jobs: visibleJobs,
                          allJobs: jobs,
                          tasks: jobsProvider.tasks,
                          batches: jobsProvider.batches,
                          freelancers: freelancers,
                          selectedJobIds: _selectedJobIds,
                          onSelectionChanged: _setJobSelected,
                          onSelectAll: _selectAllVisible,
                          onStatusChanged: _updateStatus,
                          onOpenDetails: _showJobDetails,
                          onPrint: _printJobCardFor,
                        )
                      : _BatchBoardView(
                          jobs: visibleJobs,
                          allJobs: jobs,
                          tasks: jobsProvider.tasks,
                          batches: jobsProvider.batches,
                          freelancers: freelancers,
                          selectedJobIds: _selectedJobIds,
                          onSelectionChanged: _setJobSelected,
                          onStatusChanged: _updateStatus,
                          onOpenDetails: _showJobDetails,
                          onPrintBatch: _printBatch,
                        ),
                ),
              ],
            ),
    );
  }

  List<FreelancerJob> _filterJobs(List<FreelancerJob> jobs) {
    return jobs
        .where((job) {
          final matchesFilter = switch (_filter) {
            _JobFilter.all => true,
            _JobFilter.unassigned => job.batchId == null,
            _JobFilter.active => !_isComplete(job.status),
            _JobFilter.completed => _isComplete(job.status),
          };
          if (!matchesFilter) return false;
          if (_query.isEmpty) return true;
          final haystack =
              '${job.id} ${job.itemId} ${job.batchId ?? ''} ${job.status}'
                  .toLowerCase();
          return haystack.contains(_query.toLowerCase());
        })
        .toList(growable: false);
  }

  void _setJobSelected(FreelancerJob job, bool selected) {
    if (job.batchId != null) return;
    setState(() {
      if (selected) {
        _selectedJobIds.add(job.id);
      } else {
        _selectedJobIds.remove(job.id);
      }
    });
  }

  void _selectAllVisible(List<FreelancerJob> jobs, bool selected) {
    final selectableIds = jobs
        .where((job) => job.batchId == null)
        .map((job) => job.id);
    setState(() {
      if (selected) {
        _selectedJobIds.addAll(selectableIds);
      } else {
        _selectedJobIds.removeAll(selectableIds);
      }
    });
  }

  void _printJobCardFor(
    FreelancerJob job,
    List<FreelancerJobBatch> batches,
    List<EmployeeDefinition> freelancers,
    List<FreelancerJob> jobs,
  ) {
    final batch = _firstWhereOrNull(
      batches,
      (value) => value.id == job.batchId,
    );
    if (batch == null) {
      _showMessage('This job has not been assigned to a batch yet.');
      return;
    }
    _printBatch(batch, freelancers, jobs);
  }

  void _printBatch(
    FreelancerJobBatch batch,
    List<EmployeeDefinition> freelancers,
    List<FreelancerJob> jobs,
  ) {
    final freelancer = _firstWhereOrNull(
      freelancers,
      (value) => value.id == batch.freelancerId,
    );
    if (freelancer == null) {
      _showMessage('The freelancer assigned to this batch is unavailable.');
      return;
    }
    final batchJobs = jobs
        .where((job) => job.batchId == batch.id)
        .toList(growable: false);
    JobCardPrinter.printJobCard(freelancer, batch.batchNumber, batchJobs);
  }

  void _showJobDetails(FreelancerJob job, List<FreelancerJobTask> tasks) {
    final jobTasks = tasks.where((task) => task.jobId == job.id).toList();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Expanded(child: Text('Job #${job.id}')),
            _StatusBadge(status: job.status),
          ],
        ),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _InfoPill(
                    icon: Icons.inventory_2_outlined,
                    label: 'Item #${job.itemId}',
                  ),
                  _InfoPill(
                    icon: Icons.numbers_rounded,
                    label: '${job.quantity} units',
                  ),
                  _InfoPill(
                    icon: Icons.account_balance_wallet_outlined,
                    label: _money(job.payoutBalance),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const Text(
                'Assembly items',
                style: TextStyle(
                  color: SoftErpTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              if (jobTasks.isEmpty)
                const _InlineEmpty(
                  icon: Icons.inventory_2_outlined,
                  message: 'No inventory items are attached to this job.',
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: jobTasks.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final task = jobTasks[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: SoftErpTheme.accentSoft,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.widgets_outlined,
                            size: 19,
                            color: SoftErpTheme.accentDark,
                          ),
                        ),
                        title: Text('Inventory item #${task.itemId}'),
                        subtitle: Text(_statusLabel(task.status)),
                        trailing: Text(
                          '${_formatQuantity(task.requiredQuantity)} required',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _JobsToolbar extends StatelessWidget {
  const _JobsToolbar({
    required this.view,
    required this.filter,
    required this.queryController,
    required this.allCount,
    required this.unassignedCount,
    required this.activeCount,
    required this.completedCount,
    required this.onViewChanged,
    required this.onFilterChanged,
    required this.onQueryChanged,
    required this.onRefresh,
  });

  final _JobsView view;
  final _JobFilter filter;
  final TextEditingController queryController;
  final int allCount;
  final int unassignedCount;
  final int activeCount;
  final int completedCount;
  final ValueChanged<_JobsView> onViewChanged;
  final ValueChanged<_JobFilter> onFilterChanged;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return SoftMasterToolbar(
      children: [
        SizedBox(
          width: 270,
          height: 42,
          child: TextField(
            controller: queryController,
            onChanged: onQueryChanged,
            decoration: const InputDecoration(
              hintText: 'Search job, item, or batch',
              prefixIcon: Icon(Icons.search_rounded, size: 20),
              contentPadding: EdgeInsets.symmetric(horizontal: 14),
            ),
          ),
        ),
        SoftSegmentedFilter<_JobFilter>(
          selected: filter,
          onChanged: onFilterChanged,
          options: [
            SoftSegmentOption(
              value: _JobFilter.all,
              label: 'All',
              count: allCount,
            ),
            SoftSegmentOption(
              value: _JobFilter.unassigned,
              label: 'Unassigned',
              count: unassignedCount,
            ),
            SoftSegmentOption(
              value: _JobFilter.active,
              label: 'Active',
              count: activeCount,
            ),
            SoftSegmentOption(
              value: _JobFilter.completed,
              label: 'Done',
              count: completedCount,
            ),
          ],
        ),
        SoftSegmentedFilter<_JobsView>(
          selected: view,
          onChanged: onViewChanged,
          options: const [
            SoftSegmentOption(
              value: _JobsView.spreadsheet,
              label: 'Spreadsheet',
            ),
            SoftSegmentOption(value: _JobsView.batches, label: 'Batch board'),
          ],
        ),
        SoftIconButton(
          icon: Icons.refresh_rounded,
          tooltip: 'Refresh jobs',
          onTap: onRefresh,
        ),
      ],
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.jobs,
    required this.batches,
    required this.freelancers,
  });

  final List<FreelancerJob> jobs;
  final List<FreelancerJobBatch> batches;
  final List<EmployeeDefinition> freelancers;

  @override
  Widget build(BuildContext context) {
    final unassigned = jobs.where((job) => job.batchId == null).length;
    final active = jobs.where((job) => !_isComplete(job.status)).length;
    final payout = jobs.fold<double>(0, (sum, job) => sum + job.payoutBalance);
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = constraints.maxWidth < 760
            ? (constraints.maxWidth - 10) / 2
            : (constraints.maxWidth - 30) / 4;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _SummaryTile(
              width: tileWidth,
              icon: Icons.pending_actions_rounded,
              label: 'Unassigned jobs',
              value: '$unassigned',
              tone: _Tone.warning,
            ),
            _SummaryTile(
              width: tileWidth,
              icon: Icons.construction_rounded,
              label: 'Active jobs',
              value: '$active',
              tone: _Tone.info,
            ),
            _SummaryTile(
              width: tileWidth,
              icon: Icons.layers_outlined,
              label: 'Job batches',
              value: '${batches.length}',
              tone: _Tone.accent,
            ),
            _SummaryTile(
              width: tileWidth,
              icon: Icons.account_balance_wallet_outlined,
              label: '${freelancers.length} freelancers',
              value: _money(payout),
              tone: _Tone.success,
            ),
          ],
        );
      },
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
  });

  final double width;
  final IconData icon;
  final String label;
  final String value;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final colors = _toneColors(tone);
    return SoftSurface(
      width: width,
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      elevated: false,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.$1,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, size: 20, color: colors.$2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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

class _AssignmentBar extends StatelessWidget {
  const _AssignmentBar({
    required this.selectedCount,
    required this.selectedFreelancerId,
    required this.freelancers,
    required this.onFreelancerChanged,
    required this.onAssign,
    required this.onClear,
  });

  final int selectedCount;
  final int? selectedFreelancerId;
  final List<EmployeeDefinition> freelancers;
  final ValueChanged<int?> onFreelancerChanged;
  final VoidCallback onAssign;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return SoftSurface(
      color: selectedCount > 0
          ? SoftErpTheme.accentSurface
          : SoftErpTheme.cardSurface,
      radius: 18,
      elevated: false,
      strongBorder: selectedCount > 0,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final selector = SizedBox(
            width: compact ? constraints.maxWidth : 280,
            height: 44,
            child: DropdownButtonFormField<int>(
              key: ValueKey<int?>(selectedFreelancerId),
              initialValue:
                  freelancers.any((item) => item.id == selectedFreelancerId)
                  ? selectedFreelancerId
                  : null,
              decoration: const InputDecoration(
                hintText: 'Choose freelancer',
                prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                contentPadding: EdgeInsets.symmetric(horizontal: 12),
              ),
              items: freelancers
                  .map(
                    (freelancer) => DropdownMenuItem<int>(
                      value: freelancer.id,
                      child: Text(
                        freelancer.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: freelancers.isEmpty ? null : onFreelancerChanged,
            ),
          );
          final selection = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  color: SoftErpTheme.accentSoft,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$selectedCount',
                  style: const TextStyle(
                    color: SoftErpTheme.accentDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'jobs selected',
                style: TextStyle(
                  color: SoftErpTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          );
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selectedCount > 0)
                TextButton(onPressed: onClear, child: const Text('Clear')),
              AppButton(
                label: 'Assign as batch',
                icon: Icons.assignment_ind_outlined,
                variant: selectedCount > 0 && selectedFreelancerId != null
                    ? AppButtonVariant.primary
                    : AppButtonVariant.secondary,
                onPressed: selectedCount > 0 && selectedFreelancerId != null
                    ? onAssign
                    : null,
              ),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                selection,
                const SizedBox(height: 10),
                selector,
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }
          return Row(
            children: [
              selection,
              const SizedBox(width: 18),
              selector,
              const Spacer(),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _SpreadsheetView extends StatelessWidget {
  const _SpreadsheetView({
    required this.jobs,
    required this.allJobs,
    required this.tasks,
    required this.batches,
    required this.freelancers,
    required this.selectedJobIds,
    required this.onSelectionChanged,
    required this.onSelectAll,
    required this.onStatusChanged,
    required this.onOpenDetails,
    required this.onPrint,
  });

  final List<FreelancerJob> jobs;
  final List<FreelancerJob> allJobs;
  final List<FreelancerJobTask> tasks;
  final List<FreelancerJobBatch> batches;
  final List<EmployeeDefinition> freelancers;
  final Set<int> selectedJobIds;
  final void Function(FreelancerJob, bool) onSelectionChanged;
  final void Function(List<FreelancerJob>, bool) onSelectAll;
  final void Function(FreelancerJob, String) onStatusChanged;
  final void Function(FreelancerJob, List<FreelancerJobTask>) onOpenDetails;
  final void Function(
    FreelancerJob,
    List<FreelancerJobBatch>,
    List<EmployeeDefinition>,
    List<FreelancerJob>,
  )
  onPrint;

  @override
  Widget build(BuildContext context) {
    if (jobs.isEmpty) {
      return const AppEmptyState(
        title: 'No jobs match this view',
        message: 'Create a job or change the active filter.',
        icon: Icons.work_outline_rounded,
      );
    }
    final selectable = jobs.where((job) => job.batchId == null).toList();
    final allSelected =
        selectable.isNotEmpty &&
        selectable.every((job) => selectedJobIds.contains(job.id));
    return SoftSurface(
      padding: EdgeInsets.zero,
      radius: SoftErpTheme.radiusLg,
      clipContent: true,
      child: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: DataTable(
              headingRowHeight: 48,
              dataRowMinHeight: 58,
              dataRowMaxHeight: 66,
              horizontalMargin: 16,
              columnSpacing: 28,
              headingRowColor: const WidgetStatePropertyAll(
                SoftErpTheme.cardSurfaceAlt,
              ),
              dividerThickness: 0.7,
              columns: [
                DataColumn(
                  label: Checkbox(
                    value: allSelected,
                    onChanged: selectable.isEmpty
                        ? null
                        : (value) => onSelectAll(jobs, value ?? false),
                  ),
                ),
                const DataColumn(label: Text('JOB')),
                const DataColumn(label: Text('ASSEMBLY OUTPUT')),
                const DataColumn(label: Text('ITEMS REQUIRED')),
                const DataColumn(label: Text('BATCH / FREELANCER')),
                const DataColumn(label: Text('STATUS')),
                const DataColumn(label: Text('PAYOUT'), numeric: true),
                const DataColumn(label: Text('ACTIONS')),
              ],
              rows: jobs
                  .map((job) {
                    final jobTasks = tasks
                        .where((task) => task.jobId == job.id)
                        .toList();
                    final batch = _firstWhereOrNull(
                      batches,
                      (value) => value.id == job.batchId,
                    );
                    final freelancer = _firstWhereOrNull(
                      freelancers,
                      (value) => value.id == batch?.freelancerId,
                    );
                    final assigned = job.batchId != null;
                    return DataRow(
                      selected: selectedJobIds.contains(job.id),
                      onSelectChanged: assigned
                          ? null
                          : (value) => onSelectionChanged(job, value ?? false),
                      cells: [
                        DataCell(
                          assigned
                              ? const Tooltip(
                                  message: 'Already assigned',
                                  child: Icon(
                                    Icons.check_circle_rounded,
                                    color: SoftErpTheme.successText,
                                    size: 20,
                                  ),
                                )
                              : Checkbox(
                                  value: selectedJobIds.contains(job.id),
                                  onChanged: (value) =>
                                      onSelectionChanged(job, value ?? false),
                                ),
                        ),
                        DataCell(
                          Text(
                            '#${job.id}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        DataCell(
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Item #${job.itemId}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${job.quantity} units',
                                style: const TextStyle(
                                  color: SoftErpTheme.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        DataCell(
                          InkWell(
                            onTap: () => onOpenDetails(job, tasks),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${jobTasks.length} ${jobTasks.length == 1 ? 'item' : 'items'}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    size: 18,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          batch == null
                              ? const Text(
                                  'Unassigned',
                                  style: TextStyle(
                                    color: SoftErpTheme.textSecondary,
                                  ),
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      batch.batchNumber,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      freelancer?.name ??
                                          'Freelancer unavailable',
                                      style: const TextStyle(
                                        color: SoftErpTheme.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                        DataCell(
                          _StatusMenu(
                            job: job,
                            onChanged: (status) => onStatusChanged(job, status),
                          ),
                        ),
                        DataCell(
                          Text(
                            _money(job.payoutBalance),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SoftIconButton(
                                icon: Icons.visibility_outlined,
                                tooltip: 'View job items',
                                onTap: () => onOpenDetails(job, tasks),
                              ),
                              if (assigned) ...[
                                const SizedBox(width: 6),
                                SoftIconButton(
                                  icon: Icons.print_outlined,
                                  tooltip: 'Print job card',
                                  onTap: () => onPrint(
                                    job,
                                    batches,
                                    freelancers,
                                    allJobs,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    );
                  })
                  .toList(growable: false),
            ),
          ),
        ),
      ),
    );
  }
}

class _BatchBoardView extends StatelessWidget {
  const _BatchBoardView({
    required this.jobs,
    required this.allJobs,
    required this.tasks,
    required this.batches,
    required this.freelancers,
    required this.selectedJobIds,
    required this.onSelectionChanged,
    required this.onStatusChanged,
    required this.onOpenDetails,
    required this.onPrintBatch,
  });

  final List<FreelancerJob> jobs;
  final List<FreelancerJob> allJobs;
  final List<FreelancerJobTask> tasks;
  final List<FreelancerJobBatch> batches;
  final List<EmployeeDefinition> freelancers;
  final Set<int> selectedJobIds;
  final void Function(FreelancerJob, bool) onSelectionChanged;
  final void Function(FreelancerJob, String) onStatusChanged;
  final void Function(FreelancerJob, List<FreelancerJobTask>) onOpenDetails;
  final void Function(
    FreelancerJobBatch,
    List<EmployeeDefinition>,
    List<FreelancerJob>,
  )
  onPrintBatch;

  @override
  Widget build(BuildContext context) {
    final unassigned = jobs.where((job) => job.batchId == null).toList();
    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BoardColumn(
              title: 'Unassigned pool',
              subtitle: '${unassigned.length} jobs ready to batch',
              icon: Icons.inbox_outlined,
              tone: _Tone.warning,
              child: unassigned.isEmpty
                  ? const _InlineEmpty(
                      icon: Icons.task_alt_rounded,
                      message: 'No unassigned jobs in this view.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: unassigned.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, index) {
                        final job = unassigned[index];
                        return _JobBoardCard(
                          job: job,
                          taskCount: tasks
                              .where((task) => task.jobId == job.id)
                              .length,
                          selected: selectedJobIds.contains(job.id),
                          selectable: true,
                          onSelected: (value) => onSelectionChanged(job, value),
                          onOpen: () => onOpenDetails(job, tasks),
                          onStatusChanged: (value) =>
                              onStatusChanged(job, value),
                        );
                      },
                    ),
            ),
            const SizedBox(width: 14),
            ...freelancers.map((freelancer) {
              final freelancerBatches = batches
                  .where((batch) => batch.freelancerId == freelancer.id)
                  .where((batch) => jobs.any((job) => job.batchId == batch.id))
                  .toList(growable: false);
              final assignedJobCount = jobs
                  .where(
                    (job) => freelancerBatches.any(
                      (batch) => batch.id == job.batchId,
                    ),
                  )
                  .length;
              return Padding(
                padding: const EdgeInsets.only(right: 14),
                child: _BoardColumn(
                  title: freelancer.name,
                  subtitle:
                      '${freelancerBatches.length} batches · $assignedJobCount jobs',
                  icon: Icons.person_outline_rounded,
                  tone: _Tone.info,
                  child: freelancerBatches.isEmpty
                      ? const _InlineEmpty(
                          icon: Icons.layers_clear_outlined,
                          message: 'No batches in this view.',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: freelancerBatches.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, index) {
                            final batch = freelancerBatches[index];
                            final batchJobs = jobs
                                .where((job) => job.batchId == batch.id)
                                .toList(growable: false);
                            return _BatchCard(
                              batch: batch,
                              jobs: batchJobs,
                              tasks: tasks,
                              onPrint: () =>
                                  onPrintBatch(batch, freelancers, allJobs),
                              onOpenJob: (job) => onOpenDetails(job, tasks),
                              onStatusChanged: onStatusChanged,
                            );
                          },
                        ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _BoardColumn extends StatelessWidget {
  const _BoardColumn({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tone,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final _Tone tone;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = _toneColors(tone);
    return SoftSurface(
      width: 330,
      padding: EdgeInsets.zero,
      radius: SoftErpTheme.radiusLg,
      clipContent: true,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            color: SoftErpTheme.cardSurfaceAlt,
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: colors.$1,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 20, color: colors.$2),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SoftErpTheme.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SoftErpTheme.textSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _JobBoardCard extends StatelessWidget {
  const _JobBoardCard({
    required this.job,
    required this.taskCount,
    required this.selected,
    required this.selectable,
    required this.onSelected,
    required this.onOpen,
    required this.onStatusChanged,
  });

  final FreelancerJob job;
  final int taskCount;
  final bool selected;
  final bool selectable;
  final ValueChanged<bool> onSelected;
  final VoidCallback onOpen;
  final ValueChanged<String> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    return SoftRowCard(
      isSelected: selected,
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (selectable) ...[
                  Checkbox(
                    value: selected,
                    onChanged: (value) => onSelected(value ?? false),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    'Job #${job.id}',
                    style: const TextStyle(
                      color: SoftErpTheme.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _StatusMenu(job: job, onChanged: onStatusChanged),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Item #${job.itemId}',
              style: const TextStyle(
                color: SoftErpTheme.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _MiniMetric(
                  icon: Icons.numbers_rounded,
                  label: '${job.quantity} units',
                ),
                const SizedBox(width: 12),
                _MiniMetric(
                  icon: Icons.widgets_outlined,
                  label: '$taskCount items',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BatchCard extends StatelessWidget {
  const _BatchCard({
    required this.batch,
    required this.jobs,
    required this.tasks,
    required this.onPrint,
    required this.onOpenJob,
    required this.onStatusChanged,
  });

  final FreelancerJobBatch batch;
  final List<FreelancerJob> jobs;
  final List<FreelancerJobTask> tasks;
  final VoidCallback onPrint;
  final ValueChanged<FreelancerJob> onOpenJob;
  final void Function(FreelancerJob, String) onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final completed = jobs.where((job) => _isComplete(job.status)).length;
    final progress = jobs.isEmpty ? 0.0 : completed / jobs.length;
    final payout = jobs.fold<double>(0, (sum, job) => sum + job.payoutBalance);
    return SoftSurface(
      padding: const EdgeInsets.all(13),
      radius: 18,
      elevated: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  batch.batchNumber,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SoftErpTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              SoftIconButton(
                icon: Icons.print_outlined,
                tooltip: 'Print job card',
                size: 32,
                onTap: onPrint,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 7,
                    backgroundColor: SoftErpTheme.border,
                    valueColor: const AlwaysStoppedAnimation(
                      SoftErpTheme.successText,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$completed/${jobs.length}',
                style: const TextStyle(
                  color: SoftErpTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _MiniMetric(
                icon: Icons.work_outline,
                label: '${jobs.length} jobs',
              ),
              const Spacer(),
              Text(
                _money(payout),
                style: const TextStyle(
                  color: SoftErpTheme.successText,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          ...jobs.map(
            (job) => InkWell(
              onTap: () => onOpenJob(job),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Job #${job.id} · Item #${job.itemId}',
                            style: const TextStyle(
                              color: SoftErpTheme.textPrimary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${tasks.where((task) => task.jobId == job.id).length} items · ${job.quantity} units',
                            style: const TextStyle(
                              color: SoftErpTheme.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _StatusMenu(
                      job: job,
                      compact: true,
                      onChanged: (status) => onStatusChanged(job, status),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusMenu extends StatelessWidget {
  const _StatusMenu({
    required this.job,
    required this.onChanged,
    this.compact = false,
  });

  final FreelancerJob job;
  final ValueChanged<String> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Update status',
      onSelected: onChanged,
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'pending', child: Text('Pending')),
        PopupMenuItem(value: 'in_progress', child: Text('In progress')),
        PopupMenuItem(value: 'completed', child: Text('Completed')),
      ],
      child: _StatusBadge(status: job.status, compact: compact),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, this.compact = false});

  final String status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tone = _statusTone(status);
    final colors = _toneColors(tone);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
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
            _statusLabel(status),
            style: TextStyle(
              color: colors.$2,
              fontSize: compact ? 10 : 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: 3),
            Icon(Icons.keyboard_arrow_down_rounded, size: 15, color: colors.$2),
          ],
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SoftPill(
      label: label,
      leading: Icon(icon, size: 16, color: SoftErpTheme.textSecondary),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: SoftErpTheme.textSecondary),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: SoftErpTheme.textSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: SoftErpTheme.textSecondary),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: SoftErpTheme.textSecondary,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

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

class _JobsLoadingState extends StatelessWidget {
  const _JobsLoadingState();

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
                child: const _Skeleton(height: 70),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const _Skeleton(height: 68),
        const SizedBox(height: 14),
        const Expanded(child: _Skeleton()),
      ],
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({this.height});

  final double? height;

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

enum _Tone { accent, info, success, warning, danger, neutral }

(Color, Color) _toneColors(_Tone tone) => switch (tone) {
  _Tone.accent => (SoftErpTheme.accentSoft, SoftErpTheme.accentDark),
  _Tone.info => (SoftErpTheme.infoBg, SoftErpTheme.infoText),
  _Tone.success => (SoftErpTheme.successBg, SoftErpTheme.successText),
  _Tone.warning => (SoftErpTheme.warningBg, SoftErpTheme.warningText),
  _Tone.danger => (SoftErpTheme.dangerBg, SoftErpTheme.dangerText),
  _Tone.neutral => (SoftErpTheme.cardSurfaceAlt, SoftErpTheme.textSecondary),
};

_Tone _statusTone(String status) {
  final normalized = status.toLowerCase().replaceAll('-', '_');
  if (normalized == 'completed' || normalized == 'done') return _Tone.success;
  if (normalized == 'in_progress' ||
      normalized == 'active' ||
      normalized == 'assigned') {
    return _Tone.info;
  }
  if (normalized == 'cancelled' || normalized == 'failed') return _Tone.danger;
  if (normalized == 'pending' || normalized == 'queued') return _Tone.warning;
  return _Tone.neutral;
}

bool _isComplete(String status) {
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

String _money(double value) => '₹${value.toStringAsFixed(2)}';

String _formatQuantity(double value) {
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);
}

T? _firstWhereOrNull<T>(Iterable<T> values, bool Function(T) test) {
  for (final value in values) {
    if (test(value)) return value;
  }
  return null;
}

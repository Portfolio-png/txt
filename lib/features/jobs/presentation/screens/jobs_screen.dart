import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/core/widgets/app_button.dart';
import 'package:core_erp/core/widgets/app_empty_state.dart';
import 'package:core_erp/core/widgets/app_toast.dart';
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

    final jobsErr = context.read<JobsProvider>().error;
    if (jobsErr != null) {
      _showMessage(jobsErr, isError: true);
    }

    final depsErr = context.read<DepartmentsProvider>().errorMessage;
    if (depsErr != null) {
      _showMessage(depsErr, isError: true);
    }

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
    final jobsProvider = context.read<JobsProvider>();
    final freelancers = context
        .read<DepartmentsProvider>()
        .employees
        .where((employee) => employee.employmentType == 'freelancer')
        .toList(growable: false);

    final draft = await showDialog<_CreateJobDraft>(
      context: context,
      builder: (_) => _CreateJobDialog(
        jobs: jobsProvider.jobs,
        tasks: jobsProvider.tasks,
        batches: jobsProvider.batches,
        freelancers: freelancers,
        onStatusChanged: _updateStatus,
        onOpenDetails: _showJobDetails,
        onPrintBatch: _printBatch,
      ),
    );
    if (draft == null || !mounted) return;
    try {
      await context.read<JobsProvider>().createJob(
        draft.output.itemId,
        draft.quantity,
      );
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
    String cleanMessage = message;
    if (isError && cleanMessage.startsWith('Exception: ')) {
      cleanMessage = cleanMessage.substring(11).trim();
    }
    
    showAppToast(
      context,
      cleanMessage,
      kind: isError ? AppToastKind.error : AppToastKind.success,
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
      body: jobsProvider.isLoading || departmentsProvider.isLoading
          ? const _JobsLoadingState()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SummaryStrip(
                  jobs: jobs,
                  tasks: jobsProvider.tasks,
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
                'Raw material picking list',
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
          AppButton(
            label: 'Close',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.pop(dialogContext),
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
    required this.tasks,
    required this.batches,
    required this.freelancers,
  });

  final List<FreelancerJob> jobs;
  final List<FreelancerJobTask> tasks;
  final List<FreelancerJobBatch> batches;
  final List<EmployeeDefinition> freelancers;

  @override
  Widget build(BuildContext context) {
    final unassigned = jobs.where((job) => job.batchId == null).length;
    final active = jobs.where((job) => !_isComplete(job.status)).length;
    final jobIds = jobs.map((job) => job.id).toSet();
    final materialPickLines = tasks
        .where((task) => jobIds.contains(task.jobId))
        .length;
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
              label: '${batches.length} job batches',
              value: '$materialPickLines picks',
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
    final selectedFreelancer = _firstWhereOrNull(
      freelancers,
      (freelancer) => freelancer.id == selectedFreelancerId,
    );
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
                        _freelancerMenuLabel(freelancer),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: freelancers.isEmpty ? null : onFreelancerChanged,
            ),
          );
          final selection = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
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
              ),
              if (selectedFreelancer != null) ...[
                const SizedBox(height: 6),
                _FreelancerIdentityPill(freelancer: selectedFreelancer),
              ],
            ],
          );
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selectedCount > 0)
                AppButton(
                  label: 'Clear',
                  variant: AppButtonVariant.secondary,
                  onPressed: onClear,
                ),
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

class _FreelancerIdentityPill extends StatelessWidget {
  const _FreelancerIdentityPill({required this.freelancer});

  final EmployeeDefinition freelancer;

  @override
  Widget build(BuildContext context) {
    final barcode = freelancer.barcodeId.trim();
    final hasBarcode = barcode.isNotEmpty;
    return SoftPill(
      label: hasBarcode ? barcode : 'Barcode missing',
      leading: Icon(
        Icons.qr_code_2_rounded,
        size: 15,
        color: hasBarcode ? SoftErpTheme.accentDark : SoftErpTheme.warningText,
      ),
      background: hasBarcode
          ? SoftErpTheme.accentSurface
          : SoftErpTheme.warningBg,
      foreground: hasBarcode
          ? SoftErpTheme.accentDark
          : SoftErpTheme.warningText,
      borderColor: hasBarcode
          ? SoftErpTheme.accentSoft
          : SoftErpTheme.warningBg,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    );
  }
}

String _freelancerMenuLabel(EmployeeDefinition freelancer) {
  final barcode = freelancer.barcodeId.trim();
  if (barcode.isEmpty) return freelancer.name;
  return '${freelancer.name} · $barcode';
}

String _freelancerBoardSubtitle(
  EmployeeDefinition freelancer,
  int batchCount,
  int jobCount,
) {
  final barcode = freelancer.barcodeId.trim();
  final base = '$batchCount batches · $jobCount jobs';
  if (barcode.isEmpty) return base;
  return '$base · $barcode';
}

String _freelancerBrowserSubtitle(
  EmployeeDefinition freelancer,
  int batchCount,
  int jobCount,
) {
  final barcode = freelancer.barcodeId.trim();
  final identity = barcode.isEmpty ? 'no barcode' : barcode;
  return '$jobCount jobs · $batchCount batches · $identity';
}

List<FreelancerJobBatch> _batchesForFreelancer(
  EmployeeDefinition freelancer,
  List<FreelancerJobBatch> batches,
  List<FreelancerJob> jobs,
) {
  return batches
      .where((batch) => batch.freelancerId == freelancer.id)
      .where((batch) => jobs.any((job) => job.batchId == batch.id))
      .toList(growable: false);
}

List<FreelancerJob> _jobsForBatches(
  List<FreelancerJob> jobs,
  List<FreelancerJobBatch> batches,
) {
  final batchIds = batches.map((batch) => batch.id).toSet();
  return jobs
      .where((job) => job.batchId != null && batchIds.contains(job.batchId))
      .toList(growable: false);
}

_BrowserWorkSelection? _resolveWorkSelection(
  _BrowserWorkSelection? selection,
  List<FreelancerJobBatch> batches,
  List<FreelancerJob> jobs,
) {
  if (selection == null) return null;
  if (selection.isBatch) {
    return batches.any((batch) => batch.id == selection.id) ? selection : null;
  }
  return jobs.any((job) => job.id == selection.id) ? selection : null;
}

List<FreelancerJob> _jobsForSelection(
  _BrowserWorkSelection? selection,
  List<FreelancerJob> jobs,
  List<FreelancerJobBatch> batches,
) {
  if (selection == null) return const <FreelancerJob>[];
  if (selection.isBatch) {
    return jobs
        .where((job) => job.batchId == selection.id)
        .toList(growable: false);
  }
  return jobs.where((job) => job.id == selection.id).toList(growable: false);
}

class _SpreadsheetView extends StatefulWidget {
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
  State<_SpreadsheetView> createState() => _SpreadsheetViewState();
}

class _SpreadsheetViewState extends State<_SpreadsheetView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.jobs.isEmpty) {
      return const AppEmptyState(
        title: 'No jobs match this view',
        message: 'Create a job or change the active filter.',
        icon: Icons.work_outline_rounded,
      );
    }
    final selectable = widget.jobs.where((job) => job.batchId == null).toList();
    final allSelected =
        selectable.isNotEmpty &&
        selectable.every((job) => widget.selectedJobIds.contains(job.id));
    return SoftSurface(
      padding: EdgeInsets.zero,
      radius: SoftErpTheme.radiusLg,
      clipContent: true,
      child: Scrollbar(
        thumbVisibility: true,
        controller: _scrollController,
        child: SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: DataTable(
              headingRowHeight: 48,
              dataRowMinHeight: 64,
              dataRowMaxHeight: 78,
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
                        : (value) => widget.onSelectAll(widget.jobs, value ?? false),
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
              rows: widget.jobs
                  .map((job) {
                    final jobTasks = widget.tasks
                        .where((task) => task.jobId == job.id)
                        .toList();
                    final batch = _firstWhereOrNull(
                      widget.batches,
                      (value) => value.id == job.batchId,
                    );
                    final freelancer = _firstWhereOrNull(
                      widget.freelancers,
                      (value) => value.id == batch?.freelancerId,
                    );
                    final assigned = job.batchId != null;
                    return DataRow(
                      selected: widget.selectedJobIds.contains(job.id),
                      onSelectChanged: assigned
                          ? null
                          : (value) => widget.onSelectionChanged(job, value ?? false),
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
                                  value: widget.selectedJobIds.contains(job.id),
                                  onChanged: (value) =>
                                      widget.onSelectionChanged(job, value ?? false),
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
                            onTap: () => widget.onOpenDetails(job, widget.tasks),
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
                                    if ((freelancer?.barcodeId ?? '')
                                        .trim()
                                        .isNotEmpty)
                                      Text(
                                        freelancer!.barcodeId,
                                        style: const TextStyle(
                                          color: SoftErpTheme.accentDark,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                  ],
                                ),
                        ),
                        DataCell(
                          _StatusMenu(
                            job: job,
                            onChanged: (status) => widget.onStatusChanged(job, status),
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
                                onTap: () => widget.onOpenDetails(job, widget.tasks),
                              ),
                              if (assigned) ...[
                                const SizedBox(width: 6),
                                SoftIconButton(
                                  icon: Icons.print_outlined,
                                  tooltip: 'Print job card',
                                  onTap: () => widget.onPrint(
                                    job,
                                    widget.batches,
                                    widget.freelancers,
                                    widget.allJobs,
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

class _CreateJobDraft {
  const _CreateJobDraft({required this.output, required this.quantity});

  final ExactItemVariationReference output;
  final int quantity;
}

class _CreateJobDialog extends StatefulWidget {
  const _CreateJobDialog({
    required this.jobs,
    required this.tasks,
    required this.batches,
    required this.freelancers,
    required this.onStatusChanged,
    required this.onOpenDetails,
    required this.onPrintBatch,
  });

  final List<FreelancerJob> jobs;
  final List<FreelancerJobTask> tasks;
  final List<FreelancerJobBatch> batches;
  final List<EmployeeDefinition> freelancers;
  final void Function(FreelancerJob, String) onStatusChanged;
  final void Function(FreelancerJob, List<FreelancerJobTask>) onOpenDetails;
  final void Function(
    FreelancerJobBatch,
    List<EmployeeDefinition>,
    List<FreelancerJob>,
  )
  onPrintBatch;

  @override
  State<_CreateJobDialog> createState() => _CreateJobDialogState();
}

class _CreateJobDialogState extends State<_CreateJobDialog> {
  final TextEditingController _quantityController = TextEditingController(
    text: '1',
  );
  ExactItemVariationReference? _output;

  int? get _quantity {
    final value = int.tryParse(_quantityController.text.trim());
    if (value == null || value <= 0) return null;
    return value;
  }

  @override
  void initState() {
    super.initState();
    _quantityController.addListener(_handleQuantityChanged);
  }

  @override
  void dispose() {
    _quantityController.removeListener(_handleQuantityChanged);
    _quantityController.dispose();
    super.dispose();
  }

  void _handleQuantityChanged() {
    setState(() {});
  }

  Future<void> _pickOutputItem() async {
    final selected = await showDialog<ExactItemVariationReference>(
      context: context,
      builder: (_) => const OutputItemPickerDialog(),
    );
    if (selected == null || !mounted) return;
    setState(() => _output = selected);
  }

  void _submit() {
    final output = _output;
    final quantity = _quantity;
    if (output == null || quantity == null) return;
    Navigator.of(
      context,
    ).pop(_CreateJobDraft(output: output, quantity: quantity));
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = _output != null && _quantity != null;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusLg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1560, maxHeight: 800),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: SoftErpTheme.accentSoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.add_task_rounded,
                      color: SoftErpTheme.accentDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Create freelancer job',
                          style: TextStyle(
                            color: SoftErpTheme.textPrimary,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Browse freelancer workload, inspect assigned inventory picks, then create the next assembly job.',
                          style: TextStyle(
                            color: SoftErpTheme.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SoftIconButton(
                    icon: Icons.close_rounded,
                    tooltip: 'Close',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _FreelancerColumnBrowser(
                        jobs: widget.jobs,
                        allJobs: widget.jobs,
                        tasks: widget.tasks,
                        batches: widget.batches,
                        freelancers: widget.freelancers,
                        onStatusChanged: widget.onStatusChanged,
                        onOpenDetails: widget.onOpenDetails,
                        onPrintBatch: widget.onPrintBatch,
                      ),
                    ),
                    const SizedBox(width: 14),
                    SizedBox(
                      width: 330,
                      child: _CreateJobComposer(
                        output: _output,
                        quantityController: _quantityController,
                        canCreate: canCreate,
                        onPickOutput: _pickOutputItem,
                        onCreate: _submit,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateJobComposer extends StatelessWidget {
  const _CreateJobComposer({
    required this.output,
    required this.quantityController,
    required this.canCreate,
    required this.onPickOutput,
    required this.onCreate,
  });

  final ExactItemVariationReference? output;
  final TextEditingController quantityController;
  final bool canCreate;
  final VoidCallback onPickOutput;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final outputLabel = output == null
        ? 'No output item selected'
        : [
            output!.itemLabel,
            output!.variationPathLabel,
          ].where((part) => part.trim().isNotEmpty).join(' / ');
    return SoftSurface(
      padding: const EdgeInsets.all(16),
      radius: SoftErpTheme.radiusLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'New assembly job',
            style: TextStyle(
              color: SoftErpTheme.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Create jobs here. Assign unassigned jobs as a batch from the main Jobs screen.',
            style: TextStyle(
              color: SoftErpTheme.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          _InspectorMetric(
            icon: Icons.inventory_2_outlined,
            label: 'Output item',
            value: outputLabel,
          ),
          AppButton(
            label: output == null ? 'Choose output item' : 'Change output item',
            icon: Icons.search_rounded,
            variant: AppButtonVariant.secondary,
            onPressed: onPickOutput,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: quantityController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Quantity',
              prefixIcon: Icon(Icons.numbers_rounded),
              suffixText: 'units',
            ),
          ),
          const Spacer(),
          AppButton(
            label: 'Create job',
            icon: Icons.add_task_rounded,
            onPressed: canCreate ? onCreate : null,
          ),
        ],
      ),
    );
  }
}

enum _BrowserWorkType { batch, job }

class _BrowserWorkSelection {
  const _BrowserWorkSelection.batch(this.id) : type = _BrowserWorkType.batch;
  const _BrowserWorkSelection.job(this.id) : type = _BrowserWorkType.job;

  final _BrowserWorkType type;
  final int id;

  bool get isBatch => type == _BrowserWorkType.batch;

  bool matches(_BrowserWorkType type, int id) =>
      this.type == type && this.id == id;
}

class _FreelancerColumnBrowser extends StatefulWidget {
  const _FreelancerColumnBrowser({
    required this.jobs,
    required this.allJobs,
    required this.tasks,
    required this.batches,
    required this.freelancers,
    required this.onStatusChanged,
    required this.onOpenDetails,
    required this.onPrintBatch,
  });

  final List<FreelancerJob> jobs;
  final List<FreelancerJob> allJobs;
  final List<FreelancerJobTask> tasks;
  final List<FreelancerJobBatch> batches;
  final List<EmployeeDefinition> freelancers;
  final void Function(FreelancerJob, String) onStatusChanged;
  final void Function(FreelancerJob, List<FreelancerJobTask>) onOpenDetails;
  final void Function(
    FreelancerJobBatch,
    List<EmployeeDefinition>,
    List<FreelancerJob>,
  )
  onPrintBatch;

  @override
  State<_FreelancerColumnBrowser> createState() =>
      _FreelancerColumnBrowserState();
}

class _FreelancerColumnBrowserState extends State<_FreelancerColumnBrowser> {
  final ScrollController _scrollController = ScrollController();
  int? _selectedFreelancerId;
  _BrowserWorkSelection? _selectedWork;
  int? _selectedTaskId;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.freelancers.isEmpty) {
      return const AppEmptyState(
        title: 'No freelancers available',
        message: 'Create freelancer employees first, then assign job batches.',
        icon: Icons.person_off_outlined,
      );
    }

    final selectedFreelancer =
        _firstWhereOrNull(
          widget.freelancers,
          (freelancer) => freelancer.id == _selectedFreelancerId,
        ) ??
        widget.freelancers.first;
    final selectedFreelancerId = selectedFreelancer.id;
    final freelancerBatches = _batchesForFreelancer(
      selectedFreelancer,
      widget.batches,
      widget.jobs,
    );
    final freelancerJobs = _jobsForBatches(widget.jobs, freelancerBatches);
    final selectedWork = _resolveWorkSelection(
      _selectedWork,
      freelancerBatches,
      freelancerJobs,
    );
    final selectedJobs = _jobsForSelection(
      selectedWork,
      widget.jobs,
      freelancerBatches,
    );
    final selectedJobIds = selectedJobs.map((job) => job.id).toSet();
    final pickLines = widget.tasks
        .where((task) => selectedJobIds.contains(task.jobId))
        .toList(growable: false);
    final selectedTask = _firstWhereOrNull(
      pickLines,
      (task) => task.id == _selectedTaskId,
    );

    return SoftSurface(
      padding: EdgeInsets.zero,
      radius: SoftErpTheme.radiusLg,
      clipContent: true,
      child: Scrollbar(
        thumbVisibility: true,
        controller: _scrollController,
        child: SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _BoardColumn(
                width: 290,
                title: 'Freelancers',
                subtitle: '${widget.freelancers.length} barcode identities',
                icon: Icons.people_alt_outlined,
                tone: _Tone.accent,
                child: _FreelancerColumn(
                  freelancers: widget.freelancers,
                  jobs: widget.jobs,
                  batches: widget.batches,
                  selectedFreelancerId: selectedFreelancerId,
                  onSelected: (freelancer) {
                    setState(() {
                      _selectedFreelancerId = freelancer.id;
                      _selectedWork = null;
                      _selectedTaskId = null;
                    });
                  },
                ),
              ),
              _BrowserDivider(),
              _BoardColumn(
                width: 350,
                title: selectedFreelancer.name,
                subtitle: _freelancerBoardSubtitle(
                  selectedFreelancer,
                  freelancerBatches.length,
                  freelancerJobs.length,
                ),
                icon: Icons.folder_copy_outlined,
                tone: _Tone.info,
                child: _AssignedWorkColumn(
                  freelancer: selectedFreelancer,
                  jobs: freelancerJobs,
                  batches: freelancerBatches,
                  tasks: widget.tasks,
                  selectedWork: selectedWork,
                  onSelected: (selection) {
                    setState(() {
                      _selectedWork = selection;
                      _selectedTaskId = null;
                    });
                  },
                  onStatusChanged: widget.onStatusChanged,
                ),
              ),
              _BrowserDivider(),
              _BoardColumn(
                width: 350,
                title: 'Inventory picks',
                subtitle: selectedWork == null
                    ? 'Select a batch or job'
                    : '${pickLines.length} required item lines',
                icon: Icons.inventory_2_outlined,
                tone: _Tone.warning,
                child: _InventoryPickColumn(
                  selectedWork: selectedWork,
                  jobs: selectedJobs,
                  tasks: pickLines,
                  selectedTaskId: selectedTask?.id,
                  onSelected: (task) =>
                      setState(() => _selectedTaskId = task.id),
                ),
              ),
              _BrowserDivider(),
              _BoardColumn(
                width: 340,
                title: 'Inspector',
                subtitle: selectedTask == null
                    ? 'Work summary'
                    : 'Inventory item #${selectedTask.itemId}',
                icon: Icons.view_sidebar_outlined,
                tone: _Tone.success,
                child: _BrowserInspector(
                  freelancer: selectedFreelancer,
                  selectedWork: selectedWork,
                  selectedJobs: selectedJobs,
                  selectedTask: selectedTask,
                  tasks: pickLines,
                  batches: widget.batches,
                  allJobs: widget.allJobs,
                  allTasks: widget.tasks,
                  freelancers: widget.freelancers,
                  onOpenDetails: widget.onOpenDetails,
                  onPrintBatch: widget.onPrintBatch,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FreelancerColumn extends StatelessWidget {
  const _FreelancerColumn({
    required this.freelancers,
    required this.jobs,
    required this.batches,
    required this.selectedFreelancerId,
    required this.onSelected,
  });

  final List<EmployeeDefinition> freelancers;
  final List<FreelancerJob> jobs;
  final List<FreelancerJobBatch> batches;
  final int selectedFreelancerId;
  final ValueChanged<EmployeeDefinition> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(10),
      itemCount: freelancers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final freelancer = freelancers[index];
        final freelancerBatches = _batchesForFreelancer(
          freelancer,
          batches,
          jobs,
        );
        final assignedJobs = _jobsForBatches(jobs, freelancerBatches);
        return _ColumnBrowserTile(
          selected: freelancer.id == selectedFreelancerId,
          icon: Icons.person_outline_rounded,
          title: freelancer.name,
          subtitle: _freelancerBrowserSubtitle(
            freelancer,
            freelancerBatches.length,
            assignedJobs.length,
          ),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: SoftErpTheme.textSecondary,
          ),
          onTap: () => onSelected(freelancer),
        );
      },
    );
  }
}

class _AssignedWorkColumn extends StatelessWidget {
  const _AssignedWorkColumn({
    required this.freelancer,
    required this.jobs,
    required this.batches,
    required this.tasks,
    required this.selectedWork,
    required this.onSelected,
    required this.onStatusChanged,
  });

  final EmployeeDefinition freelancer;
  final List<FreelancerJob> jobs;
  final List<FreelancerJobBatch> batches;
  final List<FreelancerJobTask> tasks;
  final _BrowserWorkSelection? selectedWork;
  final ValueChanged<_BrowserWorkSelection> onSelected;
  final void Function(FreelancerJob, String) onStatusChanged;

  @override
  Widget build(BuildContext context) {
    if (batches.isEmpty && jobs.isEmpty) {
      return const _InlineEmpty(
        icon: Icons.folder_off_outlined,
        message: 'No assigned batches or jobs for this freelancer.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        if (batches.isNotEmpty) ...[
          const _BrowserSectionLabel('Batches'),
          const SizedBox(height: 6),
          ...batches.map((batch) {
            final batchJobs = jobs
                .where((job) => job.batchId == batch.id)
                .toList(growable: false);
            final jobIds = batchJobs.map((job) => job.id).toSet();
            final pickCount = tasks
                .where((task) => jobIds.contains(task.jobId))
                .length;
            final payout = batchJobs.fold<double>(
              0,
              (sum, job) => sum + job.payoutBalance,
            );
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _ColumnBrowserTile(
                selected:
                    selectedWork?.matches(_BrowserWorkType.batch, batch.id) ??
                    false,
                icon: Icons.folder_outlined,
                title: batch.batchNumber,
                subtitle:
                    '${batchJobs.length} jobs · $pickCount picks · ${_money(payout)}',
                badge: _StatusBadge(status: batch.status, compact: true),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: SoftErpTheme.textSecondary,
                ),
                onTap: () => onSelected(_BrowserWorkSelection.batch(batch.id)),
              ),
            );
          }),
          const SizedBox(height: 8),
        ],
        if (jobs.isNotEmpty) ...[
          const _BrowserSectionLabel('Jobs'),
          const SizedBox(height: 6),
          ...jobs.map((job) {
            final batch = _firstWhereOrNull(
              batches,
              (value) => value.id == job.batchId,
            );
            final pickCount = tasks
                .where((task) => task.jobId == job.id)
                .length;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _ColumnBrowserTile(
                selected:
                    selectedWork?.matches(_BrowserWorkType.job, job.id) ??
                    false,
                icon: Icons.assignment_outlined,
                title: 'Job #${job.id}',
                subtitle:
                    '${batch?.batchNumber ?? 'No batch'} · Item #${job.itemId} · $pickCount picks',
                badge: _StatusMenu(
                  job: job,
                  compact: true,
                  onChanged: (status) => onStatusChanged(job, status),
                ),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: SoftErpTheme.textSecondary,
                ),
                onTap: () => onSelected(_BrowserWorkSelection.job(job.id)),
              ),
            );
          }),
        ],
      ],
    );
  }
}

class _InventoryPickColumn extends StatelessWidget {
  const _InventoryPickColumn({
    required this.selectedWork,
    required this.jobs,
    required this.tasks,
    required this.selectedTaskId,
    required this.onSelected,
  });

  final _BrowserWorkSelection? selectedWork;
  final List<FreelancerJob> jobs;
  final List<FreelancerJobTask> tasks;
  final int? selectedTaskId;
  final ValueChanged<FreelancerJobTask> onSelected;

  @override
  Widget build(BuildContext context) {
    if (selectedWork == null) {
      return const _InlineEmpty(
        icon: Icons.touch_app_outlined,
        message: 'Select a batch or job to reveal its inventory items.',
      );
    }
    if (tasks.isEmpty) {
      return const _InlineEmpty(
        icon: Icons.inventory_2_outlined,
        message: 'No inventory items are attached to this selection.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(10),
      itemCount: tasks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final task = tasks[index];
        final job = _firstWhereOrNull(jobs, (value) => value.id == task.jobId);
        return _ColumnBrowserTile(
          selected: task.id == selectedTaskId,
          icon: Icons.widgets_outlined,
          title: 'Inventory item #${task.itemId}',
          subtitle:
              'Job #${task.jobId} · ${_formatQuantity(task.requiredQuantity)} required${job == null ? '' : ' · ${job.quantity} units'}',
          badge: _StatusBadge(status: task.status, compact: true),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: SoftErpTheme.textSecondary,
          ),
          onTap: () => onSelected(task),
        );
      },
    );
  }
}

class _BrowserInspector extends StatelessWidget {
  const _BrowserInspector({
    required this.freelancer,
    required this.selectedWork,
    required this.selectedJobs,
    required this.selectedTask,
    required this.tasks,
    required this.batches,
    required this.allJobs,
    required this.allTasks,
    required this.freelancers,
    required this.onOpenDetails,
    required this.onPrintBatch,
  });

  final EmployeeDefinition freelancer;
  final _BrowserWorkSelection? selectedWork;
  final List<FreelancerJob> selectedJobs;
  final FreelancerJobTask? selectedTask;
  final List<FreelancerJobTask> tasks;
  final List<FreelancerJobBatch> batches;
  final List<FreelancerJob> allJobs;
  final List<FreelancerJobTask> allTasks;
  final List<EmployeeDefinition> freelancers;
  final void Function(FreelancerJob, List<FreelancerJobTask>) onOpenDetails;
  final void Function(
    FreelancerJobBatch,
    List<EmployeeDefinition>,
    List<FreelancerJob>,
  )
  onPrintBatch;

  @override
  Widget build(BuildContext context) {
    if (selectedWork == null) {
      return _InspectorEmpty(
        title: freelancer.name,
        message: 'Choose a batch or job to inspect its material requirements.',
      );
    }

    final task = selectedTask;
    if (task != null) {
      final job = _firstWhereOrNull(allJobs, (value) => value.id == task.jobId);
      final batch = job == null
          ? null
          : _firstWhereOrNull(batches, (value) => value.id == job.batchId);
      return _InspectorPanel(
        title: 'Inventory item #${task.itemId}',
        subtitle: 'Required for Job #${task.jobId}',
        children: [
          _InspectorMetric(
            icon: Icons.inventory_2_outlined,
            label: 'Required quantity',
            value: _formatQuantity(task.requiredQuantity),
          ),
          _InspectorMetric(
            icon: Icons.fact_check_outlined,
            label: 'Pick status',
            value: _statusLabel(task.status),
          ),
          if (job != null)
            _InspectorMetric(
              icon: Icons.assignment_outlined,
              label: 'Assembly output',
              value: 'Item #${job.itemId} · ${job.quantity} units',
            ),
          if (batch != null)
            _InspectorMetric(
              icon: Icons.folder_outlined,
              label: 'Batch',
              value: batch.batchNumber,
            ),
          const SizedBox(height: 14),
          if (job != null)
            AppButton(
              label: 'Open job details',
              icon: Icons.visibility_outlined,
              variant: AppButtonVariant.secondary,
              onPressed: () => onOpenDetails(job, allTasks),
            ),
          if (batch != null) ...[
            const SizedBox(height: 8),
            AppButton(
              label: 'Print job card',
              icon: Icons.print_outlined,
              onPressed: () => onPrintBatch(batch, freelancers, allJobs),
            ),
          ],
        ],
      );
    }

    final jobIds = selectedJobs.map((job) => job.id).toSet();
    final payout = selectedJobs.fold<double>(
      0,
      (sum, job) => sum + job.payoutBalance,
    );
    final completed = selectedJobs
        .where((job) => _isComplete(job.status))
        .length;
    final batch = selectedWork!.isBatch
        ? _firstWhereOrNull(batches, (value) => value.id == selectedWork!.id)
        : null;
    final primaryJob = selectedWork!.type == _BrowserWorkType.job
        ? _firstWhereOrNull(allJobs, (value) => value.id == selectedWork!.id)
        : null;
    final sourceBatch = primaryJob == null
        ? batch
        : _firstWhereOrNull(batches, (value) => value.id == primaryJob.batchId);

    return _InspectorPanel(
      title: batch?.batchNumber ?? 'Job #${primaryJob?.id ?? selectedWork!.id}',
      subtitle: selectedWork!.isBatch
          ? 'Batch assigned to ${freelancer.name}'
          : 'Single job assigned to ${freelancer.name}',
      children: [
        _InspectorMetric(
          icon: Icons.work_outline,
          label: 'Jobs selected',
          value: '${selectedJobs.length}',
        ),
        _InspectorMetric(
          icon: Icons.task_alt_outlined,
          label: 'Completion',
          value: '$completed/${selectedJobs.length}',
        ),
        _InspectorMetric(
          icon: Icons.widgets_outlined,
          label: 'Inventory pick lines',
          value: '${tasks.where((task) => jobIds.contains(task.jobId)).length}',
        ),
        _InspectorMetric(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Payout balance',
          value: _money(payout),
        ),
        const SizedBox(height: 14),
        if (primaryJob != null)
          AppButton(
            label: 'Open job details',
            icon: Icons.visibility_outlined,
            variant: AppButtonVariant.secondary,
            onPressed: () => onOpenDetails(primaryJob, allTasks),
          ),
        if (sourceBatch != null) ...[
          const SizedBox(height: 8),
          AppButton(
            label: 'Print job card',
            icon: Icons.print_outlined,
            onPressed: () => onPrintBatch(sourceBatch, freelancers, allJobs),
          ),
        ],
      ],
    );
  }
}

class _InspectorPanel extends StatelessWidget {
  const _InspectorPanel({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: SoftErpTheme.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: SoftErpTheme.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _InspectorEmpty extends StatelessWidget {
  const _InspectorEmpty({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return _InspectorPanel(
      title: title,
      subtitle: 'Freelancer selected',
      children: [
        _InspectorMetric(
          icon: Icons.touch_app_outlined,
          label: 'Next step',
          value: message,
        ),
      ],
    );
  }
}

class _InspectorMetric extends StatelessWidget {
  const _InspectorMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: SoftErpTheme.textSecondary),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: SoftErpTheme.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: SoftErpTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
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

class _ColumnBrowserTile extends StatelessWidget {
  const _ColumnBrowserTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.badge,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? badge;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? SoftErpTheme.accentSurface : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? SoftErpTheme.accentSoft : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: selected
                      ? SoftErpTheme.accentSoft
                      : SoftErpTheme.cardSurfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: SoftErpTheme.border),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: selected
                      ? SoftErpTheme.accentDark
                      : SoftErpTheme.textSecondary,
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
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected
                                  ? SoftErpTheme.accentDark
                                  : SoftErpTheme.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 6),
                          badge!,
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: SoftErpTheme.textSecondary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 6), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

class _BrowserSectionLabel extends StatelessWidget {
  const _BrowserSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: SoftErpTheme.textSecondary,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _BrowserDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 1,
      child: ColoredBox(color: SoftErpTheme.border),
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
                  subtitle: _freelancerBoardSubtitle(
                    freelancer,
                    freelancerBatches.length,
                    assignedJobCount,
                  ),
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
    this.width = 330,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final _Tone tone;
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = _toneColors(tone);
    return SoftSurface(
      width: width,
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
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _MiniMetric(
                  icon: Icons.numbers_rounded,
                  label: '${job.quantity} units',
                ),
                _MiniMetric(
                  icon: Icons.widgets_outlined,
                  label: '$taskCount picks',
                ),
                _MiniMetric(
                  icon: Icons.account_balance_wallet_outlined,
                  label: _money(job.payoutBalance),
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
    final jobIds = jobs.map((job) => job.id).toSet();
    final materialLines = tasks
        .where((task) => jobIds.contains(task.jobId))
        .length;
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
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _MiniMetric(
                icon: Icons.work_outline,
                label: '${jobs.length} jobs',
              ),
              _MiniMetric(
                icon: Icons.widgets_outlined,
                label: '$materialLines picks',
              ),
              _MiniMetric(
                icon: Icons.account_balance_wallet_outlined,
                label: _money(payout),
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

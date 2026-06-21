import 'package:barcode_widget/barcode_widget.dart';
import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/core/widgets/soft_primitives.dart';
import 'package:core_erp/features/departments/domain/employee_definition.dart';
import 'package:core_erp/features/departments/presentation/providers/departments_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../domain/freelancer_job.dart';
import '../providers/jobs_provider.dart';

class FreelancerBarcodeListener extends StatefulWidget {
  const FreelancerBarcodeListener({super.key, required this.child});

  final Widget child;

  @override
  State<FreelancerBarcodeListener> createState() =>
      _FreelancerBarcodeListenerState();
}

class _FreelancerBarcodeListenerState extends State<FreelancerBarcodeListener> {
  String _barcodeBuffer = '';
  DateTime? _lastKeystrokeTime;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    super.dispose();
  }

  bool _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final now = DateTime.now();
    if (_lastKeystrokeTime != null &&
        now.difference(_lastKeystrokeTime!).inMilliseconds > 50) {
      _barcodeBuffer = '';
    }
    _lastKeystrokeTime = now;

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      final scanned = _barcodeBuffer.trim();
      _barcodeBuffer = '';
      if (scanned.startsWith('FR-')) {
        _processBarcode(scanned);
        return true;
      }
      return false;
    }

    final character = event.character;
    if (character != null && character.isNotEmpty) {
      _barcodeBuffer += character;
    }
    return false;
  }

  Future<void> _processBarcode(String barcode) async {
    final departments = context.read<DepartmentsProvider>();
    if (departments.employees.isEmpty) {
      await departments.load();
    }
    if (!mounted) return;

    final freelancer = _firstOrNull(
      departments.employees,
      (employee) =>
          employee.employmentType == 'freelancer' &&
          employee.barcodeId.toUpperCase() == barcode.toUpperCase(),
    );
    if (freelancer == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('No freelancer found for barcode $barcode.'),
            backgroundColor: SoftErpTheme.dangerText,
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    final jobsProvider = context.read<JobsProvider>();
    if (jobsProvider.jobs.isEmpty && !jobsProvider.isLoading) {
      await jobsProvider.fetchJobsData();
    }
    if (!mounted) return;

    final batches = jobsProvider.batches
        .where((batch) => batch.freelancerId == freelancer.id)
        .toList(growable: false);
    final jobs = jobsProvider.jobs
        .where((job) => batches.any((batch) => batch.id == job.batchId))
        .toList(growable: false);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _FreelancerScanDialog(
        freelancer: freelancer,
        batches: batches,
        jobs: jobs,
        onClose: () => Navigator.pop(dialogContext),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _FreelancerScanDialog extends StatelessWidget {
  const _FreelancerScanDialog({
    required this.freelancer,
    required this.batches,
    required this.jobs,
    required this.onClose,
  });

  final EmployeeDefinition freelancer;
  final List<FreelancerJobBatch> batches;
  final List<FreelancerJob> jobs;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final completed = jobs.where((job) => _isComplete(job.status)).length;
    final active = jobs.length - completed;
    final balance = jobs.fold<double>(0, (sum, job) => sum + job.payoutBalance);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(22, 20, 16, 18),
              decoration: const BoxDecoration(
                color: SoftErpTheme.cardSurfaceAlt,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(bottom: BorderSide(color: SoftErpTheme.border)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: SoftErpTheme.accentGradient,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.badge_outlined,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Freelancer identified',
                          style: TextStyle(
                            color: SoftErpTheme.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          freelancer.name,
                          style: const TextStyle(
                            color: SoftErpTheme.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SoftStatusPill(
                    label: 'ACTIVE',
                    background: SoftErpTheme.successBg,
                    textColor: SoftErpTheme.successText,
                    borderColor: SoftErpTheme.successBg,
                  ),
                  const SizedBox(width: 6),
                  SoftIconButton(
                    icon: Icons.close_rounded,
                    tooltip: 'Close',
                    onTap: onClose,
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _ScanMetric(
                          label: 'Active jobs',
                          value: '$active',
                          icon: Icons.construction_rounded,
                          background: SoftErpTheme.infoBg,
                          foreground: SoftErpTheme.infoText,
                        ),
                        _ScanMetric(
                          label: 'Completed',
                          value: '$completed',
                          icon: Icons.task_alt_rounded,
                          background: SoftErpTheme.successBg,
                          foreground: SoftErpTheme.successText,
                        ),
                        _ScanMetric(
                          label: 'Reward balance',
                          value: '₹${balance.toStringAsFixed(2)}',
                          icon: Icons.account_balance_wallet_outlined,
                          background: SoftErpTheme.warningBg,
                          foreground: SoftErpTheme.warningText,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 13, 16, 9),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: SoftErpTheme.border),
                      ),
                      child: BarcodeWidget(
                        barcode: Barcode.code128(),
                        data: freelancer.barcodeId,
                        height: 68,
                        width: double.infinity,
                        drawText: true,
                        style: const TextStyle(
                          color: SoftErpTheme.textPrimary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Assigned batches',
                            style: TextStyle(
                              color: SoftErpTheme.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          '${batches.length} total',
                          style: const TextStyle(
                            color: SoftErpTheme.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (batches.isEmpty)
                      const _NoAssignments()
                    else
                      ...batches.map((batch) {
                        final batchJobs = jobs
                            .where((job) => job.batchId == batch.id)
                            .toList(growable: false);
                        final done = batchJobs
                            .where((job) => _isComplete(job.status))
                            .length;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: SoftErpTheme.cardSurfaceAlt,
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: SoftErpTheme.border),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: SoftErpTheme.accentSoft,
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: const Icon(
                                  Icons.layers_outlined,
                                  color: SoftErpTheme.accentDark,
                                  size: 19,
                                ),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      batch.batchNumber,
                                      style: const TextStyle(
                                        color: SoftErpTheme.textPrimary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$done/${batchJobs.length} jobs complete',
                                      style: const TextStyle(
                                        color: SoftErpTheme.textSecondary,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _ScanStatus(status: batch.status),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanMetric extends StatelessWidget {
  const _ScanMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 172,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: foreground, size: 18),
          ),
          const SizedBox(width: 10),
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
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SoftErpTheme.textSecondary,
                    fontSize: 10.5,
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

class _ScanStatus extends StatelessWidget {
  const _ScanStatus({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final complete = _isComplete(status);
    return SoftStatusPill(
      label: _statusLabel(status),
      background: complete ? SoftErpTheme.successBg : SoftErpTheme.infoBg,
      textColor: complete ? SoftErpTheme.successText : SoftErpTheme.infoText,
      borderColor: complete ? SoftErpTheme.successBg : SoftErpTheme.infoBg,
    );
  }
}

class _NoAssignments extends StatelessWidget {
  const _NoAssignments();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: const Row(
        children: [
          Icon(Icons.inbox_outlined, color: SoftErpTheme.textSecondary),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'No job batches are currently assigned.',
              style: TextStyle(color: SoftErpTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

bool _isComplete(String status) {
  final normalized = status.toLowerCase().replaceAll('-', '_');
  return normalized == 'completed' || normalized == 'done';
}

String _statusLabel(String status) {
  final value = status.replaceAll('-', ' ').replaceAll('_', ' ').trim();
  if (value.isEmpty) return 'Unknown';
  return value
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map(
        (part) => '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
      )
      .join(' ');
}

T? _firstOrNull<T>(Iterable<T> values, bool Function(T value) test) {
  for (final value in values) {
    if (test(value)) return value;
  }
  return null;
}

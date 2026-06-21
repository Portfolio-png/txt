import 'dart:convert';

import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/core/widgets/soft_primitives.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../domain/freelancer_job.dart';

class FreelancerPortalScreen extends StatefulWidget {
  const FreelancerPortalScreen({
    super.key,
    required this.token,
    this.apiBaseUrl = 'http://localhost:18080',
  });

  final String token;
  final String apiBaseUrl;

  @override
  State<FreelancerPortalScreen> createState() => _FreelancerPortalScreenState();
}

class _FreelancerPortalScreenState extends State<FreelancerPortalScreen> {
  bool _isLoading = true;
  String? _error;
  List<FreelancerJobBatch> _batches = <FreelancerJobBatch>[];
  List<FreelancerJob> _jobs = <FreelancerJob>[];
  List<FreelancerJobTask> _tasks = <FreelancerJobTask>[];

  double get _totalBalance =>
      _jobs.fold<double>(0, (sum, job) => sum + job.payoutBalance);

  int get _completedJobs =>
      _jobs.where((job) => _isCompleted(job.status)).length;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final uri = Uri.parse(
        '${widget.apiBaseUrl}/api/freelancer-portal/data?token=${Uri.encodeComponent(widget.token)}',
      );
      final response = await http.get(uri);
      final decoded = jsonDecode(response.body);
      if (response.statusCode != 200 || decoded is! Map<String, dynamic>) {
        throw Exception('Portal data is currently unavailable.');
      }
      if (decoded['success'] != true) {
        throw Exception(decoded['error'] ?? 'Could not open this job card.');
      }
      if (!mounted) return;
      setState(() {
        _batches = (decoded['batches'] as List<dynamic>? ?? const [])
            .map(
              (value) =>
                  FreelancerJobBatch.fromJson(value as Map<String, dynamic>),
            )
            .toList(growable: false);
        _jobs = (decoded['jobs'] as List<dynamic>? ?? const [])
            .map(
              (value) => FreelancerJob.fromJson(value as Map<String, dynamic>),
            )
            .toList(growable: false);
        _tasks = (decoded['tasks'] as List<dynamic>? ?? const [])
            .map(
              (value) =>
                  FreelancerJobTask.fromJson(value as Map<String, dynamic>),
            )
            .toList(growable: false);
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5FA),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: SoftErpTheme.textPrimary,
        automaticallyImplyLeading: Navigator.of(context).canPop(),
        titleSpacing: 24,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PortalMark(),
            SizedBox(width: 10),
            Text(
              'Paper · Work portal',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _fetchData,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 12),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: SoftErpTheme.border),
        ),
      ),
      body: _isLoading
          ? const _PortalLoading()
          : _error != null
          ? _PortalError(message: _error!, onRetry: _fetchData)
          : RefreshIndicator(
              color: SoftErpTheme.accent,
              onRefresh: _fetchData,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 44),
                    sliver: SliverToBoxAdapter(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1040),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _BalanceHero(
                                balance: _totalBalance,
                                activeBatches: _batches
                                    .where(
                                      (batch) => !_isCompleted(batch.status),
                                    )
                                    .length,
                              ),
                              const SizedBox(height: 18),
                              _PortalStats(
                                batches: _batches.length,
                                jobs: _jobs.length,
                                completed: _completedJobs,
                                itemLines: _tasks.length,
                              ),
                              const SizedBox(height: 30),
                              const _SectionHeading(
                                title: 'Your job batches',
                                subtitle:
                                    'Jobs assigned during the last 30 days. Open a batch to see every assembly item.',
                              ),
                              const SizedBox(height: 14),
                              if (_batches.isEmpty)
                                const _PortalEmpty()
                              else
                                ..._batches.map(
                                  (batch) => Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: _PortalBatchCard(
                                      batch: batch,
                                      jobs: _jobs
                                          .where(
                                            (job) => job.batchId == batch.id,
                                          )
                                          .toList(growable: false),
                                      tasks: _tasks,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 12),
                              const _PortalFootnote(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _PortalMark extends StatelessWidget {
  const _PortalMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        gradient: SoftErpTheme.accentGradient,
        borderRadius: BorderRadius.circular(11),
      ),
      child: const Icon(Icons.handyman_rounded, size: 19, color: Colors.white),
    );
  }
}

class _BalanceHero extends StatelessWidget {
  const _BalanceHero({required this.balance, required this.activeBatches});

  final double balance;
  final int activeBatches;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF5142CC), Color(0xFF7868F3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x335E49E6),
            blurRadius: 34,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final balanceBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    color: Colors.white70,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Total rewards earned',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Text(
                _portalMoney(balance),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 34 : 42,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Rewards are calculated per completed job.',
                style: TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
            ],
          );
          final activeCard = Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.layers_outlined,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 11),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$activeBatches',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Text(
                      'active batches',
                      style: TextStyle(color: Colors.white70, fontSize: 11.5),
                    ),
                  ],
                ),
              ],
            ),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [balanceBlock, const SizedBox(height: 22), activeCard],
            );
          }
          return Row(
            children: [
              Expanded(child: balanceBlock),
              const SizedBox(width: 24),
              activeCard,
            ],
          );
        },
      ),
    );
  }
}

class _PortalStats extends StatelessWidget {
  const _PortalStats({
    required this.batches,
    required this.jobs,
    required this.completed,
    required this.itemLines,
  });

  final int batches;
  final int jobs;
  final int completed;
  final int itemLines;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth < 660
            ? (constraints.maxWidth - 10) / 2
            : (constraints.maxWidth - 30) / 4;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _PortalStat(
              width: itemWidth,
              label: 'Batches',
              value: '$batches',
              icon: Icons.layers_outlined,
              background: SoftErpTheme.accentSoft,
              foreground: SoftErpTheme.accentDark,
            ),
            _PortalStat(
              width: itemWidth,
              label: 'Jobs assigned',
              value: '$jobs',
              icon: Icons.work_outline_rounded,
              background: SoftErpTheme.infoBg,
              foreground: SoftErpTheme.infoText,
            ),
            _PortalStat(
              width: itemWidth,
              label: 'Completed',
              value: '$completed',
              icon: Icons.task_alt_rounded,
              background: SoftErpTheme.successBg,
              foreground: SoftErpTheme.successText,
            ),
            _PortalStat(
              width: itemWidth,
              label: 'Assembly items',
              value: '$itemLines',
              icon: Icons.widgets_outlined,
              background: SoftErpTheme.warningBg,
              foreground: SoftErpTheme.warningText,
            ),
          ],
        );
      },
    );
  }
}

class _PortalStat extends StatelessWidget {
  const _PortalStat({
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
      radius: 20,
      elevated: false,
      padding: const EdgeInsets.all(15),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: foreground, size: 20),
          ),
          const SizedBox(width: 11),
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
                Text(
                  label,
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
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: SoftErpTheme.textPrimary,
            fontSize: 21,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style: const TextStyle(
            color: SoftErpTheme.textSecondary,
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _PortalBatchCard extends StatelessWidget {
  const _PortalBatchCard({
    required this.batch,
    required this.jobs,
    required this.tasks,
  });

  final FreelancerJobBatch batch;
  final List<FreelancerJob> jobs;
  final List<FreelancerJobTask> tasks;

  @override
  Widget build(BuildContext context) {
    final completed = jobs.where((job) => _isCompleted(job.status)).length;
    final progress = jobs.isEmpty ? 0.0 : completed / jobs.length;
    final reward = jobs.fold<double>(0, (sum, job) => sum + job.payoutBalance);
    return SoftSurface(
      padding: EdgeInsets.zero,
      radius: 22,
      clipContent: true,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(18, 13, 16, 13),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _portalStatusBackground(batch.status),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              _isCompleted(batch.status)
                  ? Icons.task_alt_rounded
                  : Icons.layers_outlined,
              color: _portalStatusForeground(batch.status),
              size: 22,
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  batch.batchNumber,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SoftErpTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _PortalStatus(status: batch.status),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      value: progress,
                      backgroundColor: SoftErpTheme.border,
                      valueColor: const AlwaysStoppedAnimation(
                        SoftErpTheme.successText,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '$completed/${jobs.length} complete',
                  style: const TextStyle(
                    color: SoftErpTheme.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  _portalMoney(reward),
                  style: const TextStyle(
                    color: SoftErpTheme.successText,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          children: [
            const Divider(height: 1),
            const SizedBox(height: 10),
            if (jobs.isEmpty)
              const _PortalInlineEmpty(
                message: 'No jobs are attached to this batch.',
              )
            else
              ...jobs.map(
                (job) => _PortalJobRow(
                  job: job,
                  tasks: tasks.where((task) => task.jobId == job.id).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PortalJobRow extends StatelessWidget {
  const _PortalJobRow({required this.job, required this.tasks});

  final FreelancerJob job;
  final List<FreelancerJobTask> tasks;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Job #${job.id} · Item #${job.itemId}',
                      style: const TextStyle(
                        color: SoftErpTheme.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${job.quantity} units · ${tasks.length} assembly items',
                      style: const TextStyle(
                        color: SoftErpTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _PortalStatus(status: job.status),
                  const SizedBox(height: 5),
                  Text(
                    _portalMoney(job.payoutBalance),
                    style: const TextStyle(
                      color: SoftErpTheme.successText,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (tasks.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 6),
            ...tasks.map(
              (task) => Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Row(
                  children: [
                    const Icon(
                      Icons.widgets_outlined,
                      size: 16,
                      color: SoftErpTheme.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Inventory item #${task.itemId}',
                        style: const TextStyle(
                          color: SoftErpTheme.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      '${_portalQuantity(task.requiredQuantity)} required',
                      style: const TextStyle(
                        color: SoftErpTheme.textSecondary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PortalStatus extends StatelessWidget {
  const _PortalStatus({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final foreground = _portalStatusForeground(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: _portalStatusBackground(status),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _portalStatusLabel(status),
        style: TextStyle(
          color: foreground,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PortalEmpty extends StatelessWidget {
  const _PortalEmpty();

  @override
  Widget build(BuildContext context) {
    return SoftSurface(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 46),
      radius: 22,
      child: const Column(
        children: [
          Icon(
            Icons.work_history_outlined,
            size: 46,
            color: SoftErpTheme.accent,
          ),
          SizedBox(height: 14),
          Text(
            'No recent jobs',
            style: TextStyle(
              color: SoftErpTheme.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'New batches assigned to you will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: SoftErpTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _PortalInlineEmpty extends StatelessWidget {
  const _PortalInlineEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: SoftErpTheme.textSecondary),
      ),
    );
  }
}

class _PortalFootnote extends StatelessWidget {
  const _PortalFootnote();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.lock_outline_rounded,
          size: 15,
          color: SoftErpTheme.textSecondary,
        ),
        SizedBox(width: 6),
        Flexible(
          child: Text(
            'This private link is tied to your freelancer ID. Do not share it.',
            textAlign: TextAlign.center,
            style: TextStyle(color: SoftErpTheme.textSecondary, fontSize: 11.5),
          ),
        ),
      ],
    );
  }
}

class _PortalError extends StatelessWidget {
  const _PortalError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: SoftSurface(
          width: 480,
          radius: 24,
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: SoftErpTheme.dangerBg,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.link_off_rounded,
                  color: SoftErpTheme.dangerText,
                  size: 30,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'This job card could not be opened',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: SoftErpTheme.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: SoftErpTheme.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PortalLoading extends StatelessWidget {
  const _PortalLoading();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _PortalSkeleton(height: 180),
              const SizedBox(height: 18),
              Row(
                children: List.generate(
                  4,
                  (index) => Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: index == 3 ? 0 : 10),
                      child: const _PortalSkeleton(height: 72),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 30),
              const _PortalSkeleton(height: 24),
              const SizedBox(height: 14),
              const _PortalSkeleton(height: 116),
              const SizedBox(height: 14),
              const _PortalSkeleton(height: 116),
            ],
          ),
        ),
      ),
    );
  }
}

class _PortalSkeleton extends StatelessWidget {
  const _PortalSkeleton({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFE9EAF1),
        borderRadius: BorderRadius.circular(22),
      ),
    );
  }
}

bool _isCompleted(String status) {
  final normalized = status.toLowerCase().replaceAll('-', '_');
  return normalized == 'completed' || normalized == 'done';
}

String _portalStatusLabel(String status) {
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

Color _portalStatusBackground(String status) {
  if (_isCompleted(status)) return SoftErpTheme.successBg;
  final normalized = status.toLowerCase().replaceAll('-', '_');
  if (normalized == 'in_progress' ||
      normalized == 'active' ||
      normalized == 'assigned') {
    return SoftErpTheme.infoBg;
  }
  if (normalized == 'failed' || normalized == 'cancelled') {
    return SoftErpTheme.dangerBg;
  }
  return SoftErpTheme.warningBg;
}

Color _portalStatusForeground(String status) {
  if (_isCompleted(status)) return SoftErpTheme.successText;
  final normalized = status.toLowerCase().replaceAll('-', '_');
  if (normalized == 'in_progress' ||
      normalized == 'active' ||
      normalized == 'assigned') {
    return SoftErpTheme.infoText;
  }
  if (normalized == 'failed' || normalized == 'cancelled') {
    return SoftErpTheme.dangerText;
  }
  return SoftErpTheme.warningText;
}

String _portalMoney(double value) => '₹${value.toStringAsFixed(2)}';

String _portalQuantity(double value) {
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/features/auth/presentation/providers/auth_provider.dart';
import 'package:core_erp/features/delivery_challans/domain/delivery_challan.dart';
import 'package:core_erp/features/delivery_challans/data/delivery_challan_repository.dart';
import 'package:core_erp/features/delivery_challans/presentation/providers/delivery_challan_provider.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:core_erp/features/orders/presentation/providers/orders_provider.dart';

import '../widgets/wizard_progress.dart';

/// The steps of the In-use reconciliation flow. Kept parallel to the Purchase
/// wizard so both read as the same ●———○———○ stepped experience.
enum _ReconStep { select, reconcile, done }

const List<String> _stepLabels = <String>['Select', 'Settle', 'Done'];

/// A reconciliation bucket: the label shown on the field and the JSON key the
/// [ChallanReconcileLineInput] carries. Order matches the desktop production
/// reconciliation vocabulary, expanded from leftover/scrap to five buckets.
class _ReconBucket {
  const _ReconBucket(this.key, this.label, this.color);
  final String key;
  final String label;
  final Color color;
}

const List<_ReconBucket> _kBuckets = [
  _ReconBucket('finishedGoods', 'Finished Goods', Color(0xFF3EA34D)),
  _ReconBucket('leftover', 'Leftover', Color(0xFF2F7DD1)),
  _ReconBucket('scrap', 'Scrap', Color(0xFFE2933E)),
  _ReconBucket('rejection', 'Rejection', Color(0xFFD64545)),
  _ReconBucket('lost', 'Lost', Color(0xFF8A8F98)),
];

double _asQty(String value) => double.tryParse(value.trim()) ?? 0;

String _fmtQty(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value
      .toStringAsFixed(3)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
}

/// The In-use flow as a stepped wizard: **Select** an internal-use challan →
/// **Reconcile** its consumed weight across the five buckets → **Done**. Reached
/// from the "In-use" tile on the Challan tab, gated by
/// FeatureKeys.challanReconciliation. Mirrors the Purchase wizard's rail/header.
class InUseReconciliationWizard extends StatefulWidget {
  const InUseReconciliationWizard({super.key});

  @override
  State<InUseReconciliationWizard> createState() =>
      _InUseReconciliationWizardState();
}

class _InUseReconciliationWizardState extends State<InUseReconciliationWizard> {
  _ReconStep _step = _ReconStep.select;
  DeliveryChallan? _selected;
  DeliveryChallan? _result;
  Map<String, double> _resultTotals = const {};

  void _goTo(_ReconStep step) => setState(() => _step = step);

  // Back steps within the flow (reconcile → select) rather than tearing the
  // whole wizard off the stack; on the first step it closes the wizard.
  void _handleBack() {
    switch (_step) {
      case _ReconStep.select:
        Navigator.of(context).pop();
        break;
      case _ReconStep.reconcile:
        setState(() {
          _step = _ReconStep.select;
          _selected = null;
        });
        break;
      case _ReconStep.done:
        Navigator.of(context).pop(true); // settled — leaving finishes the flow
        break;
    }
  }

  void _jumpTo(int index) {
    // Only jumping back to Select (from Reconcile) is meaningful.
    if (index == _ReconStep.select.index && _step == _ReconStep.reconcile) {
      setState(() {
        _step = _ReconStep.select;
        _selected = null;
      });
    }
  }

  String _titleForStep() {
    switch (_step) {
      case _ReconStep.select:
        return 'In-use Challans';
      case _ReconStep.reconcile:
        return _selected?.challanNo ?? 'Settle';
      case _ReconStep.done:
        return 'Done';
    }
  }

  @override
  Widget build(BuildContext context) {
    final canReconcile = context.watch<AuthProvider>().can('challans.reconcile');
    if (!canReconcile) {
      return Scaffold(
        backgroundColor: SoftErpTheme.shellSurface,
        appBar: AppBar(
          title: const Text('In-use Challans', style: TextStyle(fontWeight: FontWeight.w900)),
          backgroundColor: Colors.white,
          elevation: 0,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline_rounded, size: 48, color: SoftErpTheme.textSecondary),
                const SizedBox(height: 12),
                const Text('Permission Required', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text(
                  'You do not have permission to reconcile in-use challans. Please ask your administrator for the "In-use reconciliation" capability.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: SoftErpTheme.textSecondary),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: _step == _ReconStep.select,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: SoftErpTheme.shellSurface,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
          // First step closes the wizard; Reconcile steps back to Select; the
          // terminal Done screen has neither (its buttons drive navigation).
          leading: _step == _ReconStep.done
              ? null
              : _step == _ReconStep.select
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    )
                  : IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: 'Back',
                      onPressed: _handleBack,
                    ),
          title: Text(_titleForStep(),
              style: const TextStyle(fontWeight: FontWeight.w900)),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(72),
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.only(bottom: 12),
              child: WizardProgress(
                labels: _stepLabels,
                currentIndex: _step.index,
                onStepTapped: _step == _ReconStep.done ? null : _jumpTo,
                canTap: (i) => i < _step.index,
              ),
            ),
          ),
        ),
        body: SafeArea(child: _buildStep()),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case _ReconStep.select:
        return _SelectChallanStep(
          onPicked: (challan) {
            setState(() => _selected = challan);
            _goTo(_ReconStep.reconcile);
          },
        );
      case _ReconStep.reconcile:
        return _ReconcileStep(
          challan: _selected!,
          onSettled: (result, totals) {
            setState(() {
              _result = result;
              _resultTotals = totals;
            });
            _goTo(_ReconStep.done);
          },
        );
      case _ReconStep.done:
        return _ReconcileDoneStep(
          challan: _result!,
          totals: _resultTotals,
          onReconcileAnother: () => setState(() {
            _step = _ReconStep.select;
            _selected = null;
            _result = null;
            _resultTotals = const {};
          }),
          onFinish: () => Navigator.of(context).pop(true),
        );
    }
  }
}

// ─────────────────────────────────────────────────────────── Step 1: Select

/// Lists the internal-use challans still awaiting reconciliation and calls
/// [onPicked] when one is chosen.
class _SelectChallanStep extends StatefulWidget {
  const _SelectChallanStep({required this.onPicked});

  final ValueChanged<DeliveryChallan> onPicked;

  @override
  State<_SelectChallanStep> createState() => _SelectChallanStepState();
}

class _SelectChallanStepState extends State<_SelectChallanStep> {
  bool _loading = true;
  String? _error;
  List<DeliveryChallan> _challans = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Read from the repository directly so we don't clobber the shared
      // provider's type filter for other consumers.
      final repo = context.read<DeliveryChallanProvider>().repository;
      final all = await repo.getChallans(type: ChallanType.internal);
      final pending = all.where(_isPendingUseChallan).toList()
        ..sort((a, b) {
          final ad = a.createdAt ?? a.date;
          final bd = b.createdAt ?? b.date;
          return bd.compareTo(ad);
        });
      if (!mounted) return;
      setState(() {
        _challans = pending;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // A Use-created challan is internal, still issued (reconciled ones become
  // 'completed' and drop out), and carries the editor's "Consumption for
  // order …" purpose — which excludes pipeline leftover/scrap internal challans.
  bool _isPendingUseChallan(DeliveryChallan c) =>
      c.isInternal &&
      c.status == DeliveryChallanStatus.issued &&
      c.internalPurpose.toLowerCase().startsWith('consumption for order');

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: SoftErpTheme.accent));
    }
    if (_error != null) {
      return _EmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Could not load challans',
        subtitle: _error!,
        action: FilledButton(onPressed: _load, child: const Text('Retry')),
      );
    }
    if (_challans.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            _EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'Nothing in use',
              subtitle:
                  'Internal-use challans you create from the Use flow show up here, ready to settle.',
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _challans.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _challanCard(_challans[index]),
      ),
    );
  }

  Widget _challanCard(DeliveryChallan challan) {
    final totalWeight = challan.items.fold<double>(
      0,
      (sum, item) => sum + _asQty(item.weight),
    );
    final orderLabel = challan.orderNos.isNotEmpty
        ? challan.orderNos.join(', ')
        : (challan.orderNo.isEmpty ? '—' : challan.orderNo);
    final d = challan.date;
    final dateStr =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => widget.onPicked(challan),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: SoftErpTheme.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.precision_manufacturing_rounded,
                    color: SoftErpTheme.accent),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(challan.challanNo,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text('Order: $orderLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: SoftErpTheme.textSecondary, fontSize: 13)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        _pill('${challan.items.length} item'
                            '${challan.items.length == 1 ? '' : 's'}'),
                        _pill('${_fmtQty(totalWeight)} kg'),
                        _pill(dateStr),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: SoftErpTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: SoftErpTheme.shellSurface,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: SoftErpTheme.textSecondary)),
      );
}

// ────────────────────────────────────────────────────────── Step 2: Reconcile

/// Reconciles one internal-use challan: every consumed line is split across the
/// five buckets and the split must exactly account for the WEIGHT (kg) taken
/// (the same strict settlement invariant the desktop production reconciliation
/// enforces). Settling reverts each bucket into inventory and, once all of the
/// order's use challans are reconciled, completes the order.
class _ReconcileStep extends StatefulWidget {
  const _ReconcileStep({required this.challan, required this.onSettled});

  final DeliveryChallan challan;
  final void Function(DeliveryChallan result, Map<String, double> totals)
      onSettled;

  @override
  State<_ReconcileStep> createState() => _ReconcileStepState();
}

class _ReconcileStepState extends State<_ReconcileStep> {
  // challanItemId -> bucketKey -> controller
  final Map<int, Map<String, TextEditingController>> _controllers = {};
  bool _submitting = false;

  static const double _tolerance = 0.01;

  @override
  void initState() {
    super.initState();
    for (final item in widget.challan.items) {
      _controllers[item.id] = {
        for (final bucket in _kBuckets) bucket.key: TextEditingController(),
      };
    }
  }

  @override
  void dispose() {
    for (final row in _controllers.values) {
      for (final c in row.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  // Reconciliation settles the WEIGHT (kg) consumed, not the piece count.
  double _takenFor(DeliveryChallanItem item) => _asQty(item.weight);

  double _sumFor(DeliveryChallanItem item) {
    final row = _controllers[item.id]!;
    return _kBuckets.fold<double>(0, (sum, b) => sum + _asQty(row[b.key]!.text));
  }

  double _remainingFor(DeliveryChallanItem item) =>
      _takenFor(item) - _sumFor(item);

  bool _lineBalanced(DeliveryChallanItem item) =>
      _remainingFor(item).abs() <= _tolerance;

  bool get _allBalanced => widget.challan.items.every(_lineBalanced);

  /// Dumps a line's outstanding weight into its Leftover field — the common
  /// case where the untouched remainder is simply returned as usable stock.
  void _fillRemainingToLeftover(DeliveryChallanItem item) {
    final remaining = _remainingFor(item);
    if (remaining.abs() <= _tolerance) return;
    final row = _controllers[item.id]!;
    final current = _asQty(row['leftover']!.text);
    final next = current + remaining;
    row['leftover']!.text = next <= 0 ? '0' : _fmtQty(next);
    setState(() {});
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_allBalanced) {
      _toast('Each line must settle its full weight across the buckets.',
          error: true);
      return;
    }
    setState(() => _submitting = true);

    final lines = widget.challan.items.map((item) {
      final row = _controllers[item.id]!;
      return ChallanReconcileLineInput(
        challanItemId: item.id,
        finishedGoods: _asQty(row['finishedGoods']!.text),
        leftover: _asQty(row['leftover']!.text),
        scrap: _asQty(row['scrap']!.text),
        rejection: _asQty(row['rejection']!.text),
        lost: _asQty(row['lost']!.text),
      );
    }).toList(growable: false);

    final provider = context.read<DeliveryChallanProvider>();
    final result = await provider.reconcileChallan(
      widget.challan.id,
      ChallanReconcileInput(lines: lines),
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (result == null) {
      _toast(provider.errorMessage ?? 'Failed to settle challan.',
          error: true);
      return;
    }

    // Reverted quantities are now in inventory and the order may have been
    // completed — refresh those tabs so they reflect the settlement.
    context.read<InventoryProvider>().refresh();
    context.read<OrdersProvider>().refresh();

    // Totals per bucket (kg) for the Done summary.
    final totals = <String, double>{for (final b in _kBuckets) b.key: 0};
    for (final line in lines) {
      totals['finishedGoods'] = totals['finishedGoods']! + line.finishedGoods;
      totals['leftover'] = totals['leftover']! + line.leftover;
      totals['scrap'] = totals['scrap']! + line.scrap;
      totals['rejection'] = totals['rejection']! + line.rejection;
      totals['lost'] = totals['lost']! + line.lost;
    }
    widget.onSettled(result, totals);
  }

  void _toast(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? const Color(0xFFD64545) : Colors.green.shade600,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_submitting) {
      return const Center(
          child: CircularProgressIndicator(color: SoftErpTheme.accent));
    }
    final items = widget.challan.items;
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 16),
            itemBuilder: (context, index) => _lineCard(items[index]),
          ),
        ),
        SafeArea(
          minimum: const EdgeInsets.all(16),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              backgroundColor: SoftErpTheme.accent,
              disabledBackgroundColor: SoftErpTheme.accent.withOpacity(0.35),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            icon: const Icon(Icons.check_circle_rounded),
            label: Text(
              _allBalanced
                  ? 'Settle & Return to Inventory'
                  : 'Balance every line to continue',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            onPressed: _allBalanced ? _submit : null,
          ),
        ),
      ],
    );
  }

  Widget _lineCard(DeliveryChallanItem item) {
    final taken = _takenFor(item);
    final remaining = _remainingFor(item);
    final balanced = remaining.abs() <= _tolerance;
    final over = remaining < -_tolerance;

    final subtitle = item.variationPathLabel.trim().isEmpty
        ? null
        : item.variationPathLabel.trim();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: balanced
              ? const Color(0xFF3EA34D).withOpacity(0.5)
              : SoftErpTheme.border,
          width: balanced ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.particulars,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: const TextStyle(
                              fontSize: 12,
                              color: SoftErpTheme.textSecondary)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('TAKEN (KG)',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: SoftErpTheme.textSecondary)),
                  Text(_fmtQty(taken),
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w900)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final bucket in _kBuckets) ...[
            _bucketField(item, bucket),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(
                balanced
                    ? Icons.check_circle_rounded
                    : Icons.error_outline_rounded,
                size: 18,
                color: balanced
                    ? const Color(0xFF3EA34D)
                    : (over ? const Color(0xFFD64545) : const Color(0xFFE2933E)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  balanced
                      ? 'Fully settled'
                      : over
                          ? 'Over by ${_fmtQty(remaining.abs())} kg'
                          : 'Remaining ${_fmtQty(remaining)} kg',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: balanced
                        ? const Color(0xFF3EA34D)
                        : (over
                            ? const Color(0xFFD64545)
                            : const Color(0xFFE2933E)),
                  ),
                ),
              ),
              if (!balanced && !over)
                TextButton(
                  onPressed: () => _fillRemainingToLeftover(item),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: SoftErpTheme.accent,
                  ),
                  child: const Text('→ Leftover'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bucketField(DeliveryChallanItem item, _ReconBucket bucket) {
    final controller = _controllers[item.id]![bucket.key]!;
    return Row(
      children: [
        Container(
            width: 10,
            height: 10,
            decoration:
                BoxDecoration(color: bucket.color, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(bucket.label,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ),
        SizedBox(
          width: 120,
          child: TextField(
            controller: controller,
            textAlign: TextAlign.right,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            decoration: InputDecoration(
              isDense: true,
              hintText: '0',
              suffixText: 'kg',
              suffixStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: SoftErpTheme.textSecondary),
              filled: true,
              fillColor: SoftErpTheme.shellSurface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────── Step 3: Done

/// Confirmation of a settled reconciliation: what was reverted where, and the
/// choice to reconcile another challan or finish.
class _ReconcileDoneStep extends StatelessWidget {
  const _ReconcileDoneStep({
    required this.challan,
    required this.totals,
    required this.onReconcileAnother,
    required this.onFinish,
  });

  final DeliveryChallan challan;
  final Map<String, double> totals;
  final VoidCallback onReconcileAnother;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final orderLabel = challan.orderNos.isNotEmpty
        ? challan.orderNos.join(', ')
        : (challan.orderNo.isEmpty ? '' : challan.orderNo);
    final settled = totals.values.fold<double>(0, (a, b) => a + b);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3EA34D).withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded,
                      size: 56, color: Color(0xFF3EA34D)),
                ),
                const SizedBox(height: 20),
                Text('Settled ${challan.challanNo}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(
                  '${_fmtQty(settled)} kg returned to inventory under the Primary Group'
                  '${orderLabel.isEmpty ? '.' : ', and order $orderLabel tracking updated.'}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: SoftErpTheme.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 24),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: SoftErpTheme.border),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 8),
                  child: Column(
                    children: [
                      for (final bucket in _kBuckets)
                        _totalRow(bucket, totals[bucket.key] ?? 0),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SafeArea(
          minimum: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    foregroundColor: SoftErpTheme.accent,
                    side: const BorderSide(color: SoftErpTheme.accent),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                  ),
                  onPressed: onReconcileAnother,
                  child: const Text('Settle another',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    backgroundColor: SoftErpTheme.accent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                  ),
                  onPressed: onFinish,
                  child: const Text('Done',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _totalRow(_ReconBucket bucket, double value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                    color: bucket.color, shape: BoxShape.circle)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(bucket.label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
            ),
            Text('${_fmtQty(value)} kg',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 14)),
          ],
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.grey)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade500)),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

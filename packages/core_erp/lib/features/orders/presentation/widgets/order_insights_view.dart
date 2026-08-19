import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/utils/delivery_checkpoint_tooltip.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../items/domain/item_definition.dart';
import '../../domain/order_entry.dart';
import '../../domain/order_fulfilment.dart';

/// Which orders the insights screen is showing.
enum OrderInsightFilter { all, notStarted, started, stalled, old }

extension OrderInsightFilterX on OrderInsightFilter {
  String get label => switch (this) {
    OrderInsightFilter.all => 'All',
    OrderInsightFilter.notStarted => 'Not started',
    OrderInsightFilter.started => 'Started',
    OrderInsightFilter.stalled => 'Stalled',
    OrderInsightFilter.old => 'Old',
  };
}

/// How long a started order may sit with nothing delivered before it counts as
/// stalled, and how old an unfinished order may get before it counts as old.
/// Both are read off data already on the order — there is no "last touched"
/// timestamp to work from.
const Duration _stalledAfter = Duration(days: 14);
const Duration _oldAfter = Duration(days: 30);

/// Order-book insights: what cannot be produced yet, and how far everything
/// else has actually got.
///
/// Every number here comes off the already-loaded order list — ordered qty,
/// delivered qty (the sum of delivery-challan lines), invoiced qty and the
/// order date. Nothing fetches per order, so the screen costs one rebuild.
class OrderInsightsView extends StatefulWidget {
  const OrderInsightsView({
    super.key,
    required this.orders,
    required this.items,
    required this.fulfilment,
    required this.fulfilmentLoaded,
    required this.onOpenChallan,
    required this.onBack,
  });

  /// Opens a delivery challan by id, from a checkpoint on the fulfilment bar.
  /// Null leaves the checkpoints inert — they still describe themselves on
  /// hover, they just do not go anywhere.
  final ValueChanged<int>? onOpenChallan;

  final List<OrderEntry> orders;

  /// Used only to answer "does this order's item have a pipeline". The order
  /// itself carries no pipeline reference.
  final List<ItemDefinition> items;

  /// Floor-reconciled production per order line, keyed by order-item id.
  /// Missing entries simply mean no run data — the bar falls back to challans.
  final Map<int, OrderFulfilment> fulfilment;

  /// Whether [fulfilment] has actually been fetched. An empty map before the
  /// first fetch means "unknown", not "nothing in production", and the two must
  /// not be shown the same way.
  final bool fulfilmentLoaded;

  final VoidCallback onBack;

  @override
  State<OrderInsightsView> createState() => _OrderInsightsViewState();
}

class _OrderInsightsViewState extends State<OrderInsightsView> {
  OrderInsightFilter _filter = OrderInsightFilter.all;

  /// Whether the order has a pipeline RUN attached — not whether its item
  /// happens to name a default pipeline. Those are different questions, and
  /// only the first one decides whether the order can be produced.
  ///
  /// Once the rollup has loaded it is the only source consulted, including for
  /// orders it has no row for (which means no run). Falling back to the item's
  /// default pipeline would quietly answer a different question and put
  /// unstarted orders in the "In production" row.
  bool _hasPipeline(OrderEntry order) {
    if (widget.fulfilmentLoaded) {
      return (widget.fulfilment[order.id]?.runCount ?? 0) > 0;
    }
    // Pre-load: the item's planned route is the only thing known. It is a
    // weaker signal, so the screen also says the figures are still loading.
    final item = widget.items
        .where((candidate) => candidate.id == order.itemId)
        .firstOrNull;
    final pipelineId = item?.defaultPipelineId;
    return pipelineId != null && pipelineId.trim().isNotEmpty;
  }

  bool _isStalled(OrderEntry order) {
    if (order.status != OrderStatus.inProgress) return false;
    if (order.totalDeliveredQty > 0) return false;
    return DateTime.now().difference(order.createdAt) > _stalledAfter;
  }

  bool _isOld(OrderEntry order) {
    if (order.status == OrderStatus.completed) return false;
    return DateTime.now().difference(order.createdAt) > _oldAfter;
  }

  bool _matchesFilter(OrderEntry order) {
    return switch (_filter) {
      OrderInsightFilter.all => true,
      OrderInsightFilter.notStarted =>
        order.status == OrderStatus.notStarted ||
            order.status == OrderStatus.draft,
      OrderInsightFilter.started => order.status == OrderStatus.inProgress,
      OrderInsightFilter.stalled => _isStalled(order),
      OrderInsightFilter.old => _isOld(order),
    };
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.orders.where(_matchesFilter).toList(growable: false);
    final unattached = visible
        .where((order) => !_hasPipeline(order))
        .toList(growable: false);
    final attached = visible
        .where(_hasPipeline)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        if (!widget.fulfilmentLoaded) ...[
          const SizedBox(height: 10),
          Row(
            children: const [
              SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 9),
              Text(
                'Loading production figures — rows may move once they arrive.',
                style: TextStyle(
                  color: SoftErpTheme.textSecondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        Expanded(
          child: widget.orders.isEmpty
              ? const AppEmptyState(
                  title: 'No orders yet',
                  message: 'Insights appear once the order book has entries.',
                  icon: Icons.insights_outlined,
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    _OrderInsightRow(
                      title: 'Waiting on a pipeline',
                      caption:
                          'No pipeline run is attached, so there is no route '
                          'to produce these on yet.',
                      accent: SoftErpTheme.warningText,
                      accentBg: SoftErpTheme.warningBg,
                      orders: unattached,
                      fulfilment: widget.fulfilment,
                      onOpenChallan: widget.onOpenChallan,
                      showFulfilment: false,
                      emptyMessage: 'Every order has a pipeline. Nothing blocked.',
                      isStalled: _isStalled,
                      isOld: _isOld,
                    ),
                    const SizedBox(height: 18),
                    _OrderInsightRow(
                      title: 'In production',
                      caption:
                          'Delivered comes from challans; made comes from the '
                          'floor\'s stage reconciliation.',
                      accent: SoftErpTheme.infoText,
                      accentBg: SoftErpTheme.infoBg,
                      orders: attached,
                      fulfilment: widget.fulfilment,
                      onOpenChallan: widget.onOpenChallan,
                      showFulfilment: true,
                      emptyMessage: 'No orders with a pipeline match this filter.',
                      isStalled: _isStalled,
                      isOld: _isOld,
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Text(
          'Order Insights',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: SoftErpTheme.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final filter in OrderInsightFilter.values)
                _FilterPill(
                  label: filter.label,
                  selected: _filter == filter,
                  onTap: () => setState(() => _filter = filter),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        TextButton.icon(
          key: const ValueKey<String>('orders-insights-back'),
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back_rounded, size: 17),
          label: const Text('Order Book'),
          style: TextButton.styleFrom(
            foregroundColor: SoftErpTheme.accent,
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? SoftErpTheme.accent
                : SoftErpTheme.cardSurfaceAlt,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? SoftErpTheme.accent : SoftErpTheme.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : SoftErpTheme.textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// One horizontal band of order cards.
class _OrderInsightRow extends StatelessWidget {
  const _OrderInsightRow({
    required this.title,
    required this.caption,
    required this.accent,
    required this.accentBg,
    required this.orders,
    required this.fulfilment,
    required this.showFulfilment,
    required this.onOpenChallan,
    required this.emptyMessage,
    required this.isStalled,
    required this.isOld,
  });

  final String title;
  final String caption;
  final Color accent;
  final Color accentBg;
  final List<OrderEntry> orders;
  final Map<int, OrderFulfilment> fulfilment;
  final bool showFulfilment;
  final ValueChanged<int>? onOpenChallan;
  final String emptyMessage;
  final bool Function(OrderEntry) isStalled;
  final bool Function(OrderEntry) isOld;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: SoftErpTheme.sectionSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: accentBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: accent.withValues(alpha: 0.25)),
                ),
                child: Text(
                  '${orders.length}',
                  style: TextStyle(
                    color: accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: SoftErpTheme.textPrimary,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      caption,
                      style: const TextStyle(
                        color: SoftErpTheme.textSecondary,
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (orders.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                emptyMessage,
                style: const TextStyle(
                  color: SoftErpTheme.textSecondary,
                  fontSize: 12.5,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            // Cards wrap onto as many rows as they need. A horizontal strip
            // would hide orders off the right edge behind a scroll gesture,
            // which is the opposite of what an overview screen is for — the
            // count in the pill would disagree with what you can see.
            LayoutBuilder(
              builder: (context, constraints) {
                const gap = 12.0;
                const minCardWidth = 244.0;
                final available = constraints.maxWidth;
                final columns = math
                    .max(1, ((available + gap) / (minCardWidth + gap)).floor())
                    .clamp(1, orders.length);
                // Capped so a single card does not stretch the full width of
                // the window.
                const maxCardWidth = 360.0;
                final cardWidth = math.min(
                  (available - gap * (columns - 1)) / columns,
                  maxCardWidth,
                );
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final order in orders)
                      _OrderInsightCard(
                        width: cardWidth,
                        order: order,
                        fulfilment: fulfilment[order.id],
                        showFulfilment: showFulfilment,
                        onOpenChallan: onOpenChallan,
                        stalled: isStalled(order),
                        old: isOld(order),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _OrderInsightCard extends StatelessWidget {
  const _OrderInsightCard({
    required this.width,
    required this.order,
    required this.fulfilment,
    required this.showFulfilment,
    required this.stalled,
    required this.old,
    required this.onOpenChallan,
  });

  final ValueChanged<int>? onOpenChallan;

  /// Sized by the row so every card in a run lines up.
  final double width;
  final OrderEntry order;
  final OrderFulfilment? fulfilment;
  final bool showFulfilment;
  final bool stalled;
  final bool old;

  static String _date(DateTime value) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${value.day} ${months[value.month - 1]} ${value.year}';
  }

  @override
  Widget build(BuildContext context) {
    final delivered = order.totalDeliveredQty;
    final ordered = order.quantity.toDouble();
    final progress = ordered <= 0 ? 0.0 : (delivered / ordered).clamp(0.0, 1.0);
    final invoicedProgress = ordered <= 0
        ? 0.0
        : (order.totalInvoicedQty / ordered).clamp(0.0, 1.0);
    final age = DateTime.now().difference(order.createdAt).inDays;

    return SizedBox(
      width: width,
      // Fixed so cards in the same run share a baseline rather than sizing to
      // their own content and leaving a ragged run.
      height: showFulfilment ? 186 : 148,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: SoftErpTheme.cardSurface,
          borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
          border: Border.all(color: SoftErpTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.orderNo,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SoftErpTheme.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (stalled) const _StateTag(label: 'Stalled', danger: true),
                if (!stalled && old) const _StateTag(label: 'Old'),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              order.clientName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: SoftErpTheme.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              order.itemName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: SoftErpTheme.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
            const Spacer(),
            Row(
              children: [
                const Icon(
                  Icons.event_outlined,
                  size: 13,
                  color: SoftErpTheme.textSecondary,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '${_date(order.createdAt)}  ·  ${age}d old',
                    style: const TextStyle(
                      color: SoftErpTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${order.quantity} ${order.unitSymbol}',
                  style: const TextStyle(
                    color: SoftErpTheme.textPrimary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            if (showFulfilment) ...[
              const SizedBox(height: 10),
              _FulfilmentBar(
                progress: progress,
                invoicedProgress: invoicedProgress,
                delivered: delivered,
                ordered: ordered,
                unitSymbol: order.unitSymbol,
                fulfilment: fulfilment,
                onOpenChallan: onOpenChallan,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StateTag extends StatelessWidget {
  const _StateTag({required this.label, this.danger = false});

  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final fg = danger ? SoftErpTheme.dangerText : SoftErpTheme.warningText;
    final bg = danger ? SoftErpTheme.dangerBg : SoftErpTheme.warningBg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// How far the order has actually got.
///
/// The green fill is PRODUCTION — the quantity the floor has reconciled as
/// made. That is the thing that grows, so it is the thing that fills.
///
/// Deliveries are not growth; they are events. Each one is drawn as a cut
/// straight down through the bar — a knife through the cake — at the point the
/// order had reached when it went out. The invoiced position rides as a
/// second, quieter cut so the two can be compared at a glance.
///
/// When the floor reports in a unit the order was not placed in, no fill is
/// drawn at all: there is no conversion between kilograms and pieces, so any
/// length would be invented. The figure is stated in words instead.
class _FulfilmentBar extends StatelessWidget {
  const _FulfilmentBar({
    required this.progress,
    required this.invoicedProgress,
    required this.delivered,
    required this.ordered,
    required this.unitSymbol,
    required this.fulfilment,
    required this.onOpenChallan,
  });

  /// Opens a challan by id. Null leaves the checkpoints inert.
  final ValueChanged<int>? onOpenChallan;

  /// Delivered against ordered, 0..1. Positions the delivery cut.
  final double progress;
  final double invoicedProgress;
  final double delivered;
  final double ordered;
  final String unitSymbol;
  final OrderFulfilment? fulfilment;

  static String _qty(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final made = fulfilment?.producedQty ?? 0;
    final deliveries = fulfilment?.deliveries ?? const <OrderDelivery>[];
    // Null when the floor's unit differs from the ordered one, or when nothing
    // has been made. Either way there is no honest length to draw.
    final madeProgress = fulfilment?.producedProgress;
    const barHeight = 12.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return SizedBox(
              height: barHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: SoftErpTheme.cardSurfaceAlt,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: SoftErpTheme.border),
                    ),
                  ),
                  if (madeProgress != null && madeProgress > 0)
                    Container(
                      height: barHeight,
                      width: width * madeProgress,
                      decoration: BoxDecoration(
                        color: SoftErpTheme.successText,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  // Invoiced sits underneath the delivery cut: quieter, and
                  // drawn first so a delivery at the same point wins.
                  if (invoicedProgress > 0)
                    _Checkpoint(
                      offset: width * invoicedProgress,
                      barHeight: barHeight,
                      color: SoftErpTheme.textSecondary,
                      thickness: 2,
                      overhang: 2,
                    ),
                  // One cut per challan, at the point the order had reached
                  // when that challan went out. Falls back to a single cut at
                  // the cumulative position when the per-challan breakdown is
                  // not available, so the bar never silently loses its
                  // checkpoint.
                  if (deliveries.isNotEmpty)
                    for (final delivery in deliveries)
                      _Checkpoint(
                        key: ValueKey<String>(
                          'order-insights-checkpoint-${delivery.challanId}',
                        ),
                        offset: ordered <= 0
                            ? 0
                            : width *
                                  (delivery.cumulativeQty / ordered).clamp(
                                    0.0,
                                    1.0,
                                  ),
                        barHeight: barHeight,
                        color: SoftErpTheme.textPrimary,
                        thickness: 2.5,
                        overhang: 4,
                        tooltip: deliveryCheckpointTooltip(
                          delivery,
                          unitSymbol: unitSymbol,
                          orderedQty: ordered,
                        ),
                        onTap: onOpenChallan == null
                            ? null
                            : () => onOpenChallan!(delivery.challanId),
                      )
                  else if (delivered > 0)
                    _Checkpoint(
                      offset: width * progress.clamp(0.0, 1.0),
                      barHeight: barHeight,
                      color: SoftErpTheme.textPrimary,
                      thickness: 2.5,
                      overhang: 4,
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        DefaultTextStyle(
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  made <= 0
                      ? 'Nothing made yet'
                      : madeProgress == null
                      // Stated, not drawn: the units do not line up.
                      ? '${_qty(made)} ${fulfilment!.producedUnitLabel} made'
                      : '${_qty(made)} of ${_qty(ordered)} $unitSymbol made'
                            '  ·  ${(madeProgress * 100).round()}%',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: made > 0
                        ? SoftErpTheme.successText
                        : SoftErpTheme.textSecondary,
                  ),
                ),
              ),
              if (delivered > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '${_qty(delivered)} out',
                  style: const TextStyle(color: SoftErpTheme.textPrimary),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A cut straight down through the bar, overhanging both edges so it reads as
/// a slice through the whole depth rather than a segment of the fill.
///
/// The cut itself is 2-2.5px, far too small to hit. When it carries a
/// [tooltip] or [onTap] it is centred inside a transparent [_hitWidth] target
/// so hovering and clicking work at a normal pointer's precision, while the
/// painted mark stays hairline.
class _Checkpoint extends StatelessWidget {
  const _Checkpoint({
    super.key,
    required this.offset,
    required this.barHeight,
    required this.color,
    required this.thickness,
    required this.overhang,
    this.tooltip,
    this.onTap,
  });

  final double offset;
  final double barHeight;
  final Color color;
  final double thickness;
  final double overhang;
  final String? tooltip;
  final VoidCallback? onTap;

  static const double _hitWidth = 18;

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: thickness,
      height: barHeight + overhang * 2,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(thickness),
      ),
    );

    if (tooltip == null && onTap == null) {
      return Positioned(
        left: offset - thickness / 2,
        top: -overhang,
        child: mark,
      );
    }

    Widget child = SizedBox(
      width: _hitWidth,
      height: barHeight + overhang * 2,
      child: Center(child: mark),
    );

    if (onTap != null) {
      child = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          // Transparent pixels either side of the hairline still have to
          // register, or the target is 2.5px wide in practice.
          behavior: HitTestBehavior.opaque,
          child: child,
        ),
      );
    }

    if (tooltip != null) {
      child = Tooltip(
        message: tooltip!,
        waitDuration: const Duration(milliseconds: 350),
        child: child,
      );
    }

    return Positioned(
      left: offset - _hitWidth / 2,
      top: -overhang,
      child: child,
    );
  }
}

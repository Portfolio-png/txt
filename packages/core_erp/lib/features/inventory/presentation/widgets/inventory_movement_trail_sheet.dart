import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/inventory_repository.dart';
import '../../domain/inventory_control_tower.dart';
import '../providers/inventory_provider.dart';

/// Enhancement 5 — bottom sheet showing the immutable inventory movement ledger
/// that produced an item's on-hand quantity. Tapping a stock cell opens it.
///
/// Reuses the existing [InventoryMovement] domain model (via
/// [ItemMovementTrailEntry]); it adds no new domain object.
class InventoryMovementTrailSheet extends StatefulWidget {
  const InventoryMovementTrailSheet({
    super.key,
    required this.itemId,
    required this.title,
    this.fallbackUnitSymbol = '',
  });

  final int itemId;
  final String title;
  final String fallbackUnitSymbol;

  static Future<void> show(
    BuildContext context, {
    required int itemId,
    required String title,
    String fallbackUnitSymbol = '',
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => InventoryMovementTrailSheet(
        itemId: itemId,
        title: title,
        fallbackUnitSymbol: fallbackUnitSymbol,
      ),
    );
  }

  @override
  State<InventoryMovementTrailSheet> createState() =>
      _InventoryMovementTrailSheetState();
}

class _InventoryMovementTrailSheetState
    extends State<InventoryMovementTrailSheet> {
  late Future<List<ItemMovementTrailEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<InventoryProvider>().loadItemMovementTrail(
      widget.itemId,
    );
  }

  void _reload() {
    setState(() {
      _future = context.read<InventoryProvider>().loadItemMovementTrail(
        widget.itemId,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
            minHeight: 220,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(context),
              const Divider(height: 1),
              Flexible(
                child: FutureBuilder<List<ItemMovementTrailEntry>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 56),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError) {
                      return _buildError(context);
                    }
                    final entries = snapshot.data ?? const [];
                    if (entries.isEmpty) {
                      return _buildEmpty(context);
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemBuilder: (context, index) =>
                          _MovementRow(entry: entries[index], fallbackUnit: widget.fallbackUnitSymbol),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Stock movement history',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_toggle_off_rounded, size: 40, color: Color(0xFF9CA3AF)),
            SizedBox(height: 12),
            Text(
              'No stock movements recorded yet.',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 40, color: Color(0xFFDC2626)),
            const SizedBox(height: 12),
            const Text(
              'Could not load the movement history.',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _reload, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({required this.entry, required this.fallbackUnit});

  final ItemMovementTrailEntry entry;
  final String fallbackUnit;

  @override
  Widget build(BuildContext context) {
    final movement = entry.movement;
    final unit = movement.uom.trim().isNotEmpty
        ? movement.uom.trim()
        : fallbackUnit.trim();
    final added = entry.quantityAdded;
    final isPositive = added > 0;
    final isNegative = added < 0;
    final deltaColor = isPositive
        ? const Color(0xFF15803D)
        : isNegative
            ? const Color(0xFFB91C1C)
            : const Color(0xFF6B7280);
    final deltaText =
        '${isPositive ? '+' : ''}${_formatQty(added)}${unit.isEmpty ? '' : ' $unit'}';
    final label = (movement.sourceLabel?.trim().isNotEmpty ?? false)
        ? movement.sourceLabel!.trim()
        : _movementTypeLabel(movement.movementType);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              isPositive
                  ? Icons.south_west_rounded
                  : isNegative
                      ? Icons.north_east_rounded
                      : Icons.sync_alt_rounded,
              size: 18,
              color: deltaColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDateTime(movement.createdAt) +
                      (movement.actor.trim().isEmpty
                          ? ''
                          : ' · ${movement.actor.trim()}'),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                deltaText,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: deltaColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Bal ${_formatQty(entry.quantityAfter)}${unit.isEmpty ? '' : ' $unit'}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatQty(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final month = _months[(local.month - 1).clamp(0, 11)];
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.day} $month ${local.year}, $hh:$mm';
  }

  static String _movementTypeLabel(InventoryMovementType type) {
    switch (type) {
      case InventoryMovementType.receive:
        return 'Stock received';
      case InventoryMovementType.issue:
        return 'Stock issued';
      case InventoryMovementType.transfer:
        return 'Stock transferred';
      case InventoryMovementType.adjust:
        return 'Stock adjusted';
      case InventoryMovementType.reserve:
        return 'Stock reserved';
      case InventoryMovementType.release:
        return 'Reservation released';
      case InventoryMovementType.consume:
        return 'Stock consumed';
      case InventoryMovementType.split:
        return 'Stock split';
      case InventoryMovementType.merge:
        return 'Stock merged';
    }
  }
}

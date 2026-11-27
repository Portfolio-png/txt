import 'dart:async';

import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/core/widgets/app_button.dart';
import 'package:core_erp/features/auth/presentation/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One field in an [ArrangeableFieldGrid].
class ArrangeableField {
  const ArrangeableField({
    required this.id,
    required this.label,
    required this.child,
    this.wide = false,
  });

  /// Stable: it is what a person's saved order names.
  final String id;
  final String label;
  final Widget child;

  /// Takes a whole row (Capacity, with its unit and tick; a notes box).
  final bool wide;
}

/// A dialog card's fields, two to a row, each movable in place (owner,
/// 2026-11-27: "give an option for each field to jumble their places
/// in-place" — on the Create Machine dialog). Every field has a handle at its
/// left; dropped on another field of the same card, it takes that place. The
/// order is the signed-in person's own, kept on this computer; "Reset order"
/// puts the card back.
class ArrangeableFieldGrid extends StatefulWidget {
  const ArrangeableFieldGrid({
    super.key,
    required this.storeKey,
    required this.fields,
  });

  /// Names this card's order in storage — 'machine_dialog.identity'.
  final String storeKey;
  final List<ArrangeableField> fields;

  @override
  State<ArrangeableFieldGrid> createState() => _ArrangeableFieldGridState();
}

/// What is being dragged: a field of one grid, so another card's fields
/// do not take it.
class _Moving {
  const _Moving(this.grid, this.id);
  final Object grid;
  final String id;
}

class _ArrangeableFieldGridState extends State<ArrangeableFieldGrid> {
  List<String>? _order;
  String? _dragging;

  List<String> get _defaultOrder => [for (final f in widget.fields) f.id];

  List<String> get _currentOrder => _arrangedFrom(_order ?? _defaultOrder);

  /// A kept order as far as it names today's fields; any not in it go in at
  /// their usual place.
  List<String> _arrangedFrom(List<String> kept) {
    final ids = _defaultOrder;
    final known = [
      for (final id in kept)
        if (ids.contains(id)) id,
    ];
    for (final (i, id) in ids.indexed) {
      if (!known.contains(id)) known.insert(i.clamp(0, known.length), id);
    }
    return known;
  }

  bool get _custom {
    final a = _currentOrder;
    final b = _defaultOrder;
    for (var i = 0; i < a.length; i += 1) {
      if (a[i] != b[i]) return true;
    }
    return false;
  }

  String get _prefKey {
    var who = 'local';
    try {
      final id = context.read<AuthProvider>().user?.id;
      if (id != null) who = 'u$id';
    } catch (_) {
      // Nobody signed in here (a test): one order for the computer.
    }
    return 'field_order.${widget.storeKey}.$who';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final kept = prefs.getStringList(_prefKey);
      if (kept == null || !mounted) return;
      setState(() => _order = kept);
    } catch (_) {
      // Nothing kept: the usual order.
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_custom) {
        await prefs.setStringList(_prefKey, _currentOrder);
      } else {
        await prefs.remove(_prefKey);
      }
    } catch (_) {
      // Kept for this session only.
    }
  }

  /// [moved] dropped on [onto]: it takes that field's place.
  void _move(String moved, String onto) {
    final order = _currentOrder;
    if (moved == onto) return;
    final from = order.indexOf(moved);
    final to = order.indexOf(onto);
    final next = [...order]..remove(moved);
    final at = next.indexOf(onto);
    // Moving later lands after the field dropped on; earlier, before it.
    next.insert(from < to ? at + 1 : at, moved);
    setState(() => _order = next);
    unawaited(_save());
  }

  void _reset() {
    setState(() => _order = null);
    unawaited(_save());
  }

  Widget _cell(ArrangeableField field) {
    return DragTarget<_Moving>(
      key: ValueKey<String>('arrange_${widget.storeKey}_${field.id}'),
      onWillAcceptWithDetails: (d) =>
          identical(d.data.grid, this) && d.data.id != field.id,
      onAcceptWithDetails: (d) => _move(d.data.id, field.id),
      builder: (context, candidates, _) => Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: candidates.isEmpty
                  ? Colors.transparent
                  : SoftErpTheme.accent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Draggable<_Moving>(
                data: _Moving(this, field.id),
                onDragStarted: () => setState(() => _dragging = field.id),
                onDragEnd: (_) => setState(() => _dragging = null),
                feedback: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Text(
                      field.label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                child: Tooltip(
                  message:
                      'Drag onto another field to move ${field.label} there '
                      '— your own order',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      key: ValueKey<String>(
                        'arrange_handle_${widget.storeKey}_${field.id}',
                      ),
                      size: 18,
                      color: SoftErpTheme.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Opacity(
                opacity: _dragging == field.id ? 0.4 : 1,
                child: field.child,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final byId = {for (final f in widget.fields) f.id: f};
    final ordered = [
      for (final id in _currentOrder)
        if (byId[id] != null) byId[id]!,
    ];
    // Two to a row, as the card was; a wide field takes its own.
    final rows = <Widget>[];
    for (var i = 0; i < ordered.length; i += 1) {
      final field = ordered[i];
      if (field.wide) {
        rows.add(_cell(field));
        continue;
      }
      final next = i + 1 < ordered.length ? ordered[i + 1] : null;
      if (next != null && !next.wide) {
        rows.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _cell(field)),
              const SizedBox(width: 12),
              Expanded(child: _cell(next)),
            ],
          ),
        );
        i += 1;
      } else {
        rows.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _cell(field)),
              const SizedBox(width: 12),
              const Expanded(child: SizedBox.shrink()),
            ],
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, row) in rows.indexed) ...[
          if (i > 0) const SizedBox(height: 12),
          row,
        ],
        if (_custom) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              key: ValueKey<String>('arrange_reset_${widget.storeKey}'),
              label: 'Reset order',
              icon: Icons.restart_alt_rounded,
              variant: AppButtonVariant.secondary,
              dense: true,
              onPressed: _reset,
            ),
          ),
        ],
      ],
    );
  }
}

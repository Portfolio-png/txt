import 'package:flutter/material.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../domain/group_cover.dart';

/// A group card whose face is a mosaic of the items inside it.
///
/// A group is an abstraction with nothing to photograph, so the card borrows
/// from its contents. That is not decoration: you recognise "Electrical
/// Fittings" by the sockets and bulbs in it far faster than by reading the
/// word, and the mosaic doubles as a glance at what the group actually holds.
///
/// Items without a photo are not holes. They get a lettered tile tinted from
/// their own name, so a group nobody has photographed still reads as a
/// deliberate card rather than a broken one — which matters, because a fresh
/// install has no item photos at all.
class GroupCollageCard extends StatefulWidget {
  const GroupCollageCard({
    super.key,
    required this.name,
    required this.covers,
    required this.basis,
    this.parentName = '',
    this.unitLabel = '',
    this.itemCount = 0,
    this.structureLabel = '',
    this.onTap,
    this.onOpenItems,
    this.onEdit,
  });

  final String name;
  final List<GroupCoverItem> covers;
  final GroupCoverBasis basis;
  final String parentName;
  final String unitLabel;
  final int itemCount;
  final String structureLabel;
  final VoidCallback? onTap;

  /// Opening the group's items is the thing people actually want from a card,
  /// so it is its own affordance rather than hidden behind the editor.
  final VoidCallback? onOpenItems;

  /// Quick-edit action.
  final VoidCallback? onEdit;

  @override
  State<GroupCollageCard> createState() => _GroupCollageCardState();
}

class _GroupCollageCardState extends State<GroupCollageCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            decoration: BoxDecoration(
              color: SoftErpTheme.cardSurface,
              borderRadius: BorderRadius.circular(SoftErpTheme.radiusLg),
              border: Border.all(
                color: _hovered ? SoftErpTheme.accent : SoftErpTheme.border,
              ),
              boxShadow: _hovered
                  ? SoftErpTheme.raisedShadow
                  : SoftErpTheme.subtleShadow,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      GroupCoverMosaic(covers: widget.covers),
                      if (_hovered && widget.onEdit != null)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: _GroupMenuButton(onEdit: widget.onEdit!),
                        ),
                      if (_hovered && widget.onOpenItems != null)
                        Positioned(
                          right: widget.onEdit != null ? 40 : 8,
                          top: 8,
                          child: _OpenItemsButton(onTap: widget.onOpenItems!),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        widget.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SoftErpTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              _subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: SoftErpTheme.textSecondary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (widget.basis !=
                              GroupCoverBasis.empty) ...<Widget>[
                            const SizedBox(width: 6),
                            _BasisChip(basis: widget.basis),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// One line under the name. Short by design — it shares the row with the
  /// basis chip, and the parent group is in the tooltip rather than competing
  /// for width it would only lose to an ellipsis.
  String get _subtitle {
    final parts = <String>[
      if (widget.itemCount > 0)
        '${widget.itemCount} item${widget.itemCount == 1 ? '' : 's'}'
      else
        'No items',
      if (widget.unitLabel.trim().isNotEmpty) widget.unitLabel.trim(),
    ];
    return parts.join('  ·  ');
  }

  /// Everything the face had no room for.
  String get _tooltip {
    final parts = <String>[
      widget.name,
      if (widget.parentName.trim().isNotEmpty) 'in ${widget.parentName.trim()}',
      if (widget.unitLabel.trim().isNotEmpty)
        'measured in ${widget.unitLabel.trim()}',
      if (widget.covers.isNotEmpty)
        '${widget.basis.label}: '
            '${widget.covers.map((cover) => cover.name).join(', ')}',
    ];
    return parts.join('\n');
  }
}

/// The mosaic itself, laid out by how many items there are to show.
///
/// One fills the face; two split it; three give the best item the larger half;
/// four make a grid. Every count gets a layout that looks chosen rather than a
/// grid with gaps in it.
class GroupCoverMosaic extends StatelessWidget {
  const GroupCoverMosaic({super.key, required this.covers});

  final List<GroupCoverItem> covers;

  static const double _gap = 2;

  @override
  Widget build(BuildContext context) {
    final shown = covers.take(4).toList(growable: false);
    if (shown.isEmpty) return const _EmptyFace();

    return switch (shown.length) {
      1 => _tile(shown[0]),
      2 => Row(
        children: <Widget>[
          Expanded(child: _tile(shown[0])),
          const SizedBox(width: _gap),
          Expanded(child: _tile(shown[1])),
        ],
      ),
      // The most-ordered item earns the big half; the other two share the rest.
      3 => Row(
        children: <Widget>[
          Expanded(flex: 3, child: _tile(shown[0])),
          const SizedBox(width: _gap),
          Expanded(
            flex: 2,
            child: Column(
              children: <Widget>[
                Expanded(child: _tile(shown[1])),
                const SizedBox(height: _gap),
                Expanded(child: _tile(shown[2])),
              ],
            ),
          ),
        ],
      ),
      _ => Column(
        children: <Widget>[
          Expanded(
            child: Row(
              children: <Widget>[
                Expanded(child: _tile(shown[0])),
                const SizedBox(width: _gap),
                Expanded(child: _tile(shown[1])),
              ],
            ),
          ),
          const SizedBox(height: _gap),
          Expanded(
            child: Row(
              children: <Widget>[
                Expanded(child: _tile(shown[2])),
                const SizedBox(width: _gap),
                Expanded(child: _tile(shown[3])),
              ],
            ),
          ),
        ],
      ),
    };
  }

  Widget _tile(GroupCoverItem cover) => _CoverTile(cover: cover);
}

/// One item's square: its photo, or its letters on a colour of its own.
class _CoverTile extends StatelessWidget {
  const _CoverTile({required this.cover});

  final GroupCoverItem cover;

  /// A hue derived from the name, so the same item is the same colour every
  /// time and two items side by side are reliably different.
  static Color _tint(String seed) {
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    return HSLColor.fromAHSL(1, (hash % 360).toDouble(), 0.32, 0.62).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final tint = _tint(cover.name);
    final letters = Container(
      color: tint,
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Text(
            cover.initials,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );

    return Tooltip(
      message: cover.isOrdered
          ? '${cover.name}  ·  on ${cover.orderCount} order'
                '${cover.orderCount == 1 ? '' : 's'}'
          : cover.name,
      waitDuration: const Duration(milliseconds: 400),
      child: cover.hasPhoto
          ? Image.network(
              cover.photoUrl,
              fit: BoxFit.cover,
              // A photo that fails to load falls back to the same lettered
              // tile, so a missing file never leaves a grey hole in the grid.
              errorBuilder: (context, error, stack) => letters,
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : Container(color: tint),
            )
          : letters,
    );
  }
}

/// A group with nothing in it. Says so, rather than showing a blank panel that
/// reads as a card that failed to load.
class _EmptyFace extends StatelessWidget {
  const _EmptyFace();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SoftErpTheme.sectionSurface,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const <Widget>[
          Icon(
            Icons.grid_view_outlined,
            size: 22,
            color: SoftErpTheme.textSecondary,
          ),
          SizedBox(height: 6),
          Text(
            'No items yet',
            style: TextStyle(
              color: SoftErpTheme.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Says whether the mosaic is a popularity ranking or just what is newest.
class _BasisChip extends StatelessWidget {
  const _BasisChip({required this.basis});

  final GroupCoverBasis basis;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: SoftErpTheme.sectionSurface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Text(
        basis.label,
        style: const TextStyle(
          color: SoftErpTheme.textPrimary,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _OpenItemsButton extends StatelessWidget {
  const _OpenItemsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'See the items in this group',
      child: Material(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.inventory_2_outlined,
                  size: 13,
                  color: SoftErpTheme.textPrimary,
                ),
                SizedBox(width: 5),
                Text(
                  'Items',
                  style: TextStyle(
                    color: SoftErpTheme.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupMenuButton extends StatelessWidget {
  const _GroupMenuButton({required this.onEdit});

  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(999),
      child: PopupMenuButton<String>(
        tooltip: 'Group options',
        icon: const Icon(
          Icons.more_vert,
          size: 16,
          color: SoftErpTheme.textPrimary,
        ),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 140),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
        ),
        position: PopupMenuPosition.under,
        onSelected: (value) {
          if (value == 'edit') onEdit();
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'edit',
            height: 38,
            child: Row(
              children: [
                Icon(Icons.edit_outlined, size: 16, color: SoftErpTheme.textPrimary),
                SizedBox(width: 8),
                Text(
                  'Edit Group',
                  style: TextStyle(
                    fontSize: 13,
                    color: SoftErpTheme.textPrimary,
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

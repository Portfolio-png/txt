/// The small chrome that says what is inside a group or a set.
///
/// Both of these were private to `items_screen.dart` and are now shared,
/// because the sets master moved out into its own screen and these two were
/// the only things it needed from the file it left. They are presentation
/// only — every count is handed to them already worked out.
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/soft_erp_theme.dart';

/// `12 items`, `3 variants` — a count and what it is counting.
///
/// The colours come from the caller rather than from the label, because the
/// item/variant palette is the same one the rows and cards around it use.
class EntityCountPill extends StatelessWidget {
  const EntityCountPill({
    super.key,
    required this.count,
    required this.label,
    required this.color,
    required this.background,
    required this.border,
  });

  final int count;
  final String label;
  final Color color;
  final Color background;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        '$count $label',
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// One member inside an expanded group or set: its name, colour-coded by
/// whether it is a base item or a spawned variant.
class EntityMemberRow extends StatelessWidget {
  const EntityMemberRow({
    super.key,
    required this.label,
    required this.isVariant,
    this.quantity,
  });

  final String label;
  final bool isVariant;
  final int? quantity;

  @override
  Widget build(BuildContext context) {
    final fg = isVariant ? SoftErpTheme.entityVariant : SoftErpTheme.entityItem;
    final bg = isVariant
        ? SoftErpTheme.entityVariantBg
        : SoftErpTheme.entityItemBg;
    final border = isVariant
        ? SoftErpTheme.entityVariantBorder
        : SoftErpTheme.entityItemBorder;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (quantity != null) ...[
              const SizedBox(width: 6),
              Text(
                '×$quantity',
                style: TextStyle(
                  color: fg,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/soft_erp_theme.dart';

/// The chrome of one Miller column: a card with a header, an optional search
/// line, a scrolling body, and a footer that does not scroll with it.
///
/// Extracted from the link graph's column view so the catalog quick-entry
/// wizard draws the same column rather than a lookalike. Both are the same
/// gesture — pick something on the left, act on it to the right — and a column
/// that looked slightly different in each would read as two unrelated screens.
class ErpMillerColumn extends StatelessWidget {
  const ErpMillerColumn({
    super.key,
    required this.header,
    required this.body,
    this.search,
    this.footer,
  });

  final Widget header;
  final Widget body;
  final Widget? search;

  /// Sits below the list, outside its scroll, so it stays reachable however
  /// long the column gets.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusLg),
        border: Border.all(color: SoftErpTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (search != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: search!,
            ),
          const Divider(height: 1, color: SoftErpTheme.border),
          Expanded(child: body),
          if (footer != null) ...[
            const Divider(height: 1, color: SoftErpTheme.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: footer!,
            ),
          ],
        ],
      ),
    );
  }
}

/// A column's title row: what this column holds, how many, and what the next
/// action on it will do (the subtitle).
class ErpMillerColumnHeader extends StatelessWidget {
  const ErpMillerColumnHeader({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.count,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final String? subtitle;
  final int? count;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      child: Row(
        children: [
          Icon(icon, size: 22, color: SoftErpTheme.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: SoftErpTheme.textPrimary,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: SoftErpTheme.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 6),
            ErpMillerColumnBadge(label: '$count'),
          ],
          ?trailing,
        ],
      ),
    );
  }
}

/// The count pill on a column header.
class ErpMillerColumnBadge extends StatelessWidget {
  const ErpMillerColumnBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: SoftErpTheme.accentSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: SoftErpTheme.accentDeeper,
        ),
      ),
    );
  }
}

/// What a column says when it holds nothing — a sentence, not an empty box.
class ErpMillerColumnEmpty extends StatelessWidget {
  const ErpMillerColumnEmpty({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 14.5,
          color: SoftErpTheme.textSecondary,
        ),
      ),
    ),
  );
}

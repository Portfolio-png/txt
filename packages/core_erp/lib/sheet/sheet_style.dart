import 'package:flutter/material.dart';

import '../core/theme/soft_erp_theme.dart';

/// The item sheet's fixed visual vocabulary: cards, headings, labels.
///
/// [SheetMetrics] answers what changes with the viewport (row height, column
/// width, type size in the grid). This answers what does not, and it is all
/// drawn from [SoftErpTheme] — the sheet used to paint its own slate palette
/// (139 hex literals, radii 3/4/6/7/8/10) beside sections that used the theme,
/// so a die section mounted on it sat as a card inside a differently bordered
/// card.
abstract final class SheetStyle {
  /// Inside a section card, and between one card and the next.
  static const double cardPadding = 14;
  static const double cardGap = 14;

  static BoxDecoration card() => BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        border: Border.all(color: SoftErpTheme.border),
      );

  /// A section's name, and the raw material panel's.
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w900,
    color: SoftErpTheme.textPrimary,
  );

  /// A heading inside a section: "Dies · …", "People at …".
  static const TextStyle subHeading = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w800,
    color: SoftErpTheme.textPrimary,
  );

  /// An uppercase group heading: THE SHEET, OPERATION, THIS SHEET YIELDS.
  static const TextStyle eyebrow = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w800,
    color: SoftErpTheme.textSecondary,
    letterSpacing: 0.7,
  );

  /// The name beside or above a value.
  static const TextStyle label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w800,
    color: SoftErpTheme.textSecondary,
    letterSpacing: 0.5,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    color: SoftErpTheme.textPrimary,
  );

  static const TextStyle hint = TextStyle(
    fontSize: 14,
    color: SoftErpTheme.textSecondary,
  );

  /// Empty values and separators.
  static const TextStyle muted = TextStyle(
    fontSize: 14,
    color: SoftErpTheme.textMuted,
  );

  /// The 32px square that carries a section's icon.
  static Widget iconTile(IconData icon) => Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: SoftErpTheme.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
        ),
        child: Icon(icon, size: 18, color: SoftErpTheme.accent),
      );
}

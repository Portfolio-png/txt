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

  /// A field's name above its box — the one way a field on the sheet is
  /// labelled. Floating labels shrank to about 10 px on the border, and the
  /// die and machine forms named a field only while it was empty; a heading
  /// stays readable and stays put. [actions] sit after the name (a
  /// property's Edit and Delete); the heading row is one height with or
  /// without them, so boxes on a line stay level.
  static Widget labelled({
    required String label,
    required Widget child,
    List<Widget> actions = const [],
    Key? key,
  }) =>
      Column(
        key: key,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 28,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: SheetStyle.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (actions.isNotEmpty) ...[const SizedBox(width: 4), ...actions],
              ],
            ),
          ),
          const SizedBox(height: 2),
          child,
        ],
      );

  /// Every typed field on the sheet below the grid — the deal, people, dies,
  /// machines. They used to take whatever the field widget defaulted to:
  /// dense beside not, radius 14 enabled and 4 disabled, helpers cut to one
  /// line ("One figure for the p…"). Helpers and errors wrap to two lines.
  static InputDecoration field({
    String? label,
    String? hint,
    String? helper,
    String? error,
    Widget? suffixIcon,
    String? suffixText,
  }) {
    OutlineInputBorder border(Color colour, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(SoftErpTheme.radiusControl),
          borderSide: BorderSide(color: colour, width: width),
        );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      errorText: error,
      suffixIcon: suffixIcon,
      suffixText: suffixText,
      isDense: true,
      filled: true,
      fillColor: SoftErpTheme.cardSurfaceAlt,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      labelStyle: const TextStyle(fontSize: 14, color: SoftErpTheme.textSecondary),
      hintStyle: hint == null ? null : SheetStyle.muted,
      helperStyle: const TextStyle(fontSize: 13, color: SoftErpTheme.textSecondary),
      errorStyle: const TextStyle(fontSize: 13, color: SoftErpTheme.dangerText),
      helperMaxLines: 2,
      errorMaxLines: 2,
      border: border(SoftErpTheme.border),
      enabledBorder: border(SoftErpTheme.border),
      disabledBorder: border(SoftErpTheme.border.withValues(alpha: 0.6)),
      focusedBorder: border(SoftErpTheme.accent, 1.6),
      errorBorder: border(SoftErpTheme.dangerText),
      focusedErrorBorder: border(SoftErpTheme.dangerText, 1.6),
    );
  }

  /// "Unsaved" — a section holding changes its own Save has not written.
  static Widget unsavedPill({String label = 'Unsaved', Key? key}) => Container(
        key: key,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: SoftErpTheme.warningBg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: SoftErpTheme.warningBorder),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: SoftErpTheme.warningText,
          ),
        ),
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

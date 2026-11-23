import 'package:flutter/material.dart';

class SoftErpTheme {
  static const Color canvas = Color(0xFFE8E8F0);
  static const Color canvasAlt = Color(0xFFA7B9F9);
  static const Color shellSurface = Color(0xFFF8F9FD);
  static const Color cardSurface = Color(0xFFFFFFFF);
  static const Color cardSurfaceAlt = Color(0xFFF7F7FB);
  static const Color sectionSurface = Color(0xFFF6F7FB);
  static const Color border = Color(0xFFE6E8F4);
  static const Color borderStrong = Color(0xFFDDE0F0);
  static const Color textPrimary = Color(0xFF303646);
  static const Color textSecondary = Color(0xFF6C7386);
  // Placeholders, separators and anything greyed out — a step lighter than
  // textSecondary so an empty value never reads as an entered one.
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color accent = Color(0xFF5E49E6);
  static const Color accentDark = Color(0xFF4F43E8);
  static const Color accentDeeper = Color(0xFF4740B7);
  static const Color accentSoft = Color(0xFFECEBFF);
  static const Color accentSurface = Color(0xFFF1EEFF);
  static const Color successBg = Color(0xFFEAF8EE);
  static const Color successText = Color(0xFF0F8B45);

  static const Color warningBg = Color(0xFFFFF6E9);
  static const Color warningText = Color(0xFF946200);
  static const Color warningBorder = Color(0xFFFDE68A);
  static const Color infoBg = Color(0xFFEBF2FF);
  static const Color infoText = Color(0xFF2E57C7);
  static const Color dangerBg = Color(0xFFFDEDEE);
  static const Color dangerText = Color(0xFFC62828);
  // --- Entity kind ---------------------------------------------------------
  // Distinguishes a base item from a spawned variant ("basic item") wherever
  // the two appear in one list — combination groups, inventory sets, pickers.
  // Deliberately blue vs teal rather than reusing success green or warning
  // amber, which already carry status meaning in those same lists.
  static const Color entityItem = Color(0xFF2E57C7);
  static const Color entityItemBg = Color(0xFFEBF2FF);
  static const Color entityItemBorder = Color(0xFFC7D6F5);
  static const Color entityVariant = Color(0xFF0D7C86);
  static const Color entityVariantBg = Color(0xFFE4F5F7);
  static const Color entityVariantBorder = Color(0xFFB6E2E7);

  static const Color draftRowEdgeTint = Color(0x146366F1);
  static const Color notStartedRowEdgeTint = Color(0x14D08A2A);
  static const Color inProgressRowEdgeTint = Color(0x143F74E0);
  static const Color completedRowEdgeTint = Color(0x1417A85C);
  static const Color delayedRowEdgeTint = Color(0x17D35A5A);

  // Small chrome inside a card: chips, tags, state badges, icon tiles.
  static const double radiusXs = 6;
  static const double radiusSm = 12;
  // Every field and button the app theme draws (inputs, text/outlined/filled
  // buttons) — named so a hand-built control can match them.
  static const double radiusControl = 14;
  static const double radiusMd = 18;
  static const double radiusLg = 24;
  static const double radiusXl = 30;

  static const LinearGradient accentGradient = LinearGradient(
    colors: [accent, accentDark],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // --- Part tabs -----------------------------------------------------------
  // One per part open on the item sheet, taken in turn: the tab and the frame
  // round the sheet are drawn in the part's colour, so landing on another
  // part by mistake shows at once. Ordered by the four distinct identities:
  // Blue (#4285F4), Yellow (#FBBC05), Red (#EA4335), Green (#34A853), each
  // ranging smoothly from light luminous highlight through intermediate shades
  // to deep grounding dark.
  static const List<LinearGradient> partTabGradients = <LinearGradient>[
    // 1. Blue (#4285F4) ranging light to dark
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF8AB4F8), // light luminous blue
        Color(0xFF669DF6), // intermediate mid-light
        Color(0xFF4285F4), // base vibrant blue (#4285F4)
        Color(0xFF1A73E8), // intermediate mid-dark
        Color(0xFF174EA6), // deep dark royal blue
      ],
      stops: [0.0, 0.25, 0.50, 0.75, 1.0],
    ),
    // 2. Yellow (#FBBC05) ranging light to dark
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFFFDE293), // light luminous gold
        Color(0xFFFDD663), // intermediate mid-light
        Color(0xFFFBBC05), // base vibrant yellow (#FBBC05)
        Color(0xFFF29900), // intermediate rich amber
        Color(0xFFE37400), // deep dark warm amber
      ],
      stops: [0.0, 0.25, 0.50, 0.75, 1.0],
    ),
    // 3. Red (#EA4335) ranging light to dark
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFFF6AEA9), // light luminous coral/rose
        Color(0xFFEE675C), // intermediate mid-light
        Color(0xFFEA4335), // base vibrant red (#EA4335)
        Color(0xFFD93025), // intermediate deep crimson
        Color(0xFFA50E0E), // deep dark ruby
      ],
      stops: [0.0, 0.25, 0.50, 0.75, 1.0],
    ),
    // 4. Green (#34A853) ranging light to dark
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFFA8DAB5), // light luminous mint
        Color(0xFF5BB974), // intermediate mid-light
        Color(0xFF34A853), // base vibrant green (#34A853)
        Color(0xFF1E8E3E), // intermediate deep emerald
        Color(0xFF0D652D), // deep dark forest
      ],
      stops: [0.0, 0.25, 0.50, 0.75, 1.0],
    ),
  ];

  // Clean, neutral elevation system: soft surfaces without glow haze.
  static const List<BoxShadow> insetShadow = <BoxShadow>[
    BoxShadow(color: Color(0x0C000000), blurRadius: 6, offset: Offset(0, 2)),
  ];

  static const List<BoxShadow> raisedShadow = <BoxShadow>[
    BoxShadow(color: Color(0x0E7480C3), blurRadius: 22, offset: Offset(0, 10)),
  ];

  static const List<BoxShadow> subtleShadow = <BoxShadow>[
    BoxShadow(color: Color(0x0A818CD1), blurRadius: 16, offset: Offset(0, 6)),
  ];

  static BoxDecoration surfaceDecoration({
    Color color = cardSurface,
    double radius = radiusMd,
    bool elevated = true,
    bool strongBorder = false,
    bool showBorder = true,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: showBorder
          ? Border.all(color: strongBorder ? borderStrong : border)
          : null,
      boxShadow: elevated ? raisedShadow : subtleShadow,
    );
  }
}

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
  static const Color accent = Color(0xFF5E49E6);
  static const Color accentDark = Color(0xFF4F43E8);
  static const Color accentDeeper = Color(0xFF4740B7);
  static const Color accentSoft = Color(0xFFECEBFF);
  static const Color accentSurface = Color(0xFFF1EEFF);
  static const Color successBg = Color(0xFFEAF8EE);
  static const Color successText = Color(0xFF0F8B45);
  static const Color warningBg = Color(0xFFFFF6E9);
  static const Color warningText = Color(0xFF946200);
  static const Color infoBg = Color(0xFFEBF2FF);
  static const Color infoText = Color(0xFF2E57C7);
  static const Color dangerBg = Color(0xFFFDEDEE);
  static const Color dangerText = Color(0xFFC62828);
  static const Color draftRowEdgeTint = Color(0x146366F1);
  static const Color notStartedRowEdgeTint = Color(0x14D08A2A);
  static const Color inProgressRowEdgeTint = Color(0x143F74E0);
  static const Color completedRowEdgeTint = Color(0x1417A85C);
  static const Color delayedRowEdgeTint = Color(0x17D35A5A);

  static const double radiusSm = 12;
  static const double radiusMd = 18;
  static const double radiusLg = 24;
  static const double radiusXl = 30;

  static const LinearGradient accentGradient = LinearGradient(
    colors: [accent, accentDark],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

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

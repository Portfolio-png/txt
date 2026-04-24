import 'package:flutter/material.dart';

class SoftErpTheme {
  static const Color canvas = Color(0xFFF1F2F8);
  static const Color canvasAlt = Color(0xFFEDEFF8);
  static const Color shellSurface = Color(0xFFF7F8FC);
  static const Color cardSurface = Color(0xFFFAFBFF);
  static const Color cardSurfaceAlt = Color(0xFFF3F5FD);
  static const Color sectionSurface = Color(0xFFF6F7FD);
  static const Color border = Color(0xFFDCE1F0);
  static const Color borderStrong = Color(0xFFCCD4EA);
  static const Color textPrimary = Color(0xFF303646);
  static const Color textSecondary = Color(0xFF6C7386);
  static const Color accent = Color(0xFF6366F1);
  static const Color accentDark = Color(0xFF4F56D9);
  static const Color accentDeeper = Color(0xFF4149C8);
  static const Color accentSoft = Color(0xFFECEBFF);
  static const Color accentSurface = Color(0xFFF4F1FF);
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
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Soft "pressed" alternative for controls where true inset shadow
  // support may vary across Flutter versions.
  static const List<BoxShadow> insetShadow = <BoxShadow>[
    BoxShadow(color: Color(0x66FFFFFF), blurRadius: 4, offset: Offset(-1, -1)),
    BoxShadow(color: Color(0x12909DC3), blurRadius: 6, offset: Offset(1, 1)),
  ];

  static const List<BoxShadow> raisedShadow = <BoxShadow>[
    BoxShadow(color: Color(0x1A919CC5), blurRadius: 20, offset: Offset(0, 10)),
    BoxShadow(color: Color(0xAAFFFFFF), blurRadius: 8, offset: Offset(-2, -2)),
  ];

  static const List<BoxShadow> subtleShadow = <BoxShadow>[
    BoxShadow(color: Color(0x12909DC3), blurRadius: 12, offset: Offset(0, 6)),
    BoxShadow(
      color: Color(0xCCFFFFFF),
      blurRadius: 6,
      offset: Offset(-1.5, -1.5),
    ),
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

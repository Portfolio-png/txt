import 'package:flutter/material.dart';

import '../../../core/theme/soft_erp_theme.dart';
import '../domain/rivet.dart';

/// The rivet, drawn the way the owner drew it: the head on top (a flat,
/// tapered head or a round dome), its silver layer, the shank below, and each
/// dimension labelled with the value typed for it.
///
/// Schematic, not to scale — like the owner's sketch. A drawing scaled to the
/// numbers would turn into a sliver for a long thin rivet and hide the very
/// labels it is there to show. [focused] lights up the dimension being typed,
/// so the form and the drawing read as one.
class RivetDrawing extends StatelessWidget {
  const RivetDrawing({
    super.key,
    required this.headType,
    required this.values,
    this.rivetType = 'Bimetal',
    this.focused,
  });

  /// Bimetal, Copper or Aluminium: the metal it is drawn in, and whether it
  /// has a silver layer (only Bimetal).
  final String rivetType;
  final RivetHeadType headType;

  /// Millimetres as typed; blank shows as —.
  final Map<RivetDimension, String> values;
  final RivetDimension? focused;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Rivet drawing, ${headType.label.toLowerCase()} head',
      child: AspectRatio(
        aspectRatio: 1.08,
        child: CustomPaint(
          painter: _RivetPainter(
            rivetType: rivetType,
            headType: headType,
            values: values,
            focused: focused,
          ),
        ),
      ),
    );
  }
}

class _RivetPainter extends CustomPainter {
  _RivetPainter({
    required this.rivetType,
    required this.headType,
    required this.values,
    required this.focused,
  });

  final String rivetType;
  final RivetHeadType headType;
  final Map<RivetDimension, String> values;
  final RivetDimension? focused;

  bool get _silvered => rivetHasSilverLayer(rivetType);

  /// Copper for Bimetal and Copper (a bimetal rivet is copper under its
  /// silver), aluminium grey for Aluminium, plain steel while none is picked.
  (Color, Color) get _metal => switch (rivetType.trim().toLowerCase()) {
    'bimetal' || 'copper' => (const Color(0xFFC77B4A), const Color(0xFF8E4E2A)),
    'aluminium' ||
    'aluminum' => (const Color(0xFFC9CED6), const Color(0xFF8D949E)),
    _ => (const Color(0xFF8C929C), const Color(0xFF5F6570)),
  };
  static const Color _silver = Color(0xFFE9EBF0);
  static const Color _line = Color(0xFF4B5263);

  Color _ink(RivetDimension dim) =>
      focused == dim ? SoftErpTheme.accent : _line;

  /// The canvas, so a label near an edge is kept inside it.
  Size _canvas = Size.zero;

  @override
  void paint(Canvas canvas, Size size) {
    _canvas = size;
    final w = size.width;
    final h = size.height;
    final cx = w * 0.46;

    // Geometry, as fractions of the box.
    final headOdHalf = w * 0.24;
    final headTopHalf = w * 0.15;
    final shankHalf = w * 0.085;
    final headTop = h * 0.24;
    final headBottom = h * 0.40;
    final silverDepth = (headBottom - headTop) * 0.34;
    final shankBottom = h * 0.80;

    final bodyPaint = Paint()
      ..shader = LinearGradient(
        colors: <Color>[_metal.$2, _metal.$1, _metal.$2],
        stops: const <double>[0, 0.45, 1],
      ).createShader(Rect.fromLTWH(cx - headOdHalf, 0, headOdHalf * 2, h));
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = _line;

    // Shank.
    final shank = RRect.fromRectAndCorners(
      Rect.fromLTRB(
        cx - shankHalf,
        headBottom - 1,
        cx + shankHalf,
        shankBottom,
      ),
      bottomLeft: const Radius.circular(6),
      bottomRight: const Radius.circular(6),
    );
    canvas.drawRRect(shank, bodyPaint);
    canvas.drawRRect(
      shank,
      outline
        ..color =
            _isLit(RivetDimension.shankDia) ||
                _isLit(RivetDimension.shankLength)
            ? SoftErpTheme.accent
            : _line,
    );

    // Head and its silver layer.
    final head = Path();
    final silver = Path();
    if (headType == RivetHeadType.flat) {
      head
        ..moveTo(cx - headOdHalf, headBottom)
        ..lineTo(cx - headTopHalf, headTop)
        ..lineTo(cx + headTopHalf, headTop)
        ..lineTo(cx + headOdHalf, headBottom)
        ..close();
      final slope = (headOdHalf - headTopHalf) / (headBottom - headTop);
      final inset = headTopHalf + slope * silverDepth;
      silver
        ..moveTo(cx - headTopHalf, headTop)
        ..lineTo(cx + headTopHalf, headTop)
        ..lineTo(cx + inset, headTop + silverDepth)
        ..lineTo(cx - inset, headTop + silverDepth)
        ..close();
    } else {
      final dome = Rect.fromLTRB(
        cx - headOdHalf,
        headTop - (headBottom - headTop) * 0.35,
        cx + headOdHalf,
        headBottom + (headBottom - headTop) * 1.35,
      );
      head
        ..moveTo(cx - headOdHalf, headBottom)
        ..arcTo(dome, 3.14159, 3.14159, false)
        ..close();
      final inner = dome.deflate(silverDepth * 0.9);
      silver
        ..moveTo(cx - headOdHalf, headBottom)
        ..arcTo(dome, 3.14159, 3.14159, false)
        ..lineTo(inner.right, headBottom)
        ..arcTo(inner, 0, -3.14159, false)
        ..close();
    }
    canvas.drawPath(head, bodyPaint);
    if (_silvered) {
      canvas.drawPath(
        silver,
        Paint()
          ..color = _isLit(RivetDimension.silverLayer)
              ? SoftErpTheme.accentSoft
              : _silver,
      );
      canvas.drawPath(
        silver,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = _isLit(RivetDimension.silverLayer)
              ? SoftErpTheme.accent
              : _line.withValues(alpha: 0.5),
      );
    }
    canvas.drawPath(
      head,
      outline
        ..color =
            _isLit(RivetDimension.headOd) || _isLit(RivetDimension.headDia)
            ? SoftErpTheme.accent
            : _line,
    );

    // Head Diameter — across the top face, called out from above.
    final topY = headType == RivetHeadType.flat
        ? headTop
        : headTop - (headBottom - headTop) * 0.35;
    _span(
      canvas,
      RivetDimension.headDia,
      Offset(cx - headTopHalf, topY - 14),
      Offset(cx + headTopHalf, topY - 14),
    );
    _label(
      canvas,
      RivetDimension.headDia,
      Offset(cx, topY - 22),
      _Anchor.bottomCenter,
    );

    // Head OD — across the widest part of the head, called out at the right.
    _span(
      canvas,
      RivetDimension.headOd,
      Offset(cx - headOdHalf, headBottom + 12),
      Offset(cx + headOdHalf, headBottom + 12),
    );
    _arrow(
      canvas,
      RivetDimension.headOd,
      Offset(w * 0.80, headBottom - 4),
      Offset(cx + headOdHalf + 4, headBottom - 2),
    );
    _label(
      canvas,
      RivetDimension.headOd,
      Offset(w * 0.81, headBottom - 4),
      _Anchor.centerLeft,
    );

    // Silver Layer — the band on top of the head, called out at the left.
    // Only a bimetal rivet has one.
    if (_silvered) {
      final silverMid = Offset(
        cx - headTopHalf * 0.55,
        (headType == RivetHeadType.flat ? headTop : topY) + silverDepth * 0.55,
      );
      _arrow(
        canvas,
        RivetDimension.silverLayer,
        Offset(w * 0.15, headTop - 6),
        silverMid,
      );
      _label(
        canvas,
        RivetDimension.silverLayer,
        Offset(w * 0.15, headTop - 10),
        _Anchor.bottomCenter,
      );
    }

    // Shank Length — down the right of the shank.
    final lenX = cx + shankHalf + 18;
    _span(
      canvas,
      RivetDimension.shankLength,
      Offset(lenX, headBottom),
      Offset(lenX, shankBottom),
      vertical: true,
    );
    _label(
      canvas,
      RivetDimension.shankLength,
      Offset(lenX + 12, (headBottom + shankBottom) / 2 + 10),
      _Anchor.centerLeft,
    );

    // Shank Diameter — across the bottom of the shank.
    _span(
      canvas,
      RivetDimension.shankDia,
      Offset(cx - shankHalf, shankBottom + 12),
      Offset(cx + shankHalf, shankBottom + 12),
    );
    _label(
      canvas,
      RivetDimension.shankDia,
      Offset(cx, shankBottom + 22),
      _Anchor.topCenter,
    );
  }

  bool _isLit(RivetDimension dim) => focused == dim;

  /// A dimension line with end ticks.
  void _span(
    Canvas canvas,
    RivetDimension dim,
    Offset a,
    Offset b, {
    bool vertical = false,
  }) {
    final paint = Paint()
      ..color = _ink(dim)
      ..strokeWidth = _isLit(dim) ? 2 : 1.2;
    canvas.drawLine(a, b, paint);
    const t = 5.0;
    for (final p in <Offset>[a, b]) {
      if (vertical) {
        canvas.drawLine(p.translate(-t, 0), p.translate(t, 0), paint);
      } else {
        canvas.drawLine(p.translate(0, -t), p.translate(0, t), paint);
      }
    }
  }

  void _arrow(Canvas canvas, RivetDimension dim, Offset from, Offset to) {
    final paint = Paint()
      ..color = _ink(dim)
      ..strokeWidth = _isLit(dim) ? 2 : 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(from, to, paint);
    final dir = (to - from);
    final unit = dir / dir.distance;
    final normal = Offset(-unit.dy, unit.dx);
    final head = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo((to - unit * 8 + normal * 4).dx, (to - unit * 8 + normal * 4).dy)
      ..lineTo((to - unit * 8 - normal * 4).dx, (to - unit * 8 - normal * 4).dy)
      ..close();
    canvas.drawPath(head, Paint()..color = _ink(dim));
  }

  void _label(Canvas canvas, RivetDimension dim, Offset at, _Anchor anchor) {
    final lit = _isLit(dim);
    final value = (values[dim] ?? '').trim();
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      text: TextSpan(
        children: <InlineSpan>[
          TextSpan(
            text: '${dim.label}\n',
            style: TextStyle(
              fontSize: 14,
              fontWeight: lit ? FontWeight.w800 : FontWeight.w600,
              color: lit ? SoftErpTheme.accent : SoftErpTheme.textSecondary,
            ),
          ),
          TextSpan(
            text: value.isEmpty ? '—' : '$value mm',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: lit ? SoftErpTheme.accentDark : SoftErpTheme.textPrimary,
            ),
          ),
        ],
      ),
    )..layout();
    final size = painter.size;
    final raw = switch (anchor) {
      _Anchor.bottomCenter => at.translate(-size.width / 2, -size.height),
      _Anchor.topCenter => at.translate(-size.width / 2, 0),
      _Anchor.centerLeft => at.translate(0, -size.height / 2),
    };
    // Inside the canvas, whatever the label's length.
    final origin = Offset(
      raw.dx.clamp(
        4.0,
        (_canvas.width - size.width - 4).clamp(4.0, double.infinity),
      ),
      raw.dy.clamp(
        4.0,
        (_canvas.height - size.height - 4).clamp(4.0, double.infinity),
      ),
    );
    if (lit) {
      final box = RRect.fromRectAndRadius(
        (origin & size).inflate(6),
        const Radius.circular(8),
      );
      canvas.drawRRect(box, Paint()..color = SoftErpTheme.accentSurface);
    }
    painter.paint(canvas, origin);
  }

  @override
  bool shouldRepaint(_RivetPainter old) =>
      old.headType != headType ||
      old.rivetType != rivetType ||
      old.focused != focused ||
      !_sameValues(old.values, values);

  static bool _sameValues(
    Map<RivetDimension, String> a,
    Map<RivetDimension, String> b,
  ) {
    for (final dim in RivetDimension.values) {
      if ((a[dim] ?? '') != (b[dim] ?? '')) return false;
    }
    return true;
  }
}

enum _Anchor { bottomCenter, topCenter, centerLeft }

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/soft_erp_theme.dart';
import '../domain/spring.dart' show SpringKind;

/// What the spring drawing can light up: the field being typed.
enum SpringMark {
  coilNumber('Coil Number'),
  coilHook('Coil Hook'),
  coilLength('Coil Length'),
  coilOd('Coil OD'),
  coilId('Coil ID'),
  wireGauge('Wire Gauge'),
  freeLength('Free Length'),
  totalCoils('Total Coils'),
  smallOd('Small OD'),
  largeOd('Large OD'),
  wireDiameter('Wire Diameter');

  const SpringMark(this.label);

  final String label;
}

/// The spring, drawn the way the owner drew it: the coil with a hook at each
/// end, Coil Number called out from above, Coil Hook from the right, Coil
/// Length spanned underneath. The side view cannot show the coil's diameters,
/// so a small end view beside it carries Coil OD, Coil ID and the wire.
///
/// Schematic, not to scale (like the rivet's): the coils drawn follow the
/// count up to what can be told apart. [focused] lights up the field being
/// typed.
class SpringDrawing extends StatelessWidget {
  const SpringDrawing({
    super.key,
    required this.values,
    this.focused,
    this.kind = SpringKind.doubleHook,
  });

  /// Double Hook: the coil with a hook at each end. Iron Connector: the same
  /// coil, plain legs (no drawing of one yet). Conical: wound down from a
  /// large end to a small one, as the owner's picture.
  final SpringKind kind;

  /// What is typed for each mark; blank shows as —.
  final Map<SpringMark, String> values;
  final SpringMark? focused;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Spring drawing',
      child: AspectRatio(
        aspectRatio: 1.08,
        child: CustomPaint(
          painter: _SpringPainter(values: values, focused: focused, kind: kind),
        ),
      ),
    );
  }
}

class _SpringPainter extends CustomPainter {
  _SpringPainter({
    required this.values,
    required this.focused,
    required this.kind,
  });

  final SpringKind kind;

  final Map<SpringMark, String> values;
  final SpringMark? focused;

  static const Color _steel = Color(0xFFB7BEC8);
  static const Color _steelDark = Color(0xFF6E7681);
  static const Color _line = Color(0xFF4B5263);

  Size _canvas = Size.zero;

  bool _lit(SpringMark mark) => focused == mark;
  Color _ink(SpringMark mark) => _lit(mark) ? SoftErpTheme.accent : _line;

  @override
  void paint(Canvas canvas, Size size) {
    _canvas = size;
    if (kind == SpringKind.conical) {
      _paintConical(canvas, size);
      return;
    }
    final hooks = kind == SpringKind.doubleHook;
    final w = size.width;
    final h = size.height;

    // The side view, in the upper part.
    final left = w * 0.24;
    final right = w * 0.76;
    final cy = h * 0.36;
    final half = h * 0.085; // half the coil's height
    final hookR = half * 1.05;

    final wire = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.4, half * 0.22)
      ..strokeCap = StrokeCap.round;

    // Hooks: an open loop at each end — or, on an iron connector, a short
    // straight leg.
    final hookPaint = Paint.from(wire)
      ..color = _lit(SpringMark.coilHook) ? SoftErpTheme.accent : _steelDark;
    if (!hooks) {
      canvas.drawLine(
        Offset(left - hookR * 1.4, cy),
        Offset(left, cy),
        hookPaint,
      );
      canvas.drawLine(
        Offset(right, cy),
        Offset(right + hookR * 1.4, cy),
        hookPaint,
      );
    }
    if (hooks) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(left - hookR * 0.9, cy), radius: hookR),
        -math.pi * 0.25,
        -math.pi * 1.55,
        false,
        hookPaint,
      );
    }
    if (hooks) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(right + hookR * 0.9, cy), radius: hookR),
        math.pi * 0.75,
        -math.pi * 1.55,
        false,
        hookPaint,
      );
    }

    // The coils: as many as typed, up to what can be told apart.
    final typed = int.tryParse((values[SpringMark.coilNumber] ?? '').trim());
    final coils = (typed ?? 18).clamp(4, 28);
    final pitch = (right - left) / coils;
    final coilPaint = Paint.from(wire)
      ..color = _lit(SpringMark.coilNumber) || _lit(SpringMark.coilLength)
          ? SoftErpTheme.accent
          : _steelDark;
    final shine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, wire.strokeWidth * 0.35)
      ..strokeCap = StrokeCap.round
      ..color = _steel;
    // Each turn a ring a little wider than the pitch, so neighbours overlap
    // and read as one wound coil, not a row of brackets; the far side of the
    // ring first, fainter, then the near side over it.
    final back = Paint.from(coilPaint)
      ..color = coilPaint.color.withValues(alpha: 0.35);
    for (var i = 0; i < coils; i++) {
      final x = left + pitch * (i + 0.5);
      final rect = Rect.fromCenter(
        center: Offset(x, cy),
        width: pitch * 1.25,
        height: half * 2,
      );
      canvas.drawArc(rect, math.pi / 2, math.pi, false, back);
    }
    for (var i = 0; i < coils; i++) {
      final x = left + pitch * (i + 0.5);
      final rect = Rect.fromCenter(
        center: Offset(x, cy),
        width: pitch * 1.25,
        height: half * 2,
      );
      canvas.drawArc(rect, -math.pi / 2, math.pi, false, coilPaint);
      canvas.drawArc(
        rect.deflate(1.5),
        -math.pi / 2,
        math.pi * 0.5,
        false,
        shine,
      );
    }

    // Coil Number — from above, pointing at the coils.
    _arrow(
      canvas,
      SpringMark.coilNumber,
      Offset(w * 0.5, cy - half - 34),
      Offset(w * 0.5, cy - half - 4),
    );
    _label(
      canvas,
      SpringMark.coilNumber,
      Offset(w * 0.5, cy - half - 38),
      _Anchor.bottomCenter,
      unit: '',
    );

    // Coil Hook — from the top right, down at the right hook (clear of the
    // length below and the count above).
    final hookTop = Offset(right + hookR * 0.9, cy - hookR);
    if (hooks) {
      _arrow(
        canvas,
        SpringMark.coilHook,
        Offset(w * 0.93, cy - half - 34),
        hookTop.translate(4, -2),
      );
    }
    if (hooks) {
      _label(
        canvas,
        SpringMark.coilHook,
        Offset(w * 0.99, cy - half - 38),
        _Anchor.bottomRight,
        unit: '',
      );
    }

    // Coil Length — spanned under the coils.
    final spanY = cy + half + 16;
    _span(
      canvas,
      SpringMark.coilLength,
      Offset(left, spanY),
      Offset(right, spanY),
    );
    _label(
      canvas,
      SpringMark.coilLength,
      Offset(w * 0.5, spanY + 10),
      _Anchor.topCenter,
    );

    // The end view, lower left: the wire's ring, its outer and inner sizes.
    final ec = Offset(w * 0.26, h * 0.78);
    final outer = h * 0.12;
    final inner = outer * 0.68;
    canvas.drawCircle(
      ec,
      (outer + inner) / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = outer - inner
        ..color = _lit(SpringMark.wireGauge) ? SoftErpTheme.accentSoft : _steel,
    );
    canvas.drawCircle(
      ec,
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _lit(SpringMark.coilOd) ? 2.2 : 1.2
        ..color = _ink(SpringMark.coilOd),
    );
    canvas.drawCircle(
      ec,
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _lit(SpringMark.coilId) ? 2.2 : 1.2
        ..color = _ink(SpringMark.coilId),
    );
    // OD across the outside, ID across the inside.
    _span(
      canvas,
      SpringMark.coilOd,
      Offset(ec.dx - outer, ec.dy - outer - 10),
      Offset(ec.dx + outer, ec.dy - outer - 10),
    );
    _span(
      canvas,
      SpringMark.coilId,
      Offset(ec.dx - inner, ec.dy),
      Offset(ec.dx + inner, ec.dy),
    );
    _label(
      canvas,
      SpringMark.coilOd,
      Offset(ec.dx + outer + 16, ec.dy - outer - 10),
      _Anchor.centerLeft,
    );
    _label(
      canvas,
      SpringMark.coilId,
      Offset(ec.dx + outer + 16, ec.dy + 4),
      _Anchor.centerLeft,
    );
    _arrow(
      canvas,
      SpringMark.wireGauge,
      Offset(ec.dx + outer + 14, ec.dy + outer + 18),
      Offset(ec.dx + outer * 0.62, ec.dy + outer * 0.62),
    );
    _label(
      canvas,
      SpringMark.wireGauge,
      Offset(ec.dx + outer + 16, ec.dy + outer + 18),
      _Anchor.centerLeft,
      unit: '',
    );
    _caption(canvas, 'END VIEW', Offset(ec.dx, ec.dy + outer + 8));
  }

  /// The conical spring, as the owner's picture: coils widening downward,
  /// Small OD across the top, Large OD across the bottom, Free Length down
  /// the side, the coils numbered, Wire Diameter called out.
  void _paintConical(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.5;
    final top = h * 0.2;
    final bottom = h * 0.68;
    final smallW = w * 0.2;
    final largeW = w * 0.56;
    final typed = int.tryParse((values[SpringMark.totalCoils] ?? '').trim());
    final coils = (typed ?? 5).clamp(3, 9);
    final lit = _lit(SpringMark.totalCoils) || _lit(SpringMark.freeLength);
    final wire = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = _lit(SpringMark.wireDiameter) ? 6 : 5
      ..color = lit || _lit(SpringMark.wireDiameter)
          ? SoftErpTheme.accent
          : _steelDark;
    final back = Paint.from(wire)..color = wire.color.withValues(alpha: 0.35);
    final rects = <Rect>[
      for (var i = 0; i < coils; i++)
        Rect.fromCenter(
          center: Offset(cx, top + (bottom - top) * i / (coils - 1)),
          width: smallW + (largeW - smallW) * i / (coils - 1),
          height: 18 + i * 3.0,
        ),
    ];
    for (final r in rects) {
      canvas.drawArc(r, math.pi, math.pi, false, back);
    }
    for (final r in rects) {
      canvas.drawArc(r, 0, math.pi, false, wire);
    }
    // The coils numbered down the right, as in the picture.
    for (var i = 0; i < coils; i++) {
      _caption(
        canvas,
        '${i + 1}',
        Offset(rects[i].right + 14, rects[i].center.dy - 9),
      );
    }

    _span(
      canvas,
      SpringMark.smallOd,
      Offset(rects.first.left, top - 22),
      Offset(rects.first.right, top - 22),
    );
    _label(
      canvas,
      SpringMark.smallOd,
      Offset(cx, top - 28),
      _Anchor.bottomCenter,
    );
    _span(
      canvas,
      SpringMark.largeOd,
      Offset(rects.last.left, bottom + 24),
      Offset(rects.last.right, bottom + 24),
    );
    _label(
      canvas,
      SpringMark.largeOd,
      Offset(cx, bottom + 32),
      _Anchor.topCenter,
    );
    final lenX = rects.last.left - 24;
    _span(
      canvas,
      SpringMark.freeLength,
      Offset(lenX, top - 9),
      Offset(lenX, bottom + 12),
    );
    _label(
      canvas,
      SpringMark.freeLength,
      Offset(4, (top + bottom) / 2),
      _Anchor.centerLeft,
    );
    // Wire Diameter — from the bottom right, at the last (largest) coil's
    // wire: clear of the numbers down the right.
    final last = rects.last;
    _arrow(
      canvas,
      SpringMark.wireDiameter,
      Offset(w * 0.9, bottom + 30),
      Offset(last.right - 8, last.center.dy + last.height / 2 - 1),
    );
    _label(
      canvas,
      SpringMark.wireDiameter,
      Offset(w * 0.99, bottom + 34),
      _Anchor.topRight,
    );
    _label(
      canvas,
      SpringMark.totalCoils,
      Offset(w * 0.99, top - 28),
      _Anchor.bottomRight,
      unit: '',
    );
  }

  void _span(Canvas canvas, SpringMark mark, Offset a, Offset b) {
    final paint = Paint()
      ..color = _ink(mark)
      ..strokeWidth = _lit(mark) ? 2 : 1.2;
    canvas.drawLine(a, b, paint);
    const t = 5.0;
    final vertical = (a.dx - b.dx).abs() < 0.5;
    for (final p in <Offset>[a, b]) {
      if (vertical) {
        canvas.drawLine(p.translate(-t, 0), p.translate(t, 0), paint);
      } else {
        canvas.drawLine(p.translate(0, -t), p.translate(0, t), paint);
      }
    }
  }

  void _arrow(Canvas canvas, SpringMark mark, Offset from, Offset to) {
    final paint = Paint()
      ..color = _ink(mark)
      ..strokeWidth = _lit(mark) ? 2 : 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(from, to, paint);
    final dir = to - from;
    if (dir.distance == 0) return;
    final unit = dir / dir.distance;
    final normal = Offset(-unit.dy, unit.dx);
    final head = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo((to - unit * 8 + normal * 4).dx, (to - unit * 8 + normal * 4).dy)
      ..lineTo((to - unit * 8 - normal * 4).dx, (to - unit * 8 - normal * 4).dy)
      ..close();
    canvas.drawPath(head, Paint()..color = _ink(mark));
  }

  void _caption(Canvas canvas, String text, Offset at) {
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: SoftErpTheme.textSecondary,
        ),
      ),
    )..layout();
    painter.paint(canvas, at.translate(-painter.width / 2, 0));
  }

  void _label(
    Canvas canvas,
    SpringMark mark,
    Offset at,
    _Anchor anchor, {
    String unit = ' mm',
  }) {
    final lit = _lit(mark);
    final value = (values[mark] ?? '').trim();
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      text: TextSpan(
        children: <InlineSpan>[
          TextSpan(
            text: '${mark.label}\n',
            style: TextStyle(
              fontSize: 14,
              fontWeight: lit ? FontWeight.w800 : FontWeight.w600,
              color: lit ? SoftErpTheme.accent : SoftErpTheme.textSecondary,
            ),
          ),
          TextSpan(
            text: value.isEmpty ? '—' : '$value$unit',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: lit ? SoftErpTheme.accentDark : SoftErpTheme.textPrimary,
            ),
          ),
        ],
      ),
    )..layout(maxWidth: _canvas.width * 0.5);
    final size = painter.size;
    final raw = switch (anchor) {
      _Anchor.bottomCenter => at.translate(-size.width / 2, -size.height),
      _Anchor.topCenter => at.translate(-size.width / 2, 0),
      _Anchor.centerLeft => at.translate(0, -size.height / 2),
      _Anchor.bottomRight => at.translate(-size.width, -size.height),
      _Anchor.topRight => at.translate(-size.width, 0),
    };
    // Inside the canvas, whatever the label's length.
    final origin = Offset(
      raw.dx.clamp(4.0, math.max(4.0, _canvas.width - size.width - 4)),
      raw.dy.clamp(4.0, math.max(4.0, _canvas.height - size.height - 4)),
    );
    if (lit) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          (origin & size).inflate(6),
          const Radius.circular(8),
        ),
        Paint()..color = SoftErpTheme.accentSurface,
      );
    }
    painter.paint(canvas, origin);
  }

  @override
  bool shouldRepaint(_SpringPainter old) {
    if (old.focused != focused || old.kind != kind) return true;
    for (final mark in SpringMark.values) {
      if ((old.values[mark] ?? '') != (values[mark] ?? '')) return true;
    }
    return false;
  }
}

enum _Anchor { bottomCenter, topCenter, centerLeft, bottomRight, topRight }

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../domain/raw_stock_form.dart';

/// A strip, coil or roll, drawn as its own stock — never as something cut
/// from the sheet — with its measurements on it.
///
/// It plays once when the form is opened (key it by form, so a switch plays
/// the new one) and again on the replay button; it never loops. The strip
/// feeds in, the coil winds from its own strip, the roll rolls up its own
/// band. Width, thickness, length (usually undefined) and pitch are written
/// on the picture as it settles, and follow what is typed at once. Not to
/// scale: every size is mapped onto a range that stays on screen and readable,
/// but a wider or thicker stock always draws wider or thicker.
class BandFormAnimation extends StatefulWidget {
  const BandFormAnimation({
    super.key,
    required this.form,
    this.widthMm,
    this.thicknessMm,
    this.lengthMm,
    this.pitchMm,
    this.widthLabel = '',
    this.thicknessLabel = '',
    this.lengthLabel = '',
    this.pitchLabel = '',
  });

  /// Strip, coil or roll.
  final RawForm form;

  /// The measurements, or null while not typed. A null length is undefined.
  final double? widthMm;
  final double? thicknessMm;
  final double? lengthMm;
  final double? pitchMm;

  /// The same, as typed with their units — "250 mm", "1.6 mm", "18 ga".
  final String widthLabel;
  final String thicknessLabel;
  final String lengthLabel;
  final String pitchLabel;

  @override
  State<BandFormAnimation> createState() => _BandFormAnimationState();
}

class _BandFormAnimationState extends State<BandFormAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _play();
  }

  void _play() {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.value = 1;
      return;
    }
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final noun = widget.form.label.toLowerCase();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'THE ${widget.form.label.toUpperCase()}',
                style: const TextStyle(
                  color: SoftErpTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                ),
              ),
              const Spacer(),
              IconButton(
                key: const ValueKey<String>('band-animation-replay'),
                tooltip: 'Play it again',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.replay_rounded, size: 20),
                onPressed: _play,
              ),
            ],
          ),
          SizedBox(
            height: 190,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(
                size: Size.infinite,
                painter: BandFormPainter(
                  form: widget.form,
                  t: Curves.easeInOutCubic.transform(_controller.value),
                  widthMm: widget.widthMm,
                  thicknessMm: widget.thicknessMm,
                  lengthMm: widget.lengthMm,
                  pitchMm: widget.pitchMm,
                  widthLabel: widget.widthLabel,
                  thicknessLabel: widget.thicknessLabel,
                  lengthLabel: widget.lengthLabel,
                  pitchLabel: widget.pitchLabel,
                ),
              ),
            ),
          ),
          if ((widget.widthMm ?? 0) <= 0)
            Text(
              'Enter the width to size the $noun.',
              style: const TextStyle(
                color: SoftErpTheme.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

/// One frame of a strip, coil or roll at progress [t], 0 to 1, with its
/// measurements written on as it settles.
class BandFormPainter extends CustomPainter {
  BandFormPainter({
    required this.form,
    required this.t,
    this.widthMm,
    this.thicknessMm,
    this.lengthMm,
    this.pitchMm,
    this.widthLabel = '',
    this.thicknessLabel = '',
    this.lengthLabel = '',
    this.pitchLabel = '',
  });

  final RawForm form;
  final double t;
  final double? widthMm;
  final double? thicknessMm;
  final double? lengthMm;
  final double? pitchMm;
  final String widthLabel;
  final String thicknessLabel;
  final String lengthLabel;
  final String pitchLabel;

  static const Color _metal = SoftErpTheme.accent;
  static Color get _face => SoftErpTheme.accent.withValues(alpha: 0.16);

  /// Room on the left for the width, dimensioned up the side.
  static const double _gutter = 92;

  bool get _hasWidth => (widthMm ?? 0) > 0;
  bool get _lengthKnown => (lengthMm ?? 0) > 0;

  static double _logFrac(double v, double lo, double hi) =>
      ((math.log(v) - math.log(lo)) / (math.log(hi) - math.log(lo)))
          .clamp(0.0, 1.0);

  /// Width and thickness mapped onto what the picture can show.
  double get _wf => _hasWidth ? _logFrac(widthMm!, 5, 1500) : 0.4;
  double get _tf =>
      (thicknessMm ?? 0) > 0 ? _logFrac(thicknessMm!, 0.05, 6) : 0.35;

  double _phase(double from, double to) =>
      ((t - from) / (to - from)).clamp(0.0, 1.0);

  /// The measurements fade in as the shape settles.
  double get _labelAlpha => _phase(0.7, 1);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 200 || size.height < 120) return;
    switch (form) {
      case RawForm.strip:
        _strip(canvas, size);
      case RawForm.coil:
        _coil(canvas, size);
      case RawForm.roll:
        _roll(canvas, size);
      case RawForm.sheet:
        break;
    }
  }

  // --- the band seen face-on: a strip, and a roll's flat part -------------

  double get _bandHeight => 26 + 54 * _wf;
  static const double _bandTop = 34;

  Rect _bandRect(Size size, double right) =>
      Rect.fromLTRB(_gutter, _bandTop, right, _bandTop + _bandHeight);

  /// The band's outline: square ends, except an undefined length, whose far
  /// end is torn — there is more of it, nobody knows how much.
  Path _bandPath(Rect band, {bool tornLeft = false}) {
    if (!tornLeft) return Path()..addRect(band);
    const tooth = 6.0;
    final teeth = math.max(2, (band.height / (tooth * 2)).round());
    final step = band.height / teeth;
    final path = Path()
      ..moveTo(band.left, band.top)
      ..lineTo(band.right, band.top)
      ..lineTo(band.right, band.bottom)
      ..lineTo(band.left, band.bottom);
    for (var i = teeth; i > 0; i--) {
      final y = band.top + i * step;
      path.lineTo(band.left + tooth, y - step / 2);
      path.lineTo(band.left, y - step);
    }
    return path..close();
  }

  void _drawBand(Canvas canvas, Rect band) {
    if (band.width <= 0.5) return;
    final path = _bandPath(band, tornLeft: !_lengthKnown);
    canvas.drawPath(path, Paint()..color = _face);
    _pitchLines(canvas, band);
    canvas.drawPath(
      path,
      Paint()
        ..color = _metal
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  /// One part every pitch: faint lines across the band, at the width's
  /// scale, counted back from the leading end.
  void _pitchLines(Canvas canvas, Rect band) {
    final pitch = pitchMm ?? 0;
    if (pitch <= 0 || !_hasWidth) return;
    final px = pitch * band.height / widthMm!;
    if (px < 5) return;
    final line = Paint()
      ..color = _metal.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    var drawn = 0;
    for (var x = band.right - px; x > band.left + 2 && drawn < 400; x -= px) {
      canvas.drawLine(Offset(x, band.top + 3), Offset(x, band.bottom - 3), line);
      drawn++;
    }
  }

  /// Width up the side, pitch and thickness above, length along the bottom.
  /// [thicknessAt] puts the thickness somewhere of its own (the roll's, beside
  /// it), left-aligned; otherwise it sits above the band's leading end.
  void _bandLabels(Canvas canvas, Rect band, {Offset? thicknessAt}) {
    final a = _labelAlpha;
    if (a <= 0) return;
    final dim = Paint()
      ..color = SoftErpTheme.textSecondary.withValues(alpha: a)
      ..strokeWidth = 1;
    if (_hasWidth) {
      final x = band.left - 12;
      canvas.drawLine(Offset(x, band.top), Offset(x, band.bottom), dim);
      canvas.drawLine(Offset(x - 4, band.top), Offset(x + 4, band.top), dim);
      canvas.drawLine(
        Offset(x - 4, band.bottom),
        Offset(x + 4, band.bottom),
        dim,
      );
      _label(canvas, widthLabel, Offset(x - 6, band.center.dy),
          align: _Align.right, alpha: a, maxWidth: _gutter - 24);
    }
    if (pitchLabel.isNotEmpty) {
      _label(canvas, 'one part every $pitchLabel',
          Offset(band.left, band.top - 14), alpha: a);
    }
    if (thicknessLabel.isNotEmpty) {
      if (thicknessAt != null) {
        _label(canvas, '$thicknessLabel thick', thicknessAt, alpha: a);
      } else {
        _label(canvas, '$thicknessLabel thick',
            Offset(band.right, band.top - 14),
            align: _Align.right, alpha: a);
      }
    }
    final y = band.bottom + 16;
    if (_lengthKnown) {
      canvas.drawLine(Offset(band.left, y), Offset(band.right, y), dim);
      canvas.drawLine(Offset(band.left, y - 4), Offset(band.left, y + 4), dim);
      canvas.drawLine(
        Offset(band.right, y - 4),
        Offset(band.right, y + 4),
        dim,
      );
      _label(canvas, lengthLabel, Offset(band.center.dx, y),
          align: _Align.centre, alpha: a);
    } else {
      _label(canvas, 'length undefined', Offset(band.center.dx, y),
          align: _Align.centre, alpha: a, muted: true);
    }
  }

  /// The strip feeds in, leading end first.
  void _strip(Canvas canvas, Size size) {
    final full = size.width - 6;
    final fed = _phase(0, 0.7);
    final right = _gutter + (full - _gutter) * fed;
    final band = _bandRect(size, right);
    _drawBand(canvas, band);
    _bandLabels(canvas, _bandRect(size, full));
  }

  /// The band's leading end curls into a roll on its core, which grows as it
  /// takes up part of the band; the rest stays flat, carrying the measures.
  void _roll(Canvas canvas, Size size) {
    final full = _bandRect(size, size.width - 6);
    final wind = _phase(0, 0.8);
    final rolled = full.width * 0.4 * wind;
    const core = 5.0;
    final finalRadius = math.min(
      _bandHeight * (0.35 + 0.3 * _tf),
      full.width * 0.18,
    );
    final radius = core + (finalRadius - core) * math.sqrt(wind);
    final flatEnd = full.right - rolled;
    final axisX = flatEnd + radius;
    final flat = Rect.fromLTRB(full.left, full.top, flatEnd, full.bottom);
    _drawBand(canvas, flat);
    if (wind > 0) {
      final capH = math.min(radius * 0.7, _bandHeight * 0.35);
      final body = Rect.fromLTRB(
        axisX - radius,
        full.top,
        axisX + radius,
        full.bottom,
      );
      canvas.drawRect(body, Paint()..color = Colors.white);
      canvas.drawRect(
        body,
        Paint()
          ..shader = LinearGradient(
            colors: [
              SoftErpTheme.accent.withValues(alpha: 0.32),
              SoftErpTheme.accent.withValues(alpha: 0.10),
              SoftErpTheme.accent.withValues(alpha: 0.30),
            ],
          ).createShader(body),
      );
      final stroke = Paint()
        ..color = _metal
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawLine(body.topLeft, body.bottomLeft, stroke);
      canvas.drawLine(body.topRight, body.bottomRight, stroke);
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(axisX, full.bottom),
          width: radius * 2,
          height: capH,
        ),
        0,
        math.pi,
        false,
        stroke,
      );
      final end = Rect.fromCenter(
        center: Offset(axisX, full.top),
        width: radius * 2,
        height: capH,
      );
      canvas.drawOval(end, Paint()..color = Colors.white);
      canvas.drawOval(end, Paint()..color = _face);
      // Its wraps: few and wide apart for thick stock, many and close for
      // thin.
      final wraps = ((8 - 5 * _tf) * math.sqrt(wind)).round();
      final ring = Paint()
        ..color = _metal.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      for (var i = 1; i < wraps; i += 1) {
        final r = core + (radius - core) * i / wraps;
        canvas.drawOval(
          Rect.fromCenter(
            center: end.center,
            width: r * 2,
            height: capH * r / radius,
          ),
          ring,
        );
      }
      canvas.drawOval(end, stroke);
    }
    _bandLabels(
      canvas,
      Rect.fromLTRB(full.left, full.top, math.max(full.left + 40, flatEnd),
          full.bottom),
      // Beside the roll, where its wraps are: above the band it would
      // collide with the pitch.
      thicknessAt: Offset(axisX + radius + 8, full.center.dy),
    );
  }

  // --- the coil, seen end-on -------------------------------------------------

  /// Its own strip, edge-on, winds into a coil; the end it is fed from stays
  /// out as a tail, as thick as the stock.
  void _coil(Canvas canvas, Size size) {
    const left = 12.0;
    final wind = _phase(0, 0.85);
    final thick = 1.4 + 4.6 * _tf;
    final finalRadius = math.min(size.height * 0.3, 58.0);
    final depthFull = _hasWidth ? finalRadius * 0.6 * (0.15 + 0.85 * _wf) : 0.0;
    final depth = depthFull * wind;
    final back = Offset(depth * 0.9, -depth * 0.3);
    final centre = Offset(
      size.width - 10 - finalRadius - depthFull * 0.9,
      34 + finalRadius,
    );
    const core = 8.0;
    final fullTurns = 8 - 5 * _tf;
    final pitch = (finalRadius - core) / (fullTurns * 2 * math.pi);
    final fullArc = core * fullTurns * 2 * math.pi +
        pitch * math.pow(fullTurns * 2 * math.pi, 2) / 2;
    final arc = fullArc * wind;
    final turns = arc <= 0
        ? 0.0
        : (-core + math.sqrt(core * core + 2 * pitch * arc)) / pitch;
    final outer = core + pitch * turns;

    if (wind > 0) {
      final rim = outer + thick / 2;
      if (depth > 0.5) {
        final n = Offset(-back.dy, back.dx) / back.distance;
        final shell = Paint()
          ..color = SoftErpTheme.accent.withValues(alpha: 0.26);
        final line = Paint()
          ..color = _metal
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        final side = Path()
          ..moveTo(centre.dx + n.dx * rim, centre.dy + n.dy * rim)
          ..lineTo(centre.dx + back.dx + n.dx * rim,
              centre.dy + back.dy + n.dy * rim)
          ..lineTo(centre.dx + back.dx - n.dx * rim,
              centre.dy + back.dy - n.dy * rim)
          ..lineTo(centre.dx - n.dx * rim, centre.dy - n.dy * rim)
          ..close();
        canvas.drawCircle(centre + back, rim, shell);
        canvas.drawCircle(centre + back, rim, line);
        canvas.drawPath(side, shell);
        canvas.drawCircle(centre, rim, Paint()..color = Colors.white);
      }
      canvas.drawCircle(centre, rim, Paint()..color = _face);
      final path = Path();
      const steps = 360;
      for (var i = 0; i <= steps; i += 1) {
        final phi = turns * i / steps;
        final r = core + pitch * phi;
        final a = math.pi / 2 - (turns - phi);
        final p = centre + Offset(math.cos(a) * r, math.sin(a) * r);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = _metal
          ..style = PaintingStyle.stroke
          ..strokeWidth = thick
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(
        centre,
        core - 2,
        Paint()
          ..color = SoftErpTheme.textSecondary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }

    // The strip it is wound from, edge-on: all of it at first, then the tail
    // it is fed out by. Its far end is torn while the length is undefined.
    final tailY = wind > 0 ? centre.dy + outer : centre.dy + finalRadius;
    final startLength = centre.dx - left;
    final tail = startLength * (1 - 0.5 * wind);
    final tailRect = Rect.fromLTWH(centre.dx - tail, tailY - thick / 2, tail,
        thick + 0.4);
    canvas.drawRect(tailRect, Paint()..color = _face);
    canvas.drawRect(
      tailRect,
      Paint()
        ..color = _metal
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.min(1.5, thick / 2),
    );

    // The measures, one to a line in the room left of the coil: seen
    // end-on, the width has no edge to dimension.
    final a = _labelAlpha;
    if (a <= 0) return;
    final lines = <(String, bool)>[
      if (widthLabel.isNotEmpty) ('$widthLabel wide', false),
      if (thicknessLabel.isNotEmpty) ('$thicknessLabel thick', false),
      if (pitchLabel.isNotEmpty) ('one part every $pitchLabel', false),
      _lengthKnown ? ('$lengthLabel long', false) : ('length undefined', true),
    ];
    final room = centre.dx - finalRadius - left - 12;
    var y = 30.0;
    for (final (text, muted) in lines) {
      _label(canvas, text, Offset(left, y),
          alpha: a, muted: muted, maxWidth: math.max(80, room));
      y += 22;
    }
  }

  void _label(
    Canvas canvas,
    String text,
    Offset at, {
    _Align align = _Align.left,
    double alpha = 1,
    bool muted = false,
    double maxWidth = 260,
  }) {
    if (text.isEmpty || alpha <= 0) return;
    final colour = muted ? SoftErpTheme.textSecondary : SoftErpTheme.textPrimary;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: colour.withValues(alpha: alpha),
          fontSize: 14,
          fontWeight: muted ? FontWeight.w600 : FontWeight.w700,
          backgroundColor: Colors.white.withValues(alpha: alpha),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    final dx = switch (align) {
      _Align.left => at.dx,
      _Align.right => at.dx - painter.width,
      _Align.centre => at.dx - painter.width / 2,
    };
    painter.paint(canvas, Offset(dx, at.dy - painter.height / 2));
  }

  @override
  bool shouldRepaint(BandFormPainter old) =>
      old.t != t ||
      old.form != form ||
      old.widthMm != widthMm ||
      old.thicknessMm != thicknessMm ||
      old.lengthMm != lengthMm ||
      old.pitchMm != pitchMm ||
      old.widthLabel != widthLabel ||
      old.thicknessLabel != thicknessLabel ||
      old.lengthLabel != lengthLabel ||
      old.pitchLabel != pitchLabel;
}

enum _Align { left, right, centre }

/// The small picture of each form: a flat sheet, a long thin strip, a coil
/// seen end-on as rings, a roll as a cylinder on its core.
class RawFormGlyphPainter extends CustomPainter {
  RawFormGlyphPainter(this.form, {this.color = SoftErpTheme.textSecondary});

  final RawForm form;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final w = size.width;
    final h = size.height;
    switch (form) {
      case RawForm.sheet:
        canvas.drawRect(Rect.fromLTWH(w * 0.12, h * 0.15, w * 0.76, h * 0.7), stroke);
      case RawForm.strip:
        for (var i = 0; i < 3; i += 1) {
          final y = h * (0.25 + i * 0.25);
          canvas.drawLine(Offset(w * 0.05, y), Offset(w * 0.95, y - h * 0.1), stroke);
        }
      case RawForm.coil:
        final c = Offset(w / 2, h / 2);
        final r = math.min(w, h) * 0.46;
        canvas.drawCircle(c, r, stroke);
        canvas.drawCircle(c, r * 0.68, stroke);
        canvas.drawCircle(c, r * 0.36, stroke);
      case RawForm.roll:
        final rect = Rect.fromLTWH(w * 0.08, h * 0.12, w * 0.84, h * 0.76);
        final endW = rect.height * 0.5;
        canvas.drawOval(
          Rect.fromLTWH(rect.right - endW, rect.top, endW, rect.height),
          stroke,
        );
        canvas.drawLine(rect.topLeft + Offset(endW / 2, 0),
            Offset(rect.right - endW / 2, rect.top), stroke);
        canvas.drawLine(rect.bottomLeft + Offset(endW / 2, 0),
            Offset(rect.right - endW / 2, rect.bottom), stroke);
        canvas.drawArc(
          Rect.fromLTWH(rect.left, rect.top, endW, rect.height),
          math.pi / 2,
          math.pi,
          false,
          stroke,
        );
        canvas.drawCircle(
          Offset(rect.right - endW / 2, rect.center.dy),
          rect.height * 0.12,
          stroke,
        );
    }
  }

  @override
  bool shouldRepaint(RawFormGlyphPainter old) =>
      old.form != form || old.color != color;
}

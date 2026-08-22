import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../domain/pen_paper_baseline.dart' show SheetCutAxis;

/// The sheet the Master Data was measured from, drawn in cabinet oblique and
/// dimensioned the way a shop drawing dimensions one.
///
/// Cabinet oblique rather than isometric, because of what a sheet is: a face
/// with a gauge. The face is drawn **true** — an undistorted width × height
/// rectangle — so the cut plan lands on it as a real grid whose strip
/// proportions can be judged by eye, and a transposed width and height read as
/// the wrong shape rather than as two swapped numbers. The gauge recedes at 45°
/// and half scale, which is what makes the projection cabinet rather than
/// cavalier: a receding axis drawn full length reads far too long.
class SheetDimensionFigure extends StatelessWidget {
  const SheetDimensionFigure({
    super.key,
    required this.widthInches,
    required this.heightInches,
    required this.thicknessMm,
    this.materialLabel = '',
    this.trimInches = 0,
    this.columnBands = const <SheetFigureBand>[],
    this.rowBands = const <SheetFigureBand>[],
    this.columnPlanEndInches = 0,
    this.rowPlanEndInches = 0,
    this.regionCuts = const <SheetRegionCuts>[],
    this.primaryIsColumns = true,
  });

  final double widthInches;
  final double heightInches;
  final double thicknessMm;

  /// The cut plan as positions rather than sizes: where every score line falls,
  /// measured from the sheet's own edge, already carrying the trim offset and
  /// the blade between pieces.
  ///
  /// The drawing does not do this arithmetic. The baseline works out where the
  /// cuts land and the operator's list is printed from the same numbers, so the
  /// picture and the instruction cannot disagree.
  final double trimInches;
  final List<SheetFigureBand> columnBands;
  final List<SheetFigureBand> rowBands;

  /// Where each axis's plan stops. Everything from there to the far trim is
  /// offcut.
  final double columnPlanEndInches;
  final double rowPlanEndInches;

  /// Every region's own cuts, each with the stretch of sheet it belongs to.
  ///
  /// All of them, not just whichever the panel has open: the plan is the whole
  /// plan, and a strip you cut an hour ago is still cut. Each is clipped to its
  /// own region, which is what keeps them from reading as a lattice across the
  /// sheet.
  final List<SheetRegionCuts> regionCuts;

  /// Which way the sheet was sheared. Told rather than guessed: the drawing has
  /// to know which list is the sheet-wide split and which is one region's own,
  /// and inferring it from whether a plan happens to be non-empty would break
  /// the first time one was.
  final bool primaryIsColumns;

  /// What the sheet is, read off the variant's name. Carried on a leader out to
  /// the drawing's margin rather than lettered across the face, which the cut
  /// grid needs kept clear.
  final String materialLabel;

  @override
  Widget build(BuildContext context) {
    // The measurements travel as one value, so a change to two of them does not
    // run two tweens out of step and skew the solid mid-flight.
    return TweenAnimationBuilder<_SheetShape>(
      tween: _SheetShapeTween(
        end: _SheetShape(
          width: widthInches,
          height: heightInches,
          thickness: thicknessMm,
        ),
      ),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, shape, _) {
        return CustomPaint(
          painter: _SheetPainter(
            shape: shape,
            hasFace: widthInches > 0 && heightInches > 0,
            materialLabel: materialLabel,
            trimInches: trimInches,
            columnBands: columnBands,
            rowBands: rowBands,
            columnPlanEndInches: columnPlanEndInches,
            rowPlanEndInches: rowPlanEndInches,
            regionCuts: regionCuts,
            primaryIsColumns: primaryIsColumns,
            textDirection: Directionality.of(context),
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

/// One region's cuts, with the stretch of the primary axis they belong to.
@immutable
class SheetRegionCuts {
  const SheetRegionCuts({
    required this.fromInches,
    required this.toInches,
    required this.bands,
    this.highlighted = false,
  });

  final double fromInches;
  final double toInches;
  final List<SheetFigureBand> bands;

  /// Whether this is the region the panel has open. Drawn a shade stronger, so
  /// the one being edited is findable without the others disappearing.
  final bool highlighted;

  @override
  bool operator ==(Object other) =>
      other is SheetRegionCuts &&
      other.fromInches == fromInches &&
      other.toInches == toInches &&
      other.highlighted == highlighted &&
      listEquals(other.bands, bands);

  @override
  int get hashCode =>
      Object.hash(fromInches, toInches, highlighted, Object.hashAll(bands));
}

/// One band as the drawing needs it: where it sits along its axis in the inches
/// the sheet is drawn in, how many pieces, and which colour tells it apart.
@immutable
class SheetFigureBand {
  const SheetFigureBand({
    required this.startInches,
    required this.endInches,
    required this.sizeInches,
    required this.count,
    required this.colourIndex,
  });

  final double startInches;
  final double endInches;
  final double sizeInches;
  final int count;
  final int colourIndex;

  @override
  bool operator ==(Object other) =>
      other is SheetFigureBand &&
      other.startInches == startInches &&
      other.endInches == endInches &&
      other.sizeInches == sizeInches &&
      other.count == count &&
      other.colourIndex == colourIndex;

  @override
  int get hashCode =>
      Object.hash(startInches, endInches, sizeInches, count, colourIndex);
}

/// Colours that tell one band from the next, on the drawing and in the panel
/// alike. Muted, because they sit under hairline linework that has to stay
/// readable over them — and distinguishable from the amber the offcut uses,
/// since "a different part" and "waste" must never be confusable.
const List<Color> sheetBandPalette = <Color>[
  Color(0xFF4F46E5),
  Color(0xFF0D9488),
  Color(0xFFC026D3),
  Color(0xFF2563EB),
  Color(0xFF65A30D),
  Color(0xFFDB2777),
];

Color sheetBandColour(int index) =>
    sheetBandPalette[index % sheetBandPalette.length];

/// The measurements as one animatable value.
@immutable
class _SheetShape {
  const _SheetShape({
    required this.width,
    required this.height,
    required this.thickness,
  });

  final double width;
  final double height;
  final double thickness;

  static _SheetShape lerp(_SheetShape a, _SheetShape b, double t) {
    return _SheetShape(
      width: a.width + (b.width - a.width) * t,
      height: a.height + (b.height - a.height) * t,
      thickness: a.thickness + (b.thickness - a.thickness) * t,
    );
  }
}

class _SheetShapeTween extends Tween<_SheetShape> {
  _SheetShapeTween({required _SheetShape end})
    : super(
        begin: const _SheetShape(width: 0, height: 0, thickness: 0),
        end: end,
      );

  @override
  _SheetShape lerp(double t) => _SheetShape.lerp(begin!, end!, t);
}

class _SheetPainter extends CustomPainter {
  _SheetPainter({
    required this.shape,
    required this.hasFace,
    required this.materialLabel,
    required this.textDirection,
    this.trimInches = 0,
    this.columnBands = const <SheetFigureBand>[],
    this.rowBands = const <SheetFigureBand>[],
    this.columnPlanEndInches = 0,
    this.rowPlanEndInches = 0,
    this.regionCuts = const <SheetRegionCuts>[],
    this.primaryIsColumns = true,
  });

  final _SheetShape shape;
  final bool hasFace;
  final String materialLabel;
  final TextDirection textDirection;
  final double trimInches;
  final List<SheetFigureBand> columnBands;
  final List<SheetFigureBand> rowBands;
  final double columnPlanEndInches;
  final double rowPlanEndInches;
  final List<SheetRegionCuts> regionCuts;
  final bool primaryIsColumns;

  /// A cut line every pixel would be a solid block of ink, so past this the
  /// drawing shows the first lines and the panel's readout carries the count.
  static const int _maxDrawnCuts = 48;

  /// The cabinet factor: the receding axis is drawn at 45° and **half** its
  /// length. Halving is the whole point of cabinet over cavalier — an oblique
  /// depth drawn full length looks longer than the object is.
  static const double _cabinet = 0.35355339059327373; // 0.5 × cos 45°

  static const double _dimOffset = 18;
  static const double _extensionGap = 4;
  static const double _extensionOver = 5;

  /// The proportions a sheet is drawn at before anything is measured: square,
  /// because a placeholder that guessed at a proportion would be inventing one.
  static const double _placeholderFace = 100;

  // Drawing-office palette: hairline ink on white, the solid told apart by
  // three values of near-white rather than by colour. Colour on a drawing means
  // material, so spending it on the object itself leaves nothing to say with.
  static const Color _ink = Color(0xFF1F2328);
  static const Color _dimLine = Color(0xFF6B7280);
  static const Color _thinLine = Color(0xFFAAB2BD);
  static const Color _ghost = Color(0xFFC8CFD8);
  static const Color _faceFront = Color(0xFFFCFCFD);
  static const Color _faceTopBand = Color(0xFFEFF1F4);
  static const Color _faceSideBand = Color(0xFFE2E6EB);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 60 || size.height < 60) return;

    final width = shape.width > 0 ? shape.width : _placeholderFace;
    final height = shape.height > 0 ? shape.height : _placeholderFace;
    final gauge = _modelThickness(shape.thickness, math.max(width, height));

    // How far the receding axis carries in model units, both across and up.
    final recede = gauge * _cabinet;

    // Margins: the annotation and the gauge share the top, the height stands on
    // the left and the width underneath.
    final usable = Rect.fromLTRB(46, 46, size.width - 34, size.height - 36);
    if (usable.width < 40 || usable.height < 40) return;

    final spanX = width + recede;
    final spanY = height + recede;
    if (spanX <= 0 || spanY <= 0) return;
    final scale = math.min(usable.width / spanX, usable.height / spanY);

    final left = usable.left + (usable.width - spanX * scale) / 2;
    final top = usable.top + (usable.height - spanY * scale) / 2;

    // x runs right, y runs down, z recedes up and to the right.
    Offset at(double x, double y, double z) => Offset(
      left + (x + z * _cabinet) * scale,
      top + (y - z * _cabinet + recede) * scale,
    );

    final frontTL = at(0, 0, 0);
    final frontTR = at(width, 0, 0);
    final frontBR = at(width, height, 0);
    final frontBL = at(0, height, 0);
    final backTL = at(0, 0, gauge);
    final backTR = at(width, 0, gauge);
    final backBR = at(width, height, gauge);

    final known = hasFace;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = known ? _ink : _ghost;

    // The two receding bands first; the face is nearest, so it goes over them.
    if (gauge > 0) {
      _face(
        canvas,
        <Offset>[frontTL, frontTR, backTR, backTL],
        known ? _faceTopBand : const Color(0xFFF8F9FB),
        edge,
      );
      _face(
        canvas,
        <Offset>[frontTR, backTR, backBR, frontBR],
        known ? _faceSideBand : const Color(0xFFF3F5F7),
        edge,
      );
    }
    _face(
      canvas,
      <Offset>[frontTL, frontTR, frontBR, frontBL],
      known ? _faceFront : const Color(0xFFFDFDFE),
      edge,
    );

    _cutLines(canvas, at, width, height, scale, known);

    // Width, underneath the true face — a plain horizontal dimension, because
    // in this projection the face's own edges are true horizontals.
    _straightDimension(
      canvas,
      from: frontBL,
      to: frontBR,
      outward: const Offset(0, 1),
      label: shape.width > 0 ? 'x  ${_fmt(shape.width)} in' : 'x  width',
      known: shape.width > 0,
      vertical: false,
    );

    // Height, standing on the left.
    _straightDimension(
      canvas,
      from: frontTL,
      to: frontBL,
      outward: const Offset(-1, 0),
      label: shape.height > 0 ? 'y  ${_fmt(shape.height)} in' : 'y  height',
      known: shape.height > 0,
      vertical: true,
    );

    // The gauge, on the receding edge at the top right. Its extension lines run
    // straight up, which leaves the dimension line parallel to the edge it
    // measures — the measurement the flat drawing had nowhere to put.
    _gaugeDimension(canvas, frontTR, backTR, size);

    // The annotation last, into the clear upper left the dimensions left it.
    _annotation(canvas, frontTL, size, known);
  }

  void _face(Canvas canvas, List<Offset> points, Color fill, Paint edge) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(path, edge);
  }

  /// The cut plan on the true face: the trim boundary, each band as its own
  /// coloured region, and whatever the plan does not claim shaded as offcut.
  ///
  /// Regions rather than a line per piece. Three hundred score lines on a sheet
  /// this size do not read as three hundred pieces — they collapse into a grey
  /// smear whose dashes stack into stripes running the wrong way. So a band is
  /// drawn as the stretch of sheet it occupies, in its own colour, and the
  /// individual cuts are only drawn when there is room for them to be seen.
  void _cutLines(
    Canvas canvas,
    Offset Function(double, double, double) at,
    double width,
    double height,
    double scale,
    bool known,
  ) {
    if (!known) return;
    final trim = trimInches.clamp(0.0, math.min(width, height) / 2 - 0.001);
    final usableRight = width - trim;
    final usableBottom = height - trim;

    // The trim, hatched off. The operator will not cut into it, so it is not
    // part of the plan and must not read as material the plan could have used.
    if (trim > 0) {
      final trimPaint = Paint()..color = const Color(0x14000000);
      _quad(canvas, at, 0, 0, width, trim, trimPaint);
      _quad(canvas, at, 0, usableBottom, width, height, trimPaint);
      _quad(canvas, at, 0, trim, trim, usableBottom, trimPaint);
      _quad(canvas, at, usableRight, trim, width, usableBottom, trimPaint);

      final boundary = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..color = _thinLine;
      _dashedRect(canvas, at, trim, trim, usableRight, usableBottom, boundary);
    }

    if (columnBands.isEmpty && rowBands.isEmpty) return;

    // Each axis leaves its own offcut beyond where its plan stops.
    final takenX = columnBands.isEmpty ? usableRight : columnPlanEndInches;
    final takenY = rowBands.isEmpty ? usableBottom : rowPlanEndInches;
    final waste = Paint()
      ..color = SoftErpTheme.warningText.withValues(alpha: 0.20);
    if (takenX < usableRight - 0.0001) {
      _quad(canvas, at, takenX, trim, usableRight, usableBottom, waste);
    }
    if (takenY < usableBottom - 0.0001) {
      _quad(canvas, at, trim, takenY, takenX, usableBottom, waste);
    }

    // The shear first: it runs the full sheet.
    for (final band in columnBands) {
      _band(
        canvas,
        at,
        band,
        scale,
        acrossFrom: trim,
        acrossTo: usableBottom,
        vertical: true,
      );
    }
    for (final band in rowBands) {
      _band(
        canvas,
        at,
        band,
        scale,
        acrossFrom: trim,
        acrossTo: usableRight,
        vertical: false,
      );
    }

    // Then every region's own cuts, each confined to the region it belongs to.
    for (final region in regionCuts) {
      for (final band in region.bands) {
        _band(
          canvas,
          at,
          band,
          scale,
          acrossFrom: region.fromInches,
          acrossTo: region.toInches,
          vertical: !primaryIsColumns,
          emphasis: region.highlighted ? 1.0 : 0.6,
        );
      }
    }
  }

  /// One band: its region washed in its own colour, a firm line where it meets
  /// the next, and its own cuts drawn only if they would be legible.
  void _band(
    Canvas canvas,
    Offset Function(double, double, double) at,
    SheetFigureBand band,
    double scale, {
    required double acrossFrom,
    required double acrossTo,
    required bool vertical,
    double emphasis = 1.0,
  }) {
    if (acrossTo <= acrossFrom) return;
    final colour = sheetBandColour(band.colourIndex);
    final fill = Paint()..color = colour.withValues(alpha: 0.14 * emphasis);
    if (vertical) {
      _quad(
        canvas,
        at,
        band.startInches,
        acrossFrom,
        band.endInches,
        acrossTo,
        fill,
      );
    } else {
      _quad(
        canvas,
        at,
        acrossFrom,
        band.startInches,
        acrossTo,
        band.endInches,
        fill,
      );
    }

    // Where this band ends and the next begins: always drawn, because it is the
    // boundary between one part and a different part.
    final edge = Paint()
      ..strokeWidth = 1.1
      ..color = colour.withValues(alpha: 0.9 * emphasis);
    for (final offset in <double>[band.startInches, band.endInches]) {
      final a = vertical
          ? at(offset, acrossFrom, 0)
          : at(acrossFrom, offset, 0);
      final b = vertical ? at(offset, acrossTo, 0) : at(acrossTo, offset, 0);
      canvas.drawLine(a, b, edge);
    }

    // The pieces inside it, only while they are far enough apart to be counted
    // by eye. Below that the wash already says where the band is, and drawing
    // the cuts would only turn it into a texture.
    final pitchPx = band.sizeInches * scale;
    if (pitchPx < 6 || band.count < 2) return;
    final dash = Paint()
      ..strokeWidth = 0.7
      ..color = colour.withValues(alpha: 0.55 * emphasis);
    for (var i = 1; i < band.count; i++) {
      final offset = band.startInches + band.sizeInches * i;
      if (offset >= band.endInches - 0.0001) break;
      final a = vertical
          ? at(offset, acrossFrom, 0)
          : at(acrossFrom, offset, 0);
      final b = vertical ? at(offset, acrossTo, 0) : at(acrossTo, offset, 0);
      _dashedLine(canvas, a, b, dash);
    }
  }

  void _quad(
    Canvas canvas,
    Offset Function(double, double, double) at,
    double x0,
    double y0,
    double x1,
    double y1,
    Paint paint,
  ) {
    if (x1 <= x0 || y1 <= y0) return;
    final path = Path()
      ..moveTo(at(x0, y0, 0).dx, at(x0, y0, 0).dy)
      ..lineTo(at(x1, y0, 0).dx, at(x1, y0, 0).dy)
      ..lineTo(at(x1, y1, 0).dx, at(x1, y1, 0).dy)
      ..lineTo(at(x0, y1, 0).dx, at(x0, y1, 0).dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _dashedRect(
    Canvas canvas,
    Offset Function(double, double, double) at,
    double x0,
    double y0,
    double x1,
    double y1,
    Paint paint,
  ) {
    final a = at(x0, y0, 0);
    final b = at(x1, y0, 0);
    final c = at(x1, y1, 0);
    final d = at(x0, y1, 0);
    _dashedLine(canvas, a, b, paint);
    _dashedLine(canvas, b, c, paint);
    _dashedLine(canvas, c, d, paint);
    _dashedLine(canvas, d, a, paint);
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 5.0;
    const gap = 3.5;
    final total = (b - a).distance;
    if (total <= 0) return;
    final unit = (b - a) / total;
    var travelled = 0.0;
    while (travelled < total) {
      final end = math.min(travelled + dash, total);
      canvas.drawLine(a + unit * travelled, a + unit * end, paint);
      travelled = end + gap;
    }
  }

  /// The part marking, on a leader out to the clear upper left: a dot on the
  /// face it names, a diagonal out, a horizontal shoulder, then the text.
  void _annotation(Canvas canvas, Offset frontTL, Size size, bool known) {
    final label = materialLabel.trim();
    if (label.isEmpty || size.width < 190) return;

    final dot = frontTL + const Offset(26, 20);
    final elbow = Offset(frontTL.dx - 12, frontTL.dy - 16);
    final shoulder = Offset(math.max(6, elbow.dx - 26), elbow.dy);

    final leader = Paint()
      ..strokeWidth = 0.7
      ..color = known ? _dimLine : _thinLine;
    canvas.drawLine(dot, elbow, leader);
    canvas.drawLine(elbow, shoulder, leader);
    canvas.drawCircle(dot, 2.2, Paint()..color = known ? _ink : _thinLine);

    _text(
      canvas,
      label.toUpperCase(),
      shoulder + const Offset(0, -12),
      align: _Align.left,
      size: 8.5,
      weight: FontWeight.w700,
      color: known ? _dimLine : _thinLine,
      letterSpacing: 0.9,
    );
  }

  /// A dimension on one of the face's true edges: extension lines off each end,
  /// an arrowed dimension line between them, and the measurement floating just
  /// clear of it. No knock-out behind the number and no heavy strokes — on a
  /// drawing the dimension is a hairline annotation sitting off the part.
  void _straightDimension(
    Canvas canvas, {
    required Offset from,
    required Offset to,
    required Offset outward,
    required String label,
    required bool known,
    required bool vertical,
  }) {
    final extension = Paint()
      ..strokeWidth = 0.6
      ..color = known ? _thinLine : _ghost;
    final line = Paint()
      ..strokeWidth = 0.7
      ..color = known ? _dimLine : _ghost;

    final gap = outward * _extensionGap;
    final over = outward * (_dimOffset + _extensionOver);
    canvas.drawLine(from + gap, from + over, extension);
    canvas.drawLine(to + gap, to + over, extension);

    final a = from + outward * _dimOffset;
    final b = to + outward * _dimOffset;
    canvas.drawLine(a, b, line);

    final along = b - a;
    final length = along.distance;
    if (length < 1) return;
    final unit = along / length;
    if (length > 24) {
      _arrow(canvas, a, unit, line.color);
      _arrow(canvas, b, -unit, line.color);
    } else {
      // Too short to hold its own arrows, so they go outside pointing in.
      _arrow(canvas, a, -unit, line.color);
      _arrow(canvas, b, unit, line.color);
    }

    final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    canvas.save();
    canvas.translate(mid.dx, mid.dy);
    if (vertical) {
      // Turned to read up the line, as a height is dimensioned on a drawing.
      canvas.rotate(-math.pi / 2);
      _text(
        canvas,
        label,
        const Offset(0, -8),
        align: _Align.centre,
        size: 9.5,
        weight: FontWeight.w700,
        color: known ? _ink : _thinLine,
      );
    } else {
      _text(
        canvas,
        label,
        const Offset(0, 8),
        align: _Align.centre,
        size: 9.5,
        weight: FontWeight.w700,
        color: known ? _ink : _thinLine,
      );
    }
    canvas.restore();
  }

  /// The gauge, dimensioned along the receding edge at the top right. Extension
  /// lines run straight up from each end, which leaves the dimension line
  /// parallel to the edge it measures. It is always the shortest measurement on
  /// the drawing, so the arrows sit outside pointing in.
  void _gaugeDimension(Canvas canvas, Offset front, Offset back, Size size) {
    final known = shape.thickness > 0;
    final extension = Paint()
      ..strokeWidth = 0.6
      ..color = known ? _thinLine : _ghost;
    final line = Paint()
      ..strokeWidth = 0.7
      ..color = known ? _dimLine : _ghost;

    const rise = 16.0;
    final a = front + const Offset(0, -rise);
    final b = back + const Offset(0, -rise);
    final span = (b - a).distance;

    if (span < 2) {
      // No gauge recorded, so there is no edge to dimension. A witness line up
      // from the corner still says where the measurement belongs, which is what
      // makes the placeholder read as missing rather than as floating text.
      canvas.drawLine(
        front + const Offset(0, -4),
        front + const Offset(0, -rise - 5),
        extension,
      );
    } else {
      canvas.drawLine(
        front + const Offset(0, -4),
        a + const Offset(0, -5),
        extension,
      );
      canvas.drawLine(
        back + const Offset(0, -4),
        b + const Offset(0, -5),
        extension,
      );
      canvas.drawLine(a, b, line);
      final unit = (b - a) / span;
      if (span > 22) {
        _arrow(canvas, a, unit, line.color);
        _arrow(canvas, b, -unit, line.color);
      } else {
        _arrow(canvas, a, -unit, line.color);
        _arrow(canvas, b, unit, line.color);
      }
    }

    // Centred over the dimension line rather than trailing off its right end:
    // on a wide sheet that corner is already against the margin, and the
    // measurement is the one thing on the drawing that must not be clipped.
    final label = known ? 'z  ${_fmt(shape.thickness)} mm' : 'z  thickness';
    final mid = span < 2
        ? front + const Offset(0, -rise)
        : Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    final labelWidth = _measure(label, 9.5, FontWeight.w700);
    final cx = mid.dx
        .clamp(
          labelWidth / 2 + 4,
          math.max(labelWidth / 2 + 4, size.width - labelWidth / 2 - 4),
        )
        .toDouble();
    _text(
      canvas,
      label,
      Offset(cx, mid.dy - 14),
      align: _Align.centre,
      size: 9.5,
      weight: FontWeight.w700,
      color: known ? _ink : _thinLine,
    );
    if (known) {
      // Said plainly, in the drawing's own abbreviation: a 1 mm skin drawn true
      // against a 48 in face would be a hairline, so the gauge is exaggerated.
      // That is ordinary practice for thin material; letting the reader think
      // it is to scale would not be.
      _text(
        canvas,
        'n.t.s.',
        Offset(cx, mid.dy - 5),
        align: _Align.centre,
        size: 7.5,
        weight: FontWeight.w600,
        color: _thinLine,
      );
    }
  }

  double _measure(String value, double size, FontWeight weight) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(fontSize: size, fontWeight: weight),
      ),
      textDirection: textDirection,
    )..layout();
    return painter.width;
  }

  /// Depth the gauge is drawn at, in the same units as the face.
  ///
  /// Not to scale, and cannot be: a 1 mm sheet is a thousandth of a 48 in face
  /// and would vanish into the edge line. Compressed through a square root so
  /// the drawing stays monotonic — 4 mm still reads thicker than 1 mm, and
  /// visibly so — while a 12 mm plate does not swallow the solid.
  static double _modelThickness(double thicknessMm, double face) {
    if (thicknessMm <= 0) return 0;
    final compressed = math.sqrt(thicknessMm.clamp(0.05, 40.0));
    return (face * 0.038 * compressed).clamp(face * 0.016, face * 0.34);
  }

  void _arrow(Canvas canvas, Offset tip, Offset direction, Color colour) {
    const length = 5.5;
    const spread = 1.7;
    final base = tip + direction * length;
    final normal = Offset(-direction.dy, direction.dx) * spread;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(base.dx + normal.dx, base.dy + normal.dy)
      ..lineTo(base.dx - normal.dx, base.dy - normal.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = colour);
  }

  void _text(
    Canvas canvas,
    String value,
    Offset at, {
    required _Align align,
    required double size,
    required FontWeight weight,
    required Color color,
    double letterSpacing = 0,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: color,
          letterSpacing: letterSpacing,
        ),
      ),
      textDirection: textDirection,
    )..layout();
    final origin = switch (align) {
      _Align.centre => at - Offset(painter.width / 2, painter.height / 2),
      _Align.left => at,
    };
    painter.paint(canvas, origin);
  }

  /// Trims what a typed decimal leaves behind: 12 rather than 12.0, 12.5 whole.
  static String _fmt(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  @override
  bool shouldRepaint(_SheetPainter old) =>
      old.shape.width != shape.width ||
      old.shape.height != shape.height ||
      old.shape.thickness != shape.thickness ||
      old.trimInches != trimInches ||
      old.columnPlanEndInches != columnPlanEndInches ||
      old.rowPlanEndInches != rowPlanEndInches ||
      !listEquals(old.regionCuts, regionCuts) ||
      old.primaryIsColumns != primaryIsColumns ||
      !listEquals(old.columnBands, columnBands) ||
      !listEquals(old.rowBands, rowBands) ||
      old.hasFace != hasFace ||
      old.materialLabel != materialLabel;
}

enum _Align { left, centre }

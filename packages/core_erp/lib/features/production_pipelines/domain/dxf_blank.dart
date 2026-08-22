import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Reading a blank size out of a DXF.
///
/// The point is to stop people typing four numbers off a drawing, because that
/// is where wrong blank sizes come from and a wrong blank silently poisons every
/// sheet plan built on it.
///
/// What this deliberately does **not** do is guess which shape is the part. A
/// die drawing holds the die plate, the punch, dimension lines, notes, a title
/// block and often several views; the largest thing in it is the paper and the
/// second largest is usually the plate. The header's own `$EXTMIN`/`$EXTMAX`
/// extents are free to read and would be wrong for exactly that reason. So this
/// finds every candidate profile and hands them to a human to choose from —
/// one click, and then the size is exact and traceable.

/// How a candidate was found, which is most of how trustworthy it is.
enum DxfProfileKind {
  /// A closed polyline — the usual way a part outline is drawn.
  closedOutline,

  /// A circle, which is its own closed profile.
  circle,

  /// Everything on one layer, taken together. A fallback for drawings whose
  /// outlines are loose lines rather than closed polylines.
  layer,
}

/// The units a drawing declares, which decide whether 60 means 60 mm or 60 in.
///
/// A drawing in inches read as millimetres is wrong by 25.4×, and it would look
/// entirely plausible — so an undeclared unit is surfaced rather than assumed.
enum DxfUnits {
  unspecified,
  millimetres,
  centimetres,
  metres,
  inches,
  feet;

  /// The `$INSUNITS` header value, per the DXF specification.
  static DxfUnits fromInsUnits(int? code) => switch (code) {
    1 => DxfUnits.inches,
    2 => DxfUnits.feet,
    4 => DxfUnits.millimetres,
    5 => DxfUnits.centimetres,
    6 => DxfUnits.metres,
    _ => DxfUnits.unspecified,
  };

  /// How many millimetres one drawing unit is. Unspecified is treated as
  /// millimetres for arithmetic, but the caller is told it was a guess.
  double get millimetresPerUnit => switch (this) {
    DxfUnits.inches => 25.4,
    DxfUnits.feet => 304.8,
    DxfUnits.millimetres => 1,
    DxfUnits.centimetres => 10,
    DxfUnits.metres => 1000,
    DxfUnits.unspecified => 1,
  };

  String get label => switch (this) {
    DxfUnits.inches => 'inches',
    DxfUnits.feet => 'feet',
    DxfUnits.millimetres => 'mm',
    DxfUnits.centimetres => 'cm',
    DxfUnits.metres => 'm',
    DxfUnits.unspecified => 'unspecified',
  };
}

/// One shape in the drawing that could be the blank, with the size it would
/// give. Sizes are already converted to millimetres.
@immutable
class DxfProfile {
  const DxfProfile({
    required this.kind,
    required this.layer,
    required this.widthMm,
    required this.heightMm,
    required this.entityCount,
  });

  final DxfProfileKind kind;
  final String layer;
  final double widthMm;
  final double heightMm;
  final int entityCount;

  double get areaMm2 => widthMm * heightMm;

  bool get isUsable => widthMm > 0 && heightMm > 0;

  String get sizeLabel => '${_trim(widthMm)} × ${_trim(heightMm)} mm';

  String get kindLabel => switch (kind) {
    DxfProfileKind.closedOutline => 'closed outline',
    DxfProfileKind.circle => 'circle',
    DxfProfileKind.layer => 'layer total',
  };

  static String _trim(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}

/// What a parse produced: the candidates, and what the drawing said about its
/// own units.
@immutable
class DxfBlankCandidates {
  const DxfBlankCandidates({
    required this.profiles,
    required this.units,
    this.entitiesRead = 0,
  });

  final List<DxfProfile> profiles;
  final DxfUnits units;
  final int entitiesRead;

  bool get isEmpty => profiles.isEmpty;

  /// True when the drawing never said what its units were, so every size here
  /// rests on an assumption the reader has to confirm.
  bool get unitsAssumed => units == DxfUnits.unspecified;
}

/// Parses the entities of a DXF into candidate blank profiles.
///
/// Handles the ASCII form, which is what every CAD package exports and what the
/// client will be sending. Binary DXF and DWG are not readable here; DWG needs
/// a licensed library and is normally exported to DXF instead.
class DxfBlankReader {
  const DxfBlankReader();

  /// Reads [contents], the text of a `.dxf` file.
  ///
  /// Returns candidates rather than an answer. Ordered smallest first, because
  /// the blank is nearly always smaller than the plate it is cut on and the
  /// drawing sheet it is drawn on — but that is presentation, not a decision.
  DxfBlankCandidates read(String contents) {
    final pairs = _pairs(contents);
    if (pairs.isEmpty) {
      return const DxfBlankCandidates(
        profiles: <DxfProfile>[],
        units: DxfUnits.unspecified,
      );
    }

    final units = _readUnits(pairs);
    final scale = units.millimetresPerUnit;
    final profiles = <DxfProfile>[];
    final byLayer = <String, _Extent>{};
    var entitiesRead = 0;

    for (final entity in _entities(pairs)) {
      final extent = _extentOf(entity);
      if (extent == null) continue;
      entitiesRead++;
      (byLayer[entity.layer] ??= _Extent()).absorb(extent);

      // A closed shape stands on its own as a candidate; an open one only
      // contributes to its layer, because half an outline is not a part.
      final kind = switch (entity.type) {
        'CIRCLE' => DxfProfileKind.circle,
        'LWPOLYLINE' ||
        'POLYLINE' when entity.closed => DxfProfileKind.closedOutline,
        _ => null,
      };
      if (kind == null) continue;
      profiles.add(
        DxfProfile(
          kind: kind,
          layer: entity.layer,
          widthMm: extent.width * scale,
          heightMm: extent.height * scale,
          entityCount: 1,
        ),
      );
    }

    for (final entry in byLayer.entries) {
      final extent = entry.value;
      if (!extent.isValid) continue;
      profiles.add(
        DxfProfile(
          kind: DxfProfileKind.layer,
          layer: entry.key,
          widthMm: extent.width * scale,
          heightMm: extent.height * scale,
          entityCount: extent.count,
        ),
      );
    }

    final usable = profiles.where((profile) => profile.isUsable).toList()
      ..sort((a, b) => a.areaMm2.compareTo(b.areaMm2));
    return DxfBlankCandidates(
      profiles: List<DxfProfile>.unmodifiable(usable),
      units: units,
      entitiesRead: entitiesRead,
    );
  }

  /// A DXF is a flat run of group code / value pairs, one of each per line.
  List<_Pair> _pairs(String contents) {
    final lines = contents.split(RegExp(r'\r?\n'));
    final pairs = <_Pair>[];
    for (var i = 0; i + 1 < lines.length; i += 2) {
      final code = int.tryParse(lines[i].trim());
      if (code == null) {
        // Not a code where one was due: the file is not an ASCII DXF, or is
        // truncated. Stop rather than reading noise as geometry.
        break;
      }
      pairs.add(_Pair(code, lines[i + 1].trim()));
    }
    return pairs;
  }

  DxfUnits _readUnits(List<_Pair> pairs) {
    for (var i = 0; i < pairs.length - 1; i++) {
      if (pairs[i].code == 9 && pairs[i].value == r'$INSUNITS') {
        return DxfUnits.fromInsUnits(int.tryParse(pairs[i + 1].value));
      }
    }
    return DxfUnits.unspecified;
  }

  /// Everything between `ENTITIES` and the `ENDSEC` that closes it. Blocks are
  /// skipped: a block definition is a stencil, and its geometry is drawn at
  /// whatever place and scale an INSERT puts it.
  List<_Entity> _entities(List<_Pair> pairs) {
    var start = -1;
    for (var i = 0; i < pairs.length - 1; i++) {
      if (pairs[i].code == 2 && pairs[i].value == 'ENTITIES') {
        start = i + 1;
        break;
      }
    }
    if (start < 0) return const <_Entity>[];

    final entities = <_Entity>[];
    _Entity? current;
    for (var i = start; i < pairs.length; i++) {
      final pair = pairs[i];
      if (pair.code == 0) {
        if (current != null) entities.add(current);
        current = null;
        if (pair.value == 'ENDSEC') break;
        current = _Entity(pair.value);
        continue;
      }
      current?.add(pair);
    }
    if (current != null) entities.add(current);
    return entities;
  }

  /// The bounding box of one entity in drawing units.
  _Extent? _extentOf(_Entity entity) {
    switch (entity.type) {
      case 'LINE':
        final extent = _Extent();
        extent.point(entity.first(10), entity.first(20));
        extent.point(entity.first(11), entity.first(21));
        return extent.isValid ? extent : null;
      case 'CIRCLE':
        final cx = entity.first(10);
        final cy = entity.first(20);
        final r = entity.first(40);
        if (cx == null || cy == null || r == null || r <= 0) return null;
        final extent = _Extent()
          ..point(cx - r, cy - r)
          ..point(cx + r, cy + r);
        return extent;
      case 'ARC':
        final cx = entity.first(10);
        final cy = entity.first(20);
        final r = entity.first(40);
        if (cx == null || cy == null || r == null || r <= 0) return null;
        // The arc's own sweep, not the full circle: a fillet on a corner should
        // not inflate the part by its radius in every direction.
        return _arcExtent(cx, cy, r, entity.first(50), entity.first(51));
      case 'LWPOLYLINE':
      case 'POLYLINE':
        final xs = entity.all(10);
        final ys = entity.all(20);
        if (xs.isEmpty || ys.isEmpty) return null;
        final extent = _Extent();
        for (var i = 0; i < xs.length && i < ys.length; i++) {
          extent.point(xs[i], ys[i]);
        }
        return extent.isValid ? extent : null;
      case 'SPLINE':
        // Control points, whose hull contains the curve. An over-estimate, but
        // never an under-estimate — a blank read too small would be the
        // dangerous direction.
        final xs = entity.all(10);
        final ys = entity.all(20);
        if (xs.isEmpty || ys.isEmpty) return null;
        final extent = _Extent();
        for (var i = 0; i < xs.length && i < ys.length; i++) {
          extent.point(xs[i], ys[i]);
        }
        return extent.isValid ? extent : null;
      default:
        return null;
    }
  }

  _Extent? _arcExtent(
    double cx,
    double cy,
    double r,
    double? startDeg,
    double? endDeg,
  ) {
    if (startDeg == null || endDeg == null) {
      return _Extent()
        ..point(cx - r, cy - r)
        ..point(cx + r, cy + r);
    }
    var sweepStart = startDeg % 360;
    var sweepEnd = endDeg % 360;
    if (sweepEnd <= sweepStart) sweepEnd += 360;

    final extent = _Extent();
    double atAngle(double deg) => deg * math.pi / 180;
    extent.point(
      cx + r * math.cos(atAngle(sweepStart)),
      cy + r * math.sin(atAngle(sweepStart)),
    );
    extent.point(
      cx + r * math.cos(atAngle(sweepEnd)),
      cy + r * math.sin(atAngle(sweepEnd)),
    );
    // The compass points the sweep actually passes are where an arc reaches
    // furthest; without them a half circle would measure as its chord.
    for (final quarter in <double>[0, 90, 180, 270, 360, 450, 540, 630]) {
      if (quarter < sweepStart || quarter > sweepEnd) continue;
      extent.point(
        cx + r * math.cos(atAngle(quarter)),
        cy + r * math.sin(atAngle(quarter)),
      );
    }
    return extent.isValid ? extent : null;
  }
}

class _Pair {
  const _Pair(this.code, this.value);
  final int code;
  final String value;
}

class _Entity {
  _Entity(this.type);

  final String type;
  final Map<int, List<double>> _numbers = <int, List<double>>{};
  String layer = '0';
  bool closed = false;

  void add(_Pair pair) {
    if (pair.code == 8) {
      layer = pair.value.isEmpty ? '0' : pair.value;
      return;
    }
    if (pair.code == 70) {
      // Bit 1 of the flags marks a closed polyline.
      final flags = int.tryParse(pair.value) ?? 0;
      closed = flags & 1 == 1;
      return;
    }
    final number = double.tryParse(pair.value);
    if (number == null) return;
    (_numbers[pair.code] ??= <double>[]).add(number);
  }

  double? first(int code) {
    final values = _numbers[code];
    return values == null || values.isEmpty ? null : values.first;
  }

  List<double> all(int code) => _numbers[code] ?? const <double>[];
}

class _Extent {
  double? minX;
  double? maxX;
  double? minY;
  double? maxY;
  int count = 0;

  bool get isValid =>
      minX != null && maxX != null && minY != null && maxY != null;

  double get width => isValid ? maxX! - minX! : 0;
  double get height => isValid ? maxY! - minY! : 0;

  void point(double? x, double? y) {
    if (x == null || y == null) return;
    minX = minX == null ? x : math.min(minX!, x);
    maxX = maxX == null ? x : math.max(maxX!, x);
    minY = minY == null ? y : math.min(minY!, y);
    maxY = maxY == null ? y : math.max(maxY!, y);
  }

  void absorb(_Extent other) {
    if (!other.isValid) return;
    point(other.minX, other.minY);
    point(other.maxX, other.maxY);
    count++;
  }
}

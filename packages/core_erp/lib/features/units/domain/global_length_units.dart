/// Every length unit the system knows how to read a measurement in.
///
/// Global, and deliberately not the units master: whether a shop has installed
/// a unit decides what it can *stock* things in, not what it can *type* a
/// measurement in. A drawing quoted in thou is quoted in thou whether or not
/// anyone ever bought material by it, and refusing to read it would only push
/// the conversion back onto a calculator and a sticky note.
///
/// The units master remains the authority on what can be transacted. This is
/// the authority on what can be understood.
library;

import '../../items/domain/swg_gauge_table.dart';

/// How a unit turns into millimetres.
enum LengthUnitKind {
  /// A fixed number of millimetres per unit.
  linear,

  /// A lookup: the number typed is a gauge, and the table says what it means.
  /// There is no factor, because gauge is not proportional to anything — 20
  /// gauge is not twice 10 gauge, it is thinner.
  gauge,
}

/// One length unit, as the system understands it.
class GlobalLengthUnit {
  const GlobalLengthUnit({
    required this.name,
    required this.symbol,
    required this.kind,
    this.millimetres = 0,
    this.aliases = const <String>[],
  });

  final String name;
  final String symbol;
  final LengthUnitKind kind;

  /// Millimetres in one of this unit. Meaningless for [LengthUnitKind.gauge].
  final double millimetres;

  /// Other things people type when they mean this, for the search to match.
  final List<String> aliases;

  bool get isGauge => kind == LengthUnitKind.gauge;

  /// A typed value in millimetres.
  ///
  /// For a gauge that is a lookup, and a number the table does not have is not
  /// a thickness — it returns zero rather than inventing one, because guessing
  /// what 41 gauge means would put a wrong thickness on a real sheet.
  double toMm(double value) {
    if (value <= 0) return 0;
    if (!isGauge) return value * millimetres;
    for (final entry in swgGaugeTable) {
      if (entry.gauge == value.round()) return entry.mm;
    }
    return 0;
  }

  /// Millimetres written in this unit.
  ///
  /// A gauge is the nearest standard gauge to that thickness — nearest rather
  /// than exact, because a sheet measured at 1.2 mm is 18 gauge to everyone on
  /// the floor even though the table says 1.219.
  double fromMm(double mm) {
    if (mm <= 0) return 0;
    if (!isGauge) return mm / millimetres;
    var best = swgGaugeTable.first;
    for (final entry in swgGaugeTable) {
      if ((entry.mm - mm).abs() < (best.mm - mm).abs()) best = entry;
    }
    return best.gauge.toDouble();
  }

  /// Whether [query] should turn this unit up in a search.
  bool matches(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    if (symbol.toLowerCase().contains(needle)) return true;
    if (name.toLowerCase().contains(needle)) return true;
    return aliases.any((alias) => alias.toLowerCase().contains(needle));
  }
}

/// The length units, coarsest first — the order someone scanning a list expects
/// rather than the order they were added.
const List<GlobalLengthUnit> globalLengthUnits = <GlobalLengthUnit>[
  GlobalLengthUnit(
    name: 'meter',
    symbol: 'm',
    kind: LengthUnitKind.linear,
    millimetres: 1000,
    aliases: <String>['metre'],
  ),
  GlobalLengthUnit(
    name: 'foot',
    symbol: 'ft',
    kind: LengthUnitKind.linear,
    millimetres: 304.8,
    aliases: <String>['feet'],
  ),
  GlobalLengthUnit(
    name: 'inch',
    symbol: 'in',
    kind: LengthUnitKind.linear,
    millimetres: 25.4,
    aliases: <String>['inches', '"'],
  ),
  GlobalLengthUnit(
    name: 'centimeter',
    symbol: 'cm',
    kind: LengthUnitKind.linear,
    millimetres: 10,
    aliases: <String>['centimetre'],
  ),
  GlobalLengthUnit(
    name: 'millimeter',
    symbol: 'mm',
    kind: LengthUnitKind.linear,
    millimetres: 1,
    aliases: <String>['millimetre'],
  ),
  GlobalLengthUnit(
    name: 'thou',
    symbol: 'thou',
    kind: LengthUnitKind.linear,
    millimetres: 0.0254,
    aliases: <String>['mil', 'thousandth'],
  ),
  GlobalLengthUnit(
    name: 'gauge',
    symbol: 'ga',
    kind: LengthUnitKind.gauge,
    aliases: <String>['swg', 'gage', 'wire gauge'],
  ),
];

/// The unit written as [symbol], or [fallback] when nothing matches.
///
/// Falling back rather than throwing: a record naming a unit this build does
/// not know should still open, showing its measurement in something sensible,
/// rather than refusing to load.
GlobalLengthUnit lengthUnitBySymbol(String? symbol, {String fallback = 'mm'}) {
  for (final unit in globalLengthUnits) {
    if (unit.symbol == symbol) return unit;
  }
  for (final unit in globalLengthUnits) {
    if (unit.symbol == fallback) return unit;
  }
  return globalLengthUnits.last;
}

/// The units that can express a measurement along a face — everything except
/// gauge, which only ever means a thickness.
List<GlobalLengthUnit> get faceLengthUnits =>
    globalLengthUnits.where((unit) => !unit.isGauge).toList(growable: false);

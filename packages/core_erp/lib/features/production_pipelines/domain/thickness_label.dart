import '../../units/domain/global_length_units.dart';

/// A thickness as the part's Thickness cell writes it, and back.
///
/// The cell is text — "23 Gauge" when a gauge was picked, "1.2 mm" when a
/// measurement was typed — and the raw material panel edits the same value as
/// a number and a unit, so the two read each other through this.
class ThicknessReading {
  const ThicknessReading(this.value, this.unit);

  final double value;
  final GlobalLengthUnit unit;

  double get mm => unit.toMm(value);
}

final RegExp _gaugeText = RegExp(
  r'^(\d+)\s*(gauge|ga|swg|g)$',
  caseSensitive: false,
);
final RegExp _measuredText = RegExp(
  r'^(\d+(?:\.\d+)?|\.\d+)\s*([a-z]*)$',
  caseSensitive: false,
);

/// "23 Gauge" → 23 ga, "1.2 mm" → 1.2 mm, "1.2" → 1.2 mm. Null for text that
/// is not a measurement, or a unit nobody here measures thickness in.
ThicknessReading? readThickness(String text) {
  final clean = text.trim();
  if (clean.isEmpty) return null;
  final gauge = _gaugeText.firstMatch(clean);
  if (gauge != null) {
    return ThicknessReading(
      double.parse(gauge.group(1)!),
      lengthUnitBySymbol('ga'),
    );
  }
  final measured = _measuredText.firstMatch(clean);
  if (measured == null) return null;
  final value = double.parse(measured.group(1)!);
  final symbol = measured.group(2)!.toLowerCase();
  if (symbol.isEmpty) return ThicknessReading(value, lengthUnitBySymbol('mm'));
  for (final unit in globalLengthUnits) {
    if (unit.isGauge) continue;
    if (unit.symbol.toLowerCase() == symbol) return ThicknessReading(value, unit);
  }
  return null;
}

/// What the cell is given: "23 Gauge" — the gauge option's own label, so a
/// gauge typed here is the gauge picked there — or "1.2 mm". Empty for none.
String writeThickness(double value, GlobalLengthUnit unit) {
  if (value <= 0) return '';
  if (unit.isGauge) return '${value.round()} Gauge';
  final shown = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value
            .toStringAsFixed(4)
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '');
  return '$shown ${unit.symbol}';
}

import '../../../units/domain/unit_definition.dart';

/// A quantity re-expressed in a larger unit of the same family, for display.
class ScaledQuantity {
  const ScaledQuantity({
    required this.value,
    required this.unit,
    required this.text,
    required this.wasPromoted,
    required this.isSyntheticUnit,
  });

  /// The value in [unit] — display only. The stored quantity never changes.
  final double value;

  /// The unit the value is shown in. Null when the source unit was unknown.
  final UnitDefinition? unit;

  /// Number and symbol together, e.g. "105.39 t".
  final String text;

  /// Whether a larger unit was substituted for the recorded one.
  final bool wasPromoted;

  /// True when the display unit came from built-in SI knowledge rather than the
  /// workspace's own units master — i.e. no such unit exists to select or store
  /// against. Callers that let a user act on the figure should show the
  /// recorded unit instead.
  final bool isSyntheticUnit;
}

/// Standard SI rungs, in base units of the family's smallest member.
///
/// Consulted only when the workspace's own family has nothing bigger to offer,
/// so a factory that never created "metric ton" still reads tonnes on a rollup.
/// Recognition is by symbol or name because a unit master that lacks the bigger
/// unit usually also lacks the family metadata that would identify it.
class _SiRung {
  const _SiRung(this.symbol, this.factor);
  final String symbol;
  final double factor;
}

const Map<String, List<_SiRung>> _siLadders = <String, List<_SiRung>>{
  'mass': <_SiRung>[
    _SiRung('mg', 0.001),
    _SiRung('g', 1),
    _SiRung('kg', 1000),
    _SiRung('t', 1000000),
  ],
  'length': <_SiRung>[
    _SiRung('mm', 1),
    _SiRung('cm', 10),
    _SiRung('m', 1000),
    _SiRung('km', 1000000),
  ],
  'volume': <_SiRung>[
    _SiRung('ml', 1),
    _SiRung('l', 1000),
    _SiRung('kl', 1000000),
  ],
};

/// Symbols and names that identify a rung, so "kilogram", "kgs" and "KG" all
/// land on the same one.
const Map<String, String> _siAliases = <String, String>{
  'mg': 'mass|mg', 'milligram': 'mass|mg', 'milligrams': 'mass|mg',
  'g': 'mass|g', 'gm': 'mass|g', 'gram': 'mass|g', 'grams': 'mass|g',
  'kg': 'mass|kg', 'kgs': 'mass|kg', 'kilogram': 'mass|kg',
  'kilograms': 'mass|kg', 'kilo': 'mass|kg',
  't': 'mass|t', 'ton': 'mass|t', 'tons': 'mass|t', 'tonne': 'mass|t',
  'tonnes': 'mass|t', 'mt': 'mass|t', 'metric ton': 'mass|t',
  'mm': 'length|mm', 'millimeter': 'length|mm', 'millimetre': 'length|mm',
  'cm': 'length|cm', 'centimeter': 'length|cm', 'centimetre': 'length|cm',
  'm': 'length|m', 'meter': 'length|m', 'metre': 'length|m',
  'meters': 'length|m', 'metres': 'length|m',
  'km': 'length|km', 'kilometer': 'length|km', 'kilometre': 'length|km',
  'ml': 'volume|ml', 'milliliter': 'volume|ml', 'millilitre': 'volume|ml',
  'l': 'volume|l', 'ltr': 'volume|l', 'liter': 'volume|l',
  'litre': 'volume|l', 'liters': 'volume|l', 'litres': 'volume|l',
  'kl': 'volume|kl', 'kiloliter': 'volume|kl', 'kilolitre': 'volume|kl',
};

class QuantityFormatter {
  /// Formats a quantity, honoring the unit's precision.
  /// If [unit] is provided and has a precision, it will restrict the decimal places to that precision.
  /// Otherwise, it defaults to a reasonable maximum precision (4) and strips trailing zeros.
  static String format(double value, [UnitDefinition? unit]) {
    final rounded = value.roundToDouble();
    if ((value - rounded).abs() < 0.000001) {
      return rounded.toStringAsFixed(0);
    }

    final int precision = unit?.precision ?? 4;
    return _trimZeros(value.toStringAsFixed(precision));
  }

  /// Re-expresses [value] in the largest unit of its family that keeps the
  /// number readable: 105390.84 kg reads as "105.39 t".
  ///
  /// Display only. Nothing here converts stored data, and the ledger keeps the
  /// unit each movement was recorded in — use this for rollups and on-hand
  /// figures, where magnitude matters more than the recorded unit.
  ///
  /// The ladder comes from the unit family itself ([unitsInGroup]) rather than
  /// a hardcoded table, so it works for any family the workspace defines, using
  /// the same `value * factor` / `base / factor` arithmetic as the converter.
  ///
  /// A larger unit is substituted only when:
  ///  - the raw number reaches [promoteAbove] — below that the recorded unit is
  ///    the clearer one, so 999 kg stays 999 kg rather than 0.999 t; and
  ///  - a bigger sibling exists in which the value still reads at least 1.
  ///
  /// Table-driven units (gauge and similar) are never promoted: their values
  /// are discrete lookup keys, not a linear magnitude.
  static ScaledQuantity formatScaled(
    double value,
    UnitDefinition? unit,
    List<UnitDefinition> unitsInGroup, {
    double promoteAbove = 1000,
    int maxDecimals = 2,
  }) {
    String withSymbol(UnitDefinition? u, String text) =>
        (u?.symbol.trim().isNotEmpty ?? false) ? '$text ${u!.symbol}' : text;

    ScaledQuantity asIs() => ScaledQuantity(
      value: value,
      unit: unit,
      text: withSymbol(unit, format(value, unit)),
      wasPromoted: false,
      isSyntheticUnit: false,
    );

    if (unit == null ||
        unit.conversionType == 'table' ||
        value.abs() < promoteAbove) {
      return asIs();
    }
    // An ungrouped unit has no family to walk, but SI knowledge may still know
    // it — a lone "kg" with no unit group should still read in tonnes.
    if (unit.unitGroupId == null || unit.conversionFactor <= 0) {
      return _promoteViaSiLadder(value, unit, maxDecimals) ?? asIs();
    }

    final baseValue = value * unit.conversionFactor;
    UnitDefinition? best;
    for (final candidate in unitsInGroup) {
      if (candidate.isArchived ||
          candidate.unitGroupId != unit.unitGroupId ||
          candidate.conversionType == 'table' ||
          candidate.conversionFactor <= unit.conversionFactor) {
        continue;
      }
      // Must still read as at least 1 in the bigger unit, and we want the
      // biggest such unit — 1 500 000 g should reach tonnes, not stop at kg.
      if ((baseValue / candidate.conversionFactor).abs() < 1) {
        continue;
      }
      if (best == null || candidate.conversionFactor > best.conversionFactor) {
        best = candidate;
      }
    }

    if (best == null) {
      // The workspace's family has nothing bigger. Fall back to built-in SI
      // knowledge so the reading is still sensible.
      return _promoteViaSiLadder(value, unit, maxDecimals) ?? asIs();
    }

    final scaled = baseValue / best.conversionFactor;
    return ScaledQuantity(
      value: scaled,
      unit: best,
      text: withSymbol(best, _trimZeros(scaled.toStringAsFixed(maxDecimals))),
      wasPromoted: true,
      isSyntheticUnit: false,
    );
  }

  /// Promotes using the built-in SI ladders when the units master cannot.
  ///
  /// Returns null when the unit is not a recognisable SI unit, or when it is
  /// already the largest rung — the caller then keeps the recorded unit.
  static ScaledQuantity? _promoteViaSiLadder(
    double value,
    UnitDefinition unit,
    int maxDecimals,
  ) {
    final key =
        _siAliases[unit.symbol.trim().toLowerCase()] ??
        _siAliases[unit.name.trim().toLowerCase()];
    if (key == null) {
      return null;
    }
    final parts = key.split('|');
    final ladder = _siLadders[parts[0]];
    if (ladder == null) {
      return null;
    }
    final current = ladder.where((rung) => rung.symbol == parts[1]).firstOrNull;
    if (current == null) {
      return null;
    }

    final baseValue = value * current.factor;
    _SiRung? best;
    for (final rung in ladder) {
      if (rung.factor <= current.factor) continue;
      if ((baseValue / rung.factor).abs() < 1) continue;
      if (best == null || rung.factor > best.factor) best = rung;
    }
    if (best == null) {
      return null;
    }

    final scaled = baseValue / best.factor;
    return ScaledQuantity(
      value: scaled,
      // No UnitDefinition exists for it — that is the point of the fallback.
      unit: null,
      text: '${_trimZeros(scaled.toStringAsFixed(maxDecimals))} ${best.symbol}',
      wasPromoted: true,
      isSyntheticUnit: true,
    );
  }

  static String _trimZeros(String str) {
    if (!str.contains('.')) {
      return str;
    }
    var end = str.length - 1;
    while (end > 0 && str[end] == '0') {
      end--;
    }
    if (str[end] == '.') {
      end--;
    }
    return str.substring(0, end + 1);
  }
}

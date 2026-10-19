/// Static API and algorithms for Parsing, Formatting and Conversion.
/// Per `.claude/skills/units/SKILL.md` §4, §5.
library;

import 'quantity.dart';
import 'unit_family.dart';

class UnitParseError implements Exception {
  const UnitParseError(this.message);
  final String message;

  @override
  String toString() => 'UnitParseError: $message';
}

sealed class QtyDisplay {
  const QtyDisplay();

  /// Promote along the family ladder (e.g. 1250 g -> 1.25 kg).
  const factory QtyDisplay.auto() = _QtyDisplayAuto;

  /// Pin display to a specific unit (e.g. for documents, billed quantities).
  const factory QtyDisplay.pinned(Unit u) = _QtyDisplayPinned;

  /// Shop floor: always display in base unit, never promote.
  const factory QtyDisplay.base() = _QtyDisplayBase;
}

class _QtyDisplayAuto extends QtyDisplay {
  const _QtyDisplayAuto();
}

class _QtyDisplayPinned extends QtyDisplay {
  const _QtyDisplayPinned(this.unit);
  final Unit unit;
}

class _QtyDisplayBase extends QtyDisplay {
  const _QtyDisplayBase();
}

abstract final class Units {
  /// Parse user text in a chosen unit using pure integer/string arithmetic.
  /// Never uses `double.parse(text) * factor` (Invariant I1, I6).
  /// Throws [UnitParseError] if the result is not a whole number of base units.
  static Quantity parse(String text, Unit unit, [UnitFamily? family]) {
    final clean = text.trim().replaceAll(',', '');
    if (!RegExp(r'^-?\d+(\.\d+)?$').hasMatch(clean)) {
      throw UnitParseError('Invalid quantity format: "$text"');
    }

    final isNegative = clean.startsWith('-');
    final unsigned = isNegative ? clean.substring(1) : clean;
    final parts = unsigned.split('.');
    final wholeStr = parts[0];
    final fracStr = parts.length > 1 ? parts[1] : '';

    final factor = BigInt.from(unit.factorToBase);
    final d = fracStr.length;
    var denominator = BigInt.one;
    for (var i = 0; i < d; i++) {
      denominator *= BigInt.from(10);
    }

    final wholeBig = BigInt.parse(wholeStr);
    final fracBig = fracStr.isEmpty ? BigInt.zero : BigInt.parse(fracStr);
    final numerator = wholeBig * denominator + fracBig;

    final product = numerator * factor;
    if (product % denominator != BigInt.zero) {
      throw UnitParseError(
        '"$text ${unit.symbol}" is not a whole number of base units',
      );
    }

    final resolvedFamily = family ??
        UnitFamily(
          id: unit.familyId,
          code: '',
          name: '',
          dimension: '',
          units: [unit],
        );

    final baseBig = product ~/ denominator;
    final baseInt = (isNegative ? -baseBig : baseBig).toInt();
    return Quantity(baseInt, resolvedFamily);
  }

  static Quantity of(int amountInUnit, Unit unit, [UnitFamily? family]) {
    final resolvedFamily = family ??
        UnitFamily(
          id: unit.familyId,
          code: '',
          name: '',
          dimension: '',
          units: [unit],
        );
    return Quantity(amountInUnit * unit.factorToBase, resolvedFamily);
  }

  /// The single formatter. Every quantity shown anywhere goes through this.
  /// Per SKILL.md §5.
  static String format(
    Quantity q, {
    QtyDisplay display = const QtyDisplay.auto(),
  }) {
    final Unit targetUnit;
    switch (display) {
      case _QtyDisplayBase():
        targetUnit = q.family.base;
      case _QtyDisplayPinned(unit: final u):
        targetUnit = u;
      case _QtyDisplayAuto():
        final absQty = q.base.abs();
        final ladder = q.family.ladder;
        Unit? candidate;
        // Search largest unit with |q.base| >= u.factorToBase.
        //
        // On an INTEGRAL-ONLY family that unit must also divide exactly. Count
        // is integral-only and 228 pieces is 1.5833 gross, which is not a
        // quantity of anything: a third of a piece does not exist, so a screen
        // must never print one. 228 comes back "19 doz", and 229 — which no
        // rung above piece divides — comes back "229 Pc". The base always
        // divides (its factor is 1), so there is always an answer.
        for (var i = ladder.length - 1; i >= 0; i--) {
          if (absQty < ladder[i].factorToBase) continue;
          if (q.family.integralOnly && q.base % ladder[i].factorToBase != 0) {
            continue;
          }
          candidate = ladder[i];
          break;
        }
        targetUnit = candidate ?? (ladder.isNotEmpty ? ladder.first : q.family.base);
    }

    final factor = targetUnit.factorToBase;
    final symbol = targetUnit.symbol;
    final whole = q.base ~/ factor;
    final remainder = (q.base % factor).abs();

    if (remainder == 0) {
      return '$whole $symbol'.trim();
    }

    final maxDecimals = targetUnit.maxDecimals;
    final frac = remainder / factor;
    var fracStr = frac.toStringAsFixed(maxDecimals);
    if (fracStr.startsWith('0.')) {
      fracStr = fracStr.substring(2);
    }
    fracStr = fracStr.replaceAll(RegExp(r'0+$'), '');

    final sign = q.base < 0 && whole == 0 ? '-' : '';
    if (fracStr.isEmpty) {
      return '$sign$whole $symbol'.trim();
    }
    return '$sign$whole.$fracStr $symbol'.trim();
  }

  /// Value in a given unit as exact parts, for printing/export.
  static ({int whole, int remainder, int divisor}) inUnit(Quantity q, Unit u) {
    return (
      whole: q.base ~/ u.factorToBase,
      remainder: (q.base % u.factorToBase).abs(),
      divisor: u.factorToBase,
    );
  }
}

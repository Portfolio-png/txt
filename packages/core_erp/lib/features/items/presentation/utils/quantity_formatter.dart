import '../../../units/domain/unit_definition.dart';

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
    final str = value.toStringAsFixed(precision);
    
    if (str.contains('.')) {
      var end = str.length - 1;
      while (end > 0 && str[end] == '0') {
        end--;
      }
      if (str[end] == '.') {
        end--;
      }
      return str.substring(0, end + 1);
    }
    
    return str;
  }
}

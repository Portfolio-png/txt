/// Shorthand entry and Indian-grouped display for quantity fields.
///
/// Order quantities here run to lakhs, and counting zeroes on screen is how
/// an order for 1,00,000 becomes an order for 10,00,000. So the field accepts
/// `1k`, `1L`, `10L`, `1cr` and shows back the grouped number for confirmation.
///
/// No `intl` dependency: the app does not ship one, and Indian grouping is not
/// what `NumberFormat.decimalPattern()` gives you for a non-`en_IN` locale
/// anyway.
library;

/// Multipliers accepted as a suffix. Longest key first matters — `cr` must be
/// tried before `c`, and `lakh` before `l`.
const Map<String, num> _quantitySuffixes = <String, num>{
  'crore': 10000000,
  'cr': 10000000,
  'lakh': 100000,
  'lac': 100000,
  'l': 100000,
  'k': 1000,
  'thousand': 1000,
};

/// Parses a quantity the user typed, accepting shorthand and grouping commas.
///
/// `1k` → 1000, `1.5k` → 1500, `1L` → 100000, `10L` → 1000000,
/// `1cr` → 10000000, `1,00,000` → 100000, `250` → 250.
///
/// Returns null when the text is not a quantity at all. An empty or
/// whitespace-only string is null rather than 0, so a blank field stays blank.
num? parseQuantityShorthand(String? raw) {
  if (raw == null) return null;
  // Commas are grouping, never decimal, in this app's number entry.
  final text = raw.trim().toLowerCase().replaceAll(',', '').replaceAll(' ', '');
  if (text.isEmpty) return null;

  for (final entry in _quantitySuffixes.entries) {
    if (!text.endsWith(entry.key)) continue;
    final head = text.substring(0, text.length - entry.key.length);
    // A bare suffix ('k') is not a quantity; it needs a number in front.
    if (head.isEmpty) return null;
    final value = double.tryParse(head);
    if (value == null) return null;
    final scaled = value * entry.value;
    return scaled == scaled.roundToDouble() ? scaled.round() : scaled;
  }

  final plain = double.tryParse(text);
  if (plain == null) return null;
  return plain == plain.roundToDouble() ? plain.round() : plain;
}

/// Groups a number the Indian way: last three digits, then pairs.
/// 1000 → `1,000`; 100000 → `1,00,000`; 10000000 → `1,00,00,000`.
String formatIndianNumber(num value) {
  final negative = value < 0;
  final abs = value.abs();
  final whole = abs.truncate();
  final fraction = abs - whole;

  var digits = whole.toString();
  String grouped;
  if (digits.length <= 3) {
    grouped = digits;
  } else {
    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    grouped = '${parts.join(',')},$last3';
  }

  if (fraction > 0) {
    // Trim the trailing zeroes a raw toStringAsFixed would leave behind.
    final fractionText = fraction
        .toStringAsFixed(3)
        .substring(2)
        .replaceAll(RegExp(r'0+$'), '');
    if (fractionText.isNotEmpty) grouped = '$grouped.$fractionText';
  }
  return negative ? '-$grouped' : grouped;
}

/// The scale name for a round-ish quantity, for the tooltip's plain-English
/// half. Empty when the number is small enough to read at a glance.
String indianScaleLabel(num value) {
  final abs = value.abs();
  if (abs >= 10000000) {
    return '${_trim(abs / 10000000)} crore';
  }
  if (abs >= 100000) {
    return '${_trim(abs / 100000)} lakh';
  }
  if (abs >= 1000) {
    return '${_trim(abs / 1000)} thousand';
  }
  return '';
}

String _trim(num value) {
  final rounded = (value * 100).round() / 100;
  return rounded == rounded.roundToDouble()
      ? rounded.round().toString()
      : rounded.toString();
}

/// Tooltip for a quantity field. With nothing typed it teaches the shorthand;
/// with a value it reads the number back, so a mis-keyed zero is visible
/// without counting digits.
String quantityFieldTooltip(String? rawInput) {
  final parsed = parseQuantityShorthand(rawInput);
  if (parsed == null) {
    return 'Shorthand accepted:\n'
        '1k = 1,000\n'
        '1L = 1,00,000\n'
        '10L = 10,00,000\n'
        '1cr = 1,00,00,000';
  }
  final scale = indianScaleLabel(parsed);
  final grouped = formatIndianNumber(parsed);
  return scale.isEmpty ? grouped : '$grouped  ($scale)';
}

/// When a record was stamped, as a person on the floor reads it.
///
/// `.toLocal()` is the first thing both of these do, and it is the whole
/// reason they exist. The server writes timestamps as ISO strings ending in
/// `Z`, and `DateTime.parse` of one of those returns a UTC DateTime whose
/// `.day` and `.hour` are UTC fields. Reading them straight out shows an Indian
/// shop a part stamped at 10.05 AM as 4.35 AM — and anything stamped before
/// half past five in the morning as the day before.
library;

/// `15/05/2026` — the way a date is written on a drawing here.
String partStampDate(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day/$month/${local.year}';
}

/// `10.05 AM`, with the hour padded so a column of times lines up.
String partStampTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final meridiem = local.hour >= 12 ? 'PM' : 'AM';
  return '${hour.toString().padLeft(2, '0')}.$minute $meridiem';
}

/// Both, for a single line: `15/05/2026 10.05 AM`.
String partStamp(DateTime value) =>
    '${partStampDate(value)} ${partStampTime(value)}';

/// `₹85,000/-` — a rupee figure the way it is written on a quotation here.
///
/// Indian grouping, not the Western kind: the last three digits, then pairs
/// (`1,00,000`, not `100,000`). `/-` is a display convention and nothing else —
/// the stored value is a plain `REAL` number of rupees.
///
/// Money is deliberately NOT a unit. It never goes near the units skill: there
/// is no conversion ladder for it, no family, and every other amount in this
/// app (an order's unit price, an invoice total) is already plain rupees.
String rupeeStamp(num value, {bool trailingDash = true}) {
  final negative = value < 0;
  final absolute = value.abs();
  // Paise are shown only when there are paise. A catalogue of round quotations
  // reading "₹85,000.00/-" is noise.
  final hasPaise = (absolute * 100).round() % 100 != 0;
  final whole = absolute.truncate();
  final paise = ((absolute - whole) * 100).round();

  final digits = whole.toString();
  String grouped;
  if (digits.length <= 3) {
    grouped = digits;
  } else {
    final lastThree = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final pairs = <String>[];
    while (rest.length > 2) {
      pairs.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) pairs.insert(0, rest);
    grouped = '${pairs.join(',')},$lastThree';
  }

  final paiseSuffix = hasPaise ? '.${paise.toString().padLeft(2, '0')}' : '';
  final dash = trailingDash ? '/-' : '';
  return '${negative ? '-' : ''}₹$grouped$paiseSuffix$dash';
}

/// A rupee figure out of whatever someone typed, or null if it is not one.
///
/// Tolerant on purpose: the figure gets pasted in from a quotation, so `₹`,
/// grouping commas, spaces and the trailing `/-` all have to come off before
/// it is a number. Null rather than 0 for junk and for an empty field — "never
/// quoted" is not the figure zero, which is why the column is nullable.
double? parseRupees(String? raw) {
  final text = (raw ?? '')
      .replaceAll('₹', '')
      .replaceAll('Rs.', '')
      .replaceAll('Rs', '')
      .replaceAll('INR', '')
      .replaceAll(',', '')
      .replaceAll('/-', '')
      .replaceAll('/', '')
      .replaceAll(' ', '')
      .trim();
  if (text.isEmpty) return null;
  final parsed = double.tryParse(text);
  if (parsed == null || parsed.isNaN || parsed.isInfinite) return null;
  return parsed;
}

/// British Standard Wire Gauge (SWG, BS 3737) sheet thickness table.
///
/// The inch values are the defining SWG dimensions; mm values are the
/// standard published conversions. Values typed by hand are recorded
/// verbatim (what the vendor's paper says) and are never converted between
/// units — the table only fills the field when a gauge is picked.
class SwgGaugeEntry {
  const SwgGaugeEntry(this.gauge, this.mm, this.inch);

  final int gauge;
  final double mm;
  final double inch;
}

const List<SwgGaugeEntry> swgGaugeTable = [
  SwgGaugeEntry(1, 7.62, 0.3),
  SwgGaugeEntry(2, 7.01, 0.276),
  SwgGaugeEntry(3, 6.401, 0.252),
  SwgGaugeEntry(4, 5.893, 0.232),
  SwgGaugeEntry(5, 5.385, 0.212),
  SwgGaugeEntry(6, 4.877, 0.192),
  SwgGaugeEntry(7, 4.47, 0.176),
  SwgGaugeEntry(8, 4.064, 0.16),
  SwgGaugeEntry(9, 3.658, 0.144),
  SwgGaugeEntry(10, 3.251, 0.128),
  SwgGaugeEntry(11, 2.946, 0.116),
  SwgGaugeEntry(12, 2.642, 0.104),
  SwgGaugeEntry(13, 2.337, 0.092),
  SwgGaugeEntry(14, 2.032, 0.08),
  SwgGaugeEntry(15, 1.829, 0.072),
  SwgGaugeEntry(16, 1.626, 0.064),
  SwgGaugeEntry(17, 1.422, 0.056),
  SwgGaugeEntry(18, 1.219, 0.048),
  SwgGaugeEntry(19, 1.016, 0.04),
  SwgGaugeEntry(20, 0.914, 0.036),
  SwgGaugeEntry(21, 0.813, 0.032),
  SwgGaugeEntry(22, 0.711, 0.028),
  SwgGaugeEntry(23, 0.61, 0.024),
  SwgGaugeEntry(24, 0.559, 0.022),
  SwgGaugeEntry(25, 0.508, 0.02),
  SwgGaugeEntry(26, 0.457, 0.018),
  SwgGaugeEntry(27, 0.417, 0.0164),
  SwgGaugeEntry(28, 0.376, 0.0148),
  SwgGaugeEntry(29, 0.345, 0.0136),
  SwgGaugeEntry(30, 0.315, 0.0124),
  SwgGaugeEntry(31, 0.295, 0.0116),
  SwgGaugeEntry(32, 0.274, 0.0108),
  SwgGaugeEntry(33, 0.254, 0.01),
  SwgGaugeEntry(34, 0.234, 0.0092),
  SwgGaugeEntry(35, 0.213, 0.0084),
  SwgGaugeEntry(36, 0.193, 0.0076),
  SwgGaugeEntry(37, 0.173, 0.0068),
  SwgGaugeEntry(38, 0.152, 0.006),
  SwgGaugeEntry(39, 0.132, 0.0052),
  SwgGaugeEntry(40, 0.122, 0.0048),
];

/// The unit a gauge value is expressed in. `suffix` is what gets appended to
/// the number in the stored variation value / challan item name
/// (e.g. `0.711mm`, `0.028in`, `22G`).
enum GaugeUnit {
  mm('mm'),
  inch('in'),
  gauge('G');

  const GaugeUnit(this.suffix);

  final String suffix;
}

SwgGaugeEntry? swgEntryForGauge(int gauge) {
  for (final entry in swgGaugeTable) {
    if (entry.gauge == gauge) return entry;
  }
  return null;
}

/// Matches a typed thickness back to a standard gauge, or null when the
/// value is off-table.
SwgGaugeEntry? swgEntryForValue(double value, GaugeUnit unit) {
  switch (unit) {
    case GaugeUnit.gauge:
      final rounded = value.round();
      if ((value - rounded).abs() > 1e-9) return null;
      return swgEntryForGauge(rounded);
    case GaugeUnit.mm:
      for (final entry in swgGaugeTable) {
        if ((entry.mm - value).abs() < 0.0005) return entry;
      }
      return null;
    case GaugeUnit.inch:
      for (final entry in swgGaugeTable) {
        if ((entry.inch - value).abs() < 0.00005) return entry;
      }
      return null;
  }
}

String formatGaugeNumber(double value) {
  var text = value.toStringAsFixed(4);
  if (text.contains('.')) {
    text = text.replaceAll(RegExp(r'0+$'), '');
    text = text.replaceAll(RegExp(r'\.$'), '');
  }
  return text;
}

String swgFieldText(SwgGaugeEntry entry, GaugeUnit unit) {
  switch (unit) {
    case GaugeUnit.mm:
      return formatGaugeNumber(entry.mm);
    case GaugeUnit.inch:
      return formatGaugeNumber(entry.inch);
    case GaugeUnit.gauge:
      return '${entry.gauge}';
  }
}

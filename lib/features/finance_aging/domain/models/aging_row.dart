class AgingRow {
  const AgingRow({
    required this.id,
    required this.partyName,
    required this.totalOutstanding,
    required this.bucket0To30,
    required this.bucket31To60,
    required this.bucket61To90,
    required this.bucketOver90,
    required this.advance,
  });

  final String id;
  final String partyName;
  final double totalOutstanding;
  final double bucket0To30;
  final double bucket31To60;
  final double bucket61To90;
  final double bucketOver90;
  final double advance;
}

class SummaryMetric {
  const SummaryMetric({
    required this.id,
    required this.label,
    required this.periodLabel,
    required this.value,
  });

  final String id;
  final String label;
  final String periodLabel;
  final int value;
}

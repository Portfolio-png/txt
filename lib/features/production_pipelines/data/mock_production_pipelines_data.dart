import '../domain/models/aging_row.dart';

const String kAllValue = 'All';

class MockProductionPipelinesData {
  static const List<String> partyOptions = [
    kAllValue,
    'Acme Corporation Ltd.',
    'Tech Solutions Pvt. Ltd.',
    'Global Enterprises Inc.',
    'Metro Retailers Group',
    'Sunrise Trading Co.',
  ];

  static const List<String> groupOptions = [
    kAllValue,
    'Any Group',
    'Domestic',
    'International',
  ];

  static const List<String> outstandingOptions = [
    kAllValue,
    'Anytime',
    '0-30',
    '31-60',
    '61-90',
    '>90',
  ];

  static const List<String> statusOptions = [
    kAllValue,
    'Any',
    'Overdue',
    'Current',
  ];

  static const Map<String, List<String>> filterOptions = {
    'Party': partyOptions,
    'Group': groupOptions,
    'Outstanding': outstandingOptions,
    'Status': statusOptions,
  };

  static const List<SummaryMetric> summaryCards = [
    SummaryMetric(
      id: '90_days',
      label: 'Pending Since',
      periodLabel: '90 Days',
      value: 20,
    ),
    SummaryMetric(
      id: '1_month',
      label: 'Pending Since',
      periodLabel: '1 Month',
      value: 5,
    ),
    SummaryMetric(
      id: '3_month',
      label: 'Pending Since',
      periodLabel: '3 Month',
      value: 5,
    ),
    SummaryMetric(
      id: '6_month',
      label: 'Pending Since',
      periodLabel: '6 Month',
      value: 5,
    ),
    SummaryMetric(
      id: '1_year',
      label: 'Pending Since',
      periodLabel: '1 Year',
      value: 5,
    ),
  ];

  static const List<AgingRow> rows = [
    AgingRow(
      id: 'acme',
      partyName: 'Acme Corporation Ltd.',
      totalOutstanding: 485000,
      bucket0To30: 485000,
      bucket31To60: 485000,
      bucket61To90: 485000,
      bucketOver90: 485000,
      advance: 485000,
    ),
    AgingRow(
      id: 'tech',
      partyName: 'Tech Solutions Pvt. Ltd.',
      totalOutstanding: 485000,
      bucket0To30: 485000,
      bucket31To60: 485000,
      bucket61To90: 485000,
      bucketOver90: 485000,
      advance: 485000,
    ),
    AgingRow(
      id: 'global',
      partyName: 'Global Enterprises Inc.',
      totalOutstanding: 485000,
      bucket0To30: 485000,
      bucket31To60: 485000,
      bucket61To90: 485000,
      bucketOver90: 485000,
      advance: 485000,
    ),
    AgingRow(
      id: 'metro',
      partyName: 'Metro Retailers Group',
      totalOutstanding: 485000,
      bucket0To30: 485000,
      bucket31To60: 485000,
      bucket61To90: 485000,
      bucketOver90: 485000,
      advance: 485000,
    ),
    AgingRow(
      id: 'sunrise',
      partyName: 'Sunrise Trading Co.',
      totalOutstanding: 485000,
      bucket0To30: 485000,
      bucket31To60: 485000,
      bucket61To90: 485000,
      bucketOver90: 485000,
      advance: 485000,
    ),
    AgingRow(
      id: 'company_1',
      partyName: 'Company Name',
      totalOutstanding: 485000,
      bucket0To30: 485000,
      bucket31To60: 485000,
      bucket61To90: 485000,
      bucketOver90: 485000,
      advance: 485000,
    ),
    AgingRow(
      id: 'company_2',
      partyName: 'Company Name',
      totalOutstanding: 485000,
      bucket0To30: 485000,
      bucket31To60: 485000,
      bucket61To90: 485000,
      bucketOver90: 485000,
      advance: 485000,
    ),
    AgingRow(
      id: 'company_3',
      partyName: 'Company Name',
      totalOutstanding: 485000,
      bucket0To30: 485000,
      bucket31To60: 485000,
      bucket61To90: 485000,
      bucketOver90: 485000,
      advance: 485000,
    ),
    AgingRow(
      id: 'company_4',
      partyName: 'Company Name',
      totalOutstanding: 485000,
      bucket0To30: 485000,
      bucket31To60: 485000,
      bucket61To90: 485000,
      bucketOver90: 485000,
      advance: 485000,
    ),
  ];
}

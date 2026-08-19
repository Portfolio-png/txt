import '../../features/orders/domain/order_fulfilment.dart';

/// Tooltip text for a delivery checkpoint on the order-insights fulfilment bar.
///
/// Kept as a pure function, like [quantityFieldTooltip], so the wording can be
/// tested without pumping a widget.
String deliveryCheckpointTooltip(
  OrderDelivery delivery, {
  required String unitSymbol,
  required double orderedQty,
}) {
  String qty(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);

  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final date = delivery.date;
  final dateLabel = date == null
      ? ''
      : '${date.day} ${months[date.month - 1]} ${date.year}';

  final unit = unitSymbol.trim();
  final suffix = unit.isEmpty ? '' : ' $unit';

  return <String>[
    delivery.challanNo.isEmpty ? 'Delivery challan' : delivery.challanNo,
    if (dateLabel.isNotEmpty) dateLabel,
    '${qty(delivery.quantity)}$suffix delivered',
    if (orderedQty > 0)
      'Order stood at ${qty(delivery.cumulativeQty)} '
          'of ${qty(orderedQty)}$suffix',
    if (delivery.clientName.trim().isNotEmpty) delivery.clientName.trim(),
    'Click to open the challan',
  ].join('\n');
}

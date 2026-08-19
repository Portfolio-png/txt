import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/features/orders/domain/order_entry.dart';
import 'package:core_erp/features/orders/domain/order_fulfilment.dart';
import 'package:core_erp/features/orders/presentation/widgets/order_insights_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The insights fulfilment bar: production fills, deliveries cut through.
///
/// These render the real widget and read the painted decorations, because the
/// question being asked — "is there green on screen?" — cannot be answered by
/// reading the source.

OrderEntry _order({
  int id = 1,
  int quantity = 1000,
  double delivered = 0,
  double invoiced = 0,
  String unitSymbol = 'Pc',
}) {
  return OrderEntry(
    id: id,
    orderNo: 'SO-$id',
    clientId: 1,
    clientName: 'BluePeak Exports',
    poNumber: 'PO-$id',
    clientCode: 'BPE',
    itemId: 7,
    itemName: 'Anchor Roma Classic Socket 10A',
    variationLeafNodeId: 0,
    variationPathLabel: '',
    variationPathNodeIds: const <int>[],
    quantity: quantity,
    status: OrderStatus.inProgress,
    createdAt: DateTime.now().subtract(const Duration(days: 3)),
    unitSymbol: unitSymbol,
    totalDeliveredQty: delivered,
    totalInvoicedQty: invoiced,
  );
}

OrderFulfilment _fulfilment({
  int orderItemId = 1,
  double ordered = 1000,
  String orderedUnit = 'Pc',
  double produced = 0,
  String producedUnit = 'Pc',
  double delivered = 0,
  int runCount = 1,
  List<OrderDelivery> deliveries = const <OrderDelivery>[],
}) {
  return OrderFulfilment(
    orderItemId: orderItemId,
    orderNo: 'SO-$orderItemId',
    orderedQty: ordered,
    orderedUnit: orderedUnit,
    deliveredQty: delivered,
    producedQty: produced,
    producedUnit: producedUnit,
    scrapQty: 0,
    runCount: runCount,
    runStatus: 'inProgress',
    templateName: 'Line A',
    deliveries: deliveries,
  );
}

Future<void> _pumpInsights(
  WidgetTester tester, {
  required List<OrderEntry> orders,
  required Map<int, OrderFulfilment> fulfilment,
  ValueChanged<int>? onOpenChallan,
}) async {
  await tester.binding.setSurfaceSize(const Size(1400, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: OrderInsightsView(
          orders: orders,
          items: const [],
          fulfilment: fulfilment,
          fulfilmentLoaded: true,
          onOpenChallan: onOpenChallan,
          onBack: () {},
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Every box painted in the production green, with the width it was given.
List<double> _greenFills(WidgetTester tester) {
  final result = <double>[];
  for (final element in find.byType(Container).evaluate()) {
    final container = element.widget as Container;
    final decoration = container.decoration;
    if (decoration is! BoxDecoration) continue;
    if (decoration.color != SoftErpTheme.successText) continue;
    final size = tester.getSize(find.byWidget(container));
    result.add(size.width);
  }
  return result;
}

void main() {
  testWidgets('production fills the bar green in proportion to what was made', (
    tester,
  ) async {
    await _pumpInsights(
      tester,
      orders: [_order()],
      fulfilment: {1: _fulfilment(produced: 620, delivered: 250)},
    );

    final fills = _greenFills(tester);
    expect(fills, isNotEmpty, reason: 'made quantity must paint a green fill');
    expect(fills.single, greaterThan(0));
    expect(find.textContaining('620 of 1000 Pc made'), findsOneWidget);
  });

  testWidgets('nothing made paints no green at all', (tester) async {
    await _pumpInsights(
      tester,
      orders: [_order()],
      fulfilment: {1: _fulfilment(produced: 0)},
    );

    expect(_greenFills(tester), isEmpty);
    expect(find.text('Nothing made yet'), findsOneWidget);
  });

  testWidgets('the delivery cut is independent of the production fill', (
    tester,
  ) async {
    // 620 made, 250 delivered: the cut must sit well behind the fill's end.
    await _pumpInsights(
      tester,
      orders: [_order(delivered: 250)],
      fulfilment: {1: _fulfilment(produced: 620, delivered: 250)},
    );

    final fillWidth = _greenFills(tester).single;

    // The cut is the only box painted in textPrimary.
    Rect? cut;
    for (final element in find.byType(Container).evaluate()) {
      final container = element.widget as Container;
      final decoration = container.decoration;
      if (decoration is! BoxDecoration) continue;
      if (decoration.color != SoftErpTheme.textPrimary) continue;
      cut = tester.getRect(find.byWidget(container));
    }
    expect(cut, isNotNull, reason: 'a delivery must draw a knife cut');

    final barRect = tester.getRect(
      find.byWidgetPredicate((widget) {
        if (widget is! Container) return false;
        final decoration = widget.decoration;
        return decoration is BoxDecoration &&
            decoration.color == SoftErpTheme.cardSurfaceAlt;
      }),
    );

    // 250/1000 of the track, vs a fill at 620/1000 — the cut is nowhere near
    // the end of the fill, which is the whole point of separating them.
    final cutOffset = cut!.center.dx - barRect.left;
    expect(cutOffset, lessThan(fillWidth * 0.7));
    expect(cutOffset, greaterThan(barRect.width * 0.15));

    // And it overhangs the bar top and bottom, like a slice through it.
    expect(cut.height, greaterThan(barRect.height));
  });

  testWidgets('a floor unit that differs from the ordered unit draws no fill', (
    tester,
  ) async {
    await _pumpInsights(
      tester,
      orders: [_order()],
      fulfilment: {1: _fulfilment(produced: 1240, producedUnit: 'kg')},
    );

    expect(
      _greenFills(tester),
      isEmpty,
      reason: 'kg against a Pc order has no honest length',
    );
    expect(find.textContaining('1240 kg made'), findsOneWidget);
  });

  testWidgets('cards wrap instead of scrolling horizontally', (tester) async {
    final orders = [for (var i = 1; i <= 9; i++) _order(id: i)];
    await _pumpInsights(
      tester,
      orders: orders,
      fulfilment: {
        for (var i = 1; i <= 9; i++) i: _fulfilment(orderItemId: i, produced: 0),
      },
    );

    for (final scrollable in find.byType(Scrollable).evaluate()) {
      final widget = scrollable.widget as Scrollable;
      expect(
        widget.axisDirection,
        isNot(AxisDirection.right),
        reason: 'insights must not scroll sideways',
      );
    }
    expect(find.byType(Wrap), findsWidgets);
  });

  testWidgets('each challan gets its own checkpoint, described and clickable', (
    tester,
  ) async {
    final tapped = <int>[];
    await _pumpInsights(
      tester,
      orders: [_order(delivered: 400)],
      fulfilment: {
        1: _fulfilment(
          produced: 620,
          delivered: 400,
          deliveries: const [
            OrderDelivery(
              challanId: 11,
              challanNo: 'DC-00011',
              date: null,
              status: 'issued',
              clientName: 'BluePeak Exports',
              quantity: 250,
              weight: 0,
              cumulativeQty: 250,
            ),
            OrderDelivery(
              challanId: 12,
              challanNo: 'DC-00012',
              date: null,
              status: 'issued',
              clientName: 'BluePeak Exports',
              quantity: 150,
              weight: 0,
              cumulativeQty: 400,
            ),
          ],
        ),
      },
      onOpenChallan: tapped.add,
    );

    // Two challans, two cuts — not one merged cut at the cumulative total.
    final tips = find.byType(Tooltip).evaluate().map((element) {
      return (element.widget as Tooltip).message ?? '';
    }).where((message) => message.contains('delivered')).toList();
    expect(tips.length, 2, reason: 'one checkpoint per challan');
    expect(tips.first, contains('DC-00011'));
    expect(tips.first, contains('250 Pc delivered'));
    expect(tips.first, contains('Order stood at 250 of 1000 Pc'));
    expect(tips.last, contains('DC-00012'));

    // And the later one sits further along the bar than the earlier one.
    final cuts = <double>[];
    for (final element in find.byType(Container).evaluate()) {
      final container = element.widget as Container;
      final decoration = container.decoration;
      if (decoration is! BoxDecoration) continue;
      if (decoration.color != SoftErpTheme.textPrimary) continue;
      cuts.add(tester.getRect(find.byWidget(container)).center.dx);
    }
    expect(cuts.length, 2);
    expect(cuts[1], greaterThan(cuts[0]));

    await tester.tap(find.byTooltip(tips.first));
    await tester.pump();
    expect(tapped, [11], reason: 'tapping a checkpoint opens its challan');
  });

  testWidgets('checkpoints stay inert when no opener is supplied', (
    tester,
  ) async {
    await _pumpInsights(
      tester,
      orders: [_order(delivered: 250)],
      fulfilment: {
        1: _fulfilment(
          produced: 620,
          delivered: 250,
          deliveries: const [
            OrderDelivery(
              challanId: 11,
              challanNo: 'DC-00011',
              date: null,
              status: 'issued',
              clientName: '',
              quantity: 250,
              weight: 0,
              cumulativeQty: 250,
            ),
          ],
        ),
      },
    );

    // Still rendered and still describes itself on hover; tapping it simply
    // does nothing, which must not throw.
    final checkpoint = find.byKey(
      const ValueKey<String>('order-insights-checkpoint-11'),
    );
    expect(checkpoint, findsOneWidget);
    expect(
      find.descendant(of: checkpoint, matching: find.byType(GestureDetector)),
      findsNothing,
      reason: 'no opener means no tap target',
    );
    await tester.tap(checkpoint, warnIfMissed: false);
    await tester.pump();
  });
}

import 'package:core_erp/features/items/domain/developed_for.dart';
import 'package:core_erp/features/items/presentation/widgets/margin_health_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// What was made on a part's development job.
//
// The badge this replaces computed five inputs and not one came from the
// database: the quoted price was a hardcoded demo string whose parse stripped
// the decimal point, the alloy rate was an invented switch, the sheet weight
// an invented gauge lookup, the die cost a count times five thousand. It then
// labelled its lines 'Cell #25 · Quotation' — a citation for a number no cell
// held.
//
// This one takes two nullable figures and nothing else. The load-bearing test
// in this file is the second one.

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('MarginHealthBadge', () {
    testWidgets('both halves present gives the percentage and the breakdown',
        (tester) async {
      await tester.pumpWidget(_host(
        const MarginHealthBadge(quotation: 85000, cost: 61200),
      ));

      // (85000 - 61200) / 85000 = 28.0%
      expect(find.text('+28.0% margin'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('margin_health_indicator')));
      await tester.pumpAndSettle();

      expect(find.text('Development margin'), findsOneWidget);
      // Formatted through rupeeStamp, so Indian grouping and a trailing dash —
      // not a bare toStringAsFixed(0).
      expect(find.text('₹85,000/-'), findsOneWidget);
      expect(find.text('₹61,200/-'), findsOneWidget);
      expect(find.text('Made'), findsOneWidget);
      expect(find.text('₹23,800/-'), findsOneWidget);
    });

    testWidgets('a missing cost reads as NOT COSTED, never as zero cost',
        (tester) async {
      // The whole reason this widget exists. Zero cost is a 100% margin, so a
      // catalogue nobody has costed would show every part as pure profit —
      // the most dangerous possible default for a figure somebody might quote
      // against.
      await tester.pumpWidget(_host(
        const MarginHealthBadge(quotation: 85000, cost: null),
      ));

      expect(find.text('Not costed'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('100'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('margin_health_indicator')));
      await tester.pumpAndSettle();

      // It says what is missing, and names the figure it does have.
      expect(find.textContaining('has not been entered'), findsOneWidget);
      expect(find.textContaining('₹85,000/-'), findsOneWidget);
      expect(
        find.textContaining('not a cost of nothing'),
        findsOneWidget,
        reason: 'the popover must say why there is no number',
      );
    });

    testWidgets('a missing quotation has nothing to measure against',
        (tester) async {
      await tester.pumpWidget(_host(
        const MarginHealthBadge(quotation: null, cost: 61200),
      ));
      expect(find.text('Not costed'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('margin_health_indicator')));
      await tester.pumpAndSettle();
      expect(find.textContaining('No quotation recorded'), findsOneWidget);
    });

    testWidgets('a zero quotation does not divide by nothing', (tester) async {
      await tester.pumpWidget(_host(
        const MarginHealthBadge(quotation: 0, cost: 5000),
      ));
      expect(find.text('Not costed'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('margin_health_indicator')));
      await tester.pumpAndSettle();
      expect(find.textContaining('divide by'), findsOneWidget);
    });

    testWidgets('a job quoted below cost says so rather than hiding it',
        (tester) async {
      await tester.pumpWidget(_host(
        const MarginHealthBadge(quotation: 50000, cost: 61200),
      ));
      // (50000 - 61200) / 50000 = -22.4%
      expect(find.text('-22.4% margin'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('margin_health_indicator')));
      await tester.pumpAndSettle();
      expect(find.text('Lost'), findsOneWidget);
      expect(find.text('₹11,200/-'), findsOneWidget);
    });

    testWidgets('a cost of exactly zero IS a figure and gives 100%',
        (tester) async {
      // "The toolmaker did it for nothing" is a real answer, and is not the
      // same as nobody having entered one. Both halves are present here.
      await tester.pumpWidget(_host(
        const MarginHealthBadge(quotation: 85000, cost: 0),
      ));
      expect(find.text('+100.0% margin'), findsOneWidget);
      expect(find.text('Not costed'), findsNothing);
    });

    testWidgets('the popover opens and closes', (tester) async {
      await tester.pumpWidget(_host(
        const MarginHealthBadge(quotation: 85000, cost: 61200),
      ));
      expect(find.text('Development margin'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('margin_health_indicator')));
      await tester.pumpAndSettle();
      expect(find.text('Development margin'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('margin_health_indicator')));
      await tester.pumpAndSettle();
      expect(find.text('Development margin'), findsNothing);
    });

    testWidgets('it reads both halves straight off a Developed For block',
        (tester) async {
      await tester.pumpWidget(_host(
        MarginHealthBadge.from(const DevelopedFor(
          kind: DevelopedForKind.client,
          quotationAmount: 85000,
          costAmount: 61200,
        )),
      ));
      expect(find.text('+28.0% margin'), findsOneWidget);
    });
  });

  group('DevelopedFor margin', () {
    test('hasMargin needs both halves and a quotation above zero', () {
      const both = DevelopedFor(quotationAmount: 85000, costAmount: 61200);
      expect(both.hasMargin, isTrue);
      expect(both.marginPercent, closeTo(28.0, 0.001));

      // Null, not 0 — "we do not know" and "we broke even" must not render
      // alike, and a nullable return is what forces a caller to choose.
      expect(const DevelopedFor(quotationAmount: 85000).marginPercent, isNull);
      expect(const DevelopedFor(costAmount: 61200).marginPercent, isNull);
      expect(
        const DevelopedFor(quotationAmount: 0, costAmount: 0).marginPercent,
        isNull,
      );

      // A zero cost with a real quotation is knowable.
      const free = DevelopedFor(quotationAmount: 85000, costAmount: 0);
      expect(free.hasMargin, isTrue);
      expect(free.marginPercent, 100.0);
    });

    test('a cost on its own still counts as something recorded', () {
      // isEmpty drives whether the form shows the block at all, so a part that
      // has only been costed must not read as untouched.
      expect(const DevelopedFor(costAmount: 18700).isEmpty, isFalse);
      expect(const DevelopedFor().isEmpty, isTrue);
    });

    test('the cost round-trips through json and copyWith clears explicitly', () {
      const block = DevelopedFor(quotationAmount: 85000, costAmount: 61200);
      final json = block.toJson();
      expect(json['costAmount'], 61200);
      expect(DevelopedFor.fromJson(json).costAmount, 61200);
      expect(DevelopedFor.fromJson(const {}).costAmount, isNull);

      // copyWith cannot express "remove it" with a null, so there is a flag.
      expect(block.copyWith(costAmount: 70000).costAmount, 70000);
      expect(block.copyWith(clearCostAmount: true).costAmount, isNull);
      expect(block.copyWith(clearCostAmount: true).quotationAmount, 85000);
    });
  });
}

import 'package:core_erp/features/units/domain/unit_family.dart';
import 'package:core_erp/features/units/presentation/widgets/quantity_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// A count typed in pieces, dozens or gross, stored as whole pieces, spelt out
// down the ladder beneath.

const _piece = Unit(
  id: 1,
  familyId: 1,
  code: 'pc',
  label: 'Piece',
  symbol: 'Pc',
  factorToBase: 1,
  isBase: true,
  onLadder: true,
  uqc: 'NOS',
);
const _dozen = Unit(
  id: 2,
  familyId: 1,
  code: 'doz',
  label: 'Dozen',
  symbol: 'doz',
  factorToBase: 12,
  isBase: false,
  onLadder: true,
  uqc: 'DOZ',
);
const _gross = Unit(
  id: 3,
  familyId: 1,
  code: 'gro',
  label: 'Gross',
  symbol: 'gro',
  factorToBase: 144,
  isBase: false,
  onLadder: true,
  uqc: 'GRS',
);
final _count = UnitFamily(
  id: 1,
  code: 'count',
  name: 'Count',
  dimension: 'count',
  integralOnly: true,
  units: const [_piece, _dozen, _gross],
);

class _Host extends StatefulWidget {
  const _Host({this.family, this.initial});
  final UnitFamily? family;
  final int? initial;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late int? base = widget.initial;
  int? unitId;

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: QuantityField(
              fieldKey: const ValueKey('qty'),
              unitKey: const ValueKey('qty_unit'),
              family: widget.family,
              baseValue: base,
              unitId: unitId,
              onChanged: (b, u) => setState(() {
                base = b;
                unitId = u;
              }),
            ),
          ),
        ),
      );
}

_HostState _state(WidgetTester tester) => tester.state(find.byType(_Host));

void main() {
  testWidgets('pieces by default, spelt out once it reaches a dozen',
      (tester) async {
    await tester.pumpWidget(_Host(family: _count));
    expect(find.text('Pc'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('qty')), '2900');
    await tester.pump();
    expect(_state(tester).base, 2900);
    expect(find.text('= 20 gro · 1 doz · 8 Pc'), findsOneWidget);
  });

  testWidgets('typed in dozens, stored in pieces; a fraction of a piece refused',
      (tester) async {
    await tester.pumpWidget(_Host(family: _count));
    await tester.tap(find.byKey(const ValueKey('qty_unit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('doz').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('qty')), '1.5');
    await tester.pump();
    expect(_state(tester).base, 18);

    await tester.enterText(find.byKey(const ValueKey('qty')), '1.1');
    await tester.pump();
    expect(_state(tester).base, 18, reason: '13.2 pieces is not a count');
    expect(find.textContaining('whole'), findsWidgets);
  });

  testWidgets('switching the unit shows the same count, never a new one',
      (tester) async {
    await tester.pumpWidget(_Host(family: _count, initial: 288));
    await tester.tap(find.byKey(const ValueKey('qty_unit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('gro').last);
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byKey(const ValueKey('qty')));
    expect(field.controller!.text, '2');
    expect(_state(tester).base, 288);
  });

  testWidgets('with no Count family it still takes whole pieces',
      (tester) async {
    await tester.pumpWidget(const _Host());
    await tester.enterText(find.byKey(const ValueKey('qty')), '40');
    await tester.pump();
    expect(_state(tester).base, 40);
    expect(find.byKey(const ValueKey('qty_unit')), findsNothing);
  });
}

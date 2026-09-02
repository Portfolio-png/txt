import 'package:core_erp/core/services/app_performance.dart';
import 'package:core_erp/core/widgets/soft_primitives.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every row of every list was drawing a `FadeTransition` (a `saveLayer`), a
/// slide, and a shadow with a 12px blur — and owning an `AnimationController`
/// to drive them. With a GPU that is free. Without one, Flutter rasterises in
/// software, where `saveLayer` and blur are the two most expensive operations
/// there are, and a list pays for both on every visible row on every scroll
/// frame.
///
/// Reduced effects keeps the layout, the colours and the hover feedback and
/// drops exactly those. These check it actually drops them, rather than setting
/// a flag nothing reads.

Widget host(Widget child, {bool disableAnimations = false}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

/// Scoped to the row: MaterialApp and Scaffold bring their own
/// FadeTransitions for route changes, and a bare type finder catches those too.
Finder insideRow(Type type) => find.descendant(
  of: find.byType(SoftRowCard),
  matching: find.byType(type),
);

void main() {
  tearDown(() => AppPerformance.reducedEffects.value = false);

  testWidgets('by default a row fades in and carries a shadow', (tester) async {
    AppPerformance.reducedEffects.value = false;
    await tester.pumpWidget(host(SoftRowCard(onTap: () {}, child: const Text('row'))));
    await tester.pump();

    expect(insideRow(FadeTransition), findsOneWidget);
    expect(insideRow(SlideTransition), findsOneWidget);

    final ink = tester.widget<Ink>(find.byType(Ink).first);
    final decoration = ink.decoration as BoxDecoration;
    expect(decoration.boxShadow, isNotNull);

    await tester.pumpAndSettle();
  });

  testWidgets('reduced effects drops the saveLayer and the blur', (
    tester,
  ) async {
    AppPerformance.reducedEffects.value = true;
    await tester.pumpWidget(host(SoftRowCard(onTap: () {}, child: const Text('row'))));
    await tester.pump();

    // The fade is the expensive one: it forces a saveLayer for the whole row.
    expect(insideRow(FadeTransition), findsNothing);
    expect(insideRow(SlideTransition), findsNothing);

    // And the shadow is a blur, per row, re-rasterised on every hover.
    final ink = tester.widget<Ink>(find.byType(Ink).first);
    final decoration = ink.decoration as BoxDecoration;
    expect(decoration.boxShadow, isNull);

    // The row is still there and still readable — this is not a blank mode.
    expect(find.text('row'), findsOneWidget);
    expect(decoration.border, isNotNull, reason: 'the edge is still drawn');
  });

  testWidgets('a machine set to reduce motion gets it without being asked', (
    tester,
  ) async {
    // The OS already said what it wants. Honouring it is free and it is the
    // same request.
    AppPerformance.reducedEffects.value = false;
    await tester.pumpWidget(
      host(SoftRowCard(onTap: () {}, child: const Text('row')), disableAnimations: true),
    );
    await tester.pump();

    expect(insideRow(FadeTransition), findsNothing);
    final ink = tester.widget<Ink>(find.byType(Ink).first);
    expect((ink.decoration as BoxDecoration).boxShadow, isNull);
  });

  testWidgets('a long list settles immediately when reduced', (tester) async {
    // Without this, every row holds a 700ms controller and a stagger timer, so
    // a list is still animating long after it is on screen — and rows recycled
    // by scrolling start the whole thing again.
    AppPerformance.reducedEffects.value = true;
    await tester.pumpWidget(
      host(
        SizedBox(
          height: 400,
          child: ListView.builder(
            itemCount: 200,
            itemBuilder: (context, i) => SoftRowCard(onTap: () {}, child: Text('row $i')),
          ),
        ),
      ),
    );

    // One frame, no pending timers. pumpAndSettle would throw on a leftover
    // stagger timer, so reaching here at all is the assertion.
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    expect(find.text('row 0'), findsOneWidget);
  });
}

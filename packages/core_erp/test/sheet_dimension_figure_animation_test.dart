import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:core_erp/features/production_pipelines/presentation/widgets/sheet_dimension_figure.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The sheet figure moves when the plan changes: strips slide in and out of
/// the plan's end, and the cut lines draw themselves in before the pieces and
/// the offcut wash in. These pin the timing with a fake clock, and pin that a
/// settled drawing is the same drawing the figure made before it moved at all.
void main() {
  const band1 = SheetFigureBand(
    startInches: 1,
    endInches: 11,
    sizeInches: 5,
    count: 2,
    colourIndex: 0,
  );
  const band2 = SheetFigureBand(
    startInches: 11.2,
    endInches: 21.2,
    sizeInches: 10,
    count: 1,
    colourIndex: 1,
  );

  Widget host(Widget child, {bool disableAnimations = false}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(800, 600),
        disableAnimations: disableAnimations,
      ),
      child: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: const ValueKey<String>('figure-boundary'),
            child: SizedBox(width: 420, height: 320, child: child),
          ),
        ),
      ),
    ),
  );

  SheetDimensionFigure figure(
    List<SheetFigureBand> columns, {
    double planEnd = 11,
    double trim = 1,
    bool animate = true,
  }) => SheetDimensionFigure(
    widthInches: 48,
    heightInches: 96,
    thicknessMm: 1,
    trimXInches: trim,
    columnBands: columns,
    columnPlanEndInches: planEnd,
    rowPlanEndInches: 95,
    animate: animate,
  );

  SheetDimensionFigureState stateOf(WidgetTester tester) => tester
      .state<SheetDimensionFigureState>(find.byType(SheetDimensionFigure));

  testWidgets('an added strip grows out of the plan end and settles in place', (
    tester,
  ) async {
    await tester.pumpWidget(host(figure(const <SheetFigureBand>[band1])));
    await tester.pumpAndSettle();
    expect(stateOf(tester).debugColumnBands, const <SheetFigureBand>[band1]);

    await tester.pumpWidget(
      host(figure(const <SheetFigureBand>[band1, band2], planEnd: 21.2)),
    );
    await tester.pump();
    await tester.pump(
      Duration(
        milliseconds: SheetDimensionFigure.slideDuration.inMilliseconds ~/ 2,
      ),
    );

    final mid = stateOf(tester).debugColumnBands;
    expect(mid, hasLength(2));
    // The existing strip did not move.
    expect(mid.first, band1);
    // The new one set out collapsed at the old plan end (11) and is part way
    // to its own place — further than nothing, short of where it is going.
    final flying = mid[1];
    expect(flying.startInches, greaterThan(11));
    expect(flying.startInches, lessThan(band2.startInches));
    final width = flying.endInches - flying.startInches;
    expect(width, greaterThan(0));
    expect(width, lessThan(band2.endInches - band2.startInches));

    await tester.pumpAndSettle();
    expect(stateOf(tester).debugColumnBands, const <SheetFigureBand>[
      band1,
      band2,
    ]);
  });

  testWidgets('a removed strip shrinks back into the plan end, then is gone', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(figure(const <SheetFigureBand>[band1, band2], planEnd: 21.2)),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(host(figure(const <SheetFigureBand>[band1])));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final mid = stateOf(tester).debugColumnBands;
    expect(mid, hasLength(2));
    final leaving = mid[1];
    expect(leaving.endInches - leaving.startInches, greaterThan(0));
    expect(
      leaving.endInches - leaving.startInches,
      lessThan(band2.endInches - band2.startInches),
    );

    await tester.pumpAndSettle();
    // No collapsed leftover is kept to draw a stray edge line.
    expect(stateOf(tester).debugColumnBands, const <SheetFigureBand>[band1]);
  });

  testWidgets('the cut plan draws in over its run and restarts on a change', (
    tester,
  ) async {
    await tester.pumpWidget(host(figure(const <SheetFigureBand>[band1])));
    await tester.pump();
    // It draws itself in when it first appears.
    expect(stateOf(tester).debugCutProgress, lessThan(1));

    await tester.pump(const Duration(milliseconds: 450));
    final half = stateOf(tester).debugCutProgress;
    expect(half, greaterThan(0.3));
    expect(half, lessThan(0.7));

    await tester.pump(SheetDimensionFigure.cutDuration);
    expect(stateOf(tester).debugCutProgress, 1);

    // A rebuild with the same plan does not restart it.
    await tester.pumpWidget(host(figure(const <SheetFigureBand>[band1])));
    await tester.pump(const Duration(milliseconds: 16));
    expect(stateOf(tester).debugCutProgress, 1);

    // A different trim is a different plan.
    await tester.pumpWidget(
      host(figure(const <SheetFigureBand>[band1], trim: 0.5)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(stateOf(tester).debugCutProgress, lessThan(0.3));

    await tester.pumpAndSettle();
    expect(stateOf(tester).debugCutProgress, 1);
  });

  testWidgets('with animate off everything is already finished', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(figure(const <SheetFigureBand>[band1], animate: false)),
    );
    expect(stateOf(tester).debugCutProgress, 1);

    await tester.pumpWidget(
      host(
        figure(
          const <SheetFigureBand>[band1, band2],
          planEnd: 21.2,
          animate: false,
        ),
      ),
    );
    expect(stateOf(tester).debugCutProgress, 1);
    expect(stateOf(tester).debugColumnBands, const <SheetFigureBand>[
      band1,
      band2,
    ]);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('reduced motion from the platform does the same', (tester) async {
    await tester.pumpWidget(
      host(figure(const <SheetFigureBand>[band1]), disableAnimations: true),
    );
    expect(stateOf(tester).debugCutProgress, 1);

    await tester.pumpWidget(
      host(
        figure(const <SheetFigureBand>[band1, band2], planEnd: 21.2),
        disableAnimations: true,
      ),
    );
    expect(stateOf(tester).debugCutProgress, 1);
    expect(stateOf(tester).debugColumnBands, const <SheetFigureBand>[
      band1,
      band2,
    ]);
  });

  testWidgets('a settled drawing is the drawing that never moved', (
    tester,
  ) async {
    Future<Uint8List> capture() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey<String>('figure-boundary')),
      );
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        return data!.buffer.asUint8List();
      });
      return bytes!;
    }

    const plan = <SheetFigureBand>[band1, band2];
    await tester.pumpWidget(host(figure(plan, planEnd: 21.2, animate: false)));
    final still = await capture();

    await tester.pumpWidget(host(figure(const <SheetFigureBand>[band1])));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(figure(plan, planEnd: 21.2)));
    await tester.pumpAndSettle();
    final settled = await capture();

    expect(settled, still);

    // And the comparison can tell: mid-run the same plan is drawn differently.
    await tester.pumpWidget(host(figure(const <SheetFigureBand>[band1])));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(figure(plan, planEnd: 21.2)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final midway = await capture();
    expect(midway, isNot(still));
    await tester.pumpAndSettle();
  });
}

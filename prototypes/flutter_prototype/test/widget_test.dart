import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_prototype/main.dart';

void main() {
  testWidgets('Prototype Shell renders without errors', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const PaperPrototypeApp());
    await tester.pumpAndSettle();

    expect(find.text('Paper MES'), findsOneWidget);
    expect(find.text('2D Pipeline Designer'), findsOneWidget);
    expect(find.text('CAD Sheet Planner'), findsOneWidget);
    expect(find.text('Flow Transformation'), findsOneWidget);
  });
}

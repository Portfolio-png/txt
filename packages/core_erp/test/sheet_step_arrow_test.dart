import 'package:core_erp/sheet/sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// ← is Shift+Tab on the sheet: Tab goes forward a field, ← comes back one.
// In a text box only from the start of its text — elsewhere ← still moves the
// caret through what was typed. A dropdown, a tick or a button has no caret,
// so there ← always goes back.

void main() {
  final first = TextEditingController(text: 'Group');
  final second = TextEditingController(text: 'Patti');
  final firstFocus = FocusNode(debugLabel: 'first');
  final secondFocus = FocusNode(debugLabel: 'second');
  final boxFocus = FocusNode(debugLabel: 'box');

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SheetStep(
          flow: null,
          id: 'line',
          actions: SheetStepActions(
            title: () => 'Save part?',
            isDirty: () => false,
            save: () async => true,
            discard: () async {},
          ),
          child: Column(
            children: [
              TextField(controller: first, focusNode: firstFocus),
              TextField(controller: second, focusNode: secondFocus),
              // A dropdown's box: focusable, no caret.
              Focus(
                focusNode: boxFocus,
                child: const SizedBox(width: 100, height: 40),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  testWidgets('← at the start of a text box goes back a field', (tester) async {
    await pump(tester);
    secondFocus.requestFocus();
    await tester.pump();
    second.selection = const TextSelection.collapsed(offset: 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(firstFocus.hasPrimaryFocus, isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('← inside typed text moves the caret, not the field', (tester) async {
    await pump(tester);
    secondFocus.requestFocus();
    await tester.pump();
    second.selection = const TextSelection.collapsed(offset: 5);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(secondFocus.hasPrimaryFocus, isTrue);
    expect(second.selection.baseOffset, 4);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('← on a box with no caret always goes back', (tester) async {
    await pump(tester);
    boxFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(secondFocus.hasPrimaryFocus, isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}

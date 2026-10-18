import 'dart:convert';

import 'package:core_erp/core/devtools/mark_tool.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// The marking tool. What matters is that a right-click lands on the thing that
// was actually under the pointer and reports something a human — or a later
// pass over the file — can act on: the screen, the widget's key, its text.

/// Collects marks instead of writing them, so a test can read what the tool
/// would have put in the file.
class _RecordingSink extends MarkSink {
  _RecordingSink() : super(path: '/dev/null');

  final List<Mark> written = [];

  @override
  Future<void> write(Mark mark) async => written.add(mark);

  @override
  void clear() => written.clear();
}

/// A sink with nowhere to put anything: no server, and a path that cannot be
/// written. What a sandboxed app actually had, and what used to go unnoticed.
class _BrokenSink extends MarkSink {
  _BrokenSink() : super(path: '/proc/definitely/not/writable/marks.jsonl');
}

/// The tool where main.dart actually puts it: wrapped around
/// MaterialApp.builder's child, which is ABOVE the Navigator — so there is no
/// Overlay ancestor and no MaterialLocalizations below it to lean on. Pumping
/// it inside MaterialApp(home:) instead hid a crash that only the real app saw.
Widget _app({required MarkSink sink, GlobalKey<MarkToolState>? toolKey}) {
  return MaterialApp(
    builder: (context, child) =>
        MarkTool(key: toolKey, sink: sink, child: child ?? const SizedBox()),
    home: const _UnitFieldScreen(),
  );
}

Future<void> _arm(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.f2);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.f2);
  await tester.pumpAndSettle();
}

Future<void> _rightClickAt(WidgetTester tester, Offset position) async {
  final gesture = await tester.startGesture(
    position,
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

class _UnitFieldScreen extends StatelessWidget {
  const _UnitFieldScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Item Details'),
            const SizedBox(height: 20),
            SizedBox(
              width: 300,
              child: TextField(
                key: const ValueKey('item_unit_field'),
                decoration: const InputDecoration(labelText: 'Unit'),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 300,
              child: FilledButton(
                key: const ValueKey('save_item'),
                onPressed: () {},
                child: const Text('Save Item'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets('a right-click while armed marks what is under it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final sink = _RecordingSink();
    final key = GlobalKey<MarkToolState>();
    await tester.pumpWidget(_app(sink: sink, toolKey: key));
    await tester.pumpAndSettle();

    // Disarmed, a right-click is just a right-click.
    expect(key.currentState!.armed, isFalse);
    await _rightClickAt(
      tester,
      tester.getCenter(find.byKey(const ValueKey('item_unit_field'))),
    );
    expect(sink.written, isEmpty);

    await _arm(tester);
    expect(key.currentState!.armed, isTrue);
    expect(find.text('Marking'), findsOneWidget);
    expect(find.text('unit'), findsOneWidget, reason: 'it starts on unit');

    await _rightClickAt(
      tester,
      tester.getCenter(find.byKey(const ValueKey('item_unit_field'))),
    );

    expect(sink.written.length, 1);
    final mark = sink.written.single;
    expect(mark.n, 1);
    expect(mark.label, 'unit');
    expect(
      mark.keys,
      contains('item_unit_field'),
      reason: "the widget's key is the part that survives a redesign",
    );
    expect(mark.screen, '_UnitFieldScreen');
    expect(mark.widgets, contains('TextField'));
    expect(mark.summary, contains('#1 unit'));
    expect(mark.toJson()['keys'], contains('item_unit_field'));

    // And the badge is on screen, so it can be seen to have worked.
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('a second mark lands on a different widget, and counts up', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final sink = _RecordingSink();
    await tester.pumpWidget(_app(sink: sink));
    await tester.pumpAndSettle();
    await _arm(tester);

    await _rightClickAt(
      tester,
      tester.getCenter(find.byKey(const ValueKey('item_unit_field'))),
    );
    await _rightClickAt(
      tester,
      tester.getCenter(find.byKey(const ValueKey('save_item'))),
    );

    expect(sink.written.map((mark) => mark.n), [1, 2]);
    expect(sink.written[1].keys, contains('save_item'));
    expect(
      sink.written[1].text,
      'Save Item',
      reason: 'the text under the pointer is what a person would call it',
    );
    expect(
      sink.written[0].keys,
      isNot(contains('save_item')),
      reason: 'each mark describes what was actually under it',
    );
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('the label can be changed, and later marks carry it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final sink = _RecordingSink();
    await tester.pumpWidget(_app(sink: sink));
    await tester.pumpAndSettle();
    await _arm(tester);

    await tester.tap(find.byKey(const ValueKey('mark_label_die')));
    await tester.pumpAndSettle();

    await _rightClickAt(
      tester,
      tester.getCenter(find.byKey(const ValueKey('save_item'))),
    );
    expect(sink.written.single.label, 'die');
  });

  testWidgets('the bar survives where it actually lives, and narrow', (
    tester,
  ) async {
    // Regression for both of the first frame's exceptions in the real app:
    // "No Overlay widget found", because the bar sits above the Navigator and
    // used a PopupMenuButton; and a RenderFlex overflow behind it.
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 800);
    await tester.pumpWidget(_app(sink: _RecordingSink()));
    await tester.pumpAndSettle();
    await _arm(tester);
    expect(
      tester.takeException(),
      isNull,
      reason: 'the bar must build with no Overlay above it',
    );
    expect(find.text('Marking'), findsOneWidget);

    // Narrow enough that the chips and the path cannot both fit.
    for (final width in [900.0, 620.0, 460.0]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'the bar gives way rather than overflowing at ${width}px',
      );
      expect(find.text('Marking'), findsOneWidget);
    }
  });

  testWidgets('a mark that reaches nowhere is counted and said out loud', (
    tester,
  ) async {
    // The failure that cost eight marks: the badge counted up, the bar looked
    // healthy, and nothing was written anywhere. A sink that cannot store a
    // mark has to say so on screen, not only in a line of terminal nobody was
    // watching.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final sink = _BrokenSink();
    await tester.pumpWidget(_app(sink: sink));
    await tester.pumpAndSettle();
    await _arm(tester);
    await _rightClickAt(
      tester,
      tester.getCenter(find.byKey(const ValueKey('item_unit_field'))),
    );
    await tester.pumpAndSettle();

    expect(sink.lost, 1, reason: 'the sink knows it dropped one');
    expect(find.textContaining('1 LOST'), findsOneWidget);
  });

  test('a mark encodes to one line that can be read back', () {
    final mark = Mark(
      n: 3,
      session: '1003-0930',
      label: 'unit',
      screen: 'ItemsScreen',
      keys: const ['item_unit_field'],
      text: 'Unit',
      widgets: const ['TextField', 'SearchableSelect'],
      position: const Offset(120.4, 310.6),
      at: DateTime.utc(2026, 10, 3, 9, 30),
    );
    final line = jsonEncode(mark.toJson());
    expect(line.contains('\n'), isFalse, reason: 'one mark, one line');

    final back = jsonDecode(line) as Map<String, dynamic>;
    expect(back['n'], 3);
    expect(back['session'], '1003-0930', reason: 'tells one pass from another');
    expect(back['label'], 'unit');
    expect(back['screen'], 'ItemsScreen');
    expect(back['keys'], ['item_unit_field']);
    expect(back['text'], 'Unit');
    expect(back['at'], [120, 311], reason: 'rounded; a pixel is not the point');
    expect(back['ts'], '2026-10-03T09:30:00.000Z');
    expect(mark.summary, '#3 unit · ItemsScreen · "Unit"');
  });
}

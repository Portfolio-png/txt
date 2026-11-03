import 'package:core_erp/core/utils/dropdown_intents.dart';
import 'package:core_erp/core/widgets/searchable_select.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// The dropdown from the keyboard: type at the closed field to search, ↑ ↓ to
// choose, Enter to pick, Esc to close — and focus back on the field after,
// so Tab goes on from there.

class _Harness extends StatefulWidget {
  const _Harness({required this.created});

  final List<String> created;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  String? value;

  @override
  Widget build(BuildContext context) {
    final options = [
      for (final name in const ['Alpha', 'Beta', 'Gamma', ...<String>[]])
        SearchableSelectOption<String>(value: name, label: name),
      for (final name in widget.created)
        SearchableSelectOption<String>(value: name, label: name),
    ];
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            const TextField(key: ValueKey('before'), autofocus: true),
            SizedBox(
              width: 300,
              child: SearchableSelectField<String>(
                key: const ValueKey('field'),
                value: value,
                options: options,
                decoration: const InputDecoration(),
                canCreateOption: (query, _) => query.trim().isNotEmpty,
                createOptionLabelBuilder: (query) => 'Add "$query"',
                onCreateOption: (query) async {
                  widget.created.add(query);
                  return SearchableSelectOption<String>(value: query, label: query);
                },
                onChanged: (next) => setState(() => value = next),
              ),
            ),
            const TextField(key: ValueKey('after')),
          ],
        ),
      ),
    );
  }
}

Future<List<String>> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final created = <String>[];
  await tester.pumpWidget(_Harness(created: created));
  await tester.pump();
  // Tab from the field before it, as a person would.
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.pump();
  return created;
}

String? _picked(WidgetTester tester) =>
    tester.state<_HarnessState>(find.byType(_Harness)).value;

bool _fieldHasFocus(WidgetTester tester) {
  final field = tester.element(find.byKey(const ValueKey('field')));
  final primary = FocusManager.instance.primaryFocus;
  return primary?.context != null &&
      (primary!.context == field ||
          primary.context!.findAncestorWidgetOfExactType<SearchableSelectField<String>>() != null);
}

/// The desktop app: the search box takes focus as the list opens (it does
/// not on a phone, where the keyboard would cover the list).
final _desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

void main() {
  testWidgets('a letter typed at the closed field opens it with that letter',
      (tester) async {
    await _pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB, character: 'b');
    await tester.pumpAndSettle();

    final search = tester.widget<TextField>(find.byType(TextField).last);
    expect(search.controller!.text, 'b');
    expect(find.text('Alpha'), findsNothing, reason: 'filtered by the letter');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_picked(tester), 'Beta');
    expect(_fieldHasFocus(tester), isTrue, reason: 'Tab goes on from the field');
  }, variant: _desktop);

  testWidgets('↓ ↓ Enter picks the third row', (tester) async {
    await _pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_picked(tester), 'Gamma');
  }, variant: _desktop);

  testWidgets('Enter on an existing name picks it, not a second one',
      (tester) async {
    final created = await _pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'beta');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_picked(tester), 'Beta');
    expect(created, isEmpty);
  }, variant: _desktop);

  testWidgets('Enter on a name nobody has adds it', (tester) async {
    final created = await _pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Delta');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(created, ['Delta']);
    expect(_picked(tester), 'Delta');
  }, variant: _desktop);

  testWidgets('Esc closes it and the field keeps focus', (tester) async {
    await _pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsNothing);
    expect(_picked(tester), isNull);
    expect(_fieldHasFocus(tester), isTrue);
  }, variant: _desktop);

  testWidgets('arriving by a keyboard flow opens it; a bare Enter keeps the value',
      (tester) async {
    await _pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB, character: 'b');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_picked(tester), 'Beta');

    // What the item sheet's Tab sends to the field it lands on.
    Actions.invoke(FocusManager.instance.primaryFocus!.context!, const OpenDropdownIntent());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('searchable_select_search')), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget, reason: 'the whole list, nothing typed');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_picked(tester), 'Beta', reason: 'not the first row, Alpha');
    expect(find.byKey(const ValueKey<String>('searchable_select_search')), findsNothing);
    // Focus back on the field does not open it again.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey<String>('searchable_select_search')), findsNothing);
  }, variant: _desktop);

  testWidgets('Tab in the open list keeps the value and goes on', (tester) async {
    await _pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('searchable_select_search')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('searchable_select_search')), findsNothing);
    expect(_picked(tester), isNull, reason: 'nothing was picked');
    final focused = FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<TextField>();
    expect(focused?.key, const ValueKey('after'), reason: 'on to the next field');
  }, variant: _desktop);
}

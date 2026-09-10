import 'package:core_erp/features/groups/domain/group_cover.dart';
import 'package:core_erp/features/groups/presentation/widgets/group_collage_card.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  GroupCoverItem cover(String name) => GroupCoverItem(
        itemId: name.hashCode.abs(),
        name: name,
        photoUrl: '',
        orderCount: 0,
      );

  testWidgets('hover -> open menu -> tap Edit Group', (tester) async {
    var edits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 260,
              height: 238,
              child: GroupCollageCard(
                name: 'Sockets',
                covers: <GroupCoverItem>[cover('Anchor 10A')],
                basis: GroupCoverBasis.recent,
                itemCount: 1,
                onEdit: () => edits++,
              ),
            ),
          ),
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await tester.pump();
    await mouse.moveTo(tester.getCenter(find.text('Sockets')));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.more_vert), findsOneWidget,
        reason: 'menu button should appear on hover');

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    // Is the button still mounted after the route pushed?
    // ignore: avoid_print
    print('more_vert still present after opening menu: '
        '${find.byIcon(Icons.more_vert).evaluate().length}');
    // ignore: avoid_print
    print('PopupMenuButton still present: '
        '${find.byType(PopupMenuButton<String>).evaluate().length}');

    expect(find.text('Edit Group'), findsOneWidget,
        reason: 'menu item should be on screen');
    await tester.tap(find.text('Edit Group'));
    await tester.pumpAndSettle();

    // ignore: avoid_print
    print('EDIT CALLBACK COUNT = $edits');
    expect(edits, 1, reason: 'onEdit must fire');
  });
}

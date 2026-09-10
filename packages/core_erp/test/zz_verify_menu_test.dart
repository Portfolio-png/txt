import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core_erp/features/groups/domain/group_cover.dart';
import 'package:core_erp/features/groups/presentation/widgets/group_collage_card.dart';

void main() {
  testWidgets('hover -> menu -> Edit Group fires onEdit', (tester) async {
    int edits = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 220,
            height: 220,
            child: GroupCollageCard(
              name: 'Electrical Fittings',
              covers: const <GroupCoverItem>[
                GroupCoverItem(itemId: 1, name: 'Socket'),
              ],
              basis: GroupCoverBasis.recent,
              onEdit: () => edits++,
            ),
          ),
        ),
      ),
    ));

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.byType(GroupCollageCard)));
    await tester.pumpAndSettle();

    final menuIcon = find.byIcon(Icons.more_vert);
    print('MENU ICON FOUND: ${menuIcon.evaluate().length}');
    expect(menuIcon, findsOneWidget);

    await tester.tap(menuIcon);
    await tester.pumpAndSettle();

    final editItem = find.text('Edit Group');
    print('EDIT ITEM FOUND: ${editItem.evaluate().length}');
    print('MENU BUTTON STILL MOUNTED AFTER OPEN: '
        '${find.byType(PopupMenuButton<String>).evaluate().length}');
    expect(editItem, findsOneWidget);

    await tester.tap(editItem);
    await tester.pumpAndSettle();

    print('>>> onEdit CALL COUNT = $edits');
    expect(edits, 1, reason: 'onEdit should have fired exactly once');
  });
}

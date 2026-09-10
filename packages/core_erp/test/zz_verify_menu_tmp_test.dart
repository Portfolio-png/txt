import 'package:core_erp/features/groups/domain/group_cover.dart';
import 'package:core_erp/features/groups/presentation/widgets/group_collage_card.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('hover -> open menu -> pick Edit Group', (tester) async {
    var edits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 260,
              height: 238,
              child: GroupCollageCard(
                name: 'Electrical Fittings',
                covers: const <GroupCoverItem>[],
                basis: GroupCoverBasis.empty,
                onEdit: () => edits++,
              ),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(GroupCollageCard)));
    await tester.pumpAndSettle();

    // The kebab appears on hover.
    expect(find.byIcon(Icons.more_vert), findsOneWidget, reason: 'kebab shown');

    // Click it the way a mouse would: move onto it, then tap.
    final kebab = tester.getCenter(find.byIcon(Icons.more_vert));
    await gesture.moveTo(kebab);
    await tester.pump();
    await gesture.down(kebab);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Edit Group'), findsOneWidget, reason: 'menu is open');
    print('KEBAB STILL MOUNTED AFTER OPEN: '
        '${find.byIcon(Icons.more_vert).evaluate().length}');

    final entry = tester.getCenter(find.text('Edit Group'));
    await gesture.moveTo(entry);
    await tester.pump();
    await gesture.down(entry);
    await gesture.up();
    await tester.pumpAndSettle();

    print('EDIT CALLBACK FIRE COUNT: $edits');
    expect(edits, 1, reason: 'onEdit should have fired exactly once');
  });
}

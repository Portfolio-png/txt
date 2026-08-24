import 'package:core_erp/features/groups/domain/group_cover.dart';
import 'package:core_erp/features/groups/presentation/widgets/group_collage_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A group has no photo of its own, so its card is built from the items inside
/// it. Two things have to hold: every item count gets a layout that looks
/// chosen, and an item with no photo is a tile rather than a hole — because a
/// fresh install has no item photos at all.
void main() {
  GroupCoverItem cover(String name, {int orders = 0, bool photo = false}) {
    return GroupCoverItem(
      itemId: name.hashCode.abs(),
      name: name,
      photoUrl: photo ? 'http://localhost:8080/public/seed/item-x.png' : '',
      orderCount: orders,
    );
  }

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: SizedBox(width: 260, height: 238, child: child)),
        ),
      ),
    );
  }

  group('the mosaic', () {
    for (final count in <int>[1, 2, 3, 4]) {
      testWidgets('lays out $count item(s) without overflowing', (
        tester,
      ) async {
        await pump(
          tester,
          GroupCoverMosaic(
            covers: List<GroupCoverItem>.generate(
              count,
              (index) => cover('Item ${index + 1}'),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        // Every item given is drawn — none silently dropped by the layout.
        // "Item 3" initials to "I3", so each tile is findable by its letters.
        for (var i = 1; i <= count; i++) {
          expect(find.text('I$i'), findsOneWidget, reason: 'tile $i is drawn');
        }
      });
    }

    testWidgets('shows at most four, however many it is given', (tester) async {
      await pump(
        tester,
        GroupCoverMosaic(
          covers: List<GroupCoverItem>.generate(
            9,
            (index) => cover('Item ${index + 1}'),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      // The fifth onward are not drawn: five tiles have no layout that reads.
      expect(find.byType(Image), findsNothing);
      expect(find.text('I5'), findsNothing);
    });

    testWidgets('an empty group says so rather than showing a blank panel', (
      tester,
    ) async {
      await pump(tester, const GroupCoverMosaic(covers: <GroupCoverItem>[]));
      expect(find.text('No items yet'), findsOneWidget);
    });

    testWidgets('an item with no photo becomes letters, not a hole', (
      tester,
    ) async {
      await pump(
        tester,
        GroupCoverMosaic(covers: <GroupCoverItem>[cover('Philips LED Bulb')]),
      );
      // Two initials from the first two words.
      expect(find.text('PL'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });
  });

  group('the card', () {
    testWidgets('says whether the mosaic is popularity or just recency', (
      tester,
    ) async {
      await pump(
        tester,
        GroupCollageCard(
          name: 'Electrical Fittings',
          covers: <GroupCoverItem>[cover('Anchor Socket', orders: 3)],
          basis: GroupCoverBasis.ordered,
          itemCount: 6,
        ),
      );
      expect(find.text('Electrical Fittings'), findsOneWidget);
      expect(find.text('Most ordered'), findsOneWidget);
      expect(find.textContaining('6 items'), findsOneWidget);
    });

    testWidgets('a group nothing is ordered from says "recently added"', (
      tester,
    ) async {
      await pump(
        tester,
        GroupCollageCard(
          name: 'Raw Materials',
          covers: <GroupCoverItem>[cover('MS Sheet')],
          basis: GroupCoverBasis.recent,
          itemCount: 1,
        ),
      );
      // The distinction matters: showing new items while implying they are the
      // most used would be a quiet lie.
      expect(find.text('Recently added'), findsOneWidget);
      expect(find.text('Most ordered'), findsNothing);
      expect(find.textContaining('1 item'), findsOneWidget);
    });

    testWidgets('an empty group claims no basis at all', (tester) async {
      await pump(
        tester,
        const GroupCollageCard(
          name: 'Scrap',
          covers: <GroupCoverItem>[],
          basis: GroupCoverBasis.empty,
        ),
      );
      expect(find.text('Most ordered'), findsNothing);
      expect(find.text('Recently added'), findsNothing);
      expect(find.textContaining('No items'), findsWidgets);
    });

    testWidgets('the count and the basis share a row without crowding', (
      tester,
    ) async {
      await pump(
        tester,
        GroupCollageCard(
          name: 'Sockets',
          covers: <GroupCoverItem>[cover('Anchor 10A')],
          basis: GroupCoverBasis.recent,
          itemCount: 3,
          unitLabel: 'Nos',
          parentName: 'Electrical',
        ),
      );
      final count = find.text('3 items  ·  Nos');
      final basis = find.text('Recently added');
      expect(count, findsOneWidget);
      expect(basis, findsOneWidget);

      // Both really on screen and side by side, not stacked or clipped away.
      final countRect = tester.getRect(count);
      final basisRect = tester.getRect(basis);
      expect(countRect.width, greaterThan(0));
      expect(basisRect.width, greaterThan(0));
      expect(countRect.overlaps(basisRect), isFalse);

      // The parent group moved to the tooltip rather than being truncated.
      expect(find.text('3 items  ·  Nos  ·  in Electrical'), findsNothing);
    });

    testWidgets('nothing is painted over the mosaic at rest', (tester) async {
      await pump(
        tester,
        GroupCollageCard(
          name: 'Sockets',
          covers: <GroupCoverItem>[cover('Anchor Socket', orders: 5)],
          basis: GroupCoverBasis.ordered,
          itemCount: 4,
        ),
      );
      // The first design floated this label over the artwork, where it covered
      // the very item it was labelling.
      final mosaic = tester.getRect(find.byType(GroupCoverMosaic));
      final basis = tester.getRect(find.text('Most ordered'));
      expect(mosaic.overlaps(basis), isFalse);
    });

    testWidgets('tapping the card opens the group', (tester) async {
      var opened = false;
      await pump(
        tester,
        GroupCollageCard(
          name: 'Sockets',
          covers: <GroupCoverItem>[cover('Anchor 10A')],
          basis: GroupCoverBasis.recent,
          itemCount: 1,
          onTap: () => opened = true,
        ),
      );
      await tester.tap(find.text('Sockets'));
      await tester.pumpAndSettle();
      expect(opened, isTrue);
    });
  });

  group('cover items', () {
    test('initials come from the first two words', () {
      expect(cover('Philips LED Bulb').initials, 'PL');
      expect(cover('Socket').initials, 'S');
      expect(cover('MS-Sheet/Cut').initials, 'MS');
      expect(cover('').initials, '?');
    });

    test('an item knows whether it earned its place', () {
      expect(cover('A', orders: 2).isOrdered, isTrue);
      expect(cover('A').isOrdered, isFalse);
    });

    test('the basis parses, and anything unknown is empty', () {
      expect(GroupCoverBasis.parse('ordered'), GroupCoverBasis.ordered);
      expect(GroupCoverBasis.parse('recent'), GroupCoverBasis.recent);
      expect(GroupCoverBasis.parse(null), GroupCoverBasis.empty);
      expect(GroupCoverBasis.parse('nonsense'), GroupCoverBasis.empty);
    });
  });
}

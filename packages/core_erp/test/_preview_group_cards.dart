import 'dart:io';
import 'dart:ui' as ui;

import 'package:core_erp/features/groups/domain/group_cover.dart';
import 'package:core_erp/features/groups/presentation/widgets/group_collage_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Renders the card grid to a PNG so it can be looked at rather than inferred
// from assertions. Not a test of behaviour — a way to see the thing.
void main() {
  setUpAll(() async {
    // A real font, so the preview shows words instead of glyph boxes.
    final loader = FontLoader('Preview')
      ..addFont(
        File(
          '/System/Library/Fonts/Supplemental/Arial.ttf',
        ).readAsBytes().then((bytes) => bytes.buffer.asByteData()),
      );
    await loader.load();
  });

  testWidgets('render group cards', (tester) async {
    // physicalSize is in PHYSICAL pixels: logical size x devicePixelRatio.
    tester.view.physicalSize = const Size(2100, 1260); // 700 x 420 logical
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    GroupCoverItem c(String name, int orders) => GroupCoverItem(
      itemId: name.hashCode.abs(),
      name: name,
      orderCount: orders,
    );

    final cards = <Widget>[
      GroupCollageCard(
        name: 'Electrical Fittings',
        basis: GroupCoverBasis.ordered,
        itemCount: 12,
        unitLabel: 'Nos',
        parentName: 'Primary Group',
        covers: [
          c('Anchor Roma Socket 10A', 3),
          c('Philips LED Bulb', 2),
          c('Crompton Ceiling Fan', 1),
          c('Legrand Switch Plate', 0),
        ],
      ),
      GroupCollageCard(
        name: 'Raw Materials',
        basis: GroupCoverBasis.recent,
        itemCount: 3,
        unitLabel: 'Kg',
        covers: [
          c('MS Sheet 1.6mm', 0),
          c('Aluminium Coil', 0),
          c('Brass Rod', 0),
        ],
      ),
      GroupCollageCard(
        name: 'Finished Goods',
        basis: GroupCoverBasis.ordered,
        itemCount: 2,
        parentName: 'Manufacturing',
        covers: [c('Bracket 60x40', 8), c('Enclosure Lid', 4)],
      ),
      const GroupCollageCard(
        name: 'Scrap',
        basis: GroupCoverBasis.empty,
        itemCount: 0,
        covers: <GroupCoverItem>[],
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Preview'),
        home: Scaffold(
          backgroundColor: const Color(0xFFF7F8FC),
          body: RepaintBoundary(
            key: const ValueKey('shot'),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: GridView.count(
                crossAxisCount: 2,
                childAspectRatio: 260 / 238,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                children: cards,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: 'no overflow in any card');

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('shot')),
    );
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File(
      Platform.environment['SHOT'] ?? 'group_cards.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

import 'dart:io';
import 'dart:ui' as ui;

import 'package:core_erp/features/groups/data/repositories/group_repository.dart';
import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/groups/domain/group_overview.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/groups/presentation/widgets/group_view_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// Renders the group view to a PNG so it can be looked at rather than inferred
// from assertions. Not a behaviour test — a way to see the thing.

class _Repo implements GroupRepository {
  _Repo(this.overview);
  final GroupOverview overview;
  @override
  Future<GroupOverview> getGroupOverview(int groupId) async => overview;
  @override
  Future<void> init() async {}
  @override
  Future<List<GroupDefinition>> getGroups({bool withCovers = false}) async =>
      <GroupDefinition>[overview.group];
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    final loader = FontLoader('Preview')
      ..addFont(
        File(
          '/System/Library/Fonts/Supplemental/Arial.ttf',
        ).readAsBytes().then((bytes) => bytes.buffer.asByteData()),
      );
    await loader.load();
  });

  testWidgets('render group view', (tester) async {
    // physicalSize is in PHYSICAL pixels: logical size x devicePixelRatio.
    tester.view.physicalSize = const Size(2000, 1640); // 1000 x 820 logical
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final group = GroupDefinition(
      id: 10,
      name: 'Electrical Fittings',
      groupStructure: 'hierarchical',
      description:
          'Switches, sockets and fittings sold as finished goods. Anything '
          'wired rather than fabricated belongs here.',
      parentGroupId: 4,
      isArchived: false,
      usageCount: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    final overview = GroupOverview(
      group: group,
      items: const <GroupOverviewItem>[
        GroupOverviewItem(
          itemId: 1,
          name: 'Anchor Roma Classic Socket 10A',
          unitName: 'Nos',
          orderCount: 3,
          hasPipeline: true,
          hasBaseline: true,
        ),
        GroupOverviewItem(
          itemId: 2,
          name: 'Anchor Roma Classic Socket 20A',
          unitName: 'Nos',
          orderCount: 1,
          hasPipeline: true,
        ),
        GroupOverviewItem(
          itemId: 3,
          name: 'Philips 9W LED Bulb',
          unitName: 'Nos',
          isVariant: true,
        ),
        GroupOverviewItem(
          itemId: 4,
          name: 'Crompton Greaves 1200mm Ceiling Fan',
          unitName: 'Nos',
        ),
      ],
      children: const <GroupChild>[
        GroupChild(groupId: 11, name: 'Modular', itemCount: 4),
        GroupChild(groupId: 12, name: 'Industrial', itemCount: 2),
      ],
      properties: const <GroupProperty>[
        GroupProperty(
          propertyKey: 'amps',
          displayName: 'Amps',
          unitSymbol: 'A',
          mandatory: true,
          sourceGroupId: 10,
          sourceGroupName: 'Electrical Fittings',
        ),
        GroupProperty(
          propertyKey: 'colour',
          displayName: 'Colour',
          sourceGroupId: 4,
          sourceGroupName: 'Primary Group',
        ),
        GroupProperty(
          propertyKey: 'finish',
          displayName: 'Finish',
          sourceGroupId: 4,
          sourceGroupName: 'Primary Group',
        ),
      ],
      lineage: const <GroupChild>[
        GroupChild(groupId: 4, name: 'Primary Group'),
        GroupChild(groupId: 10, name: 'Electrical Fittings'),
      ],
      summary: const GroupSummary(
        itemCount: 4,
        orderedItemCount: 2,
        orderLineCount: 4,
        variantCount: 1,
        withPipelineCount: 2,
        withBaselineCount: 1,
        units: <String>['Nos'],
      ),
    );

    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey<String>('shot'),
        child: ChangeNotifierProvider<GroupsProvider>(
          create: (_) => GroupsProvider(repository: _Repo(overview)),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: 'Preview'),
            home: Builder(
              builder: (context) => Scaffold(
                backgroundColor: const Color(0xFFF7F8FC),
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showGroupViewDialog(
                      context,
                      group: group,
                      onEdit: (_) async {},
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'no overflow in the view');

    final repaint = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey<String>('shot')),
    );
    final image = await repaint.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File(
      Platform.environment['SHOT'] ?? 'group_view.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

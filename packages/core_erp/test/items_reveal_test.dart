import 'package:core_erp/features/items/domain/developed_for.dart';
import 'package:core_erp/core/widgets/app_button.dart';
import 'package:core_erp/features/items/presentation/widgets/catalog_quick_entry_dialog.dart';
import 'package:core_erp/core/widgets/soft_master_data.dart';
import 'package:core_erp/features/groups/data/repositories/group_repository.dart';
import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/groups/domain/group_overview.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/inventory/data/repositories/inventory_repository.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:core_erp/features/items/data/repositories/item_repository.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/features/items/presentation/screens/items_screen.dart';
import 'package:core_erp/features/items/presentation/widgets/item_detail_panel.dart';
import 'package:core_erp/features/units/data/repositories/unit_repository.dart';
import 'package:core_erp/features/units/domain/unit_definition.dart';
import 'package:core_erp/features/units/presentation/providers/units_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Another screen hands an item over; the items screen has to land on it.
///
/// The groups tree sends the user here with the item named. Arriving meant
/// nothing happened unless the table was showing — a card view, the Sets view
/// or an active search all swallowed the request — and even then the group
/// only unfolded, leaving the item somewhere in a list with nothing to say
/// which row it was.

final _unit = UnitDefinition(
  id: 1,
  name: 'gross',
  symbol: 'gr',
  notes: '',
  unitGroupId: null,
  unitGroupName: null,
  conversionFactor: 1,
  conversionBaseUnitId: null,
  conversionBaseUnitName: null,
  conversionType: 'linear',
  precision: 2,
  unitGroupDimension: null,
  unitGroupBaseUnitId: null,
  isArchived: false,
  usageCount: 0,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

GroupDefinition _group(int id, String name, {int itemCount = 0}) {
  return GroupDefinition(
    id: id,
    name: name,
    groupStructure: 'hierarchical',
    parentGroupId: null,
    unitId: 1,
    itemCount: itemCount,
    isArchived: false,
    usageCount: 0,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

final _sockets = _group(3, 'Sockets', itemCount: 1);
final _plugs = _group(4, 'Plugs', itemCount: 1);

ItemDefinition _item(
  int id,
  String name, {
  int? baseItemId,
  int? groupId,
  DevelopedFor developedFor = DevelopedFor.empty,
}) {
  return ItemDefinition(
    id: id,
    name: name,
    displayName: name,
    alias: '',
    groupId: groupId ?? _sockets.id,
    unitId: _unit.id,
    baseItemId: baseItemId,
    developedFor: developedFor,
    quantity: 0,
    namingFormat: const <String>[],
    variationTree: const <ItemVariationNodeDefinition>[],
    usageCount: 0,
    isArchived: false,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

final _leafItem = _item(50, 'Socket Earthing');
final _variantA = _item(
  51,
  'Socket Earthing 6 Amp',
  baseItemId: 50,
  developedFor: DevelopedFor(
    kind: DevelopedForKind.client,
    clientId: 7,
    clientName: 'Gold Madel Industries',
    companyName: 'Gold Madel Industries',
    contactName: 'Kissan Jain',
    designation: 'Director',
    phone: '986565656',
    email: 'kissan@goldmadel.example',
    at: DateTime.utc(2026, 5, 15, 4, 35),
    quotationAmount: 85000,
  ),
);
// Developed in-house: a recorded answer, and a different one from the blank
// the Plug Top carries.
final _selfMade = _item(
  52,
  'Socket Earthing 16 Amp',
  baseItemId: 50,
  developedFor: const DevelopedFor(kind: DevelopedForKind.self),
);
final _plug = _item(60, 'Plug Top', groupId: _plugs.id);

class _FakeGroupRepository implements GroupRepository {
  @override
  Future<void> init() async {}

  @override
  Future<List<GroupDefinition>> getGroups({bool withCovers = false}) async =>
      <GroupDefinition>[_sockets, _plugs];

  @override
  Future<GroupOverview> getGroupOverview(int groupId) async =>
      GroupOverview(group: _sockets);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeItemRepository implements ItemRepository {
  @override
  Future<void> init() async {}

  @override
  Future<List<ItemDefinition>> getItems() async => <ItemDefinition>[
    _leafItem,
    _variantA,
    _selfMade,
    _plug,
  ];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUnitRepository implements UnitRepository {
  @override
  Future<void> init() async {}

  @override
  Future<List<UnitDefinition>> getUnits() async => <UnitDefinition>[_unit];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeInventoryRepository implements InventoryRepository {
  @override
  Future<void> init() async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The items screen, with the providers its detail panel needs. Hoisted out
/// of main so the Developed For group below can open the same screen.
Future<ItemsProvider> _openItems(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1700, 1300);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final groupsProvider = GroupsProvider(repository: _FakeGroupRepository());
  final itemsProvider = ItemsProvider(repository: _FakeItemRepository());
  final unitsProvider = UnitsProvider(repository: _FakeUnitRepository());
  await groupsProvider.initialize();
  await itemsProvider.initialize();
  await unitsProvider.initialize();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<GroupsProvider>.value(value: groupsProvider),
        ChangeNotifierProvider<ItemsProvider>.value(value: itemsProvider),
        ChangeNotifierProvider<UnitsProvider>.value(value: unitsProvider),
        ChangeNotifierProvider<InventoryProvider>(
          create: (_) =>
              InventoryProvider(repository: _FakeInventoryRepository()),
        ),
      ],
      child: const MaterialApp(home: ItemsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return itemsProvider;
}

void main() {
  _developedForPanelTests();

  Iterable<SoftMasterRow> highlightedRows(WidgetTester tester) => tester
      .widgetList<SoftMasterRow>(find.byType(SoftMasterRow))
      .where((row) => row.isHighlighted);

  testWidgets('a reveal unfolds to the item, lights it and opens its details', (
    tester,
  ) async {
    final items = await _openItems(tester);

    // Collapsed: the groups are there, the items inside them are not.
    expect(find.text('Sockets'), findsOneWidget);
    expect(find.text('Socket Earthing'), findsNothing);

    items.revealItem(_variantA.id);
    await tester.pumpAndSettle();

    // The request is spent — a rebuild must not re-open rows the user closes.
    expect(items.pendingRevealItemId, isNull);

    // Group and base item unfolded, so the variant's row is on screen...
    expect(find.text('Socket Earthing'), findsWidgets);
    expect(find.text('Socket Earthing 6 Amp'), findsWidgets);
    // ...and it is the one row lit up.
    final lit = highlightedRows(tester).toList();
    expect(lit.length, 1, reason: 'exactly the revealed row is highlighted');

    // And its details are open without another click.
    expect(find.byType(ItemDetailPanel), findsOneWidget);
  });

  testWidgets('a reveal drops a search that was hiding the item', (
    tester,
  ) async {
    // Sets moved out to their own master, so there is no longer another view
    // in this screen to be brought back from — but a search that hides the
    // target still has to be dropped, which is the half that matters.
    final items = await _openItems(tester);
    items.setSearchQuery('nothing matches this');
    await tester.pumpAndSettle();
    expect(find.text('Sockets'), findsNothing);

    items.revealItem(_plug.id);
    await tester.pumpAndSettle();

    expect(items.searchQuery, '', reason: 'the search was hiding the item');
    expect(find.text('Plug Top'), findsWidgets);
    expect(highlightedRows(tester).length, 1);
    expect(find.byType(ItemDetailPanel), findsOneWidget);
  });

  testWidgets('the Wizard button opens quick entry', (tester) async {
    await _openItems(tester);

    final wizard = find.widgetWithText(AppButton, 'Wizard');
    expect(wizard, findsOneWidget);
    expect(
      tester.widget<AppButton>(wizard).onPressed,
      isNotNull,
      reason: 'the affordance was drawn disabled until it had somewhere to go',
    );
    expect(find.textContaining('not wired up yet'), findsNothing);

    await tester.tap(wizard);
    await tester.pumpAndSettle();
    expect(find.byType(CatalogQuickEntryDialog), findsOneWidget);
    // Group, set and part as three dropdowns, and the sections under them —
    // where the part goes and everything about it, on one screen.
    for (final slug in const ['group', 'set', 'part']) {
      expect(
        find.byKey(ValueKey<String>('quick-entry-$slug-field')),
        findsOneWidget,
      );
    }
    expect(find.text('Made just now'), findsOneWidget);
    expect(find.textContaining('Developed For'), findsWidgets);

    // It fills the screen bar the dialog's 24px gutter. Asserted because the
    // height is only a CAP: ErpFormScaffold's Column is MainAxisSize.min, so
    // the card shrink-wraps the moment the body stops having an Expanded in
    // it, and nothing else would notice.
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final card = tester.getSize(
      find.ancestor(
        of: find.byType(CatalogQuickEntryDialog),
        matching: find.byType(Material),
      ).first,
    );
    expect(card.width, closeTo(screen.width - 48, 1));
    expect(card.height, closeTo(screen.height - 48, 1));
  });

  testWidgets('a reveal for an item that is gone says so and does nothing', (
    tester,
  ) async {
    final items = await _openItems(tester);

    items.revealItem(999);
    await tester.pumpAndSettle();

    expect(items.pendingRevealItemId, isNull);
    expect(highlightedRows(tester), isEmpty);
    expect(find.byType(ItemDetailPanel), findsNothing);
    expect(find.text('That item is no longer in the list.'), findsOneWidget);
  });
}

/// --- the Developed For reveal ----------------------------------------------
///
/// The panel is itself a dialog, so this is a card it toggles rather than
/// another dialog on top. No fetch and no spinner either: unlike the usage
/// row beside it, the item DTO carries the block already.
void _developedForPanelTests() {
  Future<void> openPanelFor(WidgetTester tester, ItemsProvider items, int id) async {
    items.revealItem(id);
    await tester.pumpAndSettle();
    expect(find.byType(ItemDetailPanel), findsOneWidget);
  }

  Finder revealButton() => find.widgetWithText(OutlinedButton, 'Developed for');

  testWidgets('the button toggles the card, and nothing is fetched', (
    tester,
  ) async {
    final items = await _openItems(tester);
    await openPanelFor(tester, items, _variantA.id);

    // Closed to begin with: most parts were made for nobody in particular.
    expect(find.text('Developed For'), findsNothing);
    expect(revealButton(), findsOneWidget);

    await tester.tap(revealButton());
    await tester.pumpAndSettle();

    expect(find.text('Developed For'), findsOneWidget);
    expect(find.text('Gold Madel Industries'), findsOneWidget);
    expect(find.text('Kissan Jain'), findsOneWidget);
    expect(find.text('Director'), findsOneWidget);
    expect(find.text('986565656'), findsOneWidget);
    expect(find.text('₹85,000/-'), findsOneWidget);
    // Never a spinner: there is nothing to wait for.
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(revealButton());
    await tester.pumpAndSettle();
    expect(find.text('Developed For'), findsNothing);
  });

  testWidgets('self reads as in-house, with nobody to name', (tester) async {
    final items = await _openItems(tester);
    await openPanelFor(tester, items, _selfMade.id);

    await tester.tap(revealButton());
    await tester.pumpAndSettle();

    expect(find.text('Self (in-house)'), findsOneWidget);
    // No person, because there is no party — and no empty rows pretending
    // there might be.
    expect(find.text('Client Name'), findsNothing);
    expect(find.text('Company Name'), findsNothing);
  });

  testWidgets('a part developed for nobody says so on the button itself', (
    tester,
  ) async {
    final items = await _openItems(tester);
    await openPanelFor(tester, items, _plug.id);

    // Drawn disabled with a reason rather than hidden: a control that appears
    // only once its precondition holds is a control nobody knows about.
    expect(revealButton(), findsOneWidget);
    expect(tester.widget<OutlinedButton>(revealButton()).onPressed, isNull);
    final tooltip = tester.widget<Tooltip>(
      find.ancestor(of: revealButton(), matching: find.byType(Tooltip)).first,
    );
    expect(tooltip.message, contains('Nobody has recorded'));
  });
}

import 'package:core_erp/features/auth/presentation/providers/auth_provider.dart';
import 'package:core_erp/features/groups/data/repositories/group_repository.dart';
import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/items/data/repositories/item_repository.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paper/app/shell/app_sidebar.dart';
import 'package:paper/app/shell/navigation_provider.dart';
import 'package:provider/provider.dart';

/// Item Groups and Item Sets had screens, routes and keys all along — and no
/// way in from the sidebar. Unless you knew about a segmented control on the
/// Items toolbar, the two masters did not appear to exist.
///
/// They are children of Items now, which is the first nesting this sidebar has
/// ever had below the section level. What these guard is the part that is easy
/// to get wrong: a destination you cannot see is no better than one that is not
/// there, so a selection must always open the entry it lives under, and the
/// keyboard has to reach it.

const String _itemsTile = 'sidebar_tile_configurator_items';
const String _groupsTile = 'sidebar_tile_configurator_groups';
const String _setsTile = 'sidebar_tile_configurator_sets';
const String _itemsChevron = 'sidebar_chevron_configurator_items';
const String _sheetPill = 'sidebar_item_sheet';

Finder _byTileKey(String key) => find.byKey(ValueKey<String>(key));

/// An auth that answers a fixed yes or no, so the gated affordances can be
/// seen in both states. The real provider needs a signed-in user.
class _FakeAuth extends AuthProvider {
  _FakeAuth({required this.allowed}) : super(baseUrl: 'http://localhost:0');

  final bool allowed;

  @override
  bool can(String permission) => allowed;
}

/// Empty masters. `noSuchMethod` so adding to either interface stays free.
class _FakeItemRepository implements ItemRepository {
  @override
  Future<void> init() async {}

  @override
  Future<List<ItemDefinition>> getItems() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGroupRepository implements GroupRepository {
  @override
  Future<void> init() async {}

  @override
  Future<List<GroupDefinition>> getGroups({bool withCovers = false}) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<NavigationProvider> _pumpSidebar(
  WidgetTester tester, {
  bool compact = false,
  String initialKey = 'inventory',
  bool canWrite = true,
}) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final navigation = NavigationProvider(initialKey: initialKey);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<NavigationProvider>.value(value: navigation),
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => _FakeAuth(allowed: canWrite),
        ),
        // The Sheet pill pushes ItemMasterSheetScreen, which reads these two.
        // Present so the tap runs the real path — the point of the test below
        // is that the pill swallows its gesture, and a tap that throws on the
        // way out proves nothing about the drawer.
        ChangeNotifierProvider<ItemsProvider>(
          create: (_) => ItemsProvider(repository: _FakeItemRepository()),
        ),
        ChangeNotifierProvider<GroupsProvider>(
          create: (_) => GroupsProvider(repository: _FakeGroupRepository()),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 1400,
            child: AppSidebar(compact: compact),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return navigation;
}

bool _isTileSelected(WidgetTester tester, String tileKey) {
  // Selection is painted as a gradient on the tile's container; an unselected
  // tile gets a flat colour instead.
  final container = tester.widget<Container>(
    find.descendant(
      of: _byTileKey(tileKey),
      matching: find.byType(Container),
    ).first,
  );
  final decoration = container.decoration as BoxDecoration;
  return decoration.gradient != null;
}

void main() {
  testWidgets('Items holds the other two catalogue masters', (tester) async {
    await _pumpSidebar(tester);

    expect(_byTileKey(_itemsTile), findsOneWidget);
    // Open to begin with: these were unreachable from the sidebar until now,
    // and a closed drawer leaves them exactly as hard to find as they were.
    expect(_byTileKey(_groupsTile), findsOneWidget);
    expect(_byTileKey(_setsTile), findsOneWidget);
    expect(find.text('Item Groups'), findsOneWidget);
    expect(find.text('Item Sets'), findsOneWidget);
  });

  testWidgets('the chevron closes the children without going anywhere', (
    tester,
  ) async {
    final navigation = await _pumpSidebar(tester);

    await tester.tap(_byTileKey(_itemsChevron));
    await tester.pumpAndSettle();
    expect(_byTileKey(_groupsTile), findsNothing);
    expect(_byTileKey(_setsTile), findsNothing);
    expect(
      navigation.selectedKey,
      'inventory',
      reason: 'the chevron only folds — it is not a way to navigate',
    );

    await tester.tap(_byTileKey(_itemsChevron));
    await tester.pumpAndSettle();
    expect(_byTileKey(_groupsTile), findsOneWidget);
  });

  testWidgets('tapping Items goes there and leaves it open', (tester) async {
    final navigation = await _pumpSidebar(tester);

    // Folded first, so the tap has something to open.
    await tester.tap(_byTileKey(_itemsChevron));
    await tester.pumpAndSettle();

    await tester.tap(_byTileKey(_itemsTile));
    await tester.pumpAndSettle();

    expect(navigation.selectedKey, 'configurator_items');
    expect(
      _byTileKey(_groupsTile),
      findsOneWidget,
      reason: 'a parent that only navigated would hide what is under it',
    );
  });

  testWidgets('a child is the thing lit, not its parent', (tester) async {
    final navigation = await _pumpSidebar(tester);

    await tester.tap(_byTileKey(_setsTile));
    await tester.pumpAndSettle();

    expect(navigation.selectedKey, 'configurator_sets');
    expect(_isTileSelected(tester, _setsTile), isTrue);
    expect(
      _isTileSelected(tester, _itemsTile),
      isFalse,
      reason: 'Items is not where you are; Item Sets is',
    );
  });

  testWidgets('arriving at a child from elsewhere opens Items', (tester) async {
    final navigation = await _pumpSidebar(tester);

    // Fold it, then navigate the way the Items toolbar or the Action Center
    // does — from outside the sidebar entirely.
    await tester.tap(_byTileKey(_itemsChevron));
    await tester.pumpAndSettle();
    expect(_byTileKey(_groupsTile), findsNothing);

    navigation.select('configurator_groups');
    await tester.pumpAndSettle();

    expect(
      _byTileKey(_groupsTile),
      findsOneWidget,
      reason: 'the selection would otherwise be lit where nobody can see it',
    );
    expect(_isTileSelected(tester, _groupsTile), isTrue);
  });

  testWidgets('arriving from elsewhere opens a folded Masters drawer too', (
    tester,
  ) async {
    final navigation = await _pumpSidebar(tester);

    // Fold the whole Masters drawer, not just Items.
    final header = _byTileKey('sidebar_tile_configurator');
    // At its left edge: the middle of the header is the Sheet pill, which
    // opens the sheet over the sidebar rather than folding anything.
    await tester.tapAt(tester.getTopLeft(header) + const Offset(24, 20));
    await tester.pumpAndSettle();
    expect(_byTileKey(_itemsTile), findsNothing);

    navigation.select('configurator_sets');
    await tester.pumpAndSettle();

    expect(
      _byTileKey(_setsTile),
      findsOneWidget,
      reason: 'Item Sets lit inside a folded drawer is a selection nobody sees',
    );
    expect(_isTileSelected(tester, _setsTile), isTrue);
  });

  testWidgets('a child opens when the sidebar starts on it', (tester) async {
    await _pumpSidebar(tester, initialKey: 'configurator_sets');

    expect(_byTileKey(_setsTile), findsOneWidget);
    expect(_isTileSelected(tester, _setsTile), isTrue);
  });

  testWidgets('Tab reaches a child', (tester) async {
    final navigation = await _pumpSidebar(
      tester,
      initialKey: 'configurator_items',
    );

    // Focus has to be in the sidebar for its key handler to see anything.
    await tester.tap(_byTileKey(_itemsTile));
    await tester.pumpAndSettle();

    // Ctrl+Tab walks the visible keys in order; the one after Items is its
    // first child, which only happens if the children are in that list.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(navigation.selectedKey, 'configurator_groups');
  });

  group('the Sheet pill', () {
    testWidgets('sits in the Masters header', (tester) async {
      await _pumpSidebar(tester);

      expect(_byTileKey(_sheetPill), findsOneWidget);
      expect(find.text('Sheet'), findsOneWidget);
      // Beside the title, not instead of it.
      expect(find.text('Masters'), findsOneWidget);
    });

    testWidgets('opening it does not fold the drawer', (tester) async {
      await _pumpSidebar(tester);
      expect(_byTileKey(_itemsTile), findsOneWidget);

      await tester.tap(_byTileKey(_sheetPill));
      await tester.pump();

      // The header's own InkWell toggles Masters, so a pill that did not
      // swallow its tap would shut the drawer behind the window it opened.
      expect(
        _byTileKey(_itemsTile),
        findsOneWidget,
        reason: 'the drawer stayed open',
      );
    });

    testWidgets('without permission it is greyed, not gone', (tester) async {
      await _pumpSidebar(tester, canWrite: false);

      // Hiding a control until its precondition holds reads as a missing
      // feature; this says why instead.
      expect(_byTileKey(_sheetPill), findsOneWidget);
      expect(
        tester.widget<GestureDetector>(_byTileKey(_sheetPill)).onTap,
        isNull,
      );
      // Scoped to the pill rather than counted. There used to be two pills
      // here — Express and Factory Sheet — both gated on config.write, so the
      // message appeared twice and a count broke when the pair changed.
      expect(
        find.descendant(
          of: _byTileKey(_sheetPill),
          matching: find.byTooltip(
            'You do not have permission to create records (config.write).',
          ),
          matchRoot: true,
        ),
        findsOneWidget,
      );
    });

    testWidgets('it folds away with the drawer', (tester) async {
      await _pumpSidebar(tester);

      await tester.tap(_byTileKey(_itemsChevron));
      await tester.pumpAndSettle();
      // Folding Items is not folding Masters — the pill is in the header.
      expect(_byTileKey(_sheetPill), findsOneWidget);
    });

    testWidgets('the header still reads at the narrowest width', (
      tester,
    ) async {
      await _pumpSidebar(tester);

      // 300px is the narrowest the sidebar is drawn at here. The title shares
      // the row with the pill now, so it has to be allowed to ellipsize
      // rather than paint past its own edge.
      expect(tester.takeException(), isNull);
      final title = tester.widget<Text>(find.text('Masters'));
      expect(title.overflow, TextOverflow.ellipsis);
      expect(title.maxLines, 1);
    });
  });

  testWidgets('the compact rail draws no children', (tester) async {
    await _pumpSidebar(tester, compact: true);

    // Compact tiles are icons with no labels, so an indented tree would be a
    // column of anonymous glyphs.
    expect(_byTileKey(_itemsTile), findsOneWidget);
    expect(_byTileKey(_groupsTile), findsNothing);
    expect(_byTileKey(_setsTile), findsNothing);
    expect(_byTileKey(_itemsChevron), findsNothing);
    // The compact header is one icon with no label beside it, so there is
    // nowhere for a labelled pill to go.
    expect(_byTileKey(_sheetPill), findsNothing);
  });
}

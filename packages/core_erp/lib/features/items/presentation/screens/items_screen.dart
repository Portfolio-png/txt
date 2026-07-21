import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../core/navigation/app_navigation.dart';
import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_section_title.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/widgets/erp_form_dialog.dart';
import '../../../../core/widgets/searchable_select.dart';
import '../../../../core/widgets/soft_master_data.dart';
import '../../../../core/widgets/soft_primitives.dart';
import '../../../../core/widgets/soft_entrance_animation.dart';
import '../../../../core/services/feature_flags.dart';
import '../../../groups/domain/group_definition.dart';
import '../../../groups/domain/group_inputs.dart';
import '../../../groups/presentation/screens/groups_screen.dart';
import '../../../auth/presentation/widgets/track_panel.dart';
import '../../../groups/presentation/providers/groups_provider.dart';
import '../../../inventory/domain/group_property_draft.dart' as governance;
import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../units/presentation/screens/units_screen.dart';
import '../../../units/presentation/providers/units_provider.dart';
import '../../domain/item_definition.dart';
import '../../domain/item_inputs.dart';

import '../providers/items_provider.dart';
import '../../../../core/widgets/boarding_pass_card.dart';
import '../../domain/item_asset.dart';
import '../widgets/item_card.dart';
import '../widgets/item_detail_panel.dart';

import 'package:file_selector/file_selector.dart';
import 'package:crypto/crypto.dart';
import 'package:mime/mime.dart';
import 'package:http/http.dart' as http;
import 'package:collection/collection.dart';
import '../../../../core/services/generic_asset_service.dart';
import '../../../../core/widgets/export_preview_dialog.dart';

class ItemsScreen extends StatefulWidget {
  const ItemsScreen({super.key, this.initialTab = 0, this.onCreatePipeline});

  final int initialTab;
  final Future<String?> Function()? onCreatePipeline;

  static Future<ItemDefinition?> openEditor(
    BuildContext context, {
    ItemDefinition? item,
    String initialName = '',
    int? initialGroupId,
    Future<String?> Function()? onCreatePipeline,
  }) {
    final isNarrow = MediaQuery.of(context).size.width < 980;
    final body = SubmitFormShortcuts(
      child: _ItemEditorSheet(
        item: item,
        initialName: initialName,
        initialGroupId: initialGroupId,
        onCreatePipeline: onCreatePipeline,
      ),
    );
    if (isNarrow) {
      return showModalBottomSheet<ItemDefinition?>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: body,
        ),
      );
    }

    return showDialog<ItemDefinition?>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1380),
          child: body,
        ),
      ),
    );
  }

  @override
  State<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends State<ItemsScreen> {
  bool _isGridView = false;
  double _cardWidth = 200;
  double _cardHeight = 250;
  // Boarding-pass card view: number of columns the resize slider requests
  // (clamped to what the desktop width can fit). 1 = full-width hero, up to 10.
  int _columnCount = 4;

  @override
  Widget build(BuildContext context) {
    if (widget.initialTab == 1) {
      return const GroupsScreen();
    }

    return Consumer3<ItemsProvider, GroupsProvider, UnitsProvider>(
      builder: (context, items, groups, units, _) {
        if ((items.isLoading && items.items.isEmpty) ||
            (groups.isLoading && groups.groups.isEmpty) ||
            (units.isLoading && units.units.isEmpty)) {
          return const Center(child: CircularProgressIndicator());
        }

        return FocusableActionDetector(
          autofocus: true,
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.keyP, control: true):
                PrintIntent(),
            SingleActivator(LogicalKeyboardKey.keyP, meta: true): PrintIntent(),
          },
          actions: {
            PrintIntent: CallbackAction<PrintIntent>(
              onInvoke: (intent) {
                final data = items.filteredItems.map((i) {
                  final groupName =
                      groups.findById(i.groupId)?.name ?? 'Unknown';
                  final unitLabel =
                      units.units
                          .where((u) => u.id == i.unitId)
                          .firstOrNull
                          ?.displayLabel ??
                      'Unknown';
                  return {
                    'id': i.id,
                    'name': i.displayName,
                    'alias': i.alias,
                    'group': groupName,
                    'unit': unitLabel,
                    'status': i.isArchived ? 'Archived' : 'Active',
                  };
                }).toList();
                ExportPreviewDialog.show(context, title: 'Items', data: data);
                return null;
              },
            ),
          },
          child: SoftMasterDataPage(
            title: 'Items',
            subtitle:
                'Manage sellable catalog items with recursive property and value inheritance.',
            action: AppButton(
              label: 'Add Item',
              icon: Icons.add,
              isLoading: items.isSaving,
              onPressed: () => ItemsScreen.openEditor(
                context,
                onCreatePipeline: widget.onCreatePipeline,
              ),
            ),
            toolbar: _ItemsToolbar(
              isGridView: _isGridView,
              boardingPass: FeatureFlags.isEnabled(FeatureKeys.boardingPassCards),
              cardWidth: _cardWidth,
              cardHeight: _cardHeight,
              columnCount: _columnCount,
              onToggleView: () {
                setState(() {
                  _isGridView = !_isGridView;
                });
              },
              onCardWidthChanged: (value) {
                setState(() {
                  _cardWidth = value;
                });
              },
              onCardHeightChanged: (value) {
                setState(() {
                  _cardHeight = value;
                });
              },
              onColumnCountChanged: (value) {
                setState(() {
                  _columnCount = value;
                });
              },
            ),
            messages: [
              if (items.errorMessage != null)
                _ItemsMessageBanner(
                  message: items.errorMessage!,
                  isError: true,
                ),
            ],
            body: items.filteredItems.isEmpty
                ? const AppEmptyState(
                    title: 'No items found',
                    message:
                        'Create an item like Bottle - 100, then build recursive property branches such as Color -> Black -> Finish -> Matte.',
                    icon: Icons.inventory_outlined,
                  )
                : _isGridView
                ? (FeatureFlags.isEnabled(FeatureKeys.boardingPassCards)
                      ? _ItemsBoardingGrid(
                          items: items.filteredItems,
                          columnCount: _columnCount,
                          onCreatePipeline: widget.onCreatePipeline,
                        )
                      : _ItemsGrid(
                          items: items.filteredItems,
                          cardWidth: _cardWidth,
                          cardHeight: _cardHeight,
                          onCreatePipeline: widget.onCreatePipeline,
                        ))
                : _ItemsTable(
                    items: items.filteredItems,
                    onCreatePipeline: widget.onCreatePipeline,
                  ),
          ),
        );
      },
    );
  }
}

class _ItemsToolbar extends StatelessWidget {
  const _ItemsToolbar({
    required this.isGridView,
    required this.boardingPass,
    required this.cardWidth,
    required this.cardHeight,
    required this.columnCount,
    required this.onToggleView,
    required this.onCardWidthChanged,
    required this.onCardHeightChanged,
    required this.onColumnCountChanged,
  });

  final bool isGridView;
  final bool boardingPass;
  final double cardWidth;
  final double cardHeight;
  final int columnCount;
  final VoidCallback onToggleView;
  final ValueChanged<double> onCardWidthChanged;
  final ValueChanged<double> onCardHeightChanged;
  final ValueChanged<int> onColumnCountChanged;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ItemsProvider>();
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    final tabSegment = SoftSegmentedFilter<String>(
      selected: 'items',
      onChanged: (value) {
        if (value == 'groups') {
          try {
            context.read<AppNavigation>().select('configurator_groups');
          } catch (_) {}
        }
      },
      options: const [
        SoftSegmentOption<String>(value: 'items', label: 'Items Catalog'),
        SoftSegmentOption<String>(value: 'groups', label: 'Item Groups'),
      ],
    );

    return SoftMasterToolbar(
      children: [
        tabSegment,
        if (isDesktop)
          Container(
            width: 1,
            height: 28,
            color: SoftErpTheme.border,
            margin: const EdgeInsets.symmetric(horizontal: 4),
          ),
        if (!isDesktop)
          SoftMasterSearchField(
            hintText: 'Search items, properties, values, or leaf nodes',
            onChanged: provider.setSearchQuery,
          ),

        _ItemsViewToggleButton(isGridView: isGridView, onTap: onToggleView),
        if (isGridView && boardingPass)
          _ItemsColumnSlider(
            columnCount: columnCount,
            maxColumns: _maxColumnsForWidth(MediaQuery.of(context).size.width),
            onChanged: onColumnCountChanged,
          )
        else if (isGridView)
          _ItemsGridSizeControls(
            cardWidth: cardWidth,
            cardHeight: cardHeight,
            onCardWidthChanged: onCardWidthChanged,
            onCardHeightChanged: onCardHeightChanged,
          ),
      ],
    );
  }
}

/// Max columns the current desktop width can reasonably show (>= ~150px/card),
/// capped at 10. The slider runs 1..this.
int _maxColumnsForWidth(double width) {
  return (width / 170).floor().clamp(1, 10);
}

/// A single "columns" resize slider (1 -> full-width hero, up to N) that drives
/// the boarding-pass card grid density. Replaces the old width/height sliders.
class _ItemsColumnSlider extends StatelessWidget {
  const _ItemsColumnSlider({
    required this.columnCount,
    required this.maxColumns,
    required this.onChanged,
  });

  final int columnCount;
  final int maxColumns;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final max = maxColumns < 1 ? 1 : maxColumns;
    final value = columnCount.clamp(1, max).toDouble();
    return Container(
      key: const ValueKey<String>('items-column-slider'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.grid_view_rounded, size: 18, color: SoftErpTheme.textSecondary),
          const SizedBox(width: 8),
          SizedBox(
            width: 200,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: const Color(0xFFE4C17C),
                thumbColor: const Color(0xFFE4C17C),
                overlayColor: const Color(0xFFE4C17C).withValues(alpha: 0.18),
                inactiveTrackColor: const Color(0xFFE9E7DF),
                trackHeight: 2.5,
              ),
              child: Slider.adaptive(
                key: const ValueKey<String>('items-column-count-slider'),
                value: value,
                min: 1,
                max: max.toDouble(),
                divisions: max > 1 ? max - 1 : null,
                label: '${value.round()} col${value.round() == 1 ? '' : 's'}',
                onChanged: (v) => onChanged(v.round().clamp(1, max)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 30,
            child: Text(
              '${value.round()}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: SoftErpTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemsGridSizeControls extends StatelessWidget {
  const _ItemsGridSizeControls({
    required this.cardWidth,
    required this.cardHeight,
    required this.onCardWidthChanged,
    required this.onCardHeightChanged,
  });

  final double cardWidth;
  final double cardHeight;
  final ValueChanged<double> onCardWidthChanged;
  final ValueChanged<double> onCardHeightChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey<String>('items-grid-size-controls'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _ItemsGridSlider(
            sliderKey: const ValueKey<String>('items-card-width-slider'),
            icon: Icons.horizontal_distribute_rounded,
            value: cardWidth,
            min: 120,
            max: 400,
            onChanged: onCardWidthChanged,
          ),
          _ItemsGridSlider(
            sliderKey: const ValueKey<String>('items-card-height-slider'),
            icon: Icons.vertical_distribute_rounded,
            value: cardHeight,
            min: 150,
            max: 500,
            onChanged: onCardHeightChanged,
          ),
        ],
      ),
    );
  }
}

class _ItemsGridSlider extends StatelessWidget {
  const _ItemsGridSlider({
    required this.sliderKey,
    required this.icon,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final Key sliderKey;
  final IconData icon;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: SoftErpTheme.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: const Color(0xFFE4C17C),
                thumbColor: const Color(0xFFE4C17C),
                overlayColor: const Color(0xFFE4C17C).withValues(alpha: 0.18),
                inactiveTrackColor: const Color(0xFFE9E7DF),
                trackHeight: 2.5,
              ),
              child: Slider.adaptive(
                key: sliderKey,
                value: value,
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemsViewToggleButton extends StatelessWidget {
  const _ItemsViewToggleButton({required this.isGridView, required this.onTap});

  final bool isGridView;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey<String>('items-view-toggle-button'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: SoftErpTheme.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: SoftErpTheme.border),
            boxShadow: SoftErpTheme.insetShadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isGridView
                    ? Icons.view_headline_rounded
                    : Icons.grid_view_rounded,
                size: 18,
                color: SoftErpTheme.textPrimary,
              ),
              const SizedBox(width: 10),
              Text(
                isGridView ? 'List View' : 'Card View',
                style: const TextStyle(
                  color: SoftErpTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemsTable extends StatefulWidget {
  const _ItemsTable({required this.items, this.onCreatePipeline});

  final List<ItemDefinition> items;
  final Future<String?> Function()? onCreatePipeline;

  @override
  State<_ItemsTable> createState() => _ItemsTableState();
}

class _ItemsTableState extends State<_ItemsTable> {
  final Set<int> _expandedBaseItemIds = <int>{};

  @override
  Widget build(BuildContext context) {
    final topLevelItems = widget.items
        .where((i) => i.baseItemId == null)
        .toList();
    final displayItems = <ItemDefinition>[];

    for (final baseItem in topLevelItems) {
      displayItems.add(baseItem);
      if (_expandedBaseItemIds.contains(baseItem.id)) {
        final variants = widget.items
            .where((i) => i.baseItemId == baseItem.id)
            .toList();
        displayItems.addAll(variants);
      }
    }

    return SoftMasterTable(
      minWidth: 1120,
      columns: const [
        SoftTableColumn('Item', flex: 2),
        SoftTableColumn('Unit', flex: 2),
        SoftTableColumn('Group', flex: 2),
        SoftTableColumn('Tree Summary', flex: 3),
        SoftTableColumn('Status', flex: 1),
        SoftTableColumn('Actions', flex: 2),
      ],
      itemCount: displayItems.length,
      rowBuilder: (context, index) {
        final item = displayItems[index];
        final isVariant = item.baseItemId != null;
        return _ItemRow(
          item: item,
          isVariant: isVariant,
          onCreatePipeline: widget.onCreatePipeline,
          onDoubleTap: isVariant
              ? null
              : () {
                  setState(() {
                    if (_expandedBaseItemIds.contains(item.id)) {
                      _expandedBaseItemIds.remove(item.id);
                    } else {
                      _expandedBaseItemIds.add(item.id);
                    }
                  });
                },
        );
      },
    );
  }
}

class _ItemsGrid extends StatelessWidget {
  const _ItemsGrid({
    required this.items,
    required this.cardWidth,
    required this.cardHeight,
    this.onCreatePipeline,
  });

  final List<ItemDefinition> items;
  final double cardWidth;
  final double cardHeight;
  final Future<String?> Function()? onCreatePipeline;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final spacing = width >= 1200 ? 18.0 : 14.0;

        final topLevelItems = items.where((i) => i.baseItemId == null).toList();

        return GridView.builder(
          key: const ValueKey<String>('items-grid-view'),
          padding: const EdgeInsets.only(bottom: 12),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: cardWidth,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: cardWidth / cardHeight,
          ),
          itemCount: topLevelItems.length,
          itemBuilder: (context, index) => _GridItemCard(
            item: topLevelItems[index],
            onCreatePipeline: onCreatePipeline,
          ),
        );
      },
    );
  }
}

class _GridItemCard extends StatelessWidget {
  const _GridItemCard({required this.item, this.onCreatePipeline});

  final ItemDefinition item;
  final Future<String?> Function()? onCreatePipeline;

  @override
  Widget build(BuildContext context) {
    return ItemCard(
      item: item,
      onTap: () => showItemDetailPanel(
        context,
        item: item,
        onEdit: () => ItemsScreen.openEditor(
          context,
          item: item,
          onCreatePipeline: onCreatePipeline,
        ),
      ),
    );
  }
}

/// Boarding-pass card grid for the item master. Column count is driven by the
/// resize slider, clamped to what the width can fit; the tile aspect ratio (and
/// therefore the card layout) adapts so 1 column is a wide ticket and many
/// columns are compact portrait heroes.
class _ItemsBoardingGrid extends StatelessWidget {
  const _ItemsBoardingGrid({
    required this.items,
    required this.columnCount,
    this.onCreatePipeline,
  });

  final List<ItemDefinition> items;
  final int columnCount;
  final Future<String?> Function()? onCreatePipeline;

  @override
  Widget build(BuildContext context) {
    final topLevelItems = items.where((i) => i.baseItemId == null).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final maxCols = (width / 150).floor().clamp(1, 10);
        final cols = columnCount.clamp(1, maxCols);
        final spacing = width >= 1200 ? 18.0 : 14.0;
        final aspect = cols == 1
            ? 2.4
            : cols == 2
            ? 1.15
            : 0.72;
        return GridView.builder(
          key: const ValueKey<String>('items-boarding-grid'),
          padding: const EdgeInsets.only(bottom: 12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: aspect,
          ),
          itemCount: topLevelItems.length,
          itemBuilder: (context, index) => _BoardingItemCard(
            item: topLevelItems[index],
            onCreatePipeline: onCreatePipeline,
          ),
        );
      },
    );
  }
}

class _BoardingItemCard extends StatefulWidget {
  const _BoardingItemCard({required this.item, this.onCreatePipeline});

  final ItemDefinition item;
  final Future<String?> Function()? onCreatePipeline;

  @override
  State<_BoardingItemCard> createState() => _BoardingItemCardState();
}

class _BoardingItemCardState extends State<_BoardingItemCard> {
  bool _requestedAssets = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureAssetsLoaded();
    });
  }

  @override
  void didUpdateWidget(covariant _BoardingItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _requestedAssets = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureAssetsLoaded();
      });
    }
  }

  void _ensureAssetsLoaded() {
    final provider = context.read<ItemsProvider>();
    if (_requestedAssets || provider.assetsForItem(widget.item.id).isNotEmpty) {
      return;
    }
    _requestedAssets = true;
    provider.loadItemAssets(widget.item.id);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final asset = context.select<ItemsProvider, ItemAsset?>((provider) {
      final assets = provider.assetsForItem(item.id);
      return assets.where((a) => a.isPrimary).firstOrNull ?? assets.firstOrNull;
    });
    final imageUrl = asset?.readUrl?.toString() ?? item.photoUrl;
    final groupName =
        context.read<GroupsProvider>().findById(item.groupId)?.name ?? '—';
    final unitLabel =
        context
            .read<UnitsProvider>()
            .units
            .where((u) => u.id == item.unitId)
            .firstOrNull
            ?.displayLabel ??
        '—';
    final leafCount = item.leafVariationNodes.length;
    final title = item.displayName.trim().isEmpty ? item.name : item.displayName;

    return BoardingPassCard(
      title: title,
      subtitle: leafCount == 0 ? 'Base item' : '$leafCount variant${leafCount == 1 ? '' : 's'}',
      imageUrl: imageUrl,
      token: _boardingInitials(item.name.trim().isEmpty ? title : item.name),
      caption: item.alias.trim().isEmpty ? 'No image' : item.alias,
      details: [
        BoardingPassDetail('Group', groupName),
        BoardingPassDetail('Unit', unitLabel),
        BoardingPassDetail('Variants', leafCount == 0 ? 'Base' : '$leafCount'),
      ],
      // Item master items have no barcode — the design stays consistent, the
      // barcode block is simply omitted.
      barcode: null,
      onTap: () => showItemDetailPanel(
        context,
        item: item,
        onEdit: () => ItemsScreen.openEditor(
          context,
          item: item,
          onCreatePipeline: widget.onCreatePipeline,
        ),
      ),
    );
  }
}

String _boardingInitials(String source) {
  final parts = source
      .split(RegExp(r'\s+'))
      .where((p) => p.trim().isNotEmpty)
      .take(2)
      .map((p) => p.substring(0, 1).toUpperCase())
      .toList(growable: false);
  return parts.isEmpty ? 'IT' : parts.join();
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    this.onCreatePipeline,
    this.isVariant = false,
    this.onDoubleTap,
  });

  final ItemDefinition item;
  final Future<String?> Function()? onCreatePipeline;
  final bool isVariant;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final groupsProvider = context.watch<GroupsProvider>();
    final unitsProvider = context.watch<UnitsProvider>();
    final itemsProvider = context.watch<ItemsProvider>();
    final groupName = groupsProvider.findById(item.groupId)?.name ?? 'Unknown';
    final unitLabel =
        unitsProvider.units
            .where((unit) => unit.id == item.unitId)
            .firstOrNull
            ?.displayLabel ??
        'Unknown';
    final propertySummary = item.topLevelProperties.isEmpty
        ? 'No properties'
        : item.topLevelProperties.map((node) => node.name).join(', ');
    final leafSummary = item.leafVariationNodes.isEmpty
        ? 'No orderable leaves'
        : '${item.leafVariationNodes.length} orderable leaf${item.leafVariationNodes.length == 1 ? '' : 's'}';

    return SoftMasterRow(
      onTap: () => showItemDetailPanel(
        context,
        item: item,
        onEdit: () => ItemsScreen.openEditor(
          context,
          item: item,
          onCreatePipeline: onCreatePipeline,
        ),
      ),
      onDoubleTap: onDoubleTap,
      children: [
        Expanded(
          flex: 2,
          child: Padding(
            padding: EdgeInsets.only(left: isVariant ? 24.0 : 0.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isVariant)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2.0),
                        child: Icon(
                          Icons.subdirectory_arrow_right_rounded,
                          size: 16,
                          color: SoftErpTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: SoftInlineText(
                          item.displayName,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                else
                  SoftInlineText(item.displayName, weight: FontWeight.w700),
                if (item.alias.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: EdgeInsets.only(left: isVariant ? 22.0 : 0.0),
                    child: SoftInlineText(
                      item.alias,
                      color: SoftErpTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Expanded(flex: 2, child: SoftInlineText(unitLabel)),
        Expanded(flex: 2, child: SoftInlineText(groupName)),
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SoftInlineText(propertySummary),
              const SizedBox(height: 4),
              SoftInlineText(leafSummary, color: SoftErpTheme.textSecondary),
            ],
          ),
        ),
        Expanded(
          flex: 1,
          child: SoftStatusPill(
            label: item.isArchived ? 'Archived' : 'Active',
            background: item.isArchived
                ? const Color(0xFFF3F4F6)
                : const Color(0xFFECFDF5),
            textColor: item.isArchived
                ? const Color(0xFF6B7280)
                : const Color(0xFF0F766E),
            borderColor: item.isArchived
                ? const Color(0xFFE5E7EB)
                : const Color(0xFFBFEAD8),
          ),
        ),
        Expanded(
          flex: 2,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SoftActionLink(
                label: 'Edit',
                onTap: () => ItemsScreen.openEditor(
                  context,
                  item: item,
                  onCreatePipeline: onCreatePipeline,
                ),
              ),
              SoftActionLink(
                label: 'Delete',
                onTap: itemsProvider.isSaving
                    ? null
                    : () async {
                        final ok = await showConfirmDialog(
                          context,
                          title: 'Delete item?',
                          message:
                              'Permanently delete "${item.displayName}"? You can restore it later from the Action Center.',
                        );
                        if (ok) itemsProvider.deleteItem(item.id);
                      },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NodeDraft {
  _NodeDraft({
    this.id,
    required this.kind,
    required this.parent,
    String name = '',
    String code = '',
    String displayName = '',
    this.detailsExpanded = false,
    this.isNameEditing = false,
    this.displayNameTouched = false,
    this.inputType = 'Text',
    List<_NodeDraft>? children,
  }) : nameController = TextEditingController(text: name),
       codeController = TextEditingController(text: code),
       displayNameController = TextEditingController(text: displayName),
       children = children ?? <_NodeDraft>[];

  final int? id;
  final ItemVariationNodeKind kind;
  _NodeDraft? parent;
  final TextEditingController nameController;
  final TextEditingController codeController;
  final TextEditingController displayNameController;
  bool detailsExpanded;
  bool isNameEditing;
  bool displayNameTouched;
  String inputType;
  bool inheritedFromGroup = false;
  bool inheritedMandatory = false;
  String? inheritedPropertyKey;
  int? inheritedSourceGroupId;
  String? inheritedSourceGroupName;

  final List<_NodeDraft> children;

  bool get isLeafValue =>
      kind == ItemVariationNodeKind.value && children.isEmpty;

  bool get isLockedInheritedProperty =>
      inheritedFromGroup && kind == ItemVariationNodeKind.property;

  void dispose() {
    nameController.dispose();
    codeController.dispose();
    displayNameController.dispose();
    for (final child in children) {
      child.dispose();
    }
  }
}

class _UnitConversionDraft {
  _UnitConversionDraft({required this.unitId, double unitsPerPrimary = 1})
    : factorController = TextEditingController(
        text: _formatUnitConversionFactor(unitsPerPrimary),
      );

  final int unitId;
  final TextEditingController factorController;

  double get unitsPerPrimary =>
      double.tryParse(factorController.text.trim()) ?? 1.0;

  void dispose() {
    factorController.dispose();
  }
}

String _formatUnitConversionFactor(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toString();
}

class _ItemEditorSheet extends StatefulWidget {
  const _ItemEditorSheet({
    this.item,
    this.initialName = '',
    this.initialGroupId,
    this.onCreatePipeline,
  });

  final ItemDefinition? item;
  final String initialName;
  final int? initialGroupId;
  final Future<String?> Function()? onCreatePipeline;

  @override
  State<_ItemEditorSheet> createState() => _ItemEditorSheetState();
}

class _ItemEditorSheetState extends State<_ItemEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _aliasController;
  late final TextEditingController _displayNameController;
  late final TextEditingController _photoUrlController;
  final List<_NodeDraft> _rootNodes = [];
  final ScrollController _variationTreeScrollController = ScrollController();
  int? _selectedGroupId;
  int? _selectedUnitId;
  bool _displayNameTouched = false;
  bool _syncingDisplayName = false;
  List<String> _namingFormat = [];
  final Set<String> _excludedNamingTokens = <String>{};
  String? _localError;
  final List<_UnitConversionDraft> _secondaryUnitConversions = [];
  final Set<String> _promotedPropertyKeys = <String>{};
  bool _isLoadingGroupSchema = false;
  String? _defaultPipelineId;
  List<Map<String, String>> _availablePipelines = [];
  bool _availableForPurchase = false;

  bool get _isReadOnly => false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.item?.name ?? widget.initialName,
    );
    _aliasController = TextEditingController(text: widget.item?.alias ?? '');
    _displayNameController = TextEditingController(
      text: widget.item?.displayName ?? '',
    );
    _photoUrlController = TextEditingController(
      text: widget.item?.photoUrl ?? '',
    );
    _selectedGroupId = widget.item?.groupId ?? widget.initialGroupId;
    _selectedUnitId = widget.item?.unitId;
    _namingFormat = widget.item?.namingFormat.toList() ?? [];
    _defaultPipelineId = widget.item?.defaultPipelineId;
    _availableForPurchase = widget.item?.availableForPurchase ?? false;
    _displayNameTouched = (widget.item?.displayName ?? '').trim().isNotEmpty;

    _nameController.addListener(_handlePrimaryChange);
    _aliasController.addListener(_handlePrimaryChange);
    _displayNameController.addListener(() {
      if (_syncingDisplayName) {
        return;
      }
      _displayNameTouched = true;
      _handleChange();
    });

    for (final node
        in widget.item?.variationTree ??
            const <ItemVariationNodeDefinition>[]) {
      _rootNodes.add(_draftFromNode(node, null));
    }
    _hydrateExistingGroupBackedNodes();

    final savedTokens = widget.item?.namingFormat ?? [];
    if (widget.item != null) {
      final available = _availableNamingTokens;
      _excludedNamingTokens.addAll(
        available.where((t) => !savedTokens.contains(t)),
      );
    }
    _fetchPipelines();
    for (final conversion in widget.item?.unitConversions ?? const []) {
      final unit = context.read<UnitsProvider>().findById(conversion.unitId);
      final factorToV = conversion.factorToPrimary <= 0
          ? 1.0
          : 1.0 / conversion.factorToPrimary;
      final factorToB = factorToV * (unit?.conversionFactor ?? 1.0);
      final draft = _UnitConversionDraft(
        unitId: conversion.unitId,
        unitsPerPrimary: factorToB,
      );
      draft.factorController.addListener(_handleChange);
      _secondaryUnitConversions.add(draft);
    }

    _syncPrimaryDisplayName();
    _syncLeafDisplayNames();
    if (_selectedGroupId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadInheritedSchemaForGroup(_selectedGroupId!);
      });
    }
  }

  _NodeDraft _draftFromNode(
    ItemVariationNodeDefinition node,
    _NodeDraft? parent,
  ) {
    String inputType = 'Text';
    if (node.kind == ItemVariationNodeKind.property) {
      final key = _propertyKey(node.name);
      final schemaEntry = widget.item?.propertySchema
          .where((e) => _propertyKey(e.propertyKey) == key)
          .firstOrNull;
      inputType = schemaEntry?.inputType ?? 'Text';
    }

    final draft = _NodeDraft(
      id: node.id,
      kind: node.kind,
      parent: parent,
      name: node.name,
      code: node.code,
      displayName: node.displayName,
      detailsExpanded: false,
      isNameEditing: false,
      displayNameTouched: node.displayName.trim().isNotEmpty,
      inputType: inputType,
    );
    draft.nameController.addListener(() {
      _syncLeafDisplayNames();
      _handleChange();
    });
    draft.codeController.addListener(() {
      _syncLeafDisplayNames();
      _handleChange();
    });
    draft.displayNameController.addListener(() {
      if (_syncingDisplayName) {
        return;
      }
      draft.displayNameTouched = true;
      _handleChange();
    });
    for (final child in node.children) {
      draft.children.add(_draftFromNode(child, draft));
    }
    return draft;
  }

  _NodeDraft _newDraft(ItemVariationNodeKind kind, _NodeDraft? parent) {
    final draft = _NodeDraft(
      kind: kind,
      parent: parent,
      detailsExpanded: false,
      isNameEditing: false,
    );
    draft.nameController.addListener(() {
      _syncLeafDisplayNames();
      _handleChange();
    });
    draft.codeController.addListener(() {
      _syncLeafDisplayNames();
      _handleChange();
    });
    draft.displayNameController.addListener(() {
      if (_syncingDisplayName) {
        return;
      }
      draft.displayNameTouched = true;
      _handleChange();
    });
    return draft;
  }

  void _handlePrimaryChange() {
    _syncPrimaryDisplayName();
    _handleChange();
  }

  void _handleChange() {
    if (mounted) {
      setState(() {});
    }
  }

  List<int> get _orderedUnitIds => [
    ...?(_selectedUnitId == null ? null : <int>[_selectedUnitId!]),
    ..._secondaryUnitConversions.map((draft) => draft.unitId),
  ];

  bool _isDerived(int unitId) {
    if (_selectedUnitId == null) return false;
    final unitsProvider = context.read<UnitsProvider>();
    final unit = unitsProvider.findById(unitId);
    if (unit == null || unit.unitGroupId == null) return false;

    for (final id in _orderedUnitIds) {
      if (id == unitId) return false;
      final other = unitsProvider.findById(id);
      if (other != null && other.unitGroupId == unit.unitGroupId) {
        return true;
      }
    }
    return false;
  }

  double _getDerivedUnitsPerPrimary(int unitId) {
    if (_selectedUnitId == null) return 1.0;
    final unitsProvider = context.read<UnitsProvider>();
    final unit = unitsProvider.findById(unitId);
    if (unit == null) return 1.0;

    final primaryUnit = unitsProvider.findById(_selectedUnitId);
    if (primaryUnit?.unitGroupId != null &&
        primaryUnit!.unitGroupId == unit.unitGroupId) {
      final factorToB = primaryUnit.conversionFactor;
      return factorToB / unit.conversionFactor;
    }

    int? representativeId;
    if (unit.unitGroupId != null) {
      for (final id in _orderedUnitIds.skip(1)) {
        final other = unitsProvider.findById(id);
        if (other != null && other.unitGroupId == unit.unitGroupId) {
          representativeId = id;
          break;
        }
      }
    }

    if (representativeId == null) {
      _UnitConversionDraft? draft;
      for (final d in _secondaryUnitConversions) {
        if (d.unitId == unitId) {
          draft = d;
          break;
        }
      }
      return draft?.unitsPerPrimary ?? 1.0;
    }

    _UnitConversionDraft? repDraft;
    for (final d in _secondaryUnitConversions) {
      if (d.unitId == representativeId) {
        repDraft = d;
        break;
      }
    }
    final factorToB = repDraft?.unitsPerPrimary ?? 1.0;
    return factorToB / unit.conversionFactor;
  }

  void _rebuildUnitOrderFrom(
    List<int> orderedUnitIds,
    Map<int, double> unitsPerOldPrimary,
  ) {
    for (final draft in _secondaryUnitConversions) {
      draft.dispose();
    }
    _secondaryUnitConversions.clear();
    _selectedUnitId = orderedUnitIds.isEmpty ? null : orderedUnitIds.first;
    if (_selectedUnitId == null) {
      return;
    }
    final newPrimaryUnitsPerOldPrimary =
        unitsPerOldPrimary[_selectedUnitId!] ?? 1;
    for (final unitId in orderedUnitIds.skip(1)) {
      final unit = context.read<UnitsProvider>().findById(unitId);
      final factorToV =
          (unitsPerOldPrimary[unitId] ?? 1) / newPrimaryUnitsPerOldPrimary;
      final factorToB = factorToV * (unit?.conversionFactor ?? 1.0);
      final draft = _UnitConversionDraft(
        unitId: unitId,
        unitsPerPrimary: factorToB,
      );
      draft.factorController.addListener(_handleChange);
      _secondaryUnitConversions.add(draft);
    }
  }

  void _reorderUnits(int oldIndex, int newIndex) {
    final orderedUnitIds = _orderedUnitIds.toList(growable: true);
    if (orderedUnitIds.length < 2) {
      return;
    }
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    if (oldIndex < 0 ||
        oldIndex >= orderedUnitIds.length ||
        newIndex < 0 ||
        newIndex >= orderedUnitIds.length) {
      return;
    }
    final unitsPerOldPrimary = <int, double>{
      ...?(_selectedUnitId == null ? null : <int, double>{_selectedUnitId!: 1}),
      for (final draft in _secondaryUnitConversions)
        draft.unitId: _getDerivedUnitsPerPrimary(draft.unitId),
    };
    final moved = orderedUnitIds.removeAt(oldIndex);
    orderedUnitIds.insert(newIndex, moved);
    _rebuildUnitOrderFrom(orderedUnitIds, unitsPerOldPrimary);
  }

  String _propertyKey(String value) => value.trim().toLowerCase();

  String _propertyKeyForNode(_NodeDraft node) =>
      _propertyKey(node.inheritedPropertyKey ?? node.nameController.text);

  void _hydrateExistingGroupBackedNodes() {
    for (final node in _rootNodes) {
      if (node.kind != ItemVariationNodeKind.property) {
        continue;
      }
      final schemaEntry = _propertySchemaForNode(node);
      if (schemaEntry == null || schemaEntry.sourceType != 'inherited_group') {
        continue;
      }
      node.inheritedFromGroup = true;
      node.inheritedMandatory = schemaEntry.mandatory;
      node.inheritedPropertyKey = schemaEntry.propertyKey;
      node.inheritedSourceGroupId = schemaEntry.sourceGroupId;
      node.inheritedSourceGroupName = schemaEntry.sourceGroupName;
    }
  }

  void _resetInheritedFlags() {
    for (final node in _rootNodes) {
      if (node.kind != ItemVariationNodeKind.property) {
        continue;
      }
      node.inheritedFromGroup = false;
      node.inheritedMandatory = false;
      node.inheritedPropertyKey = null;
      node.inheritedSourceGroupId = null;
      node.inheritedSourceGroupName = null;
    }
  }

  void _applyEffectiveSchemaToRootNodes(
    List<governance.GroupPropertyDraft> propertyDrafts,
  ) {
    _resetInheritedFlags();
    final draftsByKey = <String, governance.GroupPropertyDraft>{
      for (final draft in propertyDrafts)
        _propertyKey(draft.propertyKey ?? draft.name): draft,
    };
    final matchedKeys = <String>{};
    for (final node in _rootNodes) {
      if (node.kind != ItemVariationNodeKind.property) {
        continue;
      }
      final key = _propertyKeyForNode(node);
      final draft = draftsByKey[key];
      if (draft == null) {
        continue;
      }
      matchedKeys.add(key);
      node.inheritedFromGroup = true;
      node.inheritedMandatory = draft.mandatory;
      node.inheritedPropertyKey = draft.propertyKey ?? key;
      node.inheritedSourceGroupId = draft.sourceGroupId;
      node.inheritedSourceGroupName = draft.sourceGroupName;
      if (node.nameController.text.trim().isEmpty) {
        node.nameController.text = draft.name;
      }
    }
    for (final entry in draftsByKey.entries) {
      if (matchedKeys.contains(entry.key)) {
        continue;
      }
      final node = _newDraft(ItemVariationNodeKind.property, null);
      node.nameController.text = entry.value.name;
      node.inheritedFromGroup = true;
      node.inheritedMandatory = entry.value.mandatory;
      node.inheritedPropertyKey = entry.value.propertyKey ?? entry.key;
      node.inheritedSourceGroupId = entry.value.sourceGroupId;
      node.inheritedSourceGroupName = entry.value.sourceGroupName;
      _rootNodes.add(node);
    }
  }

  Future<void> _loadInheritedSchemaForGroup(int groupId) async {
    setState(() {
      _isLoadingGroupSchema = true;
      _localError = null;
    });
    final schema = await context.read<InventoryProvider>().loadEffectiveSchema(
      groupId,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoadingGroupSchema = false;
      if (schema != null) {
        _applyEffectiveSchemaToRootNodes(schema.propertyDrafts);
      }
    });
  }

  Future<void> _handleGroupChanged(int? value) async {
    // Seed the item's unit from the group's unit (alongside properties).
    final groupUnitId = value == null
        ? null
        : context.read<GroupsProvider>().findById(value)?.unitId;
    setState(() {
      _selectedGroupId = value;
      _localError = null;
      // The group's unit is only a default suggestion, not a lock: seed it
      // when the item has no unit yet, but never override a unit the user has
      // already chosen (or deliberately cleared mid-edit).
      if (groupUnitId != null && _selectedUnitId == null) {
        _selectedUnitId = groupUnitId;
      }
    });
    if (value == null) {
      setState(_resetInheritedFlags);
      return;
    }
    await _loadInheritedSchemaForGroup(value);
  }

  bool _isMandatoryInheritedPropertySatisfied(_NodeDraft node) {
    if (!node.inheritedFromGroup || !node.inheritedMandatory) {
      return true;
    }
    for (final child in node.children) {
      if (child.kind == ItemVariationNodeKind.value &&
          child.nameController.text.trim().isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  String _groupInventoryBarcode(int groupId) {
    final linked = context
        .read<InventoryProvider>()
        .materials
        .where((record) => record.linkedGroupId == groupId)
        .firstOrNull;
    return linked?.barcode ?? 'GROUP-MASTER-$groupId';
  }

  ItemPropertySchemaEntry? _propertySchemaForNode(_NodeDraft node) {
    final key = _propertyKeyForNode(node);
    if (key.isEmpty) {
      return null;
    }
    return widget.item?.propertySchema
        .where((entry) => _propertyKey(entry.propertyKey) == key)
        .firstOrNull;
  }

  List<_TreeMetaPillSpec> _propertyMetaPillsForNode(_NodeDraft node) {
    if (node.kind != ItemVariationNodeKind.property) {
      return const <_TreeMetaPillSpec>[];
    }
    final propertyKey = _propertyKey(node.nameController.text);
    final schemaEntry = _propertySchemaForNode(node);
    final pills = <_TreeMetaPillSpec>[];
    if (node.inheritedFromGroup) {
      pills.add(
        const _TreeMetaPillSpec(
          label: 'Group schema',
          tone: _TreeMetaPillTone.inherited,
        ),
      );
      if (node.inheritedMandatory) {
        pills.add(
          const _TreeMetaPillSpec(
            label: 'Required',
            tone: _TreeMetaPillTone.required,
          ),
        );
      }
    } else if (schemaEntry != null) {
      switch (schemaEntry.sourceType) {
        case 'inherited_group':
          pills.add(
            _TreeMetaPillSpec(
              label: 'Group schema',
              tone: _TreeMetaPillTone.inherited,
            ),
          );
        case 'inherited_item':
          pills.add(
            _TreeMetaPillSpec(
              label: 'Inherited',
              tone: _TreeMetaPillTone.seeded,
            ),
          );
        default:
          pills.add(
            _TreeMetaPillSpec(
              label: 'Item local',
              tone: _TreeMetaPillTone.manual,
            ),
          );
      }
    } else {
      pills.add(
        _TreeMetaPillSpec(label: 'Item local', tone: _TreeMetaPillTone.manual),
      );
    }
    if (_promotedPropertyKeys.contains(propertyKey) &&
        !node.inheritedFromGroup &&
        schemaEntry?.sourceType != 'inherited_group') {
      pills.add(
        _TreeMetaPillSpec(label: 'Promoted', tone: _TreeMetaPillTone.promoted),
      );
    }
    return pills;
  }

  Future<void> _promotePropertyToGroup(_NodeDraft node) async {
    final groupId = _selectedGroupId;
    final propertyName = node.nameController.text.trim();
    if (groupId == null) {
      setState(() {
        _localError = 'Select a group before promoting a property.';
      });
      return;
    }
    if (node.kind != ItemVariationNodeKind.property || propertyName.isEmpty) {
      return;
    }
    final inventoryProvider = context.read<InventoryProvider>();
    final groupsProvider = context.read<GroupsProvider>();
    final itemsProvider = context.read<ItemsProvider>();
    final barcode = _groupInventoryBarcode(groupId);
    final configuration = await inventoryProvider.loadGroupConfiguration(
      barcode,
    );
    if (!mounted || configuration == null) {
      return;
    }
    final propertyKey = _propertyKey(propertyName);
    final schemaEntry = _propertySchemaForNode(node);
    final group = groupsProvider.findById(groupId);
    final nextDraft = governance.GroupPropertyDraft(
      name: propertyName,
      propertyKey: propertyKey,
      inputType: schemaEntry?.inputType ?? 'Text',
      mandatory: schemaEntry?.mandatory ?? false,
      unitId: schemaEntry?.unitId,
      unitSymbol: schemaEntry?.unitSymbol,
      unitLabel: schemaEntry?.unitLabel,
      sourceType: governance.GroupPropertySourceType.manual,
      state: governance.GroupPropertyState.active,
      sourceGroupId: groupId,
      sourceGroupName: group?.name,
    );
    final nextDrafts = [
      ...configuration.propertyDrafts.where(
        (draft) => _propertyKey(draft.propertyKey ?? draft.name) != propertyKey,
      ),
      nextDraft,
    ];
    final nextDiscarded = configuration.discardedPropertyKeys
        .where((key) => _propertyKey(key) != propertyKey)
        .toList(growable: false);
    await inventoryProvider.updateGroupConfiguration(
      barcode,
      inheritanceEnabled: configuration.inheritanceEnabled,
      selectedItemIds: configuration.selectedItemIds,
      propertyDrafts: nextDrafts,
      unitGovernance: configuration.unitGovernance,
      uiPreferences: configuration.uiPreferences,
      discardedPropertyKeys: nextDiscarded,
    );
    if (!mounted) {
      return;
    }
    if (inventoryProvider.errorMessage == null) {
      setState(() {
        _promotedPropertyKeys.add(propertyKey);
      });
      await groupsProvider.refresh();
      await itemsProvider.refresh();
      if (!mounted) {
        return;
      }
      showAppSnack(
        SnackBar(content: Text('Promoted "$propertyName" to group schema.')),
      );
    }
  }

  void _syncPrimaryDisplayName() {
    if (_displayNameTouched) {
      return;
    }
    final generated = _generateItemDisplayName(
      _nameController.text,
      _aliasController.text,
    );
    if (_displayNameController.text != generated) {
      _syncingDisplayName = true;
      _displayNameController.text = generated;
      _displayNameController.selection = TextSelection.collapsed(
        offset: _displayNameController.text.length,
      );
      _syncingDisplayName = false;
    }
  }

  void _syncLeafDisplayNames() {
    void visit(_NodeDraft node) {
      if (node.isLeafValue && !node.displayNameTouched) {
        final generated = _generateLeafDisplayName(node);
        if (node.displayNameController.text != generated) {
          _syncingDisplayName = true;
          node.displayNameController.text = generated;
          node.displayNameController.selection = TextSelection.collapsed(
            offset: node.displayNameController.text.length,
          );
          _syncingDisplayName = false;
        }
      }
      for (final child in node.children) {
        visit(child);
      }
    }

    for (final node in _rootNodes) {
      visit(node);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _aliasController.dispose();
    _displayNameController.dispose();
    _photoUrlController.dispose();
    _variationTreeScrollController.dispose();
    for (final node in _rootNodes) {
      node.dispose();
    }
    for (final conv in _secondaryUnitConversions) {
      conv.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final itemsProvider = context.watch<ItemsProvider>();
    final groupsProvider = context.watch<GroupsProvider>();
    final unitsProvider = context.watch<UnitsProvider>();
    final duplicate = itemsProvider.checkDuplicate(
      name: _nameController.text,
      groupId: _selectedGroupId,
      unitId: _selectedUnitId,
      variationTree: _variationTreeInputs,
      excludeId: widget.item?.id,
    );
    final availableGroups = groupsProvider.itemGroups
        .where((g) => !g.isArchived)
        .toList(growable: false);
    final selectedGroup = groupsProvider.findById(_selectedGroupId);
    final availableUnits = unitsProvider.units
        .where((u) => !u.isArchived)
        .toList(growable: false);
    final selectedUnit = availableUnits
        .where((unit) => unit.id == _selectedUnitId)
        .firstOrNull;
    final primaryUnitSymbol = selectedUnit?.symbol ?? selectedUnit?.name ?? '';
    final alreadySelectedUnitIds = {
      ...(_selectedUnitId == null ? const <int>[] : <int>[_selectedUnitId!]),
      ..._secondaryUnitConversions.map((c) => c.unitId),
    };
    final addableUnits = unitsProvider.units
        .where((u) => !u.isArchived && !alreadySelectedUnitIds.contains(u.id))
        .toList(growable: false);
    final detailsSection = _SectionCard(
      title: 'Item Details',
      child: Column(
        children: [
          _formRow(
            children: [
              _responsiveFieldPair(
                first: _buildTextField(
                  controller: _nameController,
                  label: 'Base Name',
                  helper: 'Base commercial item name',
                  readOnly: _isReadOnly,
                ),
                second: _buildTextField(
                  controller: _aliasController,
                  label: 'Alias',
                  helper: 'Optional alternate label',
                  readOnly: _isReadOnly,
                  required: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _formRow(
            children: [
              _buildTextField(
                controller: _displayNameController,
                label: 'Item Name',
                helper: 'Editable generated label',
                readOnly: _isReadOnly,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _formRow(
            children: [
              SearchableSelectField<int>(
                tapTargetKey: const ValueKey<String>('items-group-field'),
                value:
                    availableGroups.any((group) => group.id == _selectedGroupId)
                    ? _selectedGroupId
                    : selectedGroup?.id,
                decoration: _fieldDecoration(
                  label: 'Group',
                  helper: 'Use the group to classify the item.',
                ),
                dialogTitle: 'Group',
                searchHintText: 'Search group',
                fieldEnabled: !_isReadOnly,
                onCreateOption: (query) async {
                  final created = await GroupsScreen.openEditor(
                    context,
                    initialName: query,
                  );
                  if (!context.mounted || created == null) {
                    return null;
                  }
                  await context.read<GroupsProvider>().refresh();
                  if (!context.mounted) {
                    return null;
                  }
                  final refreshedGroupsProvider = context
                      .read<GroupsProvider>();
                  await _handleGroupChanged(created.id);
                  return SearchableSelectOption<int>(
                    value: created.id,
                    label: _groupOptionLabel(created, refreshedGroupsProvider),
                    searchText: _groupOptionSearchText(
                      created,
                      refreshedGroupsProvider,
                    ),
                  );
                },
                createOptionLabelBuilder: (query) => 'Create group "$query"',
                options: [
                  ...availableGroups.map(
                    (group) => SearchableSelectOption<int>(
                      value: group.id,
                      label: _groupOptionLabel(group, groupsProvider),
                      searchText: _groupOptionSearchText(group, groupsProvider),
                    ),
                  ),
                ],
                onChanged: (value) => _handleGroupChanged(value),
                validator: (value) => value == null ? 'Required' : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _formRow(
            children: [
              SearchableSelectField<int>(
                tapTargetKey: const ValueKey<String>('items-unit-field'),
                value: null,
                decoration: _fieldDecoration(
                  label: selectedUnit == null ? 'Unit' : 'Add another unit',
                  helper:
                      'Select units for this item. Each selection appears below.',
                ),
                dialogTitle: selectedUnit == null ? 'Unit' : 'Add another unit',
                searchHintText: 'Search unit',
                fieldEnabled: !_isReadOnly,
                onCreateOption: (query) async {
                  final created = await UnitsScreen.openEditor(
                    context,
                    initialName: query,
                  );
                  if (!context.mounted || created == null) {
                    return null;
                  }
                  await context.read<UnitsProvider>().refresh();
                  if (!context.mounted) {
                    return null;
                  }
                  setState(() {
                    _localError = null;
                  });
                  return SearchableSelectOption<int>(
                    value: created.id,
                    label: created.displayLabel,
                  );
                },
                createOptionLabelBuilder: (query) => 'Create unit "$query"',
                options: [
                  ...addableUnits.map(
                    (unit) => SearchableSelectOption<int>(
                      value: unit.id,
                      label: unit.displayLabel,
                    ),
                  ),
                ],
                onChanged: (value) => setState(() {
                  if (value == null) {
                    return;
                  }
                  _localError = null;
                  if (_selectedUnitId == null) {
                    _selectedUnitId = value;
                    return;
                  }
                  final primary = unitsProvider.primaryUnit;
                  if (primary != null && _selectedUnitId == primary.id) {
                    _selectedUnitId = value;
                    return;
                  }
                  final exists = _secondaryUnitConversions.any(
                    (draft) => draft.unitId == value,
                  );
                  if (exists || value == _selectedUnitId) {
                    return;
                  }
                  final draft = _UnitConversionDraft(unitId: value);
                  draft.factorController.addListener(_handleChange);
                  _secondaryUnitConversions.add(draft);
                }),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (selectedUnit != null)
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                height: 54,
                child: ReorderableListView.builder(
                  scrollDirection: Axis.horizontal,
                  buildDefaultDragHandles: false,
                  shrinkWrap: true,
                  proxyDecorator: (child, index, animation) {
                    return Material(color: Colors.transparent, child: child);
                  },
                  itemCount: _orderedUnitIds.length,
                  onReorder: _isReadOnly
                      ? (oldIndex, newIndex) {}
                      : (oldIndex, newIndex) =>
                            setState(() => _reorderUnits(oldIndex, newIndex)),
                  itemBuilder: (context, index) {
                    final unitId = _orderedUnitIds[index];
                    final unit = unitsProvider.findById(unitId);
                    return Padding(
                      key: ValueKey<String>('unit-bubble-$unitId'),
                      padding: EdgeInsets.only(
                        right: index == _orderedUnitIds.length - 1 ? 0 : 10,
                      ),
                      child: ReorderableDragStartListener(
                        index: index,
                        enabled: !_isReadOnly,
                        child: _UnitSelectionBubble(
                          label: unit?.displayLabel ?? 'Unit #$unitId',
                          showDragHandle: !_isReadOnly,
                          onRemove: _isReadOnly
                              ? null
                              : () => setState(() {
                                  if (unitId == _selectedUnitId) {
                                    _selectedUnitId = null;
                                    for (final draft
                                        in _secondaryUnitConversions) {
                                      draft.dispose();
                                    }
                                    _secondaryUnitConversions.clear();
                                    return;
                                  }
                                  final draft = _secondaryUnitConversions
                                      .firstWhere(
                                        (entry) => entry.unitId == unitId,
                                      );
                                  _secondaryUnitConversions.remove(draft);
                                  draft.dispose();
                                }),
                        ),
                      ),
                    );
                  },
                ),
              ),
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Select a unit first.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey[400]),
              ),
            ),
          if (selectedUnit != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Arrange the unit bubbles to choose the base unit. Define how 1 ${selectedUnit.displayLabel} converts to the units on the right.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
              ),
            ),
          ],
          if (_isLoadingGroupSchema) ...[
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ],
          if (_secondaryUnitConversions.isNotEmpty &&
              _secondaryUnitConversions.any((d) => !_isDerived(d.unitId))) ...[
            const SizedBox(height: 12),
            for (var i = 0; i < _secondaryUnitConversions.length; i++) ...[
              if (!_isDerived(_secondaryUnitConversions[i].unitId)) ...[
                Builder(
                  builder: (context) {
                    final draft = _secondaryUnitConversions[i];
                    final unit = unitsProvider.findById(draft.unitId);

                    var displayUnit = unit;
                    if (unit?.unitGroupId != null) {
                      for (final u in unitsProvider.units) {
                        if (u.unitGroupId == unit!.unitGroupId &&
                            u.isBaseUnit) {
                          displayUnit = u;
                          break;
                        }
                      }
                    }

                    return _UnitConversionRow(
                      draft: draft,
                      baseUnitSymbol: primaryUnitSymbol,
                      unitLabel: displayUnit?.displayLabel ?? '?',
                      unitSymbol: displayUnit?.symbol ?? '?',
                      unitGroupName: displayUnit?.unitGroupName,
                      onRemove: () => setState(() {
                        _secondaryUnitConversions.removeAt(i).dispose();
                      }),
                    );
                  },
                ),
                if (_secondaryUnitConversions
                    .skip(i + 1)
                    .any((d) => !_isDerived(d.unitId)))
                  const SizedBox(height: 8),
              ],
            ],
          ],
          if (_secondaryUnitConversions.isNotEmpty &&
              primaryUnitSymbol == '-') ...[
            const SizedBox(height: 12),
            Text(
              'Warning: You are mapping a conversion to the system default Primary Unit (-). '
              'The Primary Unit serves as an unquantified baseline placeholder. '
              'Establishing fixed conversion ratios against it can severely impact inventory valuation, yield reporting, and downstream production accounting.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFFB45309),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 12),
          _WarningText(warning: duplicate.warning),
          // Compact, flag-gated: adds no height for clients without the flag.
          if (FeatureFlags.isEnabled(FeatureKeys.catalogPurchaseItems))
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _availableForPurchase,
              onChanged: _isReadOnly
                  ? null
                  : (value) => setState(() {
                      _availableForPurchase = value;
                      _handleChange();
                    }),
              title: const Text(
                'Available for purchase',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
        ],
      ),
    );
    final photoSection = _SectionCard(
      title: 'Item Photo',
      child: _ItemPhotoPickerField(
        controller: _photoUrlController,
        readOnly: _isReadOnly,
      ),
    );
    final variationTreeSection = _SectionCard(
      title: 'Variation Tree',
      action: _isReadOnly
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppButton(
                  label: 'Add Top-Level Property',
                  icon: Icons.add,
                  variant: AppButtonVariant.secondary,
                  onPressed: _addTopLevelProperty,
                ),
                const SizedBox(width: 8),
                AppButton(
                  label: 'Variation Creation',
                  icon: Icons.account_tree_outlined,
                  variant: AppButtonVariant.secondary,
                  onPressed: _openVariationCreationDialog,
                ),
              ],
            ),
      child: _rootNodes.isEmpty
          ? const _ItemsMessageBanner(
              message:
                  'Start your variation tree with a property like Color, Size, or Material.',
              isError: false,
            )
          : Container(
              constraints: const BoxConstraints(maxHeight: 460),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFDCE2F0)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Scrollbar(
                controller: _variationTreeScrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _variationTreeScrollController,
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
                      for (
                        var index = 0;
                        index < _rootNodes.length;
                        index++
                      ) ...[
                        _TreeNodeEditor(
                          draft: _rootNodes[index],
                          depth: 0,
                          readOnly: _isReadOnly,
                          summaryLabel: _summaryLabelForNode(_rootNodes[index]),
                          metaPills: _propertyMetaPillsForNode(
                            _rootNodes[index],
                          ),
                          onToggleBranch: () =>
                              _toggleNodeDetails(_rootNodes[index]),
                          onEnableNameEditing:
                              _rootNodes[index].isLockedInheritedProperty
                              ? null
                              : () => _setNodeNameEditing(
                                  _rootNodes[index],
                                  true,
                                ),
                          onFinishNameEditing:
                              _rootNodes[index].isLockedInheritedProperty
                              ? null
                              : () => _setNodeNameEditing(
                                  _rootNodes[index],
                                  false,
                                ),
                          onAddProperty:
                              _rootNodes[index].kind ==
                                      ItemVariationNodeKind.value ||
                                  (_rootNodes[index].kind ==
                                          ItemVariationNodeKind.property &&
                                      !_rootNodes[index].children.any(
                                        (c) =>
                                            c.kind ==
                                            ItemVariationNodeKind.value,
                                      ))
                              ? () => _addChildProperty(_rootNodes[index])
                              : null,
                          onPromoteToGroup:
                              _rootNodes[index].kind ==
                                      ItemVariationNodeKind.property &&
                                  _selectedGroupId != null &&
                                  !_isReadOnly &&
                                  !_rootNodes[index].isLockedInheritedProperty
                              ? () => _promotePropertyToGroup(_rootNodes[index])
                              : null,
                          onAddValue:
                              _rootNodes[index].kind ==
                                      ItemVariationNodeKind.property &&
                                  !_rootNodes[index].children.any(
                                    (c) =>
                                        c.kind ==
                                        ItemVariationNodeKind.property,
                                  )
                              ? () => _addChildValue(_rootNodes[index])
                              : null,
                          onMoveUp: index == 0
                              ? null
                              : () => _moveNode(_rootNodes, index, index - 1),
                          onMoveDown: index == _rootNodes.length - 1
                              ? null
                              : () => _moveNode(_rootNodes, index, index + 1),
                          onRemove: () => _removeNode(_rootNodes, index),
                          buildChildEditor: _buildChildEditor,
                        ),
                        if (index != _rootNodes.length - 1)
                          const SizedBox(height: 4),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AppSectionTitle(
                          title: widget.item == null
                              ? 'Create Item'
                              : _isReadOnly
                              ? 'View Item'
                              : 'Edit Item',
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  if (_localError != null) ...[
                    const SizedBox(height: 12),
                    _ItemsMessageBanner(message: _localError!, isError: true),
                  ],
                  if (itemsProvider.errorMessage != null &&
                      !itemsProvider.isSaving) ...[
                    const SizedBox(height: 12),
                    _ItemsMessageBanner(
                      message: itemsProvider.errorMessage!,
                      isError: true,
                    ),
                  ],
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wideComposer = constraints.maxWidth >= 1140;

                      final namingFormatSection = _SectionCard(
                        title: 'Naming Format',
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFFDCE2F0)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Drag and drop properties to set the variation display name sequence. Drag blocks to the trash zone or click "x" to exclude them.',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: Colors.grey[600]),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Text(
                                    'Display Format: ',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  DropdownButton<String>(
                                    value:
                                        _namingFormat.contains(
                                          '__format:detailed',
                                        )
                                        ? 'detailed'
                                        : _namingFormat.contains(
                                            '__format:dimensions',
                                          )
                                        ? 'dimensions'
                                        : 'default',
                                    isDense: true,
                                    underline: const SizedBox.shrink(),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'default',
                                        child: Text('Default (Val1 Val2)'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'detailed',
                                        child: Text('Detailed (Prop: Val)'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'dimensions',
                                        child: Text('Dimensions (Val1 x Val2)'),
                                      ),
                                    ],
                                    onChanged: _isReadOnly
                                        ? null
                                        : (val) {
                                            setState(() {
                                              _namingFormat.removeWhere(
                                                (t) =>
                                                    t.startsWith('__format:'),
                                              );
                                              if (val != 'default' &&
                                                  val != null) {
                                                _namingFormat.add(
                                                  '__format:$val',
                                                );
                                              }
                                              _handleChange();
                                            });
                                          },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _buildActiveNamingFormatArea(context),
                              _buildInactiveNamingFormatArea(context),
                            ],
                          ),
                        ),
                      );

                      final isRawMaterialGroup =
                          selectedGroup?.name.toLowerCase().contains(
                            'raw material',
                          ) ==
                          true;

                      final defaultPipelineSection = _SectionCard(
                        title: 'Default Pipeline',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SearchableSelectField<String>(
                              options: _availablePipelines
                                  .map(
                                    (p) => SearchableSelectOption<String>(
                                      value: p['id']!,
                                      label: p['name']!,
                                      searchText: p['name']!,
                                    ),
                                  )
                                  .toList(),
                              value: _defaultPipelineId,
                              fieldEnabled: !_isReadOnly,
                              onChanged: (val) {
                                setState(() {
                                  _defaultPipelineId = val;
                                  _handleChange();
                                });
                              },
                              decoration: const InputDecoration(
                                hintText: 'Select a pipeline',
                              ),
                              searchHintText: 'Search pipelines',
                            ),
                            if (!_isReadOnly &&
                                widget.onCreatePipeline != null) ...[
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  if (widget.onCreatePipeline != null) {
                                    final newPipelineId =
                                        await widget.onCreatePipeline!();
                                    if (mounted) {
                                      await _fetchPipelines();
                                      if (newPipelineId != null) {
                                        setState(() {
                                          _defaultPipelineId = newPipelineId;
                                          _handleChange();
                                        });
                                      }
                                    }
                                  }
                                },
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('Create New Pipeline'),
                              ),
                            ],
                          ],
                        ),
                      );

                      if (wideComposer) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 5,
                              child: Column(
                                children: [
                                  detailsSection,
                                  const SizedBox(height: 16),
                                  photoSection,
                                ],
                              ),
                            ),
                            const SizedBox(width: 18),
                            Expanded(
                              flex: 6,
                              child: Column(
                                children: [
                                  variationTreeSection,
                                  const SizedBox(height: 16),
                                  namingFormatSection,
                                  if (!isRawMaterialGroup) ...[
                                    const SizedBox(height: 16),
                                    defaultPipelineSection,
                                  ],
                                ],
                              ),
                            ),
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          detailsSection,
                          const SizedBox(height: 16),
                          photoSection,
                          const SizedBox(height: 16),
                          variationTreeSection,
                          const SizedBox(height: 16),
                          namingFormatSection,
                          if (!isRawMaterialGroup) ...[
                            const SizedBox(height: 16),
                            defaultPipelineSection,
                          ],
                        ],
                      );
                    },
                  ),
                  if (widget.item != null) ...[
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: 'Track',
                      child: TrackPanel.entity(
                        entityType: 'items',
                        entityId: '${widget.item!.id}',
                        showHeader: false,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (!_isReadOnly)
                        AppButton(
                          label: widget.item == null
                              ? 'Create Item'
                              : 'Save Changes',
                          isLoading: itemsProvider.isSaving,
                          onPressed: () => _submit(context),
                        ),
                      if (widget.item != null)
                        AppButton(
                          label: 'Delete',
                          variant: AppButtonVariant.secondary,
                          isLoading: itemsProvider.isSaving,
                          onPressed: () async {
                            final ok = await showConfirmDialog(
                              context,
                              title: 'Delete item?',
                              message:
                                  'Permanently delete "${widget.item!.displayName}"? You can restore it later from the Action Center.',
                            );
                            if (!ok) return;
                            await itemsProvider.deleteItem(widget.item!.id);
                            if (!context.mounted) return;
                            if (itemsProvider.errorMessage == null) {
                              Navigator.of(context).pop(null);
                            } else {
                              showGlobalToast(
                                itemsProvider.errorMessage!,
                                kind: AppToastKind.error,
                              );
                            }
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChildEditor(
    _NodeDraft child,
    int depth,
    List<_NodeDraft> siblings,
  ) {
    final index = siblings.indexOf(child);
    return _TreeNodeEditor(
      draft: child,
      depth: depth,
      readOnly: _isReadOnly,
      summaryLabel: _summaryLabelForNode(child),
      metaPills: _propertyMetaPillsForNode(child),
      onToggleBranch: () => _toggleNodeDetails(child),
      onEnableNameEditing: child.isLockedInheritedProperty
          ? null
          : () => _setNodeNameEditing(child, true),
      onFinishNameEditing: child.isLockedInheritedProperty
          ? null
          : () => _setNodeNameEditing(child, false),
      onAddProperty:
          child.kind == ItemVariationNodeKind.value ||
              (child.kind == ItemVariationNodeKind.property &&
                  !child.children.any(
                    (c) => c.kind == ItemVariationNodeKind.value,
                  ))
          ? () => _addChildProperty(child)
          : null,
      onToggleInputType:
          child.kind == ItemVariationNodeKind.property &&
              !_isReadOnly &&
              !child.isLockedInheritedProperty
          ? () {
              setState(() {
                child.inputType = child.inputType == 'Numeric'
                    ? 'Text'
                    : 'Numeric';
              });
              _handleChange();
            }
          : null,
      onPromoteToGroup:
          child.kind == ItemVariationNodeKind.property &&
              _selectedGroupId != null &&
              !_isReadOnly &&
              !child.isLockedInheritedProperty
          ? () => _promotePropertyToGroup(child)
          : null,
      onAddValue:
          child.kind == ItemVariationNodeKind.property &&
              !child.children.any(
                (c) => c.kind == ItemVariationNodeKind.property,
              )
          ? () => _addChildValue(child)
          : null,
      onMoveUp: index == 0 ? null : () => _moveNode(siblings, index, index - 1),
      onMoveDown: index == siblings.length - 1
          ? null
          : () => _moveNode(siblings, index, index + 1),
      onRemove: () => _removeNode(siblings, index),
      buildChildEditor: _buildChildEditor,
    );
  }

  List<ItemVariationNodeInput> get _variationTreeInputs =>
      _rootNodes.map((node) => _toInput(node, null)).toList(growable: false);

  List<String> get _availableNamingTokens {
    final tokens = <String>['name'];
    for (var i = 0; i < _rootNodes.length; i++) {
      if (_rootNodes[i].kind == ItemVariationNodeKind.property) {
        tokens.add('prop_$i');
      }
    }
    return tokens;
  }

  List<String> get _activeNamingFormat {
    final available = _availableNamingTokens;
    _excludedNamingTokens.retainAll(available);
    final format = _namingFormat
        .where(
          (t) => available.contains(t) && !_excludedNamingTokens.contains(t),
        )
        .toList();
    for (final token in available) {
      if (!format.contains(token) && !_excludedNamingTokens.contains(token)) {
        format.add(token);
      }
    }
    return format;
  }

  void _resetLeafDisplayNamesTouched() {
    void resetLeaves(_NodeDraft node) {
      if (node.isLeafValue) {
        node.displayNameTouched = false;
      }
      for (final child in node.children) {
        resetLeaves(child);
      }
    }

    for (final node in _rootNodes) {
      resetLeaves(node);
    }
  }

  Widget _buildNamingTokenChip(
    String token, {
    required bool isActive,
    int? index,
  }) {
    final displayName = _getDisplayNameForToken(token);
    return MouseRegion(
      cursor: isActive ? SystemMouseCursors.grab : SystemMouseCursors.click,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? const Color(0xFFE2E8F0)
                : const Color(0xFFE2E8F0).withValues(alpha: 0.5),
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isActive) ...[
              const Icon(
                Icons.drag_indicator_rounded,
                size: 16,
                color: Color(0xFF94A3B8),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              displayName,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: isActive
                    ? const Color(0xFF334155)
                    : const Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(width: 6),
            if (isActive)
              GestureDetector(
                onTap: () {
                  setState(() {
                    _excludedNamingTokens.add(token);
                    _resetLeafDisplayNamesTouched();
                    _syncLeafDisplayNames();
                  });
                },
                child: const MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Icon(Icons.close, size: 14, color: Color(0xFF94A3B8)),
                ),
              )
            else
              GestureDetector(
                onTap: () {
                  setState(() {
                    _excludedNamingTokens.remove(token);
                    if (!_namingFormat.contains(token)) {
                      _namingFormat.add(token);
                    }
                    _resetLeafDisplayNamesTouched();
                    _syncLeafDisplayNames();
                  });
                },
                child: const MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Icon(Icons.add, size: 14, color: Color(0xFF94A3B8)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveNamingFormatArea(BuildContext context) {
    final active = _activeNamingFormat;
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) {
        final draggedToken = details.data;
        setState(() {
          if (_excludedNamingTokens.contains(draggedToken)) {
            _excludedNamingTokens.remove(draggedToken);
          }
          final list = _namingFormat.toList();
          if (!list.contains(draggedToken)) {
            list.add(draggedToken);
          } else {
            // Move to the end if dropped on empty area of active container
            list.remove(draggedToken);
            list.add(draggedToken);
          }
          _namingFormat = list;
          _resetLeafDisplayNamesTouched();
          _syncLeafDisplayNames();
        });
      },
      builder: (context, candidateData, rejectedData) {
        final isContainerHovered = candidateData.isNotEmpty;
        return Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isContainerHovered
                ? const Color(0xFFF1F5F9)
                : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isContainerHovered
                  ? Theme.of(context).primaryColor
                  : const Color(0xFFE2E8F0),
              width: isContainerHovered ? 1.5 : 1.0,
            ),
          ),
          child: active.isEmpty
              ? Center(
                  child: Text(
                    'No active naming blocks. Drag properties here to include them.',
                    style: TextStyle(color: Colors.grey[500], fontSize: 13),
                  ),
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: List.generate(active.length, (i) {
                    final token = active[i];
                    return DragTarget<String>(
                      onWillAcceptWithDetails: (details) =>
                          details.data != token,
                      onAcceptWithDetails: (details) {
                        final draggedToken = details.data;
                        setState(() {
                          if (_excludedNamingTokens.contains(draggedToken)) {
                            _excludedNamingTokens.remove(draggedToken);
                          }
                          final list = _namingFormat.toList();
                          list.remove(draggedToken);

                          int insertIdx = list.indexOf(token);
                          if (insertIdx == -1) {
                            insertIdx = 0;
                          }
                          list.insert(insertIdx, draggedToken);
                          _namingFormat = list;
                          _resetLeafDisplayNamesTouched();
                          _syncLeafDisplayNames();
                        });
                      },
                      builder: (context, candidateData, rejectedData) {
                        final isChipHovered = candidateData.isNotEmpty;
                        final chipWidget = _buildNamingTokenChip(
                          token,
                          isActive: true,
                          index: i,
                        );

                        return Draggable<String>(
                          data: token,
                          feedback: Material(
                            color: Colors.transparent,
                            child: Opacity(opacity: 0.85, child: chipWidget),
                          ),
                          childWhenDragging: Opacity(
                            opacity: 0.3,
                            child: chipWidget,
                          ),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: isChipHovered
                                    ? Theme.of(context).primaryColor
                                    : Colors.transparent,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: chipWidget,
                          ),
                        );
                      },
                    );
                  }),
                ),
        );
      },
    );
  }

  Widget _buildInactiveNamingFormatArea(BuildContext context) {
    final available = _availableNamingTokens;
    _excludedNamingTokens.retainAll(available);
    final inactive = available
        .where((t) => _excludedNamingTokens.contains(t))
        .toList();

    final showAvailable = inactive.isNotEmpty || _activeNamingFormat.isNotEmpty;
    if (!showAvailable) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          'Available Blocks (Drag blocks here to remove, or click + to include):',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.grey[600],
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        DragTarget<String>(
          onWillAcceptWithDetails: (details) =>
              !_excludedNamingTokens.contains(details.data),
          onAcceptWithDetails: (details) {
            final draggedToken = details.data;
            setState(() {
              _excludedNamingTokens.add(draggedToken);
              _resetLeafDisplayNamesTouched();
              _syncLeafDisplayNames();
            });
          },
          builder: (context, candidateData, rejectedData) {
            final isHovered = candidateData.isNotEmpty;
            return Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isHovered
                    ? const Color(0xFFF1F5F9)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isHovered
                      ? Theme.of(context).primaryColor
                      : const Color(0xFFE2E8F0).withValues(alpha: 0.5),
                  width: 1.0,
                ),
              ),
              child: inactive.isEmpty
                  ? Center(
                      child: Text(
                        'Drag active blocks here to remove them from display name sequence.',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: inactive.map((token) {
                        final chipWidget = _buildNamingTokenChip(
                          token,
                          isActive: false,
                        );
                        return Draggable<String>(
                          data: token,
                          feedback: Material(
                            color: Colors.transparent,
                            child: Opacity(opacity: 0.85, child: chipWidget),
                          ),
                          childWhenDragging: Opacity(
                            opacity: 0.3,
                            child: chipWidget,
                          ),
                          child: chipWidget,
                        );
                      }).toList(),
                    ),
            );
          },
        ),
      ],
    );
  }

  String _getDisplayNameForToken(String token) {
    if (token == 'name') {
      return 'Base Name';
    }
    if (token.startsWith('prop_')) {
      final index = int.tryParse(token.substring(5));
      if (index != null && index >= 0 && index < _rootNodes.length) {
        final name = _rootNodes[index].nameController.text.trim();
        return name.isNotEmpty ? name : 'Unnamed Property';
      }
    }
    return token;
  }

  ItemVariationNodeInput _toInput(_NodeDraft node, int? parentNodeId) {
    return ItemVariationNodeInput(
      id: node.id,
      parentNodeId: parentNodeId,
      kind: node.kind,
      name: node.nameController.text.trim(),
      code: node.codeController.text.trim(),
      displayName: node.isLeafValue
          ? node.displayNameController.text.trim()
          : '',
      inputType: node.inputType,
      children: node.children
          .map((child) => _toInput(child, node.id))
          .toList(growable: false),
    );
  }

  String _summaryLabelForNode(_NodeDraft node) {
    if (node.isLeafValue) {
      final leafLabel = node.displayNameController.text.trim();
      final base = leafLabel.isEmpty ? _generateLeafDisplayName(node) : leafLabel;
      final code = node.codeController.text.trim();
      return code.isNotEmpty ? '$base [$code]' : base;
    }
    final name = node.nameController.text.trim();
    final code = node.codeController.text.trim();
    if (name.isNotEmpty) {
      return code.isNotEmpty ? '$name [$code]' : name;
    }
    return node.kind == ItemVariationNodeKind.property
        ? 'Unnamed Property'
        : 'Unnamed Value';
  }

  void _toggleNodeDetails(_NodeDraft node) {
    setState(() {
      node.detailsExpanded = !node.detailsExpanded;
    });
  }

  void _setNodeNameEditing(_NodeDraft node, bool editing) {
    if (node.isLockedInheritedProperty) {
      return;
    }
    setState(() {
      node.isNameEditing = editing;
      if (editing) {
        node.detailsExpanded = true;
      }
    });
  }

  void _setTreeEditingState(
    List<_NodeDraft> nodes, {
    required bool detailsExpanded,
    required bool isNameEditing,
  }) {
    for (final node in nodes) {
      node.detailsExpanded = detailsExpanded;
      node.isNameEditing = isNameEditing;
      _setTreeEditingState(
        node.children,
        detailsExpanded: detailsExpanded,
        isNameEditing: isNameEditing,
      );
    }
  }

  Future<void> _openVariationCreationDialog() async {
    if (widget.item == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please save this base item before spawning variants.'),
        ),
      );
      return;
    }

    final properties = _rootNodes
        .where((n) => n.kind == ItemVariationNodeKind.property)
        .toList();
    if (properties.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please add at least one top-level property and some values first.',
          ),
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => _VariationCreationDialog(
        topLevelProperties: properties,
        onSpawnItems: (combinations) async {
          if (_selectedGroupId == null || _selectedUnitId == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Select both a group and a unit for the base item before spawning variants.',
                ),
              ),
            );
            return;
          }
          final itemsProvider = context.read<ItemsProvider>();
          final createdItemIds = <int>[];
          for (final combo in combinations) {
            final valuesStr = combo
                .map((val) => val.nameController.text.trim())
                .join(' - ');
            final newName = '${_nameController.text.trim()} - $valuesStr';
            final newDisplayName =
                '${_displayNameController.text.trim()} - $valuesStr';

            final input = CreateItemInput(
              name: newName,
              displayName: newDisplayName,
              groupId: _selectedGroupId!,
              unitId: _selectedUnitId!,
              unitConversions: _secondaryUnitConversions
                  .map(
                    (draft) => ItemUnitConversionInput(
                      unitId: draft.unitId,
                      factorToPrimary:
                          1 / _getDerivedUnitsPerPrimary(draft.unitId),
                    ),
                  )
                  .toList(),
              namingFormat: _activeNamingFormat,
              variationTree: const [], // Spawned items have a flat/empty tree
              defaultPipelineId: _defaultPipelineId,
              baseItemId: widget.item?.id,
              photoUrl: _photoUrlController.text.trim(),
              availableForPurchase: _availableForPurchase,
            );
            final created = await itemsProvider.createItem(input);
            if (created != null) {
              createdItemIds.add(created.id);
            }
          }
          if (!context.mounted) {
            return;
          }
          // Enhancement 2.2 — immediately offer to add the freshly spawned
          // variants to a combination group.
          if (FeatureFlags.isEnabled(
                FeatureKeys.catalogInventoryEnhancements,
              ) &&
              createdItemIds.isNotEmpty) {
            await _promptAddVariantsToCombinationGroup(context, createdItemIds);
            if (!context.mounted) {
              return;
            }
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Successfully spawned ${combinations.length} variant items!',
              ),
            ),
          );
          Navigator.of(context).pop();
        },
      ),
    );
  }

  /// Enhancement 2.2 — follow-up flow after spawning variants: lets the user add
  /// the new items to an existing combination group or create a new one.
  Future<void> _promptAddVariantsToCombinationGroup(
    BuildContext context,
    List<int> itemIds,
  ) async {
    final choice = await showDialog<_CombinationGroupChoice>(
      context: context,
      builder: (dialogContext) => const _AddToCombinationGroupDialog(),
    );
    if (choice == null || !context.mounted) {
      return; // user skipped
    }

    final groupsProvider = context.read<GroupsProvider>();
    int? groupId = choice.existingGroupId;
    if (choice.isCreateNew) {
      final created = await groupsProvider.createGroup(
        CreateGroupInput(
          name: choice.newName,
          groupType: 'item',
          groupStructure: 'combination',
          description: choice.newDescription,
        ),
      );
      if (created == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                groupsProvider.errorMessage ??
                    'Could not create the combination group.',
              ),
            ),
          );
        }
        return;
      }
      groupId = created.id;
    }
    if (groupId == null) {
      return;
    }

    final assigned = await groupsProvider.assignItemsToCombinationGroup(
      groupId: groupId,
      itemIds: itemIds,
    );
    if (!context.mounted) {
      return;
    }
    if (assigned == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            groupsProvider.errorMessage ??
                'Could not add variants to the combination group.',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added $assigned variant(s) to the combination group.'),
        ),
      );
    }
  }

  void _addTopLevelProperty() {
    setState(() {
      _localError = null;
      _setTreeEditingState(
        _rootNodes,
        detailsExpanded: false,
        isNameEditing: false,
      );
      final draft = _newDraft(ItemVariationNodeKind.property, null);
      draft.isNameEditing = true;
      draft.detailsExpanded = true;
      _rootNodes.add(draft);
      _syncLeafDisplayNames();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_variationTreeScrollController.hasClients) {
        return;
      }
      _variationTreeScrollController.animateTo(
        _variationTreeScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _addChildProperty(_NodeDraft parent) {
    if (parent.kind == ItemVariationNodeKind.property &&
        parent.children.any((c) => c.kind == ItemVariationNodeKind.value)) {
      setState(() {
        _localError =
            'A property cannot contain both values and sub-properties.';
      });
      return;
    }
    setState(() {
      _localError = null;
      final child = _newDraft(ItemVariationNodeKind.property, parent);
      parent.detailsExpanded = true;
      child.isNameEditing = true;
      parent.children.add(child);
      _syncLeafDisplayNames();
    });
  }

  void _addChildValue(_NodeDraft parent) {
    if (parent.kind != ItemVariationNodeKind.property) {
      setState(() {
        _localError = 'A value can only be added under a property node.';
      });
      return;
    }
    if (parent.children.any((c) => c.kind == ItemVariationNodeKind.property)) {
      setState(() {
        _localError =
            'A property cannot contain both values and sub-properties.';
      });
      return;
    }
    setState(() {
      _localError = null;
      final child = _newDraft(ItemVariationNodeKind.value, parent);
      parent.detailsExpanded = true;
      child.isNameEditing = true;
      parent.children.add(child);
      _syncLeafDisplayNames();
    });
  }

  void _moveNode(List<_NodeDraft> siblings, int from, int to) {
    setState(() {
      final node = siblings.removeAt(from);
      siblings.insert(to, node);
      _syncLeafDisplayNames();
    });
  }

  void _removeNode(List<_NodeDraft> siblings, int index) {
    if (siblings[index].isLockedInheritedProperty) {
      return;
    }
    setState(() {
      final node = siblings.removeAt(index);
      node.dispose();
      _syncLeafDisplayNames();
    });
  }

  Future<void> _submit(BuildContext context) async {
    if (_isReadOnly) {
      return;
    }
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Group is validated independently by the group field's own Form validator
    // above, so we no longer couple it with the unit. A unit is still required
    // to persist the item, but only its own absence raises an error — selecting
    // a group without a unit no longer triggers a combined cross-validation.
    if (_selectedUnitId == null) {
      setState(() {
        _localError = 'Select a unit.';
      });
      return;
    }
    for (final conversion in _secondaryUnitConversions) {
      if (_getDerivedUnitsPerPrimary(conversion.unitId) <= 0) {
        setState(() {
          _localError =
              'Every secondary unit conversion must be greater than 0.';
        });
        return;
      }
    }
    for (final node in _rootNodes) {
      if (!_isMandatoryInheritedPropertySatisfied(node)) {
        final propertyName = node.nameController.text.trim().isEmpty
            ? 'Unnamed Property'
            : node.nameController.text.trim();
        setState(() {
          _localError =
              'Provide at least one value for required property "$propertyName".';
        });
        return;
      }
    }

    final itemsProvider = context.read<ItemsProvider>();
    final duplicate = itemsProvider.checkDuplicate(
      name: _nameController.text,
      groupId: _selectedGroupId,
      unitId: _selectedUnitId,
      variationTree: _variationTreeInputs,
      excludeId: widget.item?.id,
    );
    if (duplicate.blockingDuplicate) {
      setState(() {
        _localError = _duplicateMessage(duplicate.warning);
      });
      return;
    }

    setState(() {
      _localError = null;
    });

    final result = widget.item == null
        ? await itemsProvider.createItem(
            CreateItemInput(
              name: _nameController.text.trim(),
              alias: _aliasController.text.trim(),
              displayName: _displayNameController.text.trim(),
              groupId: _selectedGroupId!,
              unitId: _selectedUnitId!,
              unitConversions: _secondaryUnitConversions
                  .map(
                    (draft) => ItemUnitConversionInput(
                      unitId: draft.unitId,
                      factorToPrimary:
                          1 / _getDerivedUnitsPerPrimary(draft.unitId),
                    ),
                  )
                  .toList(growable: false),
              namingFormat: _activeNamingFormat,
              variationTree: _variationTreeInputs,
              defaultPipelineId: _defaultPipelineId,
              photoUrl: _photoUrlController.text.trim(),
              availableForPurchase: _availableForPurchase,
            ),
          )
        : await itemsProvider.updateItem(
            UpdateItemInput(
              id: widget.item!.id,
              name: _nameController.text.trim(),
              alias: _aliasController.text.trim(),
              displayName: _displayNameController.text.trim(),
              groupId: _selectedGroupId!,
              unitId: _selectedUnitId!,
              unitConversions: _secondaryUnitConversions
                  .map(
                    (draft) => ItemUnitConversionInput(
                      unitId: draft.unitId,
                      factorToPrimary:
                          1 / _getDerivedUnitsPerPrimary(draft.unitId),
                    ),
                  )
                  .toList(growable: false),
              namingFormat: _activeNamingFormat,
              variationTree: _variationTreeInputs,
              defaultPipelineId: _defaultPipelineId,
              photoUrl: _photoUrlController.text.trim(),
              availableForPurchase: _availableForPurchase,
            ),
          );

    if (context.mounted &&
        result != null &&
        itemsProvider.errorMessage == null) {
      showAppToast(
        context,
        widget.item == null ? 'Item created' : 'Item saved',
        kind: AppToastKind.success,
      );
      Navigator.of(context).pop(result);
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String helper,
    required bool readOnly,
    bool required = true,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: keyboardType,
      decoration: _fieldDecoration(label: label, helper: helper),
      validator: (value) {
        if (!required) {
          return null;
        }
        if ((value ?? '').trim().isEmpty) {
          return 'Required';
        }
        return null;
      },
    );
  }

  Widget _formRow({required List<Widget> children}) {
    return Column(
      children: [
        for (var index = 0; index < children.length; index++) ...[
          children[index],
          if (index != children.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _responsiveFieldPair({required Widget first, required Widget second}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(children: [first, const SizedBox(height: 12), second]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        );
      },
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required String helper,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helper,
      filled: true,
      fillColor: _isReadOnly
          ? const Color(0xFFF3F4F6)
          : const Color(0xFFF9FAFB),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
      ),
    );
  }

  String _generateItemDisplayName(String name, String alias) {
    return [
      name.trim(),
      alias.trim(),
    ].where((entry) => entry.isNotEmpty).join(' / ');
  }

  String _groupOptionLabel(
    GroupDefinition group,
    GroupsProvider groupsProvider,
  ) {
    final primaryGroup = _primaryGroupFor(group, groupsProvider);
    if (primaryGroup.id == group.id) {
      return group.name;
    }
    return '${group.name} • Primary: ${primaryGroup.name}';
  }

  String _groupOptionSearchText(
    GroupDefinition group,
    GroupsProvider groupsProvider,
  ) {
    final primaryGroup = _primaryGroupFor(group, groupsProvider);
    return '${group.name} ${primaryGroup.name}';
  }

  GroupDefinition _primaryGroupFor(
    GroupDefinition group,
    GroupsProvider groupsProvider,
  ) {
    var current = group;
    final visited = <int>{current.id};
    while (current.parentGroupId != null) {
      final parent = groupsProvider.findById(current.parentGroupId);
      if (parent == null || !visited.add(parent.id)) {
        break;
      }
      current = parent;
    }
    return current;
  }

  Future<void> _fetchPipelines() async {
    final provider = context.read<ItemsProvider>();
    final pipelines = await provider.fetchPipelineTemplates();
    if (mounted) {
      setState(() {
        _availablePipelines = pipelines;
      });
    }
  }

  String _generateLeafDisplayName(_NodeDraft leaf) {
    final pathValues = <String, String>{};
    final pathValueNames = <String>[];

    _NodeDraft? current = leaf;
    while (current != null) {
      if (current.kind == ItemVariationNodeKind.value &&
          current.parent != null &&
          current.parent!.kind == ItemVariationNodeKind.property) {
        final propNode = current.parent!;
        final valueName = current.nameController.text.trim();
        if (valueName.isNotEmpty) {
          pathValueNames.insert(0, valueName);
        }
        final propIndex = _rootNodes.indexOf(propNode);
        if (propIndex != -1 && valueName.isNotEmpty) {
          pathValues['prop_$propIndex'] = valueName;
        }
      }
      current = current.parent;
    }

    final segments = <String>[];
    for (final token in _activeNamingFormat) {
      if (token == 'name') {
        continue;
      }
      if (pathValues.containsKey(token)) {
        segments.add(pathValues[token]!);
      }
    }
    for (final value in pathValueNames) {
      if (value.isNotEmpty && !segments.contains(value)) {
        segments.add(value);
      }
    }
    return segments.join(' ');
  }

  String _duplicateMessage(ItemDuplicateWarning warning) {
    return switch (warning) {
      ItemDuplicateWarning.none => '',
      ItemDuplicateWarning.sameGroup =>
        'An item with this name and variation structure already exists in the selected group with the same unit.',
      ItemDuplicateWarning.emptyNodeName =>
        'Every property and value node needs a name.',
      ItemDuplicateWarning.invalidTreeStructure =>
        'Invalid tree structure. A value node can only contain property nodes, and a property cannot contain both values and properties.',
      ItemDuplicateWarning.duplicateSiblingName =>
        'Sibling nodes under the same parent must have unique names.',
      ItemDuplicateWarning.duplicatePropertyName =>
        'A property with this name already exists elsewhere in the item.',
    };
  }
}

/// Enhancement 3 — inline configurator under a property node: marks it
/// measurable and picks the units allowed for its value leaves.

class _TreeNodeEditor extends StatelessWidget {
  const _TreeNodeEditor({
    required this.draft,
    required this.depth,
    required this.readOnly,
    required this.summaryLabel,
    required this.metaPills,
    required this.onToggleBranch,
    required this.onEnableNameEditing,
    required this.onFinishNameEditing,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRemove,
    required this.buildChildEditor,
    this.onAddProperty,
    this.onToggleInputType,
    this.onPromoteToGroup,
    this.onAddValue,
  });

  final _NodeDraft draft;
  final int depth;
  final bool readOnly;
  final String summaryLabel;
  final List<_TreeMetaPillSpec> metaPills;
  final VoidCallback onToggleBranch;

  final VoidCallback? onEnableNameEditing;
  final VoidCallback? onFinishNameEditing;
  final VoidCallback? onAddProperty;
  final VoidCallback? onToggleInputType;
  final VoidCallback? onPromoteToGroup;
  final VoidCallback? onAddValue;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onRemove;
  final Widget Function(_NodeDraft child, int depth, List<_NodeDraft> siblings)
  buildChildEditor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isProperty = draft.kind == ItemVariationNodeKind.property;
    final hasChildren = draft.children.isNotEmpty;
    final canExpand = hasChildren;
    final nodeType = isProperty ? 'Property' : 'Value';
    final icon = isProperty ? Icons.tune : Icons.circle;
    final iconSize = isProperty ? 18.0 : 10.0;
    final branchColor = theme.dividerColor.withValues(alpha: 0.55);

    // Property scope from the meta pills: item-local (manual) vs global
    // (inherited from a group / seed). Drives the row background tint so the two
    // are distinguishable at a glance.
    final isItemLocalProperty =
        isProperty &&
        metaPills.any((pill) => pill.tone == _TreeMetaPillTone.manual);
    final isGlobalProperty =
        isProperty &&
        metaPills.any(
          (pill) =>
              pill.tone == _TreeMetaPillTone.inherited ||
              pill.tone == _TreeMetaPillTone.seeded,
        );
    // Item-local: light slate; global: light green (matches the pill tones).
    final scopeColor = isItemLocalProperty
        ? const Color(0xFFF4F6F9)
        : isGlobalProperty
        ? const Color(0xFFECFDF5)
        : null;
    final rowHighlight = draft.detailsExpanded
        ? theme.colorScheme.primary.withValues(alpha: 0.08)
        : (scopeColor ?? Colors.transparent);

    final visiblePills = metaPills;

    final textColor = draft.nameController.text.trim().isEmpty
        ? theme.colorScheme.error
        : null;

    return SoftEntranceAnimation(
      direction: EntranceDirection.up,
      delay: Duration(milliseconds: 150 + (50 * depth)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(left: depth * 20.0),
            child: Material(
              color: rowHighlight,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: canExpand ? onToggleBranch : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      SizedBox(
                        width: 20,
                        child: canExpand
                            ? Icon(
                                draft.detailsExpanded
                                    ? Icons.expand_more
                                    : Icons.chevron_right,
                                size: 18,
                              )
                            : const SizedBox.shrink(),
                      ),
                      Icon(icon, size: iconSize),
                      const SizedBox(width: 8),
                      if (draft.isNameEditing && !readOnly)
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: draft.nameController,
                                  autofocus: true,
                                  onEditingComplete: onFinishNameEditing,
                                  onSubmitted: (_) =>
                                      onFinishNameEditing?.call(),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText: isProperty
                                        ? 'Property name'
                                        : 'Value name',
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 8,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: draft.codeController,
                                  onEditingComplete: onFinishNameEditing,
                                  onSubmitted: (_) =>
                                      onFinishNameEditing?.call(),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText: 'Code (Optional)',
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 8,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Expanded(
                          child: MouseRegion(
                            cursor: readOnly
                                ? MouseCursor.defer
                                : SystemMouseCursors.text,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: readOnly ? null : onEnableNameEditing,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Text(
                                  summaryLabel,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: textColor,
                                    fontWeight: isProperty
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (visiblePills.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            alignment: WrapAlignment.end,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              for (final pill in visiblePills)
                                _TreeMetaPill(
                                  label: pill.label,
                                  tone: pill.tone,
                                ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      _NodeTypePill(label: nodeType),
                      if (!readOnly) ...[
                        const SizedBox(width: 4),
                        if (onToggleInputType != null)
                          InkWell(
                            onTap: onToggleInputType,
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: draft.inputType == 'Numeric'
                                    ? Colors.blue.withValues(alpha: 0.1)
                                    : Colors.grey.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: draft.inputType == 'Numeric'
                                      ? Colors.blue.withValues(alpha: 0.3)
                                      : Colors.grey.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                draft.inputType == 'Numeric' ? '1' : 'A',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: draft.inputType == 'Numeric'
                                      ? Colors.blue[700]
                                      : Colors.grey[700],
                                ),
                              ),
                            ),
                          ),
                        if (onAddValue != null)
                          _TreeActionButton(
                            tooltip: 'Add value',
                            icon: Icons.add,
                            onPressed: onAddValue,
                          ),
                        if (onAddProperty != null)
                          _TreeActionButton(
                            tooltip: 'Add property',
                            icon: Icons.account_tree_outlined,
                            onPressed: onAddProperty,
                          ),
                        if (onPromoteToGroup != null)
                          _TreeActionButton(
                            tooltip: 'Promote to group',
                            icon: Icons.upload_rounded,
                            onPressed: onPromoteToGroup,
                          ),
                        if (onEnableNameEditing != null)
                          _TreeActionButton(
                            tooltip: 'Edit name',
                            icon: Icons.edit_outlined,
                            onPressed: onEnableNameEditing,
                          ),
                        _TreeActionButton(
                          tooltip: 'Move up',
                          icon: Icons.arrow_upward,
                          onPressed: onMoveUp,
                        ),
                        _TreeActionButton(
                          tooltip: 'Move down',
                          icon: Icons.arrow_downward,
                          onPressed: onMoveDown,
                        ),
                        if (onRemove != null)
                          _TreeActionButton(
                            tooltip: 'Remove',
                            icon: Icons.delete_outline,
                            onPressed: onRemove,
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (hasChildren && draft.detailsExpanded)
            Padding(
              padding: EdgeInsets.only(left: depth * 20.0 + 10),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: branchColor, width: 1),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: 10, top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (
                        var childIndex = 0;
                        childIndex < draft.children.length;
                        childIndex++
                      ) ...[
                        buildChildEditor(
                          draft.children[childIndex],
                          depth + 1,
                          draft.children,
                        ),
                        if (childIndex != draft.children.length - 1)
                          const SizedBox(height: 2),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum _TreeMetaPillTone { manual, seeded, inherited, promoted, required }

class _TreeMetaPillSpec {
  const _TreeMetaPillSpec({required this.label, required this.tone});

  final String label;
  final _TreeMetaPillTone tone;
}

class _TreeMetaPill extends StatelessWidget {
  const _TreeMetaPill({required this.label, required this.tone});

  final String label;
  final _TreeMetaPillTone tone;

  (Color background, Color border, Color foreground) _colors() {
    return switch (tone) {
      _TreeMetaPillTone.manual => (
        const Color(0xFFF8FAFC),
        const Color(0xFFE2E8F0),
        const Color(0xFF475569),
      ),
      _TreeMetaPillTone.seeded => (
        const Color(0xFFEEF4FF),
        const Color(0xFFC7D2FE),
        const Color(0xFF4F46E5),
      ),
      _TreeMetaPillTone.inherited => (
        const Color(0xFFECFDF5),
        const Color(0xFFBBF7D0),
        const Color(0xFF15803D),
      ),
      _TreeMetaPillTone.promoted => (
        const Color(0xFFF5F3FF),
        const Color(0xFFC4B5FD),
        const Color(0xFF6D28D9),
      ),
      _TreeMetaPillTone.required => (
        const Color(0xFFFEF3C7),
        const Color(0xFFFCD34D),
        const Color(0xFFB45309),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (background, border, foreground) = _colors();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _NodeTypePill extends StatelessWidget {
  const _NodeTypePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.72),
        ),
      ),
    );
  }
}

class _TreeActionButton extends StatelessWidget {
  const _TreeActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.action});

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1F2937),
                  ),
                ),
              ),
              action ?? const SizedBox.shrink(),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _UnitSelectionBubble extends StatelessWidget {
  const _UnitSelectionBubble({
    required this.label,
    this.onRemove,
    this.showDragHandle = false,
  });

  final String label;
  final VoidCallback? onRemove;
  final bool showDragHandle;

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFFF3F4F6);
    const borderColor = Color(0xFFE2E8F0);
    const textColor = Color(0xFF334155);

    return Container(
      padding: EdgeInsets.only(
        left: showDragHandle ? 6 : 10,
        right: 10,
        top: 6,
        bottom: 6,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDragHandle) ...[
            const Icon(
              Icons.drag_indicator_rounded,
              size: 14,
              color: Color(0xFF94A3B8),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 6),
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.all(0.5),
                child: Icon(
                  Icons.close_rounded,
                  size: 13,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WarningText extends StatelessWidget {
  const _WarningText({required this.warning});

  final ItemDuplicateWarning warning;

  @override
  Widget build(BuildContext context) {
    final message = switch (warning) {
      ItemDuplicateWarning.none => '',
      ItemDuplicateWarning.sameGroup =>
        'An item with this name already exists in the selected group.',
      ItemDuplicateWarning.emptyNodeName =>
        'Every property and value node needs a name.',
      ItemDuplicateWarning.invalidTreeStructure =>
        'Invalid tree structure. A value node can only contain property nodes, and a property cannot contain both values and properties.',
      ItemDuplicateWarning.duplicateSiblingName =>
        'Sibling names under the same parent must be unique.',
      ItemDuplicateWarning.duplicatePropertyName =>
        'A property with this name already exists elsewhere in the item.',
    };
    if (message.isEmpty) {
      return const SizedBox.shrink();
    }
    return Text(
      message,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: const Color(0xFFB45309),
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _ItemsMessageBanner extends StatelessWidget {
  const _ItemsMessageBanner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isError ? const Color(0xFFFECACA) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: isError ? const Color(0xFFB91C1C) : const Color(0xFF475569),
        ),
      ),
    );
  }
}

class _UnitConversionRow extends StatelessWidget {
  const _UnitConversionRow({
    super.key,
    required this.draft,
    required this.baseUnitSymbol,
    required this.unitLabel,
    required this.unitSymbol,
    this.unitGroupName,
    required this.onRemove,
  });

  final _UnitConversionDraft draft;
  final String baseUnitSymbol;
  final String unitLabel;
  final String unitSymbol;
  final String? unitGroupName;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: Text(
              '1 $baseUnitSymbol',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF334155),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '=',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF94A3B8),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 80,
            child: TextFormField(
              controller: draft.factorController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1F2937),
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFDCE2F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFDCE2F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF6366F1)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                unitSymbol,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF6366F1),
                ),
              ),
              if (unitGroupName != null && unitGroupName!.isNotEmpty)
                Text(
                  unitGroupName!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF94A3B8),
                    fontSize: 10,
                  ),
                ),
            ],
          ),
          const Spacer(),
          IconButton(
            onPressed: onRemove,
            tooltip: 'Remove $unitLabel',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: const Icon(
              Icons.close_rounded,
              size: 16,
              color: Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Item Photo Picker
// ---------------------------------------------------------------------------

class _ItemPhotoPickerField extends StatefulWidget {
  const _ItemPhotoPickerField({
    required this.controller,
    required this.readOnly,
  });

  final TextEditingController controller;
  final bool readOnly;

  @override
  State<_ItemPhotoPickerField> createState() => _ItemPhotoPickerFieldState();
}

class _ItemPhotoPickerFieldState extends State<_ItemPhotoPickerField> {
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  String _contentTypeFromExtension(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _pickAndUploadImage() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Images',
          mimeTypes: ['image/png', 'image/jpeg', 'image/webp'],
          extensions: ['png', 'jpg', 'jpeg', 'webp'],
        ),
      ],
    );
    if (file == null || !mounted) {
      return;
    }

    setState(() => _isUploading = true);
    final baseUrl = const String.fromEnvironment(
      'PAPER_API_BASE_URL',
      defaultValue: 'http://localhost:8080',
    );
    final service = GenericAssetService(baseUrl: baseUrl);

    try {
      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes).toString();
      final contentType =
          file.mimeType ??
          lookupMimeType(file.name, headerBytes: bytes.take(24).toList()) ??
          _contentTypeFromExtension(file.name);

      final intent = await service.createUploadIntent(
        GenericAssetUploadIntentInput(
          fileName: file.name,
          contentType: contentType,
          sizeBytes: bytes.length,
          sha256: digest,
        ),
      );

      if (intent.uploadUrl.host != 'mock.local') {
        final response = await http.put(
          intent.uploadUrl,
          headers: intent.headers,
          body: bytes,
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(
            'Image upload failed with status ${response.statusCode}.',
          );
        }
      }

      if (intent.readUrl == null) {
        throw Exception('Failed to get read URL from intent.');
      }

      widget.controller.text = intent.readUrl!;
      showAppSnack(
        const SnackBar(content: Text('Image uploaded successfully.')),
      );
    } catch (error) {
      showAppSnack(SnackBar(content: Text('Image upload failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.controller.text.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Square preview
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFDDE1F0)),
          ),
          clipBehavior: Clip.antiAlias,
          child: url.isNotEmpty
              ? Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, err, e) => const Icon(
                    Icons.inventory_2_outlined,
                    size: 40,
                    color: Color(0xFFCBD5E1),
                  ),
                )
              : const Icon(
                  Icons.inventory_2_outlined,
                  size: 40,
                  color: Color(0xFFCBD5E1),
                ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: widget.controller,
                      readOnly: widget.readOnly,
                      decoration: InputDecoration(
                        labelText: 'Photo URL',
                        hintText: 'Paste an image URL to preview\u2026',
                        helperText: 'Optional product or reference photo',
                        filled: true,
                        fillColor: const Color(0xFFF9FAFB),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Color(0xFFD7DBE7),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Color(0xFFD7DBE7),
                          ),
                        ),
                        suffixIcon: url.isNotEmpty && !widget.readOnly
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () => widget.controller.clear(),
                              )
                            : null,
                      ),
                    ),
                  ),
                  if (!widget.readOnly) ...[
                    const SizedBox(width: 8),
                    AppButton(
                      label: 'Upload',
                      icon: Icons.upload_file,
                      variant: AppButtonVariant.secondary,
                      isLoading: _isUploading,
                      onPressed: _pickAndUploadImage,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VariationCreationDialog extends StatefulWidget {
  final List<_NodeDraft> topLevelProperties;
  final Future<void> Function(List<List<_NodeDraft>>) onSpawnItems;

  const _VariationCreationDialog({
    required this.topLevelProperties,
    required this.onSpawnItems,
  });

  @override
  State<_VariationCreationDialog> createState() =>
      _VariationCreationDialogState();
}

class _VariationCreationDialogState extends State<_VariationCreationDialog> {
  final Map<_NodeDraft, Set<_NodeDraft>> _selectedValues = {};
  final List<List<_NodeDraft>> _createdCombinations = [];
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    for (final prop in widget.topLevelProperties) {
      _selectedValues[prop] = {};
    }
  }

  void _selectCard(int index) {
    setState(() {
      _selectedIndex = index;
      for (final prop in widget.topLevelProperties) {
        _selectedValues[prop]!.clear();
      }
      final combo = _createdCombinations[index];
      for (final val in combo) {
        for (final prop in widget.topLevelProperties) {
          if (prop.children.contains(val)) {
            _selectedValues[prop]!.add(val);
            break;
          }
        }
      }
    });
  }

  void _deselectCard() {
    setState(() {
      _selectedIndex = null;
      for (final prop in widget.topLevelProperties) {
        _selectedValues[prop]!.clear();
      }
    });
  }

  void _duplicateCard(int index) {
    setState(() {
      final combo = List<_NodeDraft>.from(_createdCombinations[index]);
      _createdCombinations.insert(index + 1, combo);
      _selectCard(index + 1);
    });
  }

  void _deleteCard(int index) {
    setState(() {
      _createdCombinations.removeAt(index);
      if (_selectedIndex == index) {
        _deselectCard();
      } else if (_selectedIndex != null && _selectedIndex! > index) {
        _selectedIndex = _selectedIndex! - 1;
      }
    });
  }

  void _createVariant() {
    List<List<_NodeDraft>> newCombos = [[]];
    for (final prop in widget.topLevelProperties) {
      final selectedForProp = _selectedValues[prop]!;
      if (selectedForProp.isEmpty) continue;
      final temp = <List<_NodeDraft>>[];
      for (final combo in newCombos) {
        for (final val in selectedForProp) {
          temp.add([...combo, val]);
        }
      }
      newCombos = temp;
    }
    if (newCombos.length == 1 && newCombos.first.isEmpty) {
      newCombos.clear();
    }
    setState(() {
      for (final c in newCombos) {
        bool exists = _createdCombinations.any((existing) {
          if (existing.length != c.length) return false;
          for (int i = 0; i < c.length; i++) {
            if (existing[i] != c[i]) return false;
          }
          return true;
        });
        if (!exists) {
          _createdCombinations.add(c);
        }
      }
    });
  }

  void _save() {
    widget.onSpawnItems(_createdCombinations);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 900,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Variation Creation',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(8),
                              ),
                            ),
                            width: double.infinity,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _selectedIndex == null
                                      ? 'Bulk Creation Tree'
                                      : 'Editing Selected Variant',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (_selectedIndex != null)
                                  TextButton(
                                    onPressed: _deselectCard,
                                    child: const Text('Return to Bulk Mode'),
                                  ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.all(8),
                              itemCount: widget.topLevelProperties.length,
                              itemBuilder: (context, index) {
                                final prop = widget.topLevelProperties[index];
                                final values = prop.children
                                    .where(
                                      (c) =>
                                          c.kind == ItemVariationNodeKind.value,
                                    )
                                    .toList();
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: Text(
                                        prop.nameController.text.isEmpty
                                            ? 'Unnamed Property'
                                            : prop.nameController.text,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (values.isEmpty)
                                      const Padding(
                                        padding: EdgeInsets.only(
                                          left: 16,
                                          bottom: 8,
                                        ),
                                        child: Text(
                                          'No values',
                                          style: TextStyle(
                                            color: Colors.grey,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ),
                                    for (final val in values)
                                      CheckboxListTile(
                                        dense: true,
                                        title: Text(
                                          val.nameController.text.isEmpty
                                              ? 'Unnamed Value'
                                              : val.nameController.text,
                                        ),
                                        value: _selectedValues[prop]!.contains(
                                          val,
                                        ),
                                        onChanged: (checked) {
                                          setState(() {
                                            if (_selectedIndex != null) {
                                              if (checked == true) {
                                                final activeCombo =
                                                    List<_NodeDraft>.from(
                                                      _createdCombinations[_selectedIndex!],
                                                    );
                                                final propValues = prop.children
                                                    .where(
                                                      (c) =>
                                                          c.kind ==
                                                          ItemVariationNodeKind
                                                              .value,
                                                    )
                                                    .toSet();
                                                activeCombo.removeWhere(
                                                  (val) =>
                                                      propValues.contains(val),
                                                );
                                                activeCombo.add(val);
                                                _createdCombinations[_selectedIndex!] =
                                                    activeCombo;
                                                _selectedValues[prop]!.clear();
                                                _selectedValues[prop]!.add(val);
                                              } else {
                                                final activeCombo =
                                                    List<_NodeDraft>.from(
                                                      _createdCombinations[_selectedIndex!],
                                                    );
                                                activeCombo.remove(val);
                                                _createdCombinations[_selectedIndex!] =
                                                    activeCombo;
                                                _selectedValues[prop]!.remove(
                                                  val,
                                                );
                                              }
                                            } else {
                                              if (checked == true) {
                                                _selectedValues[prop]!.add(val);
                                              } else {
                                                _selectedValues[prop]!.remove(
                                                  val,
                                                );
                                              }
                                            }
                                          });
                                        },
                                      ),
                                    const Divider(),
                                  ],
                                );
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: _selectedIndex == null
                                ? FilledButton.icon(
                                    onPressed: _createVariant,
                                    icon: const Icon(Icons.auto_awesome),
                                    label: const Text('Generate Combinations'),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    flex: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(8),
                              ),
                            ),
                            width: double.infinity,
                            child: const Text(
                              'Generated Combinations',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          Expanded(
                            child: _createdCombinations.isEmpty
                                ? const Center(
                                    child: Text(
                                      'No variants created yet.',
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.all(8),
                                    itemCount: _createdCombinations.length,
                                    itemBuilder: (context, index) {
                                      final combo = _createdCombinations[index];
                                      final label = combo
                                          .map((n) => n.nameController.text)
                                          .join(' - ');
                                      return ListTile(
                                        selected: _selectedIndex == index,
                                        selectedTileColor: Theme.of(context)
                                            .colorScheme
                                            .primaryContainer
                                            .withOpacity(0.3),
                                        onTap: () => _selectCard(index),
                                        title: Text(label),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(
                                                Icons.copy,
                                                size: 20,
                                              ),
                                              tooltip: 'Duplicate',
                                              onPressed: () =>
                                                  _duplicateCard(index),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.delete_outline,
                                                color: Colors.red,
                                                size: 20,
                                              ),
                                              tooltip: 'Delete',
                                              onPressed: () =>
                                                  _deleteCard(index),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _save,
                  child: const Text('Spawn Variants'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Result of the "Add variants to a combination group?" follow-up dialog
/// (Enhancement 2.2). `null` (not an instance of this class) means the user
/// skipped.
class _CombinationGroupChoice {
  const _CombinationGroupChoice.existing(this.existingGroupId)
    : isCreateNew = false,
      newName = '',
      newDescription = '';

  const _CombinationGroupChoice.create({
    required this.newName,
    required this.newDescription,
  }) : isCreateNew = true,
       existingGroupId = null;

  final bool isCreateNew;
  final int? existingGroupId;
  final String newName;
  final String newDescription;
}

/// Bottom dialog shown right after variants are spawned, offering to add them to
/// an existing combination group or to create a new one.
class _AddToCombinationGroupDialog extends StatefulWidget {
  const _AddToCombinationGroupDialog();

  @override
  State<_AddToCombinationGroupDialog> createState() =>
      _AddToCombinationGroupDialogState();
}

class _AddToCombinationGroupDialogState
    extends State<_AddToCombinationGroupDialog> {
  bool _createNew = false;
  int? _selectedGroupId;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    // Default to "create new" when there are no combination groups yet.
    final existing = context.read<GroupsProvider>().combinationGroups;
    _createNew = existing.isEmpty;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _confirm() {
    if (_createNew) {
      final name = _nameController.text.trim();
      if (name.isEmpty) {
        setState(() => _error = 'Enter a name for the new combination group.');
        return;
      }
      Navigator.of(context).pop(
        _CombinationGroupChoice.create(
          newName: name,
          newDescription: _descriptionController.text.trim(),
        ),
      );
      return;
    }
    if (_selectedGroupId == null) {
      setState(() => _error = 'Select a combination group.');
      return;
    }
    Navigator.of(
      context,
    ).pop(_CombinationGroupChoice.existing(_selectedGroupId!));
  }

  @override
  Widget build(BuildContext context) {
    final combinationGroups = context.watch<GroupsProvider>().combinationGroups;
    return AlertDialog(
      title: const Text('Add variants to a combination group?'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RadioListTile<bool>(
              value: false,
              groupValue: _createNew,
              onChanged: combinationGroups.isEmpty
                  ? null
                  : (value) => setState(() {
                      _createNew = false;
                      _error = null;
                    }),
              contentPadding: EdgeInsets.zero,
              title: const Text('Select existing'),
            ),
            if (!_createNew)
              Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 8),
                child: SearchableSelectField<int>(
                  value: _selectedGroupId,
                  decoration: const InputDecoration(
                    hintText: 'Choose combination group',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  dialogTitle: 'Combination group',
                  searchHintText: 'Search group',
                  emptyText: 'No combination groups yet',
                  options: combinationGroups
                      .map(
                        (group) => SearchableSelectOption<int>(
                          value: group.id,
                          label: group.name,
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) => setState(() {
                    _selectedGroupId = value;
                    _error = null;
                  }),
                ),
              ),
            RadioListTile<bool>(
              value: true,
              groupValue: _createNew,
              onChanged: (value) => setState(() {
                _createNew = true;
                _error = null;
              }),
              contentPadding: EdgeInsets.zero,
              title: const Text('Create new'),
            ),
            if (_createNew)
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Column(
                  children: [
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Group name',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _descriptionController,
                      minLines: 1,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Skip'),
        ),
        FilledButton(onPressed: _confirm, child: const Text('Add to group')),
      ],
    );
  }
}

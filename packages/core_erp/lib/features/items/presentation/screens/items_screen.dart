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
import '../../../clients/domain/client_definition.dart';
import '../../../clients/presentation/providers/clients_provider.dart';
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
import '../../data/services/item_link_options_service.dart';
import '../../domain/item_form_sections.dart';
import '../providers/item_form_sections_provider.dart';

import 'package:core_erp/features/production_pipelines/domain/pen_paper_baseline.dart';
import 'package:core_erp/features/production_pipelines/presentation/widgets/pen_paper_baseline_widget.dart';

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
      builder: (context) {
        // Let a wide monitor earn a third column instead of capping at two and
        // leaving the sections to stack.
        final available = MediaQuery.of(context).size.width - 64;
        return Dialog(
          insetPadding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: available >= 1700 ? 1680 : 1380,
            ),
            child: body,
          ),
        );
      },
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
    final isScrap = groupName.toLowerCase().trim() == 'scrap' ||
        item.name.toLowerCase().contains('scrap') ||
        item.displayName.toLowerCase().contains('scrap');
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
      subtitle: isScrap
          ? 'Scrap material'
          : (leafCount == 0 ? 'Base item' : '$leafCount variant${leafCount == 1 ? '' : 's'}'),
      imageUrl: imageUrl,
      token: _boardingInitials(item.name.trim().isEmpty ? title : item.name),
      caption: item.alias.trim().isEmpty ? (isScrap ? 'Scrap material' : 'No image') : item.alias,
      isScrap: isScrap,
      details: [
        BoardingPassDetail('Group', groupName),
        BoardingPassDetail('Unit', unitLabel),
        BoardingPassDetail('Variants', isScrap ? 'Scrap' : (leafCount == 0 ? 'Base' : '$leafCount')),
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
    final isScrap = groupName.toLowerCase().trim() == 'scrap' ||
        item.name.toLowerCase().contains('scrap') ||
        item.displayName.toLowerCase().contains('scrap');
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
                      if (isScrap) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFFDE68A)),
                          ),
                          child: const Text(
                            'SCRAP',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFB45309),
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: SoftInlineText(item.displayName, weight: FontWeight.w700),
                      ),
                      if (isScrap) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFFDE68A)),
                          ),
                          child: const Text(
                            'SCRAP',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFB45309),
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
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
        Expanded(
          flex: 2,
          child: isScrap
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.recycling_rounded, size: 12, color: Color(0xFFD97706)),
                          const SizedBox(width: 4),
                          Text(
                            groupName.isEmpty ? 'Scrap' : groupName,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFB45309),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : SoftInlineText(groupName),
        ),
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
    this.numericMin,
    this.numericMax,
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

  /// Inclusive bounds a 'Numeric' property accepts, captured when the input
  /// type is switched to Numeric. Null on either side means open-ended.
  double? numericMin;
  double? numericMax;
  bool inheritedFromGroup = false;
  bool inheritedMandatory = false;
  String? inheritedPropertyKey;
  int? inheritedSourceGroupId;
  String? inheritedSourceGroupName;

  final List<_NodeDraft> children;

  bool get isLeafValue =>
      kind == ItemVariationNodeKind.value && children.isEmpty;

  /// A property the user types a number into rather than picking a value node
  /// from — the variation-creation dialog offers a number field for these.
  bool get isNumericProperty =>
      kind == ItemVariationNodeKind.property && inputType == 'Numeric';

  /// Human-readable range for pills and hints — '1 – 40', '≥ 1', '≤ 40'.
  String get numericRangeLabel {
    if (numericMin != null && numericMax != null) {
      return '${_formatNumericBound(numericMin!)} – ${_formatNumericBound(numericMax!)}';
    }
    if (numericMin != null) return '≥ ${_formatNumericBound(numericMin!)}';
    if (numericMax != null) return '≤ ${_formatNumericBound(numericMax!)}';
    return 'Any number';
  }

  /// Whether [value] falls inside the configured bounds (open-ended when a
  /// bound is null).
  bool acceptsNumber(double value) {
    if (numericMin != null && value < numericMin!) return false;
    if (numericMax != null && value > numericMax!) return false;
    return true;
  }

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

/// Trims the trailing '.0' off whole numbers so ranges read '1 – 40', not
/// '1.0 – 40.0'.
String _formatNumericBound(double value) {
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
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
  late final TextEditingController _cadFileKeyController;
  late final TextEditingController _cadFileNameController;
  final List<_AttachmentDraft> _attachments = [];
  final Set<String> _selectedMachineIds = <String>{};
  final Set<String> _selectedDieIds = <String>{};
  List<ItemLinkOption> _machineOptions = const <ItemLinkOption>[];
  List<ItemLinkOption> _dieOptions = const <ItemLinkOption>[];
  bool _isLoadingLinkOptions = false;
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
  PenPaperBaseline _penPaperBaseline = PenPaperBaseline.createDefault();

  /// Whether [_penPaperBaseline] holds a real recording rather than the
  /// untouched default. Only a recorded baseline is sent on save, so opening
  /// and closing the editor never fabricates sample numbers.
  bool _hasPenPaperBaseline = false;
  bool _availableForPurchase = false;
  int? _developedForClientId;

  bool get _isReadOnly => false;

  /// A basic item: spawned from a base item by Variation Creation. It has no
  /// variation tree of its own and inherits group, unit and naming from its
  /// base, so the editor drops to the handful of things that are still its own
  /// — name, media, pipeline and its sample record.
  bool get _isBasicItem => widget.item?.isBasicItem ?? false;

  /// The fixed section layout for a basic item. Deliberately not the user's
  /// configurable default: what a spawned variant can carry is a property of
  /// the item, not a form preference.
  static const ItemFormSections _basicItemSections = ItemFormSections(
    itemImage: true,
    cadFile: true,
    additionalFiles: true,
    developedFor: false,
    defaultPipeline: true,
    variationTree: false,
    machines: false,
    dies: false,
  );

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
    _cadFileKeyController = TextEditingController(
      text: widget.item?.cadFileKey ?? '',
    );
    _cadFileNameController = TextEditingController(
      text: widget.item?.cadFileName ?? '',
    );
    _selectedGroupId = widget.item?.groupId ?? widget.initialGroupId;
    _selectedUnitId = widget.item?.unitId;
    _namingFormat = widget.item?.namingFormat.toList() ?? [];
    _defaultPipelineId = widget.item?.defaultPipelineId;
    _availableForPurchase = widget.item?.availableForPurchase ?? false;
    _developedForClientId = widget.item?.developedForClientId;
    final storedBaseline = widget.item?.penPaperBaseline;
    if (storedBaseline != null) {
      _penPaperBaseline = storedBaseline;
      _hasPenPaperBaseline = true;
    }
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
    for (final attachment
        in widget.item?.attachments ??
            const <ItemAttachmentDefinition>[]) {
      _attachments.add(
        _AttachmentDraft(
          id: attachment.id,
          label: attachment.label,
          objectKey: attachment.objectKey,
          fileName: attachment.fileName,
          onChanged: _handleChange,
        ),
      );
    }
    _selectedMachineIds.addAll(
      (widget.item?.machines ?? const <ItemMachineLink>[]).map((m) => m.id),
    );
    _selectedDieIds.addAll(
      (widget.item?.dies ?? const <ItemDieLink>[]).map((d) => d.id),
    );
    // Both touch providers that notify, so they run after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ItemFormSectionsProvider>().ensureLoaded();
      _loadLinkOptions();
    });
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
    String inputType = node.inputType;
    if (node.kind == ItemVariationNodeKind.property) {
      final key = _propertyKey(node.name);
      final schemaEntry = widget.item?.propertySchema
          .where((e) => _propertyKey(e.propertyKey) == key)
          .firstOrNull;
      if (schemaEntry != null) {
        inputType = schemaEntry.inputType;
      }
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
      numericMin: inputType == 'Numeric' ? node.numericMin : null,
      numericMax: inputType == 'Numeric' ? node.numericMax : null,
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
    _cadFileKeyController.dispose();
    _cadFileNameController.dispose();
    for (final attachment in _attachments) {
      attachment.dispose();
    }
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
    // A group can carry its own section layout (component groups author one in
    // the group editor). When it does it wins over the user's own default, so
    // every item filed under that group asks for the same things.
    final groupSectionOverride = groupsProvider
        .findById(_selectedGroupId)
        ?.itemFormSections;
    // A basic item's layout is fixed by what a spawned variant can own, so it
    // outranks both the group override and the user's default.
    final sections = _isBasicItem
        ? _basicItemSections
        : (groupSectionOverride ??
              context.watch<ItemFormSectionsProvider>().sections);
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
    final fullDetailsSection = _SectionCard(
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
          if (sections.developedFor) ...[
            const SizedBox(height: 12),
            _DevelopedForField(
              clientId: _developedForClientId,
              readOnly: _isReadOnly,
              onChanged: (clientId) {
                setState(() {
                  _developedForClientId = clientId;
                  _handleChange();
                });
              },
            ),
          ],
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
    // A basic item inherits group, unit and naming from its base item, so its
    // details card shows those as context instead of as editable fields.
    final detailsSection = _isBasicItem
        ? _buildBasicItemDetailsSection(context, groupsProvider, unitsProvider)
        : fullDetailsSection;
    final photoSection = _SectionCard(
      title: 'Item Photo',
      child: _ItemPhotoPickerField(
        controller: _photoUrlController,
        readOnly: _isReadOnly,
      ),
    );
    final cadFileSection = _SectionCard(
      title: 'CAD File',
      child: _CadFilePickerField(
        keyController: _cadFileKeyController,
        nameController: _cadFileNameController,
        readOnly: _isReadOnly,
      ),
    );
    final additionalFilesSection = _SectionCard(
      title: 'Additional Files',
      action: _isReadOnly
          ? null
          : AppButton(
              label: 'Add File',
              icon: Icons.attach_file,
              variant: AppButtonVariant.secondary,
              onPressed: _addAttachment,
            ),
      child: _attachments.isEmpty
          ? const Text(
              'No extra files. Add datasheets, test reports or anything else '
              'this item needs — each with its own label.',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            )
          : Column(
              children: [
                for (var index = 0; index < _attachments.length; index++) ...[
                  if (index > 0) const SizedBox(height: 10),
                  _AttachmentRow(
                    draft: _attachments[index],
                    readOnly: _isReadOnly,
                    onRemove: () {
                      final removed = _attachments.removeAt(index);
                      setState(() {});
                      removed.dispose();
                      _handleChange();
                    },
                  ),
                ],
              ],
            ),
    );
    final machinesSection = _SectionCard(
      title: 'Machines',
      child: _LinkOptionPicker(
        options: _machineOptions,
        selectedIds: _selectedMachineIds,
        readOnly: _isReadOnly,
        isLoading: _isLoadingLinkOptions,
        emptyMessage: 'No machines available to link.',
        hintText: 'Add a machine',
        searchHintText: 'Search machines',
        onChanged: (ids) {
          setState(() {
            _selectedMachineIds
              ..clear()
              ..addAll(ids);
          });
          _handleChange();
        },
      ),
    );
    final diesSection = _SectionCard(
      title: 'Dies',
      child: _LinkOptionPicker(
        options: _dieOptions,
        selectedIds: _selectedDieIds,
        readOnly: _isReadOnly,
        isLoading: _isLoadingLinkOptions,
        emptyMessage: 'No dies available to link.',
        hintText: 'Add a die',
        searchHintText: 'Search dies',
        onChanged: (ids) {
          setState(() {
            _selectedDieIds
              ..clear()
              ..addAll(ids);
          });
          _handleChange();
        },
      ),
    );
    final variationTreeSection = _SectionCard(
      title: 'Variation Tree',
      action: _isReadOnly
          ? null
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppButton(
                  label: 'Add Top-Level Property',
                  icon: Icons.add,
                  variant: AppButtonVariant.secondary,
                  onPressed: _addTopLevelProperty,
                ),
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
                          onToggleInputType:
                              _rootNodes[index].kind == ItemVariationNodeKind.property &&
                                      !_isReadOnly &&
                                      !_rootNodes[index].isLockedInheritedProperty
                                  ? () => _cycleNodeInputType(_rootNodes[index])
                                  : null,
                          onEditNumericRange:
                              _rootNodes[index].isNumericProperty &&
                                      !_isReadOnly &&
                                      !_rootNodes[index].isLockedInheritedProperty
                                  ? () =>
                                      _editNodeNumericRange(_rootNodes[index])
                                  : null,
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
                              : _isBasicItem
                              ? 'Edit Basic Item'
                              : 'Edit Item',
                        ),
                      ),
                      // The section layout is configured in Settings → Item
                      // Creation (or on the group, for components) — not from
                      // the form it controls.
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
                            // A variant is only seeded with its base item's
                            // route. How it is actually made can differ, so the
                            // pipeline is the variant's own field — this strip
                            // says what the base uses and whether this one has
                            // departed from it.
                            if (_isBasicItem) ...[
                              _buildBasePipelineStrip(context),
                              const SizedBox(height: 12),
                            ],
                            Builder(
                              builder: (context) {
                                final pipelineOptions = _availablePipelines
                                    .map(
                                      (p) => SearchableSelectOption<String>(
                                        value: p['id']!,
                                        label: p['name']!,
                                        searchText: p['name']!,
                                      ),
                                    )
                                    .toList();
                                if (_defaultPipelineId != null &&
                                    _defaultPipelineId!.isNotEmpty &&
                                    !pipelineOptions.any((p) => p.value == _defaultPipelineId)) {
                                  final label = widget.item?.defaultPipelineName ?? _defaultPipelineId!;
                                  pipelineOptions.insert(
                                    0,
                                    SearchableSelectOption<String>(
                                      value: _defaultPipelineId!,
                                      label: label,
                                      searchText: label,
                                    ),
                                  );
                                }
                                return SearchableSelectField<String>(
                                  options: pipelineOptions,
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
                                );
                              },
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
                            // Basic items get the sample record as its own
                            // always-visible card instead, so it can be filled
                            // in before a pipeline is chosen.
                            if (!_isBasicItem &&
                                _defaultPipelineId != null &&
                                _defaultPipelineId!.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              PenPaperBaselineWidget(
                                baseline: _penPaperBaseline,
                                readOnly: _isReadOnly,
                                onChanged: (updated) {
                                  setState(() {
                                    _penPaperBaseline = updated;
                                    _hasPenPaperBaseline = true;
                                    _handleChange();
                                  });
                                },
                              ),
                            ],
                          ],
                        ),
                      );

                      // The sample record a basic item carries in its own
                      // right: the pen & paper yield of a trial run of THIS
                      // variant, not of the shared pipeline template.
                      final sampleDataSection = _SectionCard(
                        title: 'Sample Data',
                        child: _hasPenPaperBaseline
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  PenPaperBaselineWidget(
                                    baseline: _penPaperBaseline,
                                    readOnly: _isReadOnly,
                                    onChanged: (updated) {
                                      setState(() {
                                        _penPaperBaseline = updated;
                                        _handleChange();
                                      });
                                    },
                                  ),
                                  if (!_isReadOnly) ...[
                                    const SizedBox(height: 10),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton.icon(
                                        onPressed: _clearSampleData,
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 16,
                                        ),
                                        label: const Text('Remove sample data'),
                                        style: TextButton.styleFrom(
                                          foregroundColor:
                                              SoftErpTheme.dangerText,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              )
                            : _EmptySampleDataPrompt(
                                onAdd: _isReadOnly ? null : _addSampleData,
                              ),
                      );

                      // Section visibility is the user's saved item-form
                      // layout, so the same choice applies everywhere the
                      // editor opens.
                      final showPipeline =
                          sections.defaultPipeline && !isRawMaterialGroup;

                      // Sections are packed by estimated height rather than
                      // assigned to fixed columns: turning sections on and off
                      // otherwise leaves one column long and the other empty,
                      // which is what forces scrolling on a wide screen.
                      final entries = <_SectionEntry>[
                        _SectionEntry(
                          detailsSection,
                          _isBasicItem
                              ? 4.5
                              : 5.5 + _secondaryUnitConversions.length * 0.6,
                        ),
                        if (sections.variationTree)
                          _SectionEntry(
                            variationTreeSection,
                            3.0 + _rootNodes.length * 1.6,
                          ),
                        // A basic item's name comes from its base item and its
                        // variation values, so there is no format to arrange.
                        if (!_isBasicItem)
                          _SectionEntry(namingFormatSection, 3.6),
                        if (sections.itemImage)
                          _SectionEntry(photoSection, 2.2),
                        if (sections.cadFile)
                          _SectionEntry(cadFileSection, 2.2),
                        if (sections.additionalFiles)
                          _SectionEntry(
                            additionalFilesSection,
                            1.8 + _attachments.length * 0.7,
                          ),
                        if (sections.machines)
                          _SectionEntry(machinesSection, 2.0),
                        if (sections.dies) _SectionEntry(diesSection, 2.0),
                        if (showPipeline)
                          _SectionEntry(
                            defaultPipelineSection,
                            (!_isBasicItem &&
                                    _defaultPipelineId != null &&
                                    _defaultPipelineId!.isNotEmpty)
                                ? 8.5
                                : 2.0,
                          ),
                        if (_isBasicItem)
                          _SectionEntry(
                            sampleDataSection,
                            _hasPenPaperBaseline ? 7.5 : 2.2,
                          ),
                      ];

                      // A third column is only worth it when each one still
                      // clears ~600px. The variation tree packs a name field
                      // and eight controls into a row; below that width the
                      // name becomes unreadable.
                      final columnCount = constraints.maxWidth >= 1860
                          ? 3
                          : (wideComposer ? 2 : 1);
                      if (columnCount == 1) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _withSectionGaps(
                            entries
                                .map((entry) => entry.child)
                                .toList(growable: false),
                          ),
                        );
                      }

                      final columns = _packSections(entries, columnCount);
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var index = 0; index < columns.length; index++)
                            ...[
                              if (index > 0) const SizedBox(width: 18),
                              Expanded(
                                child: Column(
                                  children: _withSectionGaps(columns[index]),
                                ),
                              ),
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
          ? () => _cycleNodeInputType(child)
          : null,
      onEditNumericRange:
          child.isNumericProperty &&
              !_isReadOnly &&
              !child.isLockedInheritedProperty
          ? () => _editNodeNumericRange(child)
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
      numericMin: node.isNumericProperty ? node.numericMin : null,
      numericMax: node.isNumericProperty ? node.numericMax : null,
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

  /// Shows the base item's production pipeline next to a basic item's own, so
  /// it is obvious that this variant may be manufactured differently — and
  /// obvious when it already is.
  Widget _buildBasePipelineStrip(BuildContext context) {
    final baseItem = _lookupBaseItem(context);
    final basePipelineId = baseItem?.defaultPipelineId;
    final basePipelineName = (baseItem?.defaultPipelineName ?? '').trim();
    final hasBasePipeline =
        basePipelineId != null && basePipelineId.trim().isNotEmpty;
    final current = (_defaultPipelineId ?? '').trim();
    final matchesBase = hasBasePipeline
        ? current == basePipelineId.trim()
        : current.isEmpty;

    final (Color tone, Color toneBg, String status) = matchesBase
        ? (
            SoftErpTheme.textSecondary,
            SoftErpTheme.cardSurfaceAlt,
            'Same as base item',
          )
        : (SoftErpTheme.infoText, SoftErpTheme.infoBg, 'Different from base');

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: SoftErpTheme.sectionSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  hasBasePipeline
                      ? 'Base item makes this on ${basePipelineName.isEmpty ? basePipelineId.trim() : basePipelineName}'
                      : 'Base item has no default pipeline',
                  style: const TextStyle(
                    color: SoftErpTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: toneBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: tone.withValues(alpha: 0.25)),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: tone,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'This variant can be manufactured on its own route — pick any '
            'pipeline below.',
            style: const TextStyle(
              color: SoftErpTheme.textSecondary,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
          if (!matchesBase && !_isReadOnly) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _defaultPipelineId = hasBasePipeline
                      ? basePipelineId.trim()
                      : null;
                  _handleChange();
                }),
                icon: const Icon(Icons.undo_rounded, size: 15),
                label: const Text("Use base item's pipeline"),
                style: TextButton.styleFrom(
                  foregroundColor: SoftErpTheme.accent,
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The item this variant was spawned from, when it is still in the catalogue.
  ItemDefinition? _lookupBaseItem(BuildContext context) {
    final baseItemId = widget.item?.baseItemId;
    if (baseItemId == null) {
      return null;
    }
    return context
        .read<ItemsProvider>()
        .items
        .where((candidate) => candidate.id == baseItemId)
        .firstOrNull;
  }

  /// Starts a sample record on this item, seeded with the default three-stage
  /// skeleton for the user to overwrite with the trial's real numbers.
  void _addSampleData() {
    setState(() {
      _penPaperBaseline = PenPaperBaseline.createDefault();
      _hasPenPaperBaseline = true;
      _handleChange();
    });
  }

  void _clearSampleData() {
    setState(() {
      _penPaperBaseline = PenPaperBaseline.createDefault();
      _hasPenPaperBaseline = false;
      _handleChange();
    });
  }

  /// The details card for a basic item. Group and unit are shown as inherited
  /// context rather than fields: a spawned variant takes them from its base
  /// item, and changing them on one variant would silently split the set.
  Widget _buildBasicItemDetailsSection(
    BuildContext context,
    GroupsProvider groupsProvider,
    UnitsProvider unitsProvider,
  ) {
    final item = widget.item;
    final group = groupsProvider.findById(_selectedGroupId);
    final unit = unitsProvider.findById(_selectedUnitId ?? -1);
    final baseItem = _lookupBaseItem(context);
    final combinationGroupNames = (item?.combinationGroupIds ?? const <int>[])
        .map((id) => groupsProvider.findById(id)?.name ?? 'Group #$id')
        .toList(growable: false);

    return _SectionCard(
      title: 'Item Details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _formRow(
            children: [
              _buildTextField(
                controller: _nameController,
                label: 'Item Name',
                helper: 'Name of this variant',
                readOnly: _isReadOnly,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _formRow(
            children: [
              _buildTextField(
                controller: _displayNameController,
                label: 'Display Name',
                helper: 'How this variant is labelled across the app',
                readOnly: _isReadOnly,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(
              color: SoftErpTheme.sectionSurface,
              borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
              border: Border.all(color: SoftErpTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.lock_outline_rounded,
                      size: 14,
                      color: SoftErpTheme.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Inherited from the base item',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: SoftErpTheme.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _basicInheritedRow(
                  context,
                  'Base item',
                  baseItem?.displayName.trim().isNotEmpty == true
                      ? baseItem!.displayName
                      : (baseItem?.name ?? 'Item #${item?.baseItemId}'),
                ),
                _basicInheritedRow(context, 'Group', group?.name ?? '—'),
                _basicInheritedRow(
                  context,
                  'Unit',
                  unit?.displayLabel ?? '—',
                ),
                _basicInheritedRow(
                  context,
                  'Combination group',
                  combinationGroupNames.isEmpty
                      ? 'Not in a combination group'
                      : combinationGroupNames.join(', '),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _basicInheritedRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: const TextStyle(
                color: SoftErpTheme.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: SoftErpTheme.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Cycles a property through Text → Numeric → Gauge. Numeric properties are
  /// entered by hand rather than picked from value nodes, so landing on Numeric
  /// asks for the range of numbers the property accepts.
  ///
  /// The type is switched *before* the prompt on purpose: dismissing it leaves
  /// the property Numeric with no limits (editable later from the range pill)
  /// rather than snapping back to Text, which would make the next tap re-ask
  /// and leave Gauge unreachable.
  Future<void> _cycleNodeInputType(_NodeDraft node) async {
    final next = _nextVariationInputType(node.inputType);
    setState(() {
      node.inputType = next;
      // Whichever way we moved, the old range no longer applies.
      node.numericMin = null;
      node.numericMax = null;
    });
    _handleChange();
    if (next != 'Numeric') {
      return;
    }
    final range = await _showNumericRangeDialog(
      context,
      propertyName: node.nameController.text.trim(),
    );
    if (range == null || !mounted) {
      return;
    }
    setState(() {
      node.numericMin = range.min;
      node.numericMax = range.max;
    });
    _handleChange();
  }

  /// Re-opens the range prompt for a property that is already Numeric.
  Future<void> _editNodeNumericRange(_NodeDraft node) async {
    final range = await _showNumericRangeDialog(
      context,
      propertyName: node.nameController.text.trim(),
      initialMin: node.numericMin,
      initialMax: node.numericMax,
    );
    if (range == null || !mounted) {
      return;
    }
    setState(() {
      node.numericMin = range.min;
      node.numericMax = range.max;
    });
    _handleChange();
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

    await showErpFormDialog<void>(
      context,
      maxWidth: 960,
      maxHeight: 660,
      child: _VariationCreationDialog(
        itemName: _nameController.text.trim(),
        topLevelProperties: properties,
        groupStepEnabled: FeatureFlags.isEnabled(
          FeatureKeys.catalogInventoryEnhancements,
        ),
        onAssignToGroup: _assignVariantsToCombinationGroup,
        onEditItem: (item) => ItemsScreen.openEditor(
          context,
          item: item,
          onCreatePipeline: widget.onCreatePipeline,
        ),
        onSpawnItems: (combinations) async {
          final messenger = ScaffoldMessenger.of(context);
          if (_selectedGroupId == null || _selectedUnitId == null) {
            messenger.showSnackBar(
              const SnackBar(
                content: Text(
                  'Select both a group and a unit for the base item before spawning variants.',
                ),
              ),
            );
            return const <ItemDefinition>[];
          }
          final itemsProvider = context.read<ItemsProvider>();
          final created = <ItemDefinition>[];
          for (final combo in combinations) {
            final valuesStr = combo.map((option) => option.label).join(' - ');
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
              cadFileKey: _cadFileKeyController.text.trim(),
              cadFileName: _cadFileNameController.text.trim(),
              attachments: _attachmentInputs,
              machineIds: _selectedMachineIds.toList(growable: false),
              dieIds: _selectedDieIds.toList(growable: false),
              developedForClientId: _developedForClientId,
              availableForPurchase: _availableForPurchase,
            );
            final createdItem = await itemsProvider.createItem(input);
            if (createdItem != null) {
              created.add(createdItem);
            }
          }
          // The dialog stays open and moves to its group-and-summary steps, so
          // there is no snackbar here — the footer reports the count.
          return created;
        },
      ),
    );
  }

  /// Enhancement 2.2 — files freshly spawned variants into a combination group,
  /// creating the group first when the sidebar asked for a new one. Returns null
  /// on success, or a message for the dialog's error banner.
  Future<String?> _assignVariantsToCombinationGroup(
    List<int> itemIds,
    _CombinationGroupChoice choice,
  ) async {
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
        return groupsProvider.errorMessage ??
            'Could not create the combination group.';
      }
      groupId = created.id;
    }
    if (groupId == null) {
      return 'Select a combination group, or skip this step.';
    }

    final assigned = await groupsProvider.assignItemsToCombinationGroup(
      groupId: groupId,
      itemIds: itemIds,
    );
    if (assigned == null) {
      return groupsProvider.errorMessage ??
          'Could not add variants to the combination group.';
    }
    return null;
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
              cadFileKey: _cadFileKeyController.text.trim(),
              cadFileName: _cadFileNameController.text.trim(),
              attachments: _attachmentInputs,
              machineIds: _selectedMachineIds.toList(growable: false),
              dieIds: _selectedDieIds.toList(growable: false),
              developedForClientId: _developedForClientId,
              availableForPurchase: _availableForPurchase,
              penPaperBaseline: _hasPenPaperBaseline
                  ? _penPaperBaseline
                  : null,
            ),
          )
        : await itemsProvider.updateItem(
            UpdateItemInput(
              id: widget.item!.id,
              // A spawned variant must stay attached to its base item across
              // edits, or it silently graduates into a base item of its own.
              baseItemId: widget.item!.baseItemId,
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
              cadFileKey: _cadFileKeyController.text.trim(),
              cadFileName: _cadFileNameController.text.trim(),
              attachments: _attachmentInputs,
              machineIds: _selectedMachineIds.toList(growable: false),
              dieIds: _selectedDieIds.toList(growable: false),
              developedForClientId: _developedForClientId,
              availableForPurchase: _availableForPurchase,
              penPaperBaseline: _hasPenPaperBaseline
                  ? _penPaperBaseline
                  : null,
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

  /// Inserts the standard 16px gap between whichever sections are visible, so
  /// hiding one never leaves a double gap behind.
  /// Greedy shortest-column packing.
  ///
  /// Each section goes to whichever column is currently shortest, so the
  /// columns finish at roughly the same height however many sections are
  /// switched on. Item Details is placed first and so always anchors column 1.
  List<List<Widget>> _packSections(List<_SectionEntry> entries, int columns) {
    final buckets = List.generate(columns, (_) => <Widget>[], growable: false);
    final heights = List<double>.filled(columns, 0);
    for (final entry in entries) {
      var target = 0;
      for (var index = 1; index < columns; index++) {
        if (heights[index] < heights[target]) {
          target = index;
        }
      }
      buckets[target].add(entry.child);
      heights[target] += entry.weight;
    }
    // Drop trailing empties so a spare column never renders as dead space.
    return buckets.where((bucket) => bucket.isNotEmpty).toList(growable: false);
  }

  List<Widget> _withSectionGaps(List<Widget> sections) {
    final spaced = <Widget>[];
    for (var index = 0; index < sections.length; index++) {
      if (index > 0) {
        spaced.add(const SizedBox(height: 16));
      }
      spaced.add(sections[index]);
    }
    return spaced;
  }

  /// Loads the machine and die pickers' options. Failure is non-fatal — the
  /// pickers just show an empty list and the rest of the form still works.
  Future<void> _loadLinkOptions() async {
    final sections = context.read<ItemFormSectionsProvider>().sections;
    if (!sections.machines && !sections.dies) {
      return;
    }
    ItemLinkOptionsService? service;
    try {
      service = context.read<ItemLinkOptionsService>();
    } catch (_) {
      // Host app hasn't provided the service (e.g. a lean embedding); the
      // machine/die pickers simply stay empty.
      return;
    }
    setState(() => _isLoadingLinkOptions = true);
    try {
      final machines = sections.machines
          ? await service.fetchMachines()
          : const <ItemLinkOption>[];
      final dies = sections.dies
          ? await service.fetchDies()
          : const <ItemLinkOption>[];
      if (!mounted) return;
      setState(() {
        _machineOptions = machines;
        _dieOptions = dies;
      });
    } catch (_) {
      // Swallow: an unreachable machines/dies list must not block item saving.
    } finally {
      if (mounted) {
        setState(() => _isLoadingLinkOptions = false);
      }
    }
  }

  Future<void> _addAttachment() async {
    final file = await openFile();
    if (file == null || !mounted) {
      return;
    }

    final sizeBytes = await file.length();
    if (sizeBytes > _kMaxAttachmentBytes) {
      showAppSnack(
        const SnackBar(
          content: Text('Files are limited to 50 MB.'),
        ),
      );
      return;
    }
    if (!mounted) return;

    final draft = _AttachmentDraft(
      label: '',
      objectKey: '',
      fileName: file.name,
      onChanged: _handleChange,
    );
    setState(() {
      draft.isUploading = true;
      _attachments.add(draft);
    });

    final service = _resolveAssetService(context);

    try {
      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes).toString();
      final contentType =
          file.mimeType ??
          lookupMimeType(file.name) ??
          'application/octet-stream';

      final intent = await service.createUploadIntent(
        GenericAssetUploadIntentInput(
          fileName: file.name,
          contentType: contentType,
          sizeBytes: bytes.length,
          sha256: digest,
        ),
      );
      final response = await http.put(
        intent.uploadUrl,
        headers: intent.headers,
        body: bytes,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          _describeS3UploadFailure(response.statusCode, response.body),
        );
      }
      if (intent.objectKey.isEmpty) {
        throw Exception('Upload did not return an object key.');
      }
      if (!mounted) return;
      setState(() {
        draft.objectKey = intent.objectKey;
        draft.isUploading = false;
      });
      _handleChange();
    } catch (error) {
      if (mounted) {
        // Drop the half-created row rather than leave an un-uploadable stub
        // that would be silently skipped on save.
        setState(() {
          _attachments.remove(draft);
        });
        draft.dispose();
      }
      showAppSnack(SnackBar(content: Text('File upload failed: $error')));
    }
  }

  List<ItemAttachmentInput> get _attachmentInputs => _attachments
      .where((draft) => draft.objectKey.trim().isNotEmpty)
      .map(
        (draft) => ItemAttachmentInput(
          label: draft.labelController.text.trim(),
          objectKey: draft.objectKey.trim(),
          fileName: draft.fileName,
        ),
      )
      .toList(growable: false);

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
    this.onEditNumericRange,
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
  final VoidCallback? onEditNumericRange;
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
                          // The optional Code field yields its space when the
                          // row is tight, so the name being typed stays legible
                          // instead of both shrinking to a few characters.
                          child: LayoutBuilder(
                            builder: (context, nameConstraints) {
                            final showCodeField =
                                nameConstraints.maxWidth >= 260;
                            return Row(
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
                              if (showCodeField) ...[
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
                            ],
                          );
                            },
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
                          _InputTypePill(
                            inputType: draft.inputType,
                            onTap: onToggleInputType!,
                          ),
                        if (draft.isNumericProperty) ...[
                          const SizedBox(width: 4),
                          _NumericRangePill(
                            label: draft.numericRangeLabel,
                            onTap: onEditNumericRange,
                          ),
                        ],
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
          // Wrap, not Row: an Expanded title next to a wide action row gets
          // squeezed toward zero width in a narrow column and then renders one
          // letter per line. Wrapping lets the action drop to its own line
          // instead, and the title keeps its natural width.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1F2937),
                ),
              ),
              if (action != null) action!,
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

/// The upload service every file picker in this editor uses.
///
/// `/api/upload/generic` sits behind the same auth as everything else, so the
/// intent call has to go out on the app's authenticated client. Building a bare
/// [GenericAssetService] here fails with "Authentication required"; the host
/// registers a configured one instead.
///
/// The fallback keeps lean embeddings that don't register it working, in mock
/// mode — the only mode a client with no credentials could succeed in.
/// A section card plus a rough height estimate, used to balance the columns.
///
/// The weight only needs to be right relative to the other sections — it drives
/// which column a card lands in, never how it is laid out.
/// Shown in a basic item's Sample Data card before any trial run is recorded.
class _EmptySampleDataPrompt extends StatelessWidget {
  const _EmptySampleDataPrompt({required this.onAdd});

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'No sample run recorded for this item yet. Add one to capture the '
          'input, output, scrap and rejection weights of a trial batch.',
          style: TextStyle(
            color: SoftErpTheme.textSecondary,
            fontSize: 12.5,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            label: 'Add sample data',
            icon: Icons.science_outlined,
            variant: AppButtonVariant.secondary,
            onPressed: onAdd,
          ),
        ),
      ],
    );
  }
}

class _SectionEntry {
  const _SectionEntry(this.child, this.weight);

  final Widget child;
  final double weight;
}

/// Turns a failed S3 upload into a message that says what actually went wrong.
///
/// S3 answers a rejected presigned PUT with an XML body whose `<Code>` is the
/// only thing distinguishing the causes — `SignatureDoesNotMatch` (the request
/// didn't match what was signed, usually Content-Type), `AccessDenied` (the
/// signing identity lacks s3:PutObject, or a bucket policy blocked it),
/// `ExpiredToken`, and so on. Reporting the bare status code throws that away.
String _describeS3UploadFailure(int statusCode, String body) {
  String? tagValue(String tag) {
    final match = RegExp('<$tag>(.*?)</$tag>', dotAll: true).firstMatch(body);
    return match?.group(1)?.trim();
  }

  final code = tagValue('Code');
  final message = tagValue('Message');
  if (code == null && message == null) {
    return 'upload rejected with status $statusCode.';
  }
  return '$statusCode ${code ?? ''}${message == null ? '' : ' — $message'}'
      .trim();
}

/// Opens the system file picker, reporting failure instead of throwing past the
/// caller.
///
/// A type group the host platform rejects makes openFile throw before any of
/// the upload code runs, which presents as a button that does nothing.
Future<XFile?> _pickFileOrNull(XTypeGroup group, String what) async {
  try {
    return await openFile(acceptedTypeGroups: <XTypeGroup>[group]);
  } catch (error) {
    showAppSnack(
      SnackBar(content: Text('Could not open the $what picker: $error')),
    );
    return null;
  }
}

GenericAssetService _resolveAssetService(BuildContext context) {
  try {
    return context.read<GenericAssetService>();
  } catch (_) {
    return GenericAssetService(
      baseUrl: const String.fromEnvironment(
        'PAPER_API_BASE_URL',
        defaultValue: 'http://localhost:8080',
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
    // Extensions only. Declaring mimeTypes as well makes the macOS picker
    // reject the type group outright, and openFile then throws before the
    // try below — which looked like the button doing nothing at all.
    final file = await _pickFileOrNull(
      const XTypeGroup(
        label: 'Images',
        extensions: ['png', 'jpg', 'jpeg', 'webp'],
      ),
      'image',
    );
    if (file == null || !mounted) {
      return;
    }

    setState(() => _isUploading = true);
    final service = _resolveAssetService(context);

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
            _describeS3UploadFailure(response.statusCode, response.body),
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

/// "Developed for" — links the item to the client it was developed for, so it
/// can be listed under them. Renders as a button until a client is picked, then
/// as a clearable chip.
class _DevelopedForField extends StatelessWidget {
  const _DevelopedForField({
    required this.clientId,
    required this.readOnly,
    required this.onChanged,
  });

  final int? clientId;
  final bool readOnly;
  final ValueChanged<int?> onChanged;

  Future<void> _pick(BuildContext context, List<ClientDefinition> clients) async {
    final selected = await showSearchableSelectDialog<int>(
      context: context,
      title: 'Developed for',
      searchHintText: 'Search clients',
      options: clients
          .map(
            (client) => SearchableSelectOption<int>(
              value: client.id,
              label: client.name,
              searchText: client.name,
            ),
          )
          .toList(growable: false),
      selectedValue: clientId,
    );
    if (selected != null) {
      onChanged(selected.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clients = context
        .watch<ClientsProvider>()
        .clients
        .where((client) => !client.isArchived)
        .toList(growable: false);
    final selected = clients.where((c) => c.id == clientId).firstOrNull;

    return Row(
      children: [
        const Text(
          'Developed for',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(width: 12),
        if (selected != null)
          Chip(
            label: Text(selected.name, style: const TextStyle(fontSize: 12.5)),
            onDeleted: readOnly ? null : () => onChanged(null),
          )
        else if (clientId != null)
          // The client was archived or removed after this item was saved.
          Chip(
            label: Text(
              'Client #$clientId',
              style: const TextStyle(fontSize: 12.5),
            ),
            onDeleted: readOnly ? null : () => onChanged(null),
          ),
        if (!readOnly) ...[
          const SizedBox(width: 8),
          AppButton(
            label: clientId == null ? 'Select client' : 'Change',
            icon: Icons.person_search_outlined,
            variant: AppButtonVariant.secondary,
            onPressed: () => _pick(context, clients),
          ),
        ],
      ],
    );
  }
}

/// A presigned PUT sends the whole file from memory, so cap the size.
const int _kMaxAttachmentBytes = 50 * 1024 * 1024;

/// One in-progress extra file: the user's label plus the uploaded object key.
class _AttachmentDraft {
  _AttachmentDraft({
    this.id,
    required String label,
    required this.objectKey,
    required this.fileName,
    required VoidCallback onChanged,
  }) : labelController = TextEditingController(text: label) {
    labelController.addListener(onChanged);
  }

  final int? id;
  final TextEditingController labelController;
  String objectKey;
  final String fileName;
  bool isUploading = false;

  void dispose() {
    labelController.dispose();
  }
}

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({
    required this.draft,
    required this.readOnly,
    required this.onRemove,
  });

  final _AttachmentDraft draft;
  final bool readOnly;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFDDE1F0)),
          ),
          child: draft.isUploading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(
                  Icons.insert_drive_file_outlined,
                  size: 19,
                  color: Color(0xFF64748B),
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextFormField(
            controller: draft.labelController,
            readOnly: readOnly,
            decoration: InputDecoration(
              labelText: 'Label',
              hintText: 'e.g. Datasheet',
              helperText: draft.fileName,
              isDense: true,
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
              ),
            ),
          ),
        ),
        if (!readOnly) ...[
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Remove file',
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 18),
            color: const Color(0xFF64748B),
          ),
        ],
      ],
    );
  }
}

/// Multi-select for machines and dies: a searchable "add" field plus a chip per
/// selection.
class _LinkOptionPicker extends StatelessWidget {
  const _LinkOptionPicker({
    required this.options,
    required this.selectedIds,
    required this.readOnly,
    required this.isLoading,
    required this.emptyMessage,
    required this.hintText,
    required this.searchHintText,
    required this.onChanged,
  });

  final List<ItemLinkOption> options;
  final Set<String> selectedIds;
  final bool readOnly;
  final bool isLoading;
  final String emptyMessage;
  final String hintText;
  final String searchHintText;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final optionsById = {for (final option in options) option.id: option};
    final addable = options
        .where((option) => !selectedIds.contains(option.id))
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (selectedIds.isEmpty)
          Text(
            isLoading ? 'Loading…' : emptyMessage,
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final id in selectedIds)
                Chip(
                  label: Text(
                    // An id with no matching option means the record was
                    // deleted after this item was saved; show the raw id
                    // rather than dropping the link silently.
                    optionsById[id]?.label ?? 'Removed ($id)',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  onDeleted: readOnly
                      ? null
                      : () => onChanged({...selectedIds}..remove(id)),
                ),
            ],
          ),
        if (!readOnly && addable.isNotEmpty) ...[
          const SizedBox(height: 12),
          SearchableSelectField<String>(
            options: addable
                .map(
                  (option) => SearchableSelectOption<String>(
                    value: option.id,
                    label: option.label,
                    searchText: '${option.label} ${option.subtitle}',
                  ),
                )
                .toList(growable: false),
            value: null,
            onChanged: (value) {
              if (value == null) return;
              onChanged({...selectedIds}..add(value));
            },
            decoration: InputDecoration(hintText: hintText),
            searchHintText: searchHintText,
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// CAD File Picker
// ---------------------------------------------------------------------------

class _CadFilePickerField extends StatefulWidget {
  const _CadFilePickerField({
    required this.keyController,
    required this.nameController,
    required this.readOnly,
  });

  /// Permanent S3 object key of the uploaded drawing. Presigned URLs expire,
  /// so the key — not a link — is what gets saved on the item.
  final TextEditingController keyController;

  /// Original file name, shown instead of the opaque object key.
  final TextEditingController nameController;
  final bool readOnly;

  @override
  State<_CadFilePickerField> createState() => _CadFilePickerFieldState();
}

class _CadFilePickerFieldState extends State<_CadFilePickerField> {
  /// Deliberately broad — shops exchange native part files as often as the
  /// neutral interchange formats.
  static const List<String> _cadExtensions = [
    'dwg',
    'dxf',
    'step',
    'stp',
    'iges',
    'igs',
    'stl',
    'sat',
    'sldprt',
    'sldasm',
    'ipt',
    'iam',
    'catpart',
    'catproduct',
    'prt',
    'asm',
    '3dm',
    'obj',
    'x_t',
    'x_b',
    'f3d',
  ];

  /// A presigned PUT sends the whole file from memory, so cap the size rather
  /// than let a large assembly stall the editor.
  static const int _maxSizeBytes = 50 * 1024 * 1024;

  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    widget.keyController.addListener(_rebuild);
    widget.nameController.addListener(_rebuild);
  }

  @override
  void dispose() {
    widget.keyController.removeListener(_rebuild);
    widget.nameController.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  String get _extension {
    final name = widget.nameController.text.trim();
    if (!name.contains('.')) {
      return 'CAD';
    }
    return name.split('.').last.toUpperCase();
  }

  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  Future<void> _pickAndUploadCadFile() async {
    final file = await _pickFileOrNull(
      const XTypeGroup(label: 'CAD files', extensions: _cadExtensions),
      'CAD file',
    );
    if (file == null || !mounted) {
      return;
    }

    final sizeBytes = await file.length();
    if (sizeBytes > _maxSizeBytes) {
      showAppSnack(
        SnackBar(
          content: Text(
            'CAD file is ${_formatSize(sizeBytes)} — the limit is '
            '${_formatSize(_maxSizeBytes)}.',
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _isUploading = true);
    final service = _resolveAssetService(context);

    try {
      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes).toString();
      // CAD formats have no registered MIME type, so octet-stream is the norm.
      final contentType =
          file.mimeType ??
          lookupMimeType(file.name) ??
          'application/octet-stream';

      final intent = await service.createUploadIntent(
        GenericAssetUploadIntentInput(
          fileName: file.name,
          contentType: contentType,
          sizeBytes: bytes.length,
          sha256: digest,
        ),
      );

      final response = await http.put(
        intent.uploadUrl,
        headers: intent.headers,
        body: bytes,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          _describeS3UploadFailure(response.statusCode, response.body),
        );
      }

      if (intent.objectKey.isEmpty) {
        throw Exception('Upload did not return an object key.');
      }

      // Store the key, not intent.readUrl — that link expires, the key does not.
      widget.keyController.text = intent.objectKey;
      widget.nameController.text = file.name;
      showAppSnack(
        SnackBar(content: Text('${file.name} uploaded successfully.')),
      );
    } catch (error) {
      showAppSnack(SnackBar(content: Text('CAD upload failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileName = widget.nameController.text.trim();
    final hasFile = widget.keyController.text.trim().isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFDDE1F0)),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasFile
                    ? Icons.description_outlined
                    : Icons.architecture_outlined,
                size: 34,
                color: hasFile
                    ? const Color(0xFF64748B)
                    : const Color(0xFFCBD5E1),
              ),
              if (hasFile) ...[
                const SizedBox(height: 6),
                Text(
                  _extension,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasFile
                    ? (fileName.isEmpty ? 'CAD file attached' : fileName)
                    : 'No CAD file attached',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: hasFile
                      ? const Color(0xFF1F2937)
                      : const Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                hasFile
                    ? 'Stays attached to this item until you remove it. '
                          'Download it from the item view.'
                    : 'Optional — DWG, DXF, STEP, IGES, STL, SLDPRT and similar',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                ),
              ),
              if (!widget.readOnly) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppButton(
                      label: hasFile ? 'Replace' : 'Upload CAD File',
                      icon: Icons.upload_file,
                      variant: AppButtonVariant.secondary,
                      isLoading: _isUploading,
                      onPressed: _pickAndUploadCadFile,
                    ),
                    if (hasFile)
                      AppButton(
                        label: 'Remove',
                        icon: Icons.delete_outline,
                        variant: AppButtonVariant.secondary,
                        onPressed: () {
                          widget.keyController.clear();
                          widget.nameController.clear();
                        },
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One choice a property contributes to a variant: either a value node picked
/// from the variation tree, or — for Numeric properties, which have no value
/// nodes — a number typed by the user.
class _VariantOption {
  const _VariantOption.value(this.property, _NodeDraft node)
    : valueNode = node,
      typedNumber = null;

  const _VariantOption.number(this.property, double number)
    : valueNode = null,
      typedNumber = number;

  final _NodeDraft property;
  final _NodeDraft? valueNode;
  final double? typedNumber;

  String get label {
    if (typedNumber != null) {
      return _formatNumericBound(typedNumber!);
    }
    final name = valueNode!.nameController.text.trim();
    return name.isEmpty ? 'Unnamed Value' : name;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _VariantOption &&
        identical(other.property, property) &&
        identical(other.valueNode, valueNode) &&
        other.typedNumber == typedNumber;
  }

  @override
  int get hashCode =>
      Object.hash(identityHashCode(property), identityHashCode(valueNode), typedNumber);
}

/// The dialog runs as three steps in one window rather than a chain of popups:
/// build the combinations, then file the spawned variants into a combination
/// group from a sidebar, then be told what a basic item lets you edit.
enum _SpawnPhase { building, chooseGroup, done }

class _VariationCreationDialog extends StatefulWidget {
  const _VariationCreationDialog({
    required this.itemName,
    required this.topLevelProperties,
    required this.onSpawnItems,
    required this.onAssignToGroup,
    required this.onEditItem,
    required this.groupStepEnabled,
  });

  /// Base item name, used for the generated-name preview.
  final String itemName;
  final List<_NodeDraft> topLevelProperties;

  /// Creates the variants and returns them. An empty list means nothing was
  /// created, which leaves the dialog on the building step.
  final Future<List<ItemDefinition>> Function(List<List<_VariantOption>>)
  onSpawnItems;

  /// Files the spawned variants into a combination group. Returns null on
  /// success, or a message to show in the error banner.
  final Future<String?> Function(List<int> itemIds, _CombinationGroupChoice)
  onAssignToGroup;

  /// Opens the basic-item editor for one spawned variant, returning the saved
  /// item so the list can pick up a rename.
  final Future<ItemDefinition?> Function(ItemDefinition item) onEditItem;

  /// Whether the combination-group step is offered at all (Enhancement 2.2 is
  /// behind a feature flag). When off, spawning goes straight to the last step.
  final bool groupStepEnabled;

  @override
  State<_VariationCreationDialog> createState() =>
      _VariationCreationDialogState();
}

class _VariationCreationDialogState extends State<_VariationCreationDialog> {
  /// Selections per property, in the order they were picked, so generated
  /// combinations come out in a predictable order.
  final Map<_NodeDraft, List<_VariantOption>> _selected = {};

  /// Number field per Numeric property.
  final Map<_NodeDraft, TextEditingController> _numberControllers = {};

  final List<List<_VariantOption>> _createdCombinations = [];
  int? _selectedIndex;
  String? _error;
  bool _isSpawning = false;

  _SpawnPhase _phase = _SpawnPhase.building;

  /// The variants that were actually created, once spawning has run.
  List<ItemDefinition> _spawnedItems = const <ItemDefinition>[];

  // Combination-group sidebar state.
  bool _createNewGroup = false;
  int? _selectedCombinationGroupId;
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _groupDescriptionController =
      TextEditingController();
  bool _isAssigning = false;

  /// Name of the group the variants ended up in, for the closing summary.
  String? _assignedGroupName;

  @override
  void initState() {
    super.initState();
    for (final prop in widget.topLevelProperties) {
      _selected[prop] = <_VariantOption>[];
      if (prop.isNumericProperty) {
        _numberControllers[prop] = TextEditingController();
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _numberControllers.values) {
      controller.dispose();
    }
    _groupNameController.dispose();
    _groupDescriptionController.dispose();
    super.dispose();
  }

  // --- selection -----------------------------------------------------------

  bool get _isEditingCard => _selectedIndex != null;

  bool get _hasAnySelection =>
      _selected.values.any((options) => options.isNotEmpty);

  List<_NodeDraft> _valuesOf(_NodeDraft property) => property.children
      .where((child) => child.kind == ItemVariationNodeKind.value)
      .toList(growable: false);

  /// How many variants the current selection would produce.
  int get _pendingCombinationCount {
    var count = 0;
    for (final options in _selected.values) {
      if (options.isEmpty) continue;
      count = count == 0 ? options.length : count * options.length;
    }
    return count;
  }

  void _toggleOption(_NodeDraft property, _VariantOption option) {
    setState(() {
      _error = null;
      final options = _selected[property]!;
      if (_isEditingCard) {
        // Editing one variant: a property holds exactly one value, and the
        // pick is written straight through to the card.
        final combo = List<_VariantOption>.from(
          _createdCombinations[_selectedIndex!],
        );
        combo.removeWhere((existing) => identical(existing.property, property));
        if (!options.contains(option)) {
          combo.add(option);
          options
            ..clear()
            ..add(option);
        } else {
          options.clear();
        }
        // Keep the variant's values in variation-tree order so its generated
        // name doesn't reshuffle when a value is edited.
        combo.sort(
          (a, b) => widget.topLevelProperties
              .indexOf(a.property)
              .compareTo(widget.topLevelProperties.indexOf(b.property)),
        );
        _createdCombinations[_selectedIndex!] = combo;
        return;
      }
      if (options.contains(option)) {
        options.remove(option);
      } else {
        options.add(option);
      }
    });
  }

  void _selectAllValues(_NodeDraft property) {
    setState(() {
      _error = null;
      final options = _selected[property]!;
      final all = _valuesOf(
        property,
      ).map((node) => _VariantOption.value(property, node)).toList();
      if (options.length == all.length) {
        options.clear();
      } else {
        options
          ..clear()
          ..addAll(all);
      }
    });
  }

  /// Commits whatever is typed in a Numeric property's field, after checking it
  /// against the range configured on the variation tree.
  void _addTypedNumber(_NodeDraft property) {
    final controller = _numberControllers[property]!;
    final raw = controller.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Enter a number for ${_propertyName(property)}.');
      return;
    }
    final value = double.tryParse(raw);
    if (value == null) {
      setState(
        () => _error = '"$raw" is not a valid number for '
            '${_propertyName(property)}.',
      );
      return;
    }
    if (!property.acceptsNumber(value)) {
      setState(
        () => _error = '${_propertyName(property)} accepts '
            '${property.numericRangeLabel}.',
      );
      return;
    }
    final option = _VariantOption.number(property, value);
    if (_selected[property]!.contains(option)) {
      setState(() {
        _error = null;
        controller.clear();
      });
      return;
    }
    controller.clear();
    _toggleOption(property, option);
  }

  String _propertyName(_NodeDraft property) {
    final name = property.nameController.text.trim();
    return name.isEmpty ? 'Unnamed Property' : name;
  }

  // --- generated variants --------------------------------------------------

  void _selectCard(int index) {
    setState(() {
      _error = null;
      _selectedIndex = index;
      for (final options in _selected.values) {
        options.clear();
      }
      for (final option in _createdCombinations[index]) {
        _selected[option.property]?.add(option);
      }
    });
  }

  void _deselectCard() {
    setState(() {
      _error = null;
      _selectedIndex = null;
      for (final options in _selected.values) {
        options.clear();
      }
    });
  }

  void _duplicateCard(int index) {
    setState(() {
      _createdCombinations.insert(
        index + 1,
        List<_VariantOption>.from(_createdCombinations[index]),
      );
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

  void _clearAllCards() {
    setState(() {
      _createdCombinations.clear();
      _deselectCard();
    });
  }

  /// Cartesian product of the selected options, skipping combinations that are
  /// already on the list.
  void _generateCombinations() {
    if (!_hasAnySelection) {
      setState(
        () => _error =
            'Select at least one value before generating combinations.',
      );
      return;
    }
    var newCombos = <List<_VariantOption>>[<_VariantOption>[]];
    for (final prop in widget.topLevelProperties) {
      final selectedForProp = _selected[prop]!;
      if (selectedForProp.isEmpty) continue;
      final expanded = <List<_VariantOption>>[];
      for (final combo in newCombos) {
        for (final option in selectedForProp) {
          expanded.add([...combo, option]);
        }
      }
      newCombos = expanded;
    }

    var added = 0;
    setState(() {
      _error = null;
      for (final combo in newCombos) {
        final exists = _createdCombinations.any((existing) {
          if (existing.length != combo.length) return false;
          for (var i = 0; i < combo.length; i++) {
            if (existing[i] != combo[i]) return false;
          }
          return true;
        });
        if (!exists) {
          _createdCombinations.add(combo);
          added++;
        }
      }
      if (added == 0) {
        _error = 'Those combinations are already on the list.';
      }
    });
  }

  String _comboLabel(List<_VariantOption> combo) =>
      combo.map((option) => option.label).join(' - ');

  Future<void> _spawn() async {
    if (_createdCombinations.isEmpty) {
      setState(() => _error = 'Generate at least one variant before spawning.');
      return;
    }
    // Editing a variant down to no values would spawn an item named after the
    // base item alone — make the user give it at least one value back.
    final emptyIndex = _createdCombinations.indexWhere((c) => c.isEmpty);
    if (emptyIndex != -1) {
      setState(() {
        _error = 'Variant #${emptyIndex + 1} has no values. Give it at least '
            'one value or remove it.';
      });
      return;
    }
    setState(() {
      _error = null;
      _isSpawning = true;
    });
    final spawned = await widget.onSpawnItems(_createdCombinations);
    if (!mounted) return;
    setState(() {
      _isSpawning = false;
      if (spawned.isEmpty) {
        _error = 'No variants were created. Check the messages above and retry.';
        return;
      }
      _spawnedItems = spawned;
      _deselectCard();
      // Nothing to pick from on a fresh install, so open on the create form.
      _createNewGroup = context.read<GroupsProvider>().combinationGroups.isEmpty;
      // The window stays open and grows a sidebar instead of handing off to a
      // popup: filing the variants and learning what they can carry is part of
      // creating them, not a separate errand.
      _phase = widget.groupStepEnabled
          ? _SpawnPhase.chooseGroup
          : _SpawnPhase.done;
    });
  }

  /// Opens one variant's editor and folds any rename back into the list, so the
  /// row keeps matching the item after the editor closes.
  Future<void> _editSpawnedItem(int index) async {
    final updated = await widget.onEditItem(_spawnedItems[index]);
    if (!mounted || updated == null) {
      return;
    }
    setState(() {
      final next = List<ItemDefinition>.from(_spawnedItems);
      next[index] = updated;
      _spawnedItems = next;
    });
  }

  // --- combination-group sidebar -------------------------------------------

  Future<void> _assignToGroup() async {
    final choice = _createNewGroup
        ? _CombinationGroupChoice.create(
            newName: _groupNameController.text.trim(),
            newDescription: _groupDescriptionController.text.trim(),
          )
        : (_selectedCombinationGroupId == null
              ? null
              : _CombinationGroupChoice.existing(_selectedCombinationGroupId!));
    if (choice == null) {
      setState(() => _error = 'Select a combination group, or skip this step.');
      return;
    }
    if (choice.isCreateNew && choice.newName.isEmpty) {
      setState(
        () => _error = 'Enter a name for the new combination group.',
      );
      return;
    }

    setState(() {
      _error = null;
      _isAssigning = true;
    });
    final failure = await widget.onAssignToGroup(
      _spawnedItems.map((item) => item.id).toList(growable: false),
      choice,
    );
    if (!mounted) return;
    setState(() {
      _isAssigning = false;
      if (failure != null) {
        _error = failure;
        return;
      }
      _assignedGroupName = choice.isCreateNew
          ? choice.newName
          : context
                    .read<GroupsProvider>()
                    .findById(choice.existingGroupId)
                    ?.name ??
                'the combination group';
      _phase = _SpawnPhase.done;
    });
  }

  void _skipGroupStep() {
    setState(() {
      _error = null;
      _phase = _SpawnPhase.done;
    });
  }

  // --- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final building = _phase == _SpawnPhase.building;
    return ErpFormScaffold(
      title: 'Variation Creation',
      subtitle: switch (_phase) {
        _SpawnPhase.building =>
          'Pick the values each property should contribute, generate every '
              'combination, then spawn them as their own items.',
        _SpawnPhase.chooseGroup =>
          'Your variants exist. File them into a combination group so they '
              'stay together across orders and inventory.',
        _SpawnPhase.done =>
          'Your variants are basic items — each one can now carry its own '
              'photo, files, pipeline and sample data.',
      },
      bodyScrollable: false,
      bodyPadding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      eyebrow: widget.itemName.trim().isEmpty
          ? null
          : SoftStatusPill(label: widget.itemName.trim()),
      errorBanner: _error == null
          ? null
          : ErpFormMessageBanner(message: _error!),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 720;
          final panes = building
              ? <Widget>[_buildPickerPane(), _buildResultsPane()]
              : <Widget>[_buildSpawnedPane(), _buildSidebar()];
          if (stacked) {
            return Column(
              children: [
                Expanded(child: panes[0]),
                const SizedBox(height: 14),
                Expanded(child: panes[1]),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: building ? 5 : 6, child: panes[0]),
              const SizedBox(width: 16),
              // Post-spawn the second pane is a true sidebar: a fixed, narrower
              // rail beside the variants rather than an equal half.
              building
                  ? Expanded(flex: 4, child: panes[1])
                  : SizedBox(width: 320, child: panes[1]),
            ],
          );
        },
      ),
      footer: switch (_phase) {
        _SpawnPhase.building => _buildBuildingFooter(),
        _SpawnPhase.chooseGroup => _buildGroupFooter(),
        _SpawnPhase.done => _buildDoneFooter(),
      },
    );
  }

  Widget _buildBuildingFooter() {
    final variantCount = _createdCombinations.length;
    return Row(
      children: [
        Expanded(
          child: Text(
            variantCount == 0
                ? 'No variants generated yet.'
                : '$variantCount variant${variantCount == 1 ? '' : 's'} ready to spawn.',
            style: const TextStyle(
              color: SoftErpTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.secondary,
          onPressed: _isSpawning ? null : () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 12),
        AppButton(
          label: variantCount == 0
              ? 'Spawn Variants'
              : 'Spawn $variantCount Variant${variantCount == 1 ? '' : 's'}',
          icon: Icons.auto_awesome_rounded,
          isLoading: _isSpawning,
          onPressed: variantCount == 0 || _isSpawning ? null : _spawn,
        ),
      ],
    );
  }

  Widget _buildGroupFooter() {
    return Row(
      children: [
        Expanded(
          child: Text(
            '${_spawnedItems.length} variant${_spawnedItems.length == 1 ? '' : 's'} spawned.',
            style: const TextStyle(
              color: SoftErpTheme.successText,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        AppButton(
          label: 'Skip for now',
          variant: AppButtonVariant.secondary,
          onPressed: _isAssigning ? null : _skipGroupStep,
        ),
        const SizedBox(width: 12),
        AppButton(
          label: 'Add to group',
          icon: Icons.playlist_add_rounded,
          isLoading: _isAssigning,
          onPressed: _isAssigning ? null : _assignToGroup,
        ),
      ],
    );
  }

  Widget _buildDoneFooter() {
    return Row(
      children: [
        Expanded(
          child: Text(
            _assignedGroupName == null
                ? '${_spawnedItems.length} variant${_spawnedItems.length == 1 ? '' : 's'} spawned.'
                : '${_spawnedItems.length} variant${_spawnedItems.length == 1 ? '' : 's'} added to $_assignedGroupName.',
            style: const TextStyle(
              color: SoftErpTheme.successText,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        AppButton(
          label: 'Done',
          icon: Icons.check_rounded,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  // --- post-spawn: the variants and the sidebar ----------------------------

  Widget _buildSpawnedPane() {
    final canEdit = _phase == _SpawnPhase.done;
    return _paneShell(
      title: 'Spawned variants',
      caption: canEdit
          ? 'Open one to add its photo, files, pipeline or sample data.'
          : 'These items now exist in the catalogue.',
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _spawnedItems.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final item = _spawnedItems[index];
          final label = item.displayName.trim().isEmpty
              ? item.name
              : item.displayName;
          return Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            decoration: BoxDecoration(
              color: SoftErpTheme.cardSurface,
              borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
              border: Border.all(color: SoftErpTheme.border),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: SoftErpTheme.successText,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SoftErpTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (canEdit)
                  TextButton.icon(
                    onPressed: () => _editSpawnedItem(index),
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    label: const Text('Edit'),
                    style: TextButton.styleFrom(
                      foregroundColor: SoftErpTheme.accent,
                      textStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSidebar() {
    return _phase == _SpawnPhase.chooseGroup
        ? _buildGroupSidebar()
        : _buildBasicItemSidebar();
  }

  Widget _buildGroupSidebar() {
    final combinationGroups = context.watch<GroupsProvider>().combinationGroups;
    return _paneShell(
      title: 'Combination group',
      caption: 'Keeps this variant set together.',
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final group in combinationGroups)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SidebarChoiceTile(
                label: group.name,
                subtitle: group.description.trim().isEmpty
                    ? null
                    : group.description,
                selected:
                    !_createNewGroup && _selectedCombinationGroupId == group.id,
                onTap: () => setState(() {
                  _error = null;
                  _createNewGroup = false;
                  _selectedCombinationGroupId = group.id;
                }),
              ),
            ),
          _SidebarChoiceTile(
            label: 'Create a new group',
            subtitle: combinationGroups.isEmpty
                ? 'No combination groups exist yet.'
                : null,
            icon: Icons.add_rounded,
            selected: _createNewGroup,
            onTap: () => setState(() {
              _error = null;
              _createNewGroup = true;
              _selectedCombinationGroupId = null;
            }),
          ),
          if (_createNewGroup) ...[
            const SizedBox(height: 12),
            _sidebarField(
              controller: _groupNameController,
              label: 'Group name',
              hint: 'e.g. Brass Sheet variants',
            ),
            const SizedBox(height: 10),
            _sidebarField(
              controller: _groupDescriptionController,
              label: 'Description',
              hint: 'Optional',
              maxLines: 2,
            ),
          ],
        ],
      ),
    );
  }

  /// The closing step: says plainly what a spawned variant can carry, because
  /// the trimmed basic-item editor is otherwise easy to never discover.
  Widget _buildBasicItemSidebar() {
    const editable = <(IconData, String, String?)>[
      (Icons.image_outlined, 'Item photo', null),
      (Icons.view_in_ar_outlined, 'CAD file', null),
      (Icons.attach_file_rounded, 'Additional files', null),
      (
        Icons.account_tree_outlined,
        'Default pipeline',
        'Starts as the base item\'s, but a variant can be made on its own route.',
      ),
      (
        Icons.science_outlined,
        'Sample data',
        'This variant\'s own trial run, not the pipeline\'s.',
      ),
    ];
    return _paneShell(
      title: 'What you can edit',
      caption: 'Per variant, from its Edit button.',
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: SoftErpTheme.accentSurface,
              borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
              border: Border.all(
                color: SoftErpTheme.accent.withValues(alpha: 0.25),
              ),
            ),
            child: const Text(
              'These are basic items. They inherit their group, unit and name '
              'format from the base item, so their editor only asks for what '
              'is genuinely their own:',
              style: TextStyle(
                color: SoftErpTheme.textPrimary,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final (icon, label, note) in editable)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(icon, size: 16, color: SoftErpTheme.accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            color: SoftErpTheme.textPrimary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (note != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            note,
                            style: const TextStyle(
                              color: SoftErpTheme.textSecondary,
                              fontSize: 11,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          const Text(
            'You can come back to any of this later from the items list.',
            style: TextStyle(
              color: SoftErpTheme.textSecondary,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebarField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      onChanged: (_) => setState(() => _error = null),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: SoftErpTheme.cardSurfaceAlt,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: SoftErpTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: SoftErpTheme.border),
        ),
      ),
    );
  }

  Widget _paneShell({
    required String title,
    required String caption,
    Widget? headerAction,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: SoftErpTheme.sectionSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: SoftErpTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        caption,
                        style: const TextStyle(
                          color: SoftErpTheme.textSecondary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (headerAction != null) ...[
                  const SizedBox(width: 8),
                  headerAction,
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: SoftErpTheme.border),
          Expanded(child: child),
        ],
      ),
    );
  }

  // --- left pane: pick values ---------------------------------------------

  Widget _buildPickerPane() {
    final editing = _isEditingCard;
    final pending = _pendingCombinationCount;
    return _paneShell(
      title: editing ? 'Editing variant #${_selectedIndex! + 1}' : 'Choose values',
      caption: editing
          ? 'Picks replace that variant\'s value for the property.'
          : 'Every selected value is crossed with the others.',
      headerAction: editing
          ? TextButton.icon(
              onPressed: _deselectCard,
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Bulk mode'),
              style: TextButton.styleFrom(
                foregroundColor: SoftErpTheme.accent,
                textStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                visualDensity: VisualDensity.compact,
              ),
            )
          : null,
      child: Column(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: widget.topLevelProperties.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) =>
                  _buildPropertyCard(widget.topLevelProperties[index]),
            ),
          ),
          if (!editing)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: SoftErpTheme.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppButton(
                    label: pending <= 1
                        ? 'Generate Combinations'
                        : 'Generate $pending Combinations',
                    icon: Icons.grid_view_rounded,
                    onPressed: _hasAnySelection ? _generateCombinations : null,
                  ),
                  if (!_hasAnySelection) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Select at least one value to continue.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: SoftErpTheme.textSecondary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPropertyCard(_NodeDraft property) {
    final selectedCount = _selected[property]!.length;
    final values = _valuesOf(property);
    final isNumeric = property.isNumericProperty;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        border: Border.all(
          color: selectedCount > 0
              ? SoftErpTheme.accent.withValues(alpha: 0.35)
              : SoftErpTheme.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _propertyName(property),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SoftErpTheme.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _InputTypePill.static(inputType: property.inputType),
              if (isNumeric) ...[
                const SizedBox(width: 6),
                _NumericRangePill(
                  label: property.numericRangeLabel,
                  onTap: null,
                ),
              ],
              if (!isNumeric && values.length > 1 && !_isEditingCard) ...[
                const SizedBox(width: 4),
                TextButton(
                  onPressed: () => _selectAllValues(property),
                  style: TextButton.styleFrom(
                    foregroundColor: SoftErpTheme.accent,
                    textStyle: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(
                    selectedCount == values.length ? 'Clear' : 'All',
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          if (isNumeric)
            _buildNumericPicker(property)
          else if (values.isEmpty)
            _buildEmptyValuesNote(property)
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in values)
                  _SelectableChip(
                    label: value.nameController.text.trim().isEmpty
                        ? 'Unnamed Value'
                        : value.nameController.text.trim(),
                    selected: _selected[property]!.contains(
                      _VariantOption.value(property, value),
                    ),
                    onTap: () => _toggleOption(
                      property,
                      _VariantOption.value(property, value),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyValuesNote(_NodeDraft property) {
    final message = property.inputType == 'Gauge'
        ? 'Gauge values are entered on orders and challans, not on variants.'
        : 'No values yet — add them to this property in the variation tree.';
    return Text(
      message,
      style: const TextStyle(
        color: SoftErpTheme.textSecondary,
        fontSize: 12,
        fontStyle: FontStyle.italic,
      ),
    );
  }

  /// Numeric properties have no value nodes, so the user types the numbers that
  /// should become variants. Each accepted number becomes a removable chip.
  Widget _buildNumericPicker(_NodeDraft property) {
    final controller = _numberControllers[property]!;
    final chosen = _selected[property]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^-?[0-9]*\.?[0-9]*'),
                  ),
                ],
                onSubmitted: (_) => _addTypedNumber(property),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Enter a number (${property.numericRangeLabel})',
                  hintStyle: const TextStyle(
                    color: SoftErpTheme.textSecondary,
                    fontSize: 12.5,
                  ),
                  filled: true,
                  fillColor: SoftErpTheme.cardSurfaceAlt,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: SoftErpTheme.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: SoftErpTheme.border),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SoftIconButton(
              icon: Icons.add_rounded,
              tooltip: 'Add this number',
              onTap: () => _addTypedNumber(property),
            ),
          ],
        ),
        if (chosen.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in chosen)
                _SelectableChip(
                  label: option.label,
                  selected: true,
                  trailing: Icons.close_rounded,
                  onTap: () => _toggleOption(property, option),
                ),
            ],
          ),
        ],
      ],
    );
  }

  // --- right pane: generated variants --------------------------------------

  Widget _buildResultsPane() {
    return _paneShell(
      title: 'Generated variants',
      caption: 'Tap one to edit its values, or remove it.',
      headerAction: _createdCombinations.isEmpty
          ? null
          : TextButton.icon(
              onPressed: _clearAllCards,
              icon: const Icon(Icons.delete_sweep_outlined, size: 16),
              label: const Text('Clear'),
              style: TextButton.styleFrom(
                foregroundColor: SoftErpTheme.dangerText,
                textStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                visualDensity: VisualDensity.compact,
              ),
            ),
      child: _createdCombinations.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_awesome_outlined,
                      size: 30,
                      color: SoftErpTheme.textSecondary,
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Nothing generated yet',
                      style: TextStyle(
                        color: SoftErpTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Pick values on the left, then generate.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: SoftErpTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _createdCombinations.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) => _buildVariantCard(index),
            ),
    );
  }

  Widget _buildVariantCard(int index) {
    final combo = _createdCombinations[index];
    final label = _comboLabel(combo);
    final selected = _selectedIndex == index;
    final base = widget.itemName.trim();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => selected ? _deselectCard() : _selectCard(index),
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            color: selected
                ? SoftErpTheme.accentSurface
                : SoftErpTheme.cardSurface,
            borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
            border: Border.all(
              color: selected ? SoftErpTheme.accent : SoftErpTheme.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? SoftErpTheme.accent
                      : SoftErpTheme.cardSurfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: selected ? Colors.white : SoftErpTheme.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label.isEmpty ? 'No values' : label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: SoftErpTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (base.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '$base - $label',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SoftErpTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SoftIconButton(
                icon: Icons.copy_rounded,
                size: 30,
                tooltip: 'Duplicate',
                onTap: () => _duplicateCard(index),
              ),
              const SizedBox(width: 6),
              SoftIconButton(
                icon: Icons.delete_outline_rounded,
                size: 30,
                iconColor: SoftErpTheme.dangerText,
                tooltip: 'Delete',
                onTap: () => _deleteCard(index),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A full-width selectable row in the post-spawn sidebar.
class _SidebarChoiceTile extends StatelessWidget {
  const _SidebarChoiceTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.icon,
  });

  final String label;
  final String? subtitle;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: selected
                ? SoftErpTheme.accentSoft
                : SoftErpTheme.cardSurface,
            borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
            border: Border.all(
              color: selected ? SoftErpTheme.accent : SoftErpTheme.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon ??
                    (selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded),
                size: 16,
                color: selected
                    ? SoftErpTheme.accent
                    : SoftErpTheme.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? SoftErpTheme.accentDeeper
                            : SoftErpTheme.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SoftErpTheme.textSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pill-shaped toggle used for variation values and typed numbers — the
/// selected state carries the accent fill rather than a Material checkbox.
class _SelectableChip extends StatelessWidget {
  const _SelectableChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? SoftErpTheme.accentSoft
                : SoftErpTheme.cardSurfaceAlt,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? SoftErpTheme.accent : SoftErpTheme.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 15,
                color: selected
                    ? SoftErpTheme.accent
                    : SoftErpTheme.textSecondary,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? SoftErpTheme.accentDeeper
                      : SoftErpTheme.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 6),
                Icon(trailing, size: 14, color: SoftErpTheme.accentDeeper),
              ],
            ],
          ),
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

/// The inclusive bounds a Numeric variation property accepts. Either side may
/// be null, meaning "no limit in that direction".
class _NumericRange {
  const _NumericRange(this.min, this.max);

  final double? min;
  final double? max;
}

/// Asks for the range a Numeric property accepts. Returns null when dismissed —
/// callers treat that as "leave the property's input type alone".
Future<_NumericRange?> _showNumericRangeDialog(
  BuildContext context, {
  required String propertyName,
  double? initialMin,
  double? initialMax,
}) {
  return showErpFormDialog<_NumericRange>(
    context,
    maxWidth: 460,
    maxHeight: 420,
    child: _NumericRangeDialog(
      propertyName: propertyName,
      initialMin: initialMin,
      initialMax: initialMax,
    ),
  );
}

class _NumericRangeDialog extends StatefulWidget {
  const _NumericRangeDialog({
    required this.propertyName,
    this.initialMin,
    this.initialMax,
  });

  final String propertyName;
  final double? initialMin;
  final double? initialMax;

  @override
  State<_NumericRangeDialog> createState() => _NumericRangeDialogState();
}

class _NumericRangeDialogState extends State<_NumericRangeDialog> {
  late final TextEditingController _minController;
  late final TextEditingController _maxController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _minController = TextEditingController(
      text: widget.initialMin == null
          ? ''
          : _formatNumericBound(widget.initialMin!),
    );
    _maxController = TextEditingController(
      text: widget.initialMax == null
          ? ''
          : _formatNumericBound(widget.initialMax!),
    );
  }

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  void _submit() {
    final rawMin = _minController.text.trim();
    final rawMax = _maxController.text.trim();
    final min = rawMin.isEmpty ? null : double.tryParse(rawMin);
    final max = rawMax.isEmpty ? null : double.tryParse(rawMax);
    if (rawMin.isNotEmpty && min == null) {
      setState(() => _error = 'Minimum must be a number.');
      return;
    }
    if (rawMax.isNotEmpty && max == null) {
      setState(() => _error = 'Maximum must be a number.');
      return;
    }
    if (min != null && max != null && min > max) {
      setState(() => _error = 'Minimum cannot be greater than maximum.');
      return;
    }
    Navigator.of(context).pop(_NumericRange(min, max));
  }

  Widget _boundField({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^-?[0-9]*\.?[0-9]*')),
      ],
      onSubmitted: (_) => _submit(),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: SoftErpTheme.cardSurfaceAlt,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: SoftErpTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: SoftErpTheme.border),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.propertyName.trim().isEmpty
        ? 'This property'
        : widget.propertyName.trim();
    return ErpFormScaffold(
      title: 'Number range',
      subtitle:
          '$name is entered as a number. Set the range it accepts so variants '
          'and orders can be checked against it.',
      eyebrow: const _InputTypePill.static(inputType: 'Numeric'),
      errorBanner: _error == null
          ? null
          : ErpFormMessageBanner(message: _error!),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _boundField(
                  controller: _minController,
                  label: 'Minimum',
                  hint: 'No limit',
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                child: Text(
                  '–',
                  style: TextStyle(
                    color: SoftErpTheme.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: _boundField(
                  controller: _maxController,
                  label: 'Maximum',
                  hint: 'No limit',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: SoftErpTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Leave a side blank for no limit on that end. Both blank '
                  'accepts any number.',
                  style: TextStyle(
                    color: SoftErpTheme.textSecondary,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 12),
          AppButton(label: 'Save range', onPressed: _submit),
        ],
      ),
    );
  }
}

String _nextVariationInputType(String current) {
  switch (current) {
    case 'Text':
      return 'Numeric';
    case 'Numeric':
      return 'Gauge';
    default:
      return 'Text';
  }
}

/// The A / 1 / G marker on a property row; tapping cycles Text -> Numeric ->
/// Gauge.
class _InputTypePill extends StatelessWidget {
  const _InputTypePill({required this.inputType, required this.onTap});

  /// Non-interactive variant, for headers and legends.
  const _InputTypePill.static({required this.inputType}) : onTap = null;

  final String inputType;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final MaterialColor color = inputType == 'Numeric'
        ? Colors.blue
        : inputType == 'Gauge'
        ? Colors.purple
        : Colors.grey;
    final label = inputType == 'Numeric'
        ? '1'
        : inputType == 'Gauge'
        ? 'G'
        : 'A';
    final name = inputType == 'Numeric'
        ? 'Numeric input'
        : inputType == 'Gauge'
        ? 'Gauge input (SWG)'
        : 'Text input';
    return Tooltip(
      message: onTap == null ? name : '$name — tap to change',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color[700],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows (and edits) the range a Numeric property accepts, sitting next to its
/// input-type pill in the variation tree.
class _NumericRangePill extends StatelessWidget {
  const _NumericRangePill({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: onTap == null
          ? 'Accepted range: $label'
          : 'Accepted range: $label — tap to edit',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.blue[700],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../groups/presentation/providers/groups_provider.dart';
import '../../domain/item_asset.dart';
import '../../domain/item_definition.dart';
import '../providers/items_provider.dart';

const Color _itemCardBannerColor = Color(0xFFE4C17C);
const Color _itemCardScrapBannerColor = Color(0xFFD97706);
const Color _itemCardFooterColor = Color(0xFFF8F8FC);
const Color _itemCardScrapFooterColor = Color(0xFFFFFDF5);

/// Clean catalog card for the optional item grid view.
class ItemCard extends StatefulWidget {
  const ItemCard({super.key, required this.item, this.onTap});

  final ItemDefinition item;
  final VoidCallback? onTap;

  @override
  State<ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<ItemCard> {
  bool _requestedAssets = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _ensureAssetsLoaded();
    });
  }

  @override
  void didUpdateWidget(covariant ItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _requestedAssets = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _ensureAssetsLoaded();
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
    final groupName = context.select<GroupsProvider, String>(
      (p) => p.findById(widget.item.groupId)?.name ?? '',
    );
    final isScrap = groupName.toLowerCase().trim() == 'scrap' ||
        widget.item.name.toLowerCase().contains('scrap') ||
        widget.item.displayName.toLowerCase().contains('scrap');

    final primaryAsset = context.select<ItemsProvider, ItemAsset?>((provider) {
      final assets = provider.assetsForItem(widget.item.id);
      return assets.where((asset) => asset.isPrimary).firstOrNull ??
          assets.firstOrNull;
    });
    final leafCount = widget.item.leafVariationNodes.length;
    final subtitle = isScrap
        ? 'Scrap material'
        : (leafCount == 0
            ? 'Base item'
            : '$leafCount variant${leafCount == 1 ? '' : 's'}');

    return AppCard(
      key: ValueKey<String>('item-card-${widget.item.id}'),
      onTap: widget.onTap,
      padding: EdgeInsets.zero,
      backgroundColor: isScrap ? const Color(0xFFFFFDF8) : Colors.white,
      borderColor: isScrap ? const Color(0xFFFED7AA) : const Color(0xFFE6E8F0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              key: ValueKey<String>('item-card-banner-${widget.item.id}'),
              height: 20,
              color: isScrap ? _itemCardScrapBannerColor : _itemCardBannerColor,
            ),
            Expanded(
              child: ColoredBox(
                color: isScrap ? const Color(0xFFFFFDF8) : Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _ItemCardPreview(
                    item: widget.item,
                    primaryAsset: primaryAsset,
                    isScrap: isScrap,
                  ),
                ),
              ),
            ),
            Container(
              key: ValueKey<String>('item-card-footer-${widget.item.id}'),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: isScrap ? _itemCardScrapFooterColor : _itemCardFooterColor,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _itemLabel(widget.item),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
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
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFB45309),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isScrap ? const Color(0xFF92400E) : SoftErpTheme.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemCardPreview extends StatelessWidget {
  const _ItemCardPreview({
    required this.item,
    required this.primaryAsset,
    this.isScrap = false,
  });

  final ItemDefinition item;
  final ItemAsset? primaryAsset;
  final bool isScrap;

  @override
  Widget build(BuildContext context) {
    final readUrl = primaryAsset?.readUrl?.toString() ?? item.photoUrl;
    if (readUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.network(
          readUrl,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _ItemCardPlaceholder(item: item, isScrap: isScrap),
        ),
      );
    }
    return _ItemCardPlaceholder(item: item, isScrap: isScrap);
  }
}

class _ItemCardPlaceholder extends StatelessWidget {
  const _ItemCardPlaceholder({
    required this.item,
    this.isScrap = false,
  });

  final ItemDefinition item;
  final bool isScrap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final token = _itemToken(item);
    final tokenBg = isScrap ? const Color(0xFFFEF3C7) : SoftErpTheme.accentSoft;
    final tokenColor = isScrap ? const Color(0xFFB45309) : SoftErpTheme.accentDark;
    final gradientColors = isScrap
        ? const [Color(0xFFFFFDF8), Color(0xFFFEF3C7)]
        : const [Color(0xFFFDFBF6), Color(0xFFF7F8FC)];

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: gradientColors,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final iconSize = (constraints.biggest.shortestSide * 0.54).clamp(
            44.0,
            78.0,
          );
          final iconRadius = (iconSize * 0.31).clamp(14.0, 24.0);
          final spacing = constraints.maxHeight < 110 ? 8.0 : 12.0;
          final caption = item.alias.trim().isEmpty
              ? (isScrap ? 'Scrap material' : 'No image uploaded')
              : item.alias;
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: iconSize,
                    height: iconSize,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tokenBg,
                      borderRadius: BorderRadius.circular(iconRadius),
                      border: Border.all(
                        color: isScrap
                            ? const Color(0xFFD97706).withValues(alpha: 0.35)
                            : SoftErpTheme.accent.withValues(alpha: 0.16),
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          token,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: tokenColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: spacing),
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isScrap ? const Color(0xFF92400E) : SoftErpTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

String _itemLabel(ItemDefinition item) {
  final displayName = item.displayName.trim();
  return displayName.isEmpty ? item.name : displayName;
}

String _itemToken(ItemDefinition item) {
  final source = item.name.trim().isEmpty ? _itemLabel(item) : item.name;
  final parts = source
      .split(RegExp(r'\s+'))
      .where((part) => part.trim().isNotEmpty)
      .take(2)
      .map((part) => part.substring(0, 1).toUpperCase())
      .toList(growable: false);
  if (parts.isEmpty) {
    return 'IT';
  }
  return parts.join();
}

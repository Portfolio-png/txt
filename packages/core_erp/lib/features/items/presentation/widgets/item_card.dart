import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_card.dart';
import '../../domain/item_asset.dart';
import '../../domain/item_definition.dart';
import '../providers/items_provider.dart';

const Color _itemCardBannerColor = Color(0xFFE4C17C);
const Color _itemCardFooterColor = Color(0xFFF8F8FC);

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
    final primaryAsset = context.select<ItemsProvider, ItemAsset?>((provider) {
      final assets = provider.assetsForItem(widget.item.id);
      return assets.where((asset) => asset.isPrimary).firstOrNull ??
          assets.firstOrNull;
    });
    final leafCount = widget.item.leafVariationNodes.length;
    final subtitle = leafCount == 0
        ? 'Base item'
        : '$leafCount variant${leafCount == 1 ? '' : 's'}';

    return AppCard(
      key: ValueKey<String>('item-card-${widget.item.id}'),
      onTap: widget.onTap,
      padding: EdgeInsets.zero,
      backgroundColor: Colors.white,
      borderColor: const Color(0xFFE6E8F0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              key: ValueKey<String>('item-card-banner-${widget.item.id}'),
              height: 20,
              color: _itemCardBannerColor,
            ),
            Expanded(
              child: ColoredBox(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _ItemCardPreview(
                    item: widget.item,
                    primaryAsset: primaryAsset,
                  ),
                ),
              ),
            ),
            Container(
              key: ValueKey<String>('item-card-footer-${widget.item.id}'),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: const BoxDecoration(color: _itemCardFooterColor),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _itemLabel(widget.item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SoftErpTheme.textSecondary,
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
  const _ItemCardPreview({required this.item, required this.primaryAsset});

  final ItemDefinition item;
  final ItemAsset? primaryAsset;

  @override
  Widget build(BuildContext context) {
    final readUrl = primaryAsset?.readUrl?.toString();
    if (readUrl != null && readUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.network(
          readUrl,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _ItemCardPlaceholder(item: item),
        ),
      );
    }
    return _ItemCardPlaceholder(item: item);
  }
}

class _ItemCardPlaceholder extends StatelessWidget {
  const _ItemCardPlaceholder({required this.item});

  final ItemDefinition item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final token = _itemToken(item);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFDFBF6), Color(0xFFF7F8FC)],
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
              ? 'No image uploaded'
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
                      color: SoftErpTheme.accentSoft,
                      borderRadius: BorderRadius.circular(iconRadius),
                      border: Border.all(
                        color: SoftErpTheme.accent.withValues(alpha: 0.16),
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
                            color: SoftErpTheme.accentDark,
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
                      color: SoftErpTheme.textSecondary,
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

import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../groups/presentation/providers/groups_provider.dart';
import '../../../units/presentation/providers/units_provider.dart';
import '../../domain/item_asset.dart';
import '../../domain/item_definition.dart';
import '../providers/items_provider.dart';

Future<void> showItemDetailPanel(
  BuildContext context, {
  required ItemDefinition item,
  String? barcode,
  VoidCallback? onEdit,
}) {
  final resolvedBarcode = barcode ?? itemMasterBarcode(item.id);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Item details',
    barrierColor: const Color(0x66100D1F),
    pageBuilder: (context, animation, secondaryAnimation) {
      final screenWidth = MediaQuery.sizeOf(context).width;
      final panelWidth = math.min(
        screenWidth >= 980 ? 920.0 : 540.0,
        screenWidth - 24,
      );
      final screenHeight = MediaQuery.sizeOf(context).height;
      final panelHeight = math.min(
        screenHeight - 24,
        screenWidth >= 980 ? 900.0 : screenHeight - 24,
      );
      return SafeArea(
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(top: 12, right: 12, bottom: 12),
            child: SizedBox(
              width: panelWidth,
              height: panelHeight,
              child: ItemDetailPanel(
                item: item,
                barcode: resolvedBarcode,
                onEdit: onEdit,
              ),
            ),
          ),
        ),
      );
    },
    transitionDuration: const Duration(milliseconds: 220),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.08, 0),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

String itemMasterBarcode(int itemId) => 'ITEM-MASTER-$itemId';

class ItemDetailPanel extends StatefulWidget {
  const ItemDetailPanel({
    super.key,
    required this.item,
    required this.barcode,
    this.onEdit,
  });

  final ItemDefinition item;
  final String barcode;
  final VoidCallback? onEdit;

  @override
  State<ItemDetailPanel> createState() => _ItemDetailPanelState();
}

class _ItemDetailPanelState extends State<ItemDetailPanel> {
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.read<ItemsProvider>().loadItemAssets(widget.item.id);
    });
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
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<ItemsProvider>();
    try {
      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes).toString();
      final contentType =
          file.mimeType ??
          lookupMimeType(file.name, headerBytes: bytes.take(24).toList()) ??
          _contentTypeFromExtension(file.name);
      final intent = await provider.createAssetUploadIntent(
        ItemAssetUploadIntentInput(
          itemId: widget.item.id,
          fileName: file.name,
          contentType: contentType,
          sizeBytes: bytes.length,
          sha256: digest,
          isPrimary: true,
        ),
      );
      if (intent == null) {
        throw Exception(provider.errorMessage ?? 'Failed to prepare upload.');
      }
      if (intent.alreadyUploaded && intent.asset != null) {
        await provider.loadItemAssets(widget.item.id);
        messenger.showSnackBar(
          const SnackBar(content: Text('Image already uploaded.')),
        );
        return;
      }
      final upload = intent.upload;
      if (upload == null) {
        throw Exception('Upload target was not returned.');
      }
      if (upload.uploadUrl.host != 'mock.local') {
        final response = await http.put(
          upload.uploadUrl,
          headers: upload.headers,
          body: bytes,
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(
            'Image upload failed with status ${response.statusCode}.',
          );
        }
      }
      final completed = await provider.completeAssetUpload(
        CompleteItemAssetUploadInput(
          uploadSessionId: upload.uploadSessionId,
          objectKey: upload.objectKey,
          itemId: widget.item.id,
        ),
      );
      if (completed == null) {
        throw Exception(provider.errorMessage ?? 'Failed to finish upload.');
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Item image uploaded.')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Image upload failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _deleteImage(ItemAsset asset) async {
    final provider = context.read<ItemsProvider>();
    final success = await provider.deleteAsset(asset);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Image removed.'
              : provider.errorMessage ?? 'Failed to remove image.',
        ),
      ),
    );
  }

  void _openImagePreview(ItemAsset asset) {
    final readUrl = asset.readUrl;
    if (readUrl == null) {
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(32),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Image.network(readUrl.toString(), fit: BoxFit.contain),
        ),
      ),
    );
  }

  String _contentTypeFromExtension(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final groups = context.watch<GroupsProvider>();
    final units = context.watch<UnitsProvider>();
    final itemsProvider = context.watch<ItemsProvider>();
    final assets = itemsProvider.assetsForItem(item.id);
    final primaryAsset =
        assets.where((asset) => asset.isPrimary).firstOrNull ??
        (assets.isEmpty ? null : assets.first);
    final groupName = groups.findById(item.groupId)?.name ?? 'Unknown group';
    final unitLabel =
        units.units
            .where((unit) => unit.id == item.unitId)
            .firstOrNull
            ?.displayLabel ??
        'Unknown unit';
    final title = itemTitle(item);
    final generatedCodes = generatedItemCodes(item);

    return Material(
      color: SoftErpTheme.shellSurface,
      elevation: 10,
      shadowColor: const Color(0x26303646),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: SoftErpTheme.borderStrong),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: const BoxDecoration(
              color: SoftErpTheme.cardSurface,
              border: Border(bottom: BorderSide(color: SoftErpTheme.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SoftErpTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: SoftErpTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final useTwoColumn = constraints.maxWidth >= 760;
                final sameNamingFormatItems = itemsProvider.items.where((other) {
                  if (other.namingFormat.length != item.namingFormat.length) return false;
                  for (int i = 0; i < item.namingFormat.length; i++) {
                    if (other.namingFormat[i] != item.namingFormat[i]) return false;
                  }
                  return true;
                }).toList();

                final imagePreview = _ItemImagePreview(
                  item: item,
                  primaryAsset: primaryAsset,
                  isUploading: _isUploading || itemsProvider.isAssetUploading,
                  onUpload: _pickAndUploadImage,
                  onOpenImage: primaryAsset == null
                      ? null
                      : () => _openImagePreview(primaryAsset),
                  onDeleteImage: primaryAsset == null
                      ? null
                      : () => _deleteImage(primaryAsset),
                );
                final factsheet = _ItemFactsheet(
                  item: item,
                  groupName: groupName,
                  unitLabel: unitLabel,
                  generatedCodes: generatedCodes,
                  imageCount: assets.length,
                  sameNamingFormatItems: sameNamingFormatItems,
                );
                final editButton = widget.onEdit == null
                    ? null
                    : AppButton(
                        label: 'Edit Item',
                        icon: Icons.edit_outlined,
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onEdit?.call();
                        },
                      );

                final content = useTwoColumn
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 240,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                imagePreview,
                                if (editButton != null) ...[
                                  const SizedBox(height: 16),
                                  editButton,
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          SizedBox(
                            width: 320,
                            child: factsheet,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _ItemVariationSection(item: item),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          imagePreview,
                          const SizedBox(height: 18),
                          factsheet,
                          const SizedBox(height: 18),
                          _ItemVariationSection(item: item),
                          if (editButton != null) ...[
                            const SizedBox(height: 18),
                            editButton,
                          ],
                        ],
                      );

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: content,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemImagePreview extends StatelessWidget {
  const _ItemImagePreview({
    required this.item,
    required this.primaryAsset,
    required this.isUploading,
    required this.onUpload,
    this.onOpenImage,
    this.onDeleteImage,
  });

  final ItemDefinition item;
  final ItemAsset? primaryAsset;
  final bool isUploading;
  final VoidCallback onUpload;
  final VoidCallback? onOpenImage;
  final VoidCallback? onDeleteImage;

  @override
  Widget build(BuildContext context) {
    final code = generatedCodeForText(itemTitle(item));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1.55,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: primaryAsset?.readUrl == null ? onUpload : onOpenImage,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE1E5F0)),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(child: _previewContent(code)),
                    if (isUploading)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        ),
                      ),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: Row(
                        children: [
                          if (onDeleteImage != null) ...[
                            _ImageActionButton(
                              icon: Icons.delete_outline,
                              tooltip: 'Remove image',
                              onTap: onDeleteImage!,
                            ),
                            const SizedBox(width: 8),
                          ],
                          _ImageActionButton(
                            icon: primaryAsset == null
                                ? Icons.add_photo_alternate_outlined
                                : Icons.upload_file_outlined,
                            tooltip: primaryAsset == null
                                ? 'Upload image'
                                : 'Replace image',
                            onTap: onUpload,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewContent(String code) {
    final readUrl = primaryAsset?.readUrl;
    if (readUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Image.network(
          readUrl.toString(),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _placeholderContent(code),
        ),
      );
    }
    return _placeholderContent(code);
  }

  Widget _placeholderContent(String code) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 86,
            height: 86,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: SoftErpTheme.accentSoft,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: SoftErpTheme.accent.withValues(alpha: 0.28),
              ),
            ),
            child: Text(
              code,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: SoftErpTheme.accentDark,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: SoftErpTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageActionButton extends StatelessWidget {
  const _ImageActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xF8FFFFFF),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFD9E1F3)),
            ),
            child: Icon(icon, color: SoftErpTheme.textSecondary, size: 20),
          ),
        ),
      ),
    );
  }
}

class _ItemFactsheet extends StatelessWidget {
  const _ItemFactsheet({
    required this.item,
    required this.groupName,
    required this.unitLabel,
    required this.generatedCodes,
    required this.imageCount,
    required this.sameNamingFormatItems,
  });

  final ItemDefinition item;
  final String groupName;
  final String unitLabel;
  final List<String> generatedCodes;
  final int imageCount;
  final List<ItemDefinition> sameNamingFormatItems;

  @override
  Widget build(BuildContext context) {
    return _DetailCard(
      title: 'Factsheet',
      children: [
        _FactRow(label: 'Item name', value: item.name),
        if (item.alias.trim().isNotEmpty)
          _FactRow(label: 'Alias', value: item.alias),
        _FactRow(label: 'Display name', value: item.displayName),
        _FactRow(label: 'Group', value: groupName),
        _FactRow(label: 'Unit', value: unitLabel),
        _FactRow(
          label: 'Status',
          value: item.isArchived ? 'Archived' : 'Active',
        ),
        _FactRow(
          label: 'Usage',
          value: '${item.usageCount} linked record(s)',
        ),
        _FactRow(label: 'Images', value: imageCount.toString()),
        const SizedBox(height: 8),
        _FactWrapRow(
          label: 'Items with same naming format',
          values: sameNamingFormatItems
              .map((it) => it.displayName.trim().isEmpty ? it.name : it.displayName)
              .toList(growable: false),
          emptyText: 'No other items use this naming format.',
        ),
        _FactWrapRow(
          label: 'Generated codes',
          values: generatedCodes,
          emptyText: 'No generated code available.',
        ),
        if (item.unitConversions.isNotEmpty)
          _FactWrapRow(
            label: 'Conversions',
            values: item.unitConversions
                .map(
                  (entry) =>
                      '1 ${entry.unitSymbol} = ${entry.factorToPrimary} base',
                )
                .toList(growable: false),
            emptyText: '',
          ),
      ],
    );
  }
}

class _ItemVariationSection extends StatelessWidget {
  const _ItemVariationSection({required this.item});

  final ItemDefinition item;

  @override
  Widget build(BuildContext context) {
    final rootNodes = item.variationTree.where((node) => !node.isArchived).toList();
    return _DetailCard(
      title: 'Variation Tree',
      children: [
        if (rootNodes.isEmpty)
          const Text(
            'No variation tree configured.',
            style: TextStyle(
              color: SoftErpTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(rootNodes.length, (index) {
                final node = rootNodes[index];
                final isLast = index == rootNodes.length - 1;
                return _VariationTreeNodeWidget(
                  node: node,
                  depth: 0,
                  isLastChild: isLast,
                  parentHasNextSibling: const [],
                );
              }),
            ),
          ),
      ],
    );
  }
}

class _VariationTreeNodeWidget extends StatelessWidget {
  const _VariationTreeNodeWidget({
    required this.node,
    required this.depth,
    required this.isLastChild,
    required this.parentHasNextSibling,
  });

  final ItemVariationNodeDefinition node;
  final int depth;
  final bool isLastChild;
  final List<bool> parentHasNextSibling;

  @override
  Widget build(BuildContext context) {
    final isProperty = node.kind == ItemVariationNodeKind.property;
    final Color badgeBg = isProperty ? const Color(0xFFEEF2FE) : const Color(0xFFF0FDF4);
    final Color badgeText = isProperty ? const Color(0xFF3B82F6) : const Color(0xFF16A34A);
    final Color badgeBorder = isProperty ? const Color(0xFFBFDBFE) : const Color(0xFFBBF7D0);
    final IconData icon = isProperty ? Icons.account_tree_outlined : Icons.label_outlined;
    
    final activeChildren = node.activeChildren;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < depth; i++)
              Container(
                width: 24,
                height: 32,
                alignment: Alignment.center,
                child: i < parentHasNextSibling.length && parentHasNextSibling[i]
                    ? Container(
                        width: 1.5,
                        color: const Color(0xFFCBD5E1),
                      )
                    : null,
              ),
            if (depth > 0)
              SizedBox(
                width: 24,
                height: 32,
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.topLeft,
                      child: Container(
                        width: 1.5,
                        height: isLastChild ? 16 : 32,
                        color: const Color(0xFFCBD5E1),
                        margin: const EdgeInsets.only(left: 11),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 12,
                        height: 1.5,
                        color: const Color(0xFFCBD5E1),
                        margin: const EdgeInsets.only(left: 11),
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: badgeBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: badgeText),
                  const SizedBox(width: 6),
                  Text(
                    node.name.isEmpty ? node.displayName : node.name,
                    style: TextStyle(
                      color: badgeText,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (node.code.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(
                      '(${node.code})',
                      style: TextStyle(
                        color: badgeText.withValues(alpha: 0.6),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (activeChildren.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(activeChildren.length, (index) {
              final child = activeChildren[index];
              final isLast = index == activeChildren.length - 1;
              return _VariationTreeNodeWidget(
                node: child,
                depth: depth + 1,
                isLastChild: isLast,
                parentHasNextSibling: [...parentHasNextSibling, !isLastChild],
              );
            }),
          ),
      ],
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: SoftErpTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: SoftErpTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.trim().isEmpty ? '-' : value,
            style: const TextStyle(
              color: SoftErpTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}



class _FactWrapRow extends StatelessWidget {
  const _FactWrapRow({
    required this.label,
    required this.values,
    required this.emptyText,
  });

  final String label;
  final List<String> values;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final filtered = values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: SoftErpTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (filtered.isEmpty)
            Text(
              emptyText,
              style: const TextStyle(
                color: SoftErpTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: filtered
                  .map((value) => _DetailChip(label: value))
                  .toList(growable: false),
            ),
        ],
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: SoftErpTheme.accentSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFDCD6FF)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: SoftErpTheme.accentDark,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

List<String> generatedItemCodes(ItemDefinition item) {
  final leaves = item.leafVariationNodes;
  if (leaves.isEmpty) {
    return <String>[generatedCodeForText(itemTitle(item))];
  }
  return leaves
      .take(8)
      .map((leaf) => generatedItemVariationCode(item, leaf))
      .where((code) => code.trim().isNotEmpty)
      .toList(growable: false);
}

List<String> resolvedItemNamingTokens(ItemDefinition item) {
  final available = <String>['name'];
  for (var index = 0; index < item.topLevelProperties.length; index++) {
    available.add('prop_$index');
  }
  final tokens = item.namingFormat
      .where((token) => available.contains(token))
      .toList(growable: true);
  for (final token in available) {
    if (!tokens.contains(token)) {
      tokens.add(token);
    }
  }
  return tokens;
}

String itemNamingTokenLabel(ItemDefinition item, String token) {
  if (token == 'name') {
    return 'Item Name';
  }
  if (token.startsWith('prop_')) {
    final index = int.tryParse(token.substring(5));
    if (index != null && index >= 0 && index < item.topLevelProperties.length) {
      final name = item.topLevelProperties[index].name.trim();
      return name.isEmpty ? 'Unnamed Property' : name;
    }
  }
  return token;
}

String generatedItemVariationCode(
  ItemDefinition item,
  ItemVariationNodeDefinition leaf,
) {
  final selectedByTopPropertyId = <int, String>{};
  ItemVariationNodeDefinition? current = leaf;
  while (current != null) {
    final parent = findVariationNodeById(
      item.variationTree,
      current.parentNodeId,
    );
    if (parent != null && parent.kind == ItemVariationNodeKind.property) {
      final topProperty = topPropertyForNode(item, parent);
      if (topProperty != null) {
        selectedByTopPropertyId[topProperty.id] = nodeCodeOrGenerated(current);
      }
    }
    current = parent;
  }

  final parts = <String>[];
  for (final token in resolvedItemNamingTokens(item)) {
    if (token == 'name') {
      parts.add(generatedCodeForText(itemTitle(item)));
    } else if (token.startsWith('prop_')) {
      final index = int.tryParse(token.substring(5));
      if (index != null &&
          index >= 0 &&
          index < item.topLevelProperties.length) {
        final value =
            selectedByTopPropertyId[item.topLevelProperties[index].id];
        if (value != null && value.isNotEmpty) {
          parts.add(value);
        }
      }
    }
  }
  return parts.join(' ');
}

ItemVariationNodeDefinition? topPropertyForNode(
  ItemDefinition item,
  ItemVariationNodeDefinition node,
) {
  var current = node;
  while (current.parentNodeId != null) {
    final parent = findVariationNodeById(
      item.variationTree,
      current.parentNodeId,
    );
    if (parent == null) {
      break;
    }
    current = parent;
  }
  return current.kind == ItemVariationNodeKind.property ? current : null;
}

ItemVariationNodeDefinition? findVariationNodeById(
  List<ItemVariationNodeDefinition> nodes,
  int? id,
) {
  if (id == null) {
    return null;
  }
  for (final node in nodes) {
    if (node.id == id) {
      return node;
    }
    final childMatch = findVariationNodeById(node.children, id);
    if (childMatch != null) {
      return childMatch;
    }
  }
  return null;
}

String itemTitle(ItemDefinition item) {
  return item.displayName.trim().isEmpty ? item.name : item.displayName;
}

String nodeCodeOrGenerated(ItemVariationNodeDefinition node) {
  final code = node.code.trim();
  if (code.isNotEmpty) {
    return code;
  }
  final source = node.name.trim().isEmpty ? node.displayName : node.name;
  return generatedCodeForText(source);
}

String generatedCodeForText(String value) {
  final words = RegExp(
    r'[A-Za-z0-9]+',
  ).allMatches(value).map((match) => match.group(0)!).toList();
  if (words.isEmpty) {
    return value.trim();
  }
  if (words.length == 1) {
    final word = words.single.toUpperCase();
    return word.length <= 4 ? word : word.substring(0, 4);
  }
  return words
      .map((word) => RegExp(r'^\d+$').hasMatch(word) ? word : word[0])
      .join()
      .toUpperCase();
}

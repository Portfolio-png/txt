import 'dart:math' as math;

import 'package:barcode_widget/barcode_widget.dart';
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
                final imagePreview = _ItemImagePreview(
                  item: item,
                  barcode: widget.barcode,
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
                  barcode: widget.barcode,
                  groupName: groupName,
                  unitLabel: unitLabel,
                  generatedCodes: generatedCodes,
                  imageCount: assets.length,
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
                            width: 320,
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
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                factsheet,
                                const SizedBox(height: 18),
                                _ItemVariationSection(item: item),
                              ],
                            ),
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
    required this.barcode,
    required this.primaryAsset,
    required this.isUploading,
    required this.onUpload,
    this.onOpenImage,
    this.onDeleteImage,
  });

  final ItemDefinition item;
  final String barcode;
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
          const SizedBox(height: 14),
          Text(
            barcode,
            style: const TextStyle(
              color: SoftErpTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7F0)),
            ),
            child: BarcodeWidget(
              barcode: Barcode.code128(),
              data: barcode,
              drawText: false,
              height: 52,
              color: const Color(0xFF111827),
              backgroundColor: Colors.white,
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
    required this.barcode,
    required this.groupName,
    required this.unitLabel,
    required this.generatedCodes,
    required this.imageCount,
  });

  final ItemDefinition item;
  final String barcode;
  final String groupName;
  final String unitLabel;
  final List<String> generatedCodes;
  final int imageCount;

  @override
  Widget build(BuildContext context) {
    final factRows = <_FactGridRow>[
      _FactGridRow(label: 'Barcode', value: barcode),
      _FactGridRow(label: 'Item name', value: item.name),
      if (item.alias.trim().isNotEmpty)
        _FactGridRow(label: 'Alias', value: item.alias),
      _FactGridRow(label: 'Display name', value: item.displayName),
      _FactGridRow(label: 'Group', value: groupName),
      _FactGridRow(label: 'Unit', value: unitLabel),
      _FactGridRow(
        label: 'Status',
        value: item.isArchived ? 'Archived' : 'Active',
      ),
      _FactGridRow(
        label: 'Usage',
        value: '${item.usageCount} linked record(s)',
      ),
      _FactGridRow(label: 'Images', value: imageCount.toString()),
    ];
    return _DetailCard(
      title: 'Factsheet',
      children: [
        _FactGrid(rows: factRows),
        _FactWrapRow(
          label: 'Naming format',
          values: resolvedItemNamingTokens(item)
              .map((token) => itemNamingTokenLabel(item, token))
              .toList(growable: false),
          emptyText: 'No naming format configured.',
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
    final leaves = item.leafVariationNodes;
    return _DetailCard(
      title: 'Variation Tree',
      children: [
        _FactWrapRow(
          label: 'Properties',
          values: item.topLevelProperties
              .map((node) => node.name)
              .toList(growable: false),
          emptyText: 'No properties configured.',
        ),
        _FactWrapRow(
          label: 'Orderable leaves',
          values: leaves
              .take(10)
              .map(
                (leaf) => leaf.displayName.trim().isEmpty
                    ? leaf.name
                    : leaf.displayName,
              )
              .toList(growable: false),
          emptyText: 'No orderable leaf variations.',
        ),
        if (leaves.length > 10)
          _FactRow(label: 'More leaves', value: '+${leaves.length - 10}'),
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

class _FactGridRow {
  const _FactGridRow({required this.label, required this.value});

  final String label;
  final String value;
}

class _FactGrid extends StatelessWidget {
  const _FactGrid({required this.rows});

  final List<_FactGridRow> rows;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useTwoColumns = constraints.maxWidth >= 360;
        final tileWidth = useTwoColumns
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: rows
                .map(
                  (row) => SizedBox(
                    width: tileWidth,
                    child: _CompactFactTile(row: row),
                  ),
                )
                .toList(growable: false),
          ),
        );
      },
    );
  }
}

class _CompactFactTile extends StatelessWidget {
  const _CompactFactTile({required this.row});

  final _FactGridRow row;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: SoftErpTheme.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            row.value.trim().isEmpty ? '-' : row.value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: SoftErpTheme.textPrimary,
              fontSize: 13.5,
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

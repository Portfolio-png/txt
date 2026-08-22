import 'dart:math' as math;
import 'package:core_erp/core/widgets/app_toast.dart';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/soft_entrance_animation.dart';
import '../../../groups/presentation/providers/groups_provider.dart';
import '../../../units/presentation/providers/units_provider.dart';
import '../../domain/item_asset.dart';
import '../../domain/item_definition.dart';
import '../../domain/item_usage_record.dart';
import '../providers/items_provider.dart';

import 'item_pipeline_metrics_card.dart';

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
        screenWidth >= 1100 ? 1020.0 : (screenWidth >= 980 ? 920.0 : 560.0),
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
  int _activeTab = 0;

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
        showAppSnack(const SnackBar(content: Text('Image already uploaded.')));
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
      showAppSnack(const SnackBar(content: Text('Item image uploaded.')));
    } catch (error) {
      showAppSnack(SnackBar(content: Text('Image upload failed: $error')));
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
    showAppSnack(
      SnackBar(
        content: Text(
          success
              ? 'Image removed.'
              : provider.errorMessage ?? 'Failed to remove image.',
        ),
      ),
    );
  }

  void _openImagePreview(String imageUrl) {
    if (imageUrl.isEmpty) {
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(32),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Image.network(imageUrl, fit: BoxFit.contain),
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
    final generatedNames = itemsProvider.items
        .where((i) => i.baseItemId == item.id)
        .map((i) => i.displayName)
        .toList(growable: false);

    final isScrap =
        groupName.toLowerCase().trim() == 'scrap' ||
        item.name.toLowerCase().contains('scrap') ||
        item.displayName.toLowerCase().contains('scrap');

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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
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
                      if (isScrap) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFFDE68A)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.recycling_rounded,
                                size: 13,
                                color: Color(0xFFD97706),
                              ),
                              SizedBox(width: 4),
                              Text(
                                'SCRAP MATERIAL',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFB45309),
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (item.defaultPipelineId != null &&
                    item.defaultPipelineId!.isNotEmpty) ...[
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment<int>(
                        value: 0,
                        label: Text('Item Specifications'),
                        icon: Icon(Icons.inventory_2_outlined, size: 15),
                      ),
                      ButtonSegment<int>(
                        value: 1,
                        label: Text('Pipeline & Mass Balance'),
                        icon: Icon(Icons.analytics_outlined, size: 15),
                      ),
                    ],
                    selected: {_activeTab},
                    onSelectionChanged: (set) =>
                        setState(() => _activeTab = set.first),
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
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
            child:
                _activeTab == 1 &&
                    item.defaultPipelineId != null &&
                    item.defaultPipelineId!.isNotEmpty
                ? SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: ItemPipelineMetricsCard(item: item),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final useTwoColumn = constraints.maxWidth >= 760;
                      final sameNamingFormatItems = itemsProvider.items.where((
                        other,
                      ) {
                        if (other.namingFormat.length !=
                            item.namingFormat.length)
                          return false;
                        for (int i = 0; i < item.namingFormat.length; i++) {
                          if (other.namingFormat[i] != item.namingFormat[i])
                            return false;
                        }
                        return true;
                      }).toList();

                      final imagePreview = _ItemImagePreview(
                        item: item,
                        primaryAsset: primaryAsset,
                        isUploading:
                            _isUploading || itemsProvider.isAssetUploading,
                        onUpload: _pickAndUploadImage,
                        onOpenImage:
                            (primaryAsset?.readUrl?.toString() ?? item.photoUrl)
                                .isEmpty
                            ? null
                            : () => _openImagePreview(
                                primaryAsset?.readUrl?.toString() ??
                                    item.photoUrl,
                              ),
                        onDeleteImage: primaryAsset == null
                            ? null
                            : () => _deleteImage(primaryAsset),
                      );
                      final factsheet = _ItemFactsheet(
                        item: item,
                        groupName: groupName,
                        unitLabel: unitLabel,
                        generatedCodes: generatedNames,
                        imageCount: assets.length,
                        sameNamingFormatItems: sameNamingFormatItems,
                      );
                      final cadFileCard = item.cadFileKey.trim().isEmpty
                          ? null
                          : _ItemCadFileCard(item: item);
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      imagePreview,
                                      if (cadFileCard != null) ...[
                                        const SizedBox(height: 16),
                                        cadFileCard,
                                      ],
                                      if (editButton != null) ...[
                                        const SizedBox(height: 16),
                                        editButton,
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                SizedBox(width: 320, child: factsheet),
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
                                if (cadFileCard != null) ...[
                                  const SizedBox(height: 18),
                                  cadFileCard,
                                ],
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
              onTap: (primaryAsset?.readUrl == null && item.photoUrl.isEmpty)
                  ? onUpload
                  : onOpenImage,
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
                            tooltip:
                                (primaryAsset == null && item.photoUrl.isEmpty)
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
    final readUrl = primaryAsset?.readUrl?.toString() ?? item.photoUrl;
    if (readUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Image.network(
          readUrl,
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

/// Read-only view of the item's CAD attachment. Only rendered when the item
/// actually has one — uploading and replacing stay in the item editor.
class _ItemCadFileCard extends StatefulWidget {
  const _ItemCadFileCard({required this.item});

  final ItemDefinition item;

  @override
  State<_ItemCadFileCard> createState() => _ItemCadFileCardState();
}

class _ItemCadFileCardState extends State<_ItemCadFileCard> {
  bool _isPreparing = false;

  String get _fileName {
    final name = widget.item.cadFileName.trim();
    if (name.isNotEmpty) {
      return name;
    }
    // Records saved before the file name was captured fall back to the last
    // segment of the object key.
    final segments = widget.item.cadFileKey.trim().split('/');
    if (segments.isNotEmpty && segments.last.isNotEmpty) {
      return segments.last;
    }
    return 'CAD file';
  }

  String get _extension {
    final name = _fileName;
    if (!name.contains('.')) {
      return 'CAD';
    }
    return name.split('.').last.toUpperCase();
  }

  /// The item stores a permanent object key, so the download link is signed
  /// fresh on every click instead of read from a stored URL that could expire.
  Future<void> _download(BuildContext context) async {
    if (_isPreparing) {
      return;
    }
    setState(() => _isPreparing = true);
    final itemsProvider = context.read<ItemsProvider>();
    try {
      final uri = await itemsProvider.createCadFileReadUrl(widget.item.id);
      if (uri == null) {
        showAppSnack(
          SnackBar(
            content: Text(
              itemsProvider.errorMessage ?? 'Could not prepare the download.',
            ),
          ),
        );
        return;
      }
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        await Clipboard.setData(ClipboardData(text: uri.toString()));
        showAppSnack(
          const SnackBar(content: Text('CAD file link copied to clipboard.')),
        );
      }
    } catch (error) {
      showAppSnack(
        SnackBar(content: Text('Could not download the CAD file: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isPreparing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _DetailCard(
      title: 'CAD File',
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE1E5F0)),
              ),
              child: Text(
                _extension,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: const TextStyle(
                  color: SoftErpTheme.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _fileName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: SoftErpTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: AppButton(
            label: 'Download CAD File',
            icon: Icons.download_outlined,
            variant: AppButtonVariant.secondary,
            isLoading: _isPreparing,
            onPressed: () => _download(context),
          ),
        ),
      ],
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
    final allUnits = [
      unitLabel,
      ...item.unitConversions.map((e) => e.unitSymbol),
    ].join(', ');

    return _DetailCard(
      title: 'Factsheet',
      children: [
        Wrap(
          children: [
            _FactRow(label: 'Item name', value: item.name, width: 90),
            _FactRow(label: 'Unit', value: allUnits, width: 90),
            _UsageFactRow(item: item, width: 140),
            _FactRow(label: 'Display name', value: item.displayName, width: 90),
            _FactRow(
              label: 'Status',
              value: item.isArchived ? 'Archived' : 'Active',
              width: 90,
            ),
            _FactRow(label: 'Group', value: groupName, width: 120),
            if (item.defaultPipelineName != null &&
                item.defaultPipelineName!.isNotEmpty)
              _FactRow(
                label: 'Default pipeline',
                value: item.defaultPipelineName!,
                width: 140,
              ),
            if (item.alias.trim().isNotEmpty)
              _FactRow(label: 'Alias', value: item.alias, width: 90),
            if (imageCount > 0)
              _FactRow(
                label: 'Images',
                value: imageCount.toString(),
                width: 90,
              ),
          ],
        ),
        const SizedBox(height: 8),
        _FactWrapRow(
          label: 'Items variation',
          values: generatedCodes,
          emptyText: 'No variations found.',
          useChips: false,
        ),

        if (item.unitConversions.isNotEmpty)
          _FactWrapRow(
            label: 'Conversions',
            values: item.unitConversions
                .map(
                  (entry) =>
                      '1 ${entry.unitSymbol} = ${_fmtFactor(entry.factorToPrimary)} base',
                )
                .toList(growable: false),
            emptyText: '',
            useChips: true,
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
    final rootNodes = item.variationTree
        .where((node) => !node.isArchived)
        .toList();
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
    final Color badgeBg = isProperty
        ? const Color(0xFFEEF2FE)
        : const Color(0xFFF0FDF4);
    final Color badgeText = isProperty
        ? const Color(0xFF3B82F6)
        : const Color(0xFF16A34A);
    final Color badgeBorder = isProperty
        ? const Color(0xFFBFDBFE)
        : const Color(0xFFBBF7D0);
    final IconData icon = isProperty
        ? Icons.account_tree_outlined
        : Icons.label_outlined;

    final activeChildren = node.activeChildren;

    return SoftEntranceAnimation(
      direction: EntranceDirection.up,
      delay: Duration(milliseconds: 150 + (50 * depth)),
      child: Column(
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
                  child:
                      i < parentHasNextSibling.length && parentHasNextSibling[i]
                      ? Container(width: 1.5, color: const Color(0xFFCBD5E1))
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
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
      ),
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
  const _FactRow({required this.label, required this.value, this.width});

  final String label;
  final String value;
  final double? width;

  @override
  Widget build(BuildContext context) {
    Widget content = Padding(
      padding: const EdgeInsets.only(bottom: 14, right: 8),
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
    if (width != null) {
      return SizedBox(width: width, child: content);
    }
    return content;
  }
}

class _FactWrapRow extends StatelessWidget {
  const _FactWrapRow({
    required this.label,
    required this.values,
    required this.emptyText,
    this.useChips = true,
  });

  final String label;
  final List<String> values;
  final String emptyText;
  final bool useChips;

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
          else if (useChips)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: filtered
                  .map((value) => _DetailChip(label: value))
                  .toList(growable: false),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: filtered
                  .map(
                    (value) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        value,
                        style: const TextStyle(
                          color: SoftErpTheme.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
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
  if (item.namingFormat.isEmpty) {
    return available;
  }
  return item.namingFormat
      .where((token) => available.contains(token))
      .toList(growable: true);
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

String nodeNameOrGenerated(ItemVariationNodeDefinition node) {
  final name = node.displayName.trim().isEmpty
      ? node.name.trim()
      : node.displayName.trim();
  return name.isNotEmpty ? name : 'Unnamed';
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

/// Conversion factors to 3 decimal places, trailing zeros stripped
/// (0.006944… → "0.007", 144.0 → "144").
String _fmtFactor(num value) {
  var s = value.toStringAsFixed(3);
  if (s.contains('.')) {
    s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
  return s;
}

class _UsageFactRow extends StatefulWidget {
  const _UsageFactRow({required this.item, this.width});

  final ItemDefinition item;
  final double? width;

  @override
  State<_UsageFactRow> createState() => _UsageFactRowState();
}

class _UsageFactRowState extends State<_UsageFactRow> {
  bool _expanded = false;
  bool _loading = false;
  List<ItemUsageRecord>? _records;

  Future<void> _toggle() async {
    setState(() {
      _expanded = !_expanded;
    });
    if (_expanded && _records == null && !_loading) {
      setState(() => _loading = true);
      final records = await context.read<ItemsProvider>().fetchItemUsage(
        widget.item.id,
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _records = records;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content = Padding(
      padding: const EdgeInsets.only(bottom: 14, right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Usage',
            style: TextStyle(
              color: SoftErpTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          InkWell(
            onTap: widget.item.usageCount > 0 ? _toggle : null,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      '${widget.item.usageCount} linked record(s)',
                      style: TextStyle(
                        color: widget.item.usageCount > 0
                            ? SoftErpTheme.accent
                            : SoftErpTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        decoration: widget.item.usageCount > 0
                            ? TextDecoration.underline
                            : TextDecoration.none,
                      ),
                    ),
                  ),
                  if (widget.item.usageCount > 0) ...[
                    const SizedBox(width: 4),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 16,
                      color: SoftErpTheme.accent,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 8),
            if (_loading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (_records == null || _records!.isEmpty)
              const Text(
                'No usage details found.',
                style: TextStyle(
                  color: SoftErpTheme.textSecondary,
                  fontSize: 13,
                ),
              )
            else
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: SoftErpTheme.border),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _records!.map((record) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            record.title,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: SoftErpTheme.textPrimary,
                            ),
                          ),
                          if (record.subtitle.isNotEmpty)
                            Text(
                              record.subtitle,
                              style: const TextStyle(
                                fontSize: 12,
                                color: SoftErpTheme.textSecondary,
                              ),
                            ),
                          if (record.status != null)
                            Text(
                              'Status: ${record.status}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: SoftErpTheme.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ],
      ),
    );

    if (widget.width != null && !_expanded) {
      return SizedBox(width: widget.width, child: content);
    }
    return SizedBox(
      width: _expanded ? double.infinity : widget.width,
      child: content,
    );
  }
}

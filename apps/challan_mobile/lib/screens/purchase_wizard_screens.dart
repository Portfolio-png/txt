import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:core_erp/core/services/generic_asset_service.dart';
import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/core/widgets/app_toast.dart';
import 'package:core_erp/features/delivery_challans/domain/delivery_challan.dart';
import 'package:core_erp/features/delivery_challans/data/delivery_challan_repository.dart';
import 'package:core_erp/features/delivery_challans/presentation/providers/delivery_challan_provider.dart';
import 'package:core_erp/features/delivery_challans/presentation/widgets/challan_printable_document.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/presentation/providers/favorites_provider.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/features/vendors/domain/vendor_definition.dart';
import 'package:core_erp/features/vendors/presentation/providers/vendors_provider.dart';
import 'package:core_erp/widgets/variation_path_selector_dialog.dart';

import '../widgets/piece_barcode_bottom_sheet.dart';
import '../widgets/wizard_progress.dart';
import 'purchase_challan_screens.dart' show showPurchaseQuantitySheet;

/// Purchase Wizard (v2) — gated by `FeatureKeys.purchaseFlowV2`.
///
/// Vendor → Items → Challan photo → Print preview → Barcodes. Unlike the v1
/// browse flow, every piece of state lives in this one State object rather than
/// in top-level globals, so backing out of the wizard cannot leave a half-built
/// challan behind for the next run to inherit.
class PurchaseWizardScreen extends StatefulWidget {
  const PurchaseWizardScreen({super.key});

  @override
  State<PurchaseWizardScreen> createState() => _PurchaseWizardScreenState();
}

enum _Step { vendor, items, photo, preview, done }

const _stepLabels = <String>['Supplier', 'Items', 'Photo', 'Preview', 'Done'];

class _PurchaseWizardScreenState extends State<PurchaseWizardScreen> {
  _Step _step = _Step.vendor;

  VendorDefinition? _vendor;
  final List<DeliveryChallanItem> _lines = [];
  final List<XFile> _photos = [];
  List<Map<String, dynamic>> _uploadedAssets = const [];

  bool _uploading = false;
  bool _submitting = false;
  DeliveryChallan? _created;

  /// Date and location are fixed on mobile: the preview is read-only, so there
  /// is nowhere to correct them. Back-dating or a non-MAIN location is a
  /// desktop job.
  final DateTime _date = DateTime.now();
  static const String _location = 'MAIN';

  void _goTo(_Step step) => setState(() => _step = step);

  Future<bool> _confirmDiscard() async {
    if (_lines.isEmpty && _vendor == null) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete challan?', style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text('Everything you\'ve added will be cleared.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD64545)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// Back steps one form at a time and never throws work away implicitly — the
  /// only way to lose progress is the explicit Discard button. On the first
  /// form there is no earlier form, so back offers to discard. Once submitted
  /// (Done) the challan is saved, so back just closes the wizard.
  Future<void> _handleBack() async {
    switch (_step) {
      case _Step.vendor:
        await _discardWizard();
      case _Step.items:
        _goTo(_Step.vendor);
      case _Step.photo:
        _goTo(_Step.items);
      case _Step.preview:
        _goTo(_Step.photo);
      case _Step.done:
        Navigator.of(context).pop(true);
    }
  }

  /// Explicit teardown: confirm, then close the wizard (its route pops back to
  /// the Challan tiles). Switching tabs instead keeps everything — the wizard
  /// stays mounted in the tab, so work is only lost on a deliberate discard.
  Future<void> _discardWizard() async {
    if (await _confirmDiscard() && mounted) Navigator.of(context).pop();
  }

  /// Jump straight to a form from the progress rail. Only the pre-submit forms
  /// are reachable; once submitted the flow is terminal.
  void _jumpTo(int index) {
    if (_step == _Step.done) return;
    if (index < _Step.vendor.index || index > _Step.preview.index) return;
    setState(() => _step = _Step.values[index]);
  }

  Future<void> _addItem() async {
    final line = await Navigator.of(context).push<DeliveryChallanItem>(
      MaterialPageRoute(
        builder: (_) => _ItemPickerScreen(nextLineNo: _lines.length + 1),
      ),
    );
    if (line == null || !mounted) return;
    setState(() => _lines.add(line));
  }

  // ---------------------------------------------------------------- photo

  Future<void> _capturePhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _photos.add(picked);
      // A new photo invalidates the previous upload — force a re-upload so the
      // "go ahead" button can't let through a set that was never sent to S3.
      _uploadedAssets = const [];
    });
  }

  Future<void> _uploadPhotos() async {
    if (_photos.isEmpty || _uploading) return;
    setState(() => _uploading = true);
    final assetService = context.read<GenericAssetService>();
    final uploaded = <Map<String, dynamic>>[];
    try {
      for (final photo in _photos) {
        final bytes = await photo.readAsBytes();
        final contentType = 'image/${photo.name.split('.').last}';
        final intent = await assetService.createUploadIntent(
          GenericAssetUploadIntentInput(
            fileName: photo.name,
            contentType: contentType,
            sizeBytes: bytes.length,
            sha256: '',
          ),
        );
        // Mock mode returns a placeholder upload target with no real bucket
        // behind it, so there is nothing to PUT to — the intent itself stands
        // in for the upload. Only the real presigned flow does the network PUT.
        if (!assetService.useMockResponses) {
          final response = await http.put(
            intent.uploadUrl,
            headers: intent.headers,
            body: bytes,
          );
          // A presigned PUT that returns non-2xx has not stored the object, and
          // recording its key anyway would attach a challan asset that 404s.
          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw Exception(
              'Upload of ${photo.name} rejected with HTTP ${response.statusCode}',
            );
          }
        }
        uploaded.add({
          'fileName': photo.name,
          'contentType': contentType,
          'sizeBytes': bytes.length,
          'objectKey': intent.objectKey,
          'sha256': '',
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      showAppToast(context, 'Upload failed: $e', kind: AppToastKind.error);
      return;
    }
    if (!mounted) return;
    setState(() {
      _uploadedAssets = uploaded;
      _uploading = false;
    });
    showAppToast(
      context,
      'Attached ${uploaded.length} photo${uploaded.length == 1 ? '' : 's'}',
      kind: AppToastKind.success,
    );
  }

  // --------------------------------------------------------------- submit

  /// The unsaved challan rendered by the preview. [challanNo] is a placeholder:
  /// the real number is minted server-side on create, so it cannot be known
  /// here — it lands on the Done step instead.
  DeliveryChallan _draftForPreview() {
    return DeliveryChallan(
      id: 0,
      type: ChallanType.reception,
      purpose: ChallanPurpose.trading,
      orderId: 0,
      orderIds: const [],
      clientId: null,
      orderNo: '',
      orderNos: const [],
      challanNo: 'Auto — on submit',
      date: _date,
      location: _location,
      customerName: '',
      customerGstin: '',
      vendorId: _vendor?.id ?? 0,
      vendorName: _vendor?.name ?? '',
      vendorGstin: _vendor?.gstNumber ?? '',
      sourceReference: '',
      companyProfileSnapshot: null,
      notes: '',
      maintainStocks: true,
      status: DeliveryChallanStatus.draft,
      items: _lines,
      itemsCount: _lines.length,
      assets: const [],
      createdAt: null,
      updatedAt: null,
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    final provider = context.read<DeliveryChallanProvider>();
    final draft = DeliveryChallanDraftInput(
      type: ChallanType.reception,
      purpose: ChallanPurpose.trading,
      internalPurpose: '',
      challanNo: '', // empty → backend auto-generates
      orderId: 0,
      orderIds: const [],
      vendorId: _vendor?.id ?? 0,
      materialOwnerClientId: null,
      date: _date,
      location: _location,
      sourceReference: '',
      notes: '',
      maintainStocks: true,
      customerName: '',
      customerGstin: '',
      vendorName: _vendor?.name ?? '',
      vendorGstin: _vendor?.gstNumber ?? '',
      items: _lines,
      genericAssets: _uploadedAssets,
    );

    final created = await provider.createChallan(draft);
    if (!mounted) return;
    if (created == null) {
      setState(() => _submitting = false);
      showAppToast(
        context,
        provider.errorMessage ?? 'Failed to create challan',
        kind: AppToastKind.error,
      );
      return;
    }

    // Mobile submits an issued challan, not a draft. If the issue is rejected
    // the challan survives as a draft, so surface the reason instead of
    // pretending it went through.
    final issued = await provider.issueChallan(created.id);
    if (!mounted) return;
    setState(() {
      _created = issued ?? created;
      _submitting = false;
      _step = _Step.done;
    });

    if (issued == null) {
      showAppToast(
        context,
        'Saved draft ${created.challanNo} — could not issue: '
        '${provider.errorMessage ?? 'unknown error'}. Issue it from the desktop.',
        kind: AppToastKind.error,
      );
    }
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: SoftErpTheme.shellSurface,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
          // First form has no earlier form to step to → a close affordance;
          // later forms step back; the terminal Done screen has neither.
          leading: _step == _Step.done
              ? null
              : _step == _Step.vendor
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Close',
                      onPressed: _discardWizard,
                    )
                  : IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: 'Back',
                      onPressed: _handleBack,
                    ),
          title: Text(
            _titleForStep(),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          actions: [
            // Discard is available on every pre-submit form so work can be
            // dropped at any moment; once issued there is nothing to discard.
            if (_step != _Step.done)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton.icon(
                  onPressed: _discardWizard,
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFFD64545)),
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  label: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(72),
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.only(bottom: 12),
              child: WizardProgress(
                labels: _stepLabels,
                currentIndex: _step.index,
                onStepTapped: _step == _Step.done ? null : _jumpTo,
                canTap: (i) => i <= _Step.preview.index,
              ),
            ),
          ),
        ),
        body: SafeArea(child: _buildStep()),
      ),
    );
  }

  String _titleForStep() {
    switch (_step) {
      case _Step.vendor:
        return 'Select Supplier';
      case _Step.items:
        return _vendor?.name ?? 'Items';
      case _Step.photo:
        return 'Challan Photo';
      case _Step.preview:
        return 'Preview';
      case _Step.done:
        return 'Barcodes';
    }
  }

  Widget _buildStep() {
    switch (_step) {
      case _Step.vendor:
        return _VendorStep(
          selected: _vendor,
          onPicked: (v) {
            setState(() => _vendor = v);
            _goTo(_Step.items);
          },
        );
      case _Step.items:
        return _ItemsStep(
          lines: _lines,
          onAdd: _addItem,
          onRemove: (i) => setState(() => _lines.removeAt(i)),
          onNext: () => _goTo(_Step.photo),
        );
      case _Step.photo:
        return _PhotoStep(
          photos: _photos,
          uploading: _uploading,
          uploaded: _uploadedAssets.isNotEmpty,
          onCapture: _capturePhoto,
          onUpload: _uploadPhotos,
          onRemove: (i) => setState(() {
            _photos.removeAt(i);
            _uploadedAssets = const [];
          }),
          onContinue: () => _goTo(_Step.preview),
          onSkip: () => _goTo(_Step.preview),
        );
      case _Step.preview:
        return _PreviewStep(
          challan: _draftForPreview(),
          submitting: _submitting,
          onSubmit: _submit,
        );
      case _Step.done:
        return _DoneStep(
          challan: _created!,
          onFinish: () => Navigator.of(context).pop(true),
        );
    }
  }
}

// =========================================================== step 1: vendor

class _VendorStep extends StatefulWidget {
  const _VendorStep({required this.selected, required this.onPicked});

  final VendorDefinition? selected;
  final ValueChanged<VendorDefinition> onPicked;

  @override
  State<_VendorStep> createState() => _VendorStepState();
}

class _VendorStepState extends State<_VendorStep> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = context
        .watch<VendorsProvider>()
        .vendors
        .where((v) => !v.isArchived)
        .toList(growable: false);
    final vendors = _query.isEmpty
        ? all
        : all
            .where((v) => v.name.toLowerCase().contains(_query.toLowerCase()))
            .toList(growable: false);

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search suppliers...',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: SoftErpTheme.shellSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
        ),
        Expanded(
          child: vendors.isEmpty
              ? const _EmptyState(
                  icon: Icons.storefront_outlined,
                  title: 'No suppliers found',
                  message: 'Add suppliers in the desktop app first.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: vendors.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final v = vendors[i];
                    final isSelected = widget.selected?.id == v.id;
                    return ListTile(
                      tileColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: isSelected
                            ? const BorderSide(color: SoftErpTheme.accent, width: 2)
                            : BorderSide.none,
                      ),
                      leading: const Icon(Icons.storefront_rounded, color: SoftErpTheme.accent),
                      title: Text(v.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(v.gstNumber.isNotEmpty ? 'GST: ${v.gstNumber}' : 'Supplier'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => widget.onPicked(v),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ============================================================ step 2: items

class _ItemsStep extends StatelessWidget {
  const _ItemsStep({
    required this.lines,
    required this.onAdd,
    required this.onRemove,
    required this.onNext,
  });

  final List<DeliveryChallanItem> lines;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 200,
                height: 200,
                child: Material(
                  color: Colors.white,
                  shape: const CircleBorder(),
                  elevation: 2,
                  shadowColor: SoftErpTheme.accent.withOpacity(0.25),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onAdd,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.add_rounded, size: 64, color: SoftErpTheme.accent),
                        SizedBox(height: 8),
                        Text(
                          'Add Item',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: SoftErpTheme.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Add the goods you received from this supplier.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: lines.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final line = lines[i];
              final def = context.read<ItemsProvider>().findById(line.itemId);
              final unit = (def != null && def.unitConversions.isNotEmpty) ? def.unitConversions.first.unitSymbol : 'kg';
              return ListTile(
                tileColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                leading: const Icon(Icons.inventory_2_rounded, color: SoftErpTheme.accent),
                title: Text(line.particulars, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(
                  [
                    if (line.variationPathLabel.isNotEmpty) line.variationPathLabel,
                    'Qty: ${line.quantityPcs}',
                    if (line.weight != '0' && line.weight != '0.0') 'Wt: ${line.weight} $unit',
                  ].join('  ·  '),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                  onPressed: () => onRemove(i),
                  tooltip: 'Remove',
                ),
              );
            },
          ),
        ),
        SafeArea(
          minimum: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    side: const BorderSide(color: SoftErpTheme.accent, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded, color: SoftErpTheme.accent),
                  label: const Text(
                    'Add more',
                    style: TextStyle(fontWeight: FontWeight.w800, color: SoftErpTheme.accent),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    backgroundColor: SoftErpTheme.accent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  onPressed: onNext,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(
                    'Next (${lines.length})',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Group → item → variation → quantity, popping the finished line back to the
/// wizard. Mirrors the v1 group browser's shape (search, single-group collapse,
/// expand-all toggle, favourites) but owns no cart of its own.
class _ItemPickerScreen extends StatefulWidget {
  const _ItemPickerScreen({required this.nextLineNo});

  final int nextLineNo;

  @override
  State<_ItemPickerScreen> createState() => _ItemPickerScreenState();
}

class _ItemPickerScreenState extends State<_ItemPickerScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  bool _expandAll = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pick(ItemDefinition item) async {
    final favProvider = context.read<FavoritesProvider>();
    VariationPathSelectionResult? variation;
    // Items with no variation properties skip the picker — it can never resolve
    // a leaf for them, so its Confirm button would stay disabled forever.
    if (item.topLevelProperties.isNotEmpty) {
      variation = await showDialog<VariationPathSelectionResult>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          insetPadding: const EdgeInsets.all(24),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: VariationPathSelectorDialog(
                item: item,
                initialRootPropertyId: null,
                initialValueNodeIds: const [],

                allowCustomValues: false,
                isFavorite: (result) => favProvider.isFavorite(item.id, result.valueNodeIds),
                onFavoriteToggled: (result, isFav) {
                  favProvider.toggleFavorite(
                    _lineFrom(
                      item: item,
                      variation: result,
                      qty: '1',
                      weight: '0.0',
                      lineNo: 0,
                    ),
                    isFav,
                  );
                  showAppToast(
                    context,
                    isFav ? 'Variation saved to favorites' : 'Variation removed from favorites',
                    kind: AppToastKind.success,
                  );
                },
              ),
            ),
          ),
        ),
      );
      if (variation == null || !mounted) return;
    }

    showPurchaseQuantitySheet(
      context,
      onConfirm: (qty, weight) {
        Navigator.of(context).pop(
          _lineFrom(
            item: item,
            variation: variation,
            qty: qty,
            weight: weight,
            lineNo: widget.nextLineNo,
          ),
        );
      },
    );
  }

  DeliveryChallanItem _lineFrom({
    required ItemDefinition item,
    required VariationPathSelectionResult? variation,
    required String qty,
    required String weight,
    required int lineNo,
  }) {
    return DeliveryChallanItem(
      id: 0,
      orderItemId: null,
      productionRunId: null,
      itemId: item.id,
      variationLeafNodeId: variation?.leaf?.id ?? 0,
      variationPathLabel: variation?.summaryLabel ?? '',
      variationPathNodeIds: variation?.valueNodeIds ?? const <int>[],
      customVariationValues: variation?.customVariationValues ?? const <int, String>{},
      particulars: item.displayName,
      quantityPcs: qty,
      weight: weight,
      lineNo: lineNo,
      hsnCode: '',
      note: '',
    );
  }

  void _pickFavorite(DeliveryChallanItem fav) {
    // Favorites load with an empty `particulars` (FavoritesProvider hydrates the
    // name from ItemsProvider only for display), so resolve the real item name
    // here — otherwise the cart line and preview show a blank product.
    final itemsProvider = context.read<ItemsProvider>();
    final idx = itemsProvider.items.indexWhere((i) => i.id == fav.itemId);
    final resolvedName = idx >= 0
        ? itemsProvider.items[idx].displayName
        : (fav.particulars.isNotEmpty ? fav.particulars : 'Item');

    showPurchaseQuantitySheet(
      context,
      onConfirm: (qty, weight) {
        Navigator.of(context).pop(
          DeliveryChallanItem(
            id: 0,
            orderItemId: null,
            productionRunId: null,
            itemId: fav.itemId,
            variationLeafNodeId: fav.variationLeafNodeId,
            variationPathLabel: fav.variationPathLabel,
            variationPathNodeIds: fav.variationPathNodeIds,
            customVariationValues: fav.customVariationValues,
            particulars: resolvedName,
            quantityPcs: qty,
            weight: weight,
            lineNo: widget.nextLineNo,
            hsnCode: '',
            note: '',
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final itemsProvider = context.watch<ItemsProvider>();
    final groupsProvider = context.watch<GroupsProvider>();
    final favorites = context.watch<FavoritesProvider>().favorites;

    final purchaseItems = itemsProvider.items
        .where((i) => i.availableForPurchase && !i.isArchived)
        .toList(growable: false);
    final filtered = _query.isEmpty
        ? purchaseItems
        : purchaseItems
            .where((i) => i.displayName.toLowerCase().contains(_query.toLowerCase()))
            .toList(growable: false);

    final groupIds = filtered.map((i) => i.groupId).toSet();
    final groups = groupsProvider.itemGroups
        .where((g) => !g.isArchived && groupIds.contains(g.id))
        .toList(growable: false);
    final isSingleGroup = groups.length == 1;

    return Scaffold(
      backgroundColor: SoftErpTheme.shellSurface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: Text(
          isSingleGroup ? groups.first.name : 'Select Item',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          if (!isSingleGroup && groups.isNotEmpty)
            IconButton(
              tooltip: 'Toggle groups',
              icon: Icon(
                _expandAll ? Icons.unfold_less_rounded : Icons.unfold_more_rounded,
                color: SoftErpTheme.accent,
              ),
              onPressed: () => setState(() => _expandAll = !_expandAll),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search items...',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: SoftErpTheme.shellSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          Expanded(
            child: groups.isEmpty && favorites.isEmpty
                ? const _EmptyState(
                    icon: Icons.category_outlined,
                    title: 'No purchase items',
                    message: 'Mark items as "Available for purchase" in the desktop app.',
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (favorites.isNotEmpty && _query.isEmpty) ...[
                        Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                          color: Colors.white,
                          child: ExpansionTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.pink.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.favorite_rounded, color: Colors.pink),
                            ),
                            title: const Text('Favorites', style: TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(
                              '${favorites.length} item${favorites.length == 1 ? '' : 's'}',
                              style: const TextStyle(fontSize: 12, color: SoftErpTheme.textSecondary),
                            ),
                            children: favorites.map((fav) {
                              final idx = itemsProvider.items.indexWhere((i) => i.id == fav.itemId);
                              final name = idx >= 0 ? itemsProvider.items[idx].displayName : fav.particulars;
                              return ListTile(
                                leading: const Icon(Icons.favorite_rounded, color: Colors.pink),
                                title: Text(
                                  name.isEmpty ? 'Unknown item' : name,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  fav.variationPathLabel.isNotEmpty ? fav.variationPathLabel : 'Standard',
                                ),
                                trailing: const Icon(Icons.add_circle_outline_rounded, color: SoftErpTheme.accent),
                                onTap: () => _pickFavorite(fav),
                              );
                            }).toList(growable: false),
                          ),
                        ),
                      ],
                      ...groups.map((group) {
                        final groupItems =
                            filtered.where((i) => i.groupId == group.id).toList(growable: false);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                          color: Colors.white,
                          child: ExpansionTile(
                            initiallyExpanded: _expandAll || isSingleGroup || _query.isNotEmpty,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: SoftErpTheme.accent.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.folder_open_rounded, color: SoftErpTheme.accent),
                            ),
                            title: Text(group.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(
                              '${groupItems.length} item${groupItems.length == 1 ? '' : 's'}',
                              style: const TextStyle(fontSize: 12, color: SoftErpTheme.textSecondary),
                            ),
                            children: groupItems
                                .map(
                                  (item) => ListTile(
                                    leading: const Icon(Icons.inventory_2_rounded, color: Colors.grey),
                                    title: Text(item.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    subtitle: Text('ID: ${item.id}'),
                                    trailing: const Icon(Icons.add_circle_outline_rounded, color: SoftErpTheme.accent),
                                    onTap: () => _pick(item),
                                  ),
                                )
                                .toList(growable: false),
                          ),
                        );
                      }),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ============================================================ step 3: photo

class _PhotoStep extends StatelessWidget {
  const _PhotoStep({
    required this.photos,
    required this.uploading,
    required this.uploaded,
    required this.onCapture,
    required this.onUpload,
    required this.onRemove,
    required this.onContinue,
    required this.onSkip,
  });

  final List<XFile> photos;
  final bool uploading;
  final bool uploaded;
  final VoidCallback onCapture;
  final VoidCallback onUpload;
  final ValueChanged<int> onRemove;
  final VoidCallback onContinue;

  /// Advance to the preview without attaching a photo — the challan document is
  /// the same either way, so the photo is a convenience, not a requirement.
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: photos.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 200,
                          height: 200,
                          child: Material(
                            color: Colors.white,
                            shape: const CircleBorder(),
                            elevation: 2,
                            shadowColor: SoftErpTheme.accent.withOpacity(0.25),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: onCapture,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.camera_alt_rounded, size: 64, color: SoftErpTheme.accent),
                                  SizedBox(height: 8),
                                  Text(
                                    'Scan Challan',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      color: SoftErpTheme.accent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Photograph the supplier\'s physical challan.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: onSkip,
                          style: TextButton.styleFrom(foregroundColor: SoftErpTheme.textSecondary),
                          icon: const Icon(Icons.skip_next_rounded, size: 20),
                          label: const Text(
                            'Skip — no photo',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: photos.length + 1,
                  itemBuilder: (context, i) {
                    if (i == photos.length) {
                      return Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: uploading ? null : onCapture,
                          child: const Center(
                            child: Icon(Icons.add_a_photo_rounded, color: SoftErpTheme.accent, size: 32),
                          ),
                        ),
                      );
                    }
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.file(File(photos[i].path), fit: BoxFit.cover),
                        ),
                        if (!uploading)
                          Positioned(
                            top: 4,
                            right: 4,
                            child: InkWell(
                              onTap: () => onRemove(i),
                              child: const CircleAvatar(
                                radius: 14,
                                backgroundColor: Colors.red,
                                child: Icon(Icons.close, size: 16, color: Colors.white),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
        ),
        if (photos.isNotEmpty)
          SafeArea(
            minimum: const EdgeInsets.all(16),
            child: uploading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      children: [
                        CircularProgressIndicator(color: SoftErpTheme.accent),
                        SizedBox(height: 12),
                        Text('Uploading...', style: TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  )
                : uploaded
                    // The "go ahead" button only exists once S3 has the file, so
                    // a failed upload can't be walked past.
                    ? FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          backgroundColor: Colors.green.shade600,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        ),
                        onPressed: onContinue,
                        icon: const Icon(Icons.check_circle_rounded),
                        label: const Text(
                          'Attached · Go ahead',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                      )
                    : FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          backgroundColor: SoftErpTheme.accent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        ),
                        onPressed: onUpload,
                        icon: const Icon(Icons.cloud_upload_rounded),
                        label: Text(
                          'Upload ${photos.length} photo${photos.length == 1 ? '' : 's'}',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                      ),
          ),
      ],
    );
  }
}

// ========================================================== step 4: preview

class _PreviewStep extends StatelessWidget {
  const _PreviewStep({
    required this.challan,
    required this.submitting,
    required this.onSubmit,
  });

  final DeliveryChallan challan;
  final bool submitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    if (submitting) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: SoftErpTheme.accent),
            SizedBox(height: 16),
            Text('Submitting...', style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: InteractiveViewer(
            minScale: 0.4,
            maxScale: 3,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              // The document lays out at a fixed 760px and does not reflow, so
              // scale it to the viewport rather than letting it overflow.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topCenter,
                child: Material(
                  elevation: 3,
                  child: ChallanPrintableDocument(challan: challan),
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          minimum: const EdgeInsets.all(16),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              backgroundColor: SoftErpTheme.accent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            onPressed: onSubmit,
            icon: const Icon(Icons.check_circle_rounded),
            label: const Text('Submit Challan', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ),
      ],
    );
  }
}

// ============================================================= step 5: done

class _DoneStep extends StatelessWidget {
  const _DoneStep({required this.challan, required this.onFinish});

  final DeliveryChallan challan;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final isIssued = challan.status == DeliveryChallanStatus.issued;
    return Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isIssued ? Colors.green.shade50 : Colors.orange.shade50,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isIssued ? Colors.green.shade200 : Colors.orange.shade200,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isIssued ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                color: isIssued ? Colors.green.shade700 : Colors.orange.shade800,
                size: 32,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isIssued ? 'Issued ${challan.challanNo}' : 'Saved draft ${challan.challanNo}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: isIssued ? Colors.green.shade900 : Colors.orange.shade900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isIssued
                          ? 'Print barcode tags for the received pieces.'
                          : 'Could not issue — finish it from the desktop.',
                      style: TextStyle(
                        color: isIssued ? Colors.green.shade800 : Colors.orange.shade800,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: challan.items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final item = challan.items[i];
              return ListTile(
                tileColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                leading: const Icon(Icons.qr_code_2_rounded, color: SoftErpTheme.accent),
                title: Text(item.particulars, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(
                  [
                    if (item.variationPathLabel.isNotEmpty) item.variationPathLabel,
                    'Qty: ${item.quantityPcs}',
                  ].join('  ·  '),
                ),
                trailing: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: SoftErpTheme.accent.withOpacity(0.1),
                    foregroundColor: SoftErpTheme.accent,
                    elevation: 0,
                  ),
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => PieceBarcodeBottomSheet(
                      item: item,
                      orderOrigin: challan.challanNo,
                    ),
                  ),
                  icon: const Icon(Icons.print_rounded, size: 18),
                  label: const Text('Tags', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              );
            },
          ),
        ),
        SafeArea(
          minimum: const EdgeInsets.all(16),
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              side: const BorderSide(color: SoftErpTheme.accent, width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            onPressed: onFinish,
            child: const Text(
              'Skip printing · Done',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: SoftErpTheme.accent),
            ),
          ),
        ),
      ],
    );
  }
}

// ================================================================== shared

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';

import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/features/delivery_challans/domain/delivery_challan.dart';
import 'package:core_erp/features/delivery_challans/data/delivery_challan_repository.dart';
import 'package:core_erp/features/delivery_challans/presentation/providers/delivery_challan_provider.dart';
import 'package:core_erp/features/clients/presentation/providers/clients_provider.dart';
import 'package:core_erp/features/vendors/presentation/providers/vendors_provider.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/features/items/presentation/providers/favorites_provider.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/orders/domain/order_entry.dart';
import 'package:core_erp/widgets/variation_path_selector_dialog.dart';
import 'package:core_erp/core/services/generic_asset_service.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../widgets/piece_barcode_bottom_sheet.dart';

class ChallanMobileEditorScreen extends StatefulWidget {
  const ChallanMobileEditorScreen({
    super.key,
    this.initialItems,
    this.lockedType,
    this.initialVendorId,
    this.initialOrderGroup,
  });

  /// Line items pre-collected by the Purchase browse flow. When provided, the
  /// editor opens as a review-and-submit screen with these already added.
  final List<DeliveryChallanItem>? initialItems;

  /// When set, the document-type dropdown is hidden and the type is fixed
  /// (the Purchase flow locks this to [ChallanType.reception]).
  final ChallanType? lockedType;
  
  /// Pre-select a vendor if navigating from a vendor-specific flow
  final int? initialVendorId;

  /// Pre-select an order group if navigating from a use workflow
  final OrderGroup? initialOrderGroup;

  @override
  State<ChallanMobileEditorScreen> createState() => _ChallanMobileEditorScreenState();
}

class _ChallanMobileEditorScreenState extends State<ChallanMobileEditorScreen> with TickerProviderStateMixin {
  ChallanType _type = ChallanType.delivery;
  final _formKey = GlobalKey<FormState>();
  
  int? _selectedClientId;
  int? _selectedVendorId;
  DateTime _challanDate = DateTime.now();
  final _challanNoController = TextEditingController();
  final _locationController = TextEditingController(text: 'MAIN');
  final _notesController = TextEditingController();
  
  final List<DeliveryChallanItem> _items = [];
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  bool _isSaving = false;
  final List<XFile> _attachedImages = [];

  late AnimationController _fabAnimController;

  @override
  void initState() {
    super.initState();
    if (widget.initialOrderGroup != null) _type = ChallanType.internal;
    if (widget.lockedType != null) _type = widget.lockedType!;
    if (widget.initialVendorId != null) _selectedVendorId = widget.initialVendorId;
    if (widget.initialItems != null) _items.addAll(widget.initialItems!);
    _fabAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _fabAnimController.dispose();
    _challanNoController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    
    if (pickedFile != null) {
      setState(() {
        _attachedImages.add(pickedFile);
      });
    }
  }

  void _showQuantityBottomSheet(
    BuildContext context, 
    DeliveryChallanItem? existingItem, 
    Function(String qty, String weight) onConfirm
  ) {
    int qty = int.tryParse(existingItem?.quantityPcs ?? '1') ?? 1;
    double weight = double.tryParse(existingItem?.weight ?? '0.0') ?? 0.0;
    final isTablet = MediaQuery.of(context).size.width >= 600;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Container(
              margin: EdgeInsets.only(top: MediaQuery.of(ctx).padding.top + 40),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                boxShadow: [
                  BoxShadow(color: Colors.black26, blurRadius: 20, spreadRadius: 5)
                ]
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
                left: 24, right: 24, top: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 50,
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    existingItem == null ? 'Set Quantity' : 'Edit Quantity',
                    style: const TextStyle(
                      fontSize: 24.0, 
                      fontWeight: FontWeight.w900,
                      color: SoftErpTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: SoftErpTheme.shellSurface,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Quantity (Pcs)', 
                          style: TextStyle(
                            fontSize: 16.0,
                            fontWeight: FontWeight.w700,
                            color: SoftErpTheme.textSecondary,
                          )
                        ),
                        Row(
                          children: [
                            _buildCounterButton(Icons.remove, Colors.red, () {
                              if (qty > 1) setModalState(() => qty--);
                            }),
                            const SizedBox(width: 20),
                            Text(
                              '$qty', 
                              style: const TextStyle(
                                fontSize: 24.0, 
                                fontWeight: FontWeight.bold,
                                color: SoftErpTheme.textPrimary,
                              )
                            ),
                            const SizedBox(width: 20),
                            _buildCounterButton(Icons.add, Colors.green, () {
                              setModalState(() => qty++);
                            }),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          style: const TextStyle(fontSize: 18.0, fontWeight: FontWeight.w600, color: SoftErpTheme.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'Weight (kg)',
                            labelStyle: const TextStyle(color: SoftErpTheme.textSecondary, fontWeight: FontWeight.normal),
                            filled: true,
                            fillColor: SoftErpTheme.shellSurface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide.none,
                            ),
                            prefixIcon: const Icon(Icons.scale, color: SoftErpTheme.accent),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          controller: TextEditingController(text: weight.toString())..selection = TextSelection.collapsed(offset: weight.toString().length),
                          onChanged: (v) {
                            weight = double.tryParse(v) ?? 0.0;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                          backgroundColor: SoftErpTheme.accent.withOpacity(0.1),
                          foregroundColor: SoftErpTheme.accent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          elevation: 0,
                        ),
                        onPressed: () {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('Fetching weight...'), behavior: SnackBarBehavior.floating),
                          );
                        },
                        icon: const Icon(Icons.bluetooth_connected_rounded, size: 20),
                        label: const Text('Fetch\nWeight', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, height: 1.1, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 60.0,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SoftErpTheme.accent,
                        foregroundColor: Colors.white,
                        elevation: 4,
                        shadowColor: SoftErpTheme.accent.withOpacity(0.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        onConfirm(qty.toString(), weight.toString());
                      },
                      child: const Text(
                        'Confirm Details', 
                        style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold, letterSpacing: 1.1)
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      }
    );
  }

  Widget _buildCounterButton(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))
          ]
        ),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }

  Future<ItemDefinition?> _selectProduct() async {
    final itemsProvider = context.read<ItemsProvider>();
    // In the Purchase (reception) flow only purchase-available items are offered.
    final availableItems = widget.lockedType == ChallanType.reception
        ? itemsProvider.items
            .where((i) => i.availableForPurchase && !i.isArchived)
            .toList(growable: false)
        : itemsProvider.items;
    if (availableItems.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No items available.')));
      return null;
    }

    return await showModalBottomSheet<ItemDefinition>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          margin: EdgeInsets.only(top: MediaQuery.of(ctx).padding.top + 40),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 16),
              Center(
                child: Container(
                  width: 50,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24.0),
                child: Text(
                  'Select Product', 
                  style: TextStyle(
                    fontSize: 24.0, 
                    fontWeight: FontWeight.w900,
                    color: SoftErpTheme.textPrimary,
                  )
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: availableItems.length,
                  itemBuilder: (ctx, i) {
                    final item = availableItems[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: SoftErpTheme.shellSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: SoftErpTheme.accent.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.inventory_2_rounded, color: SoftErpTheme.accent),
                        ),
                        title: Text(
                          item.displayName, 
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0)
                        ),
                        subtitle: Text('ID: ${item.id}', style: const TextStyle(color: SoftErpTheme.textSecondary)),
                        trailing: const Icon(Icons.chevron_right, color: SoftErpTheme.textSecondary),
                        onTap: () => Navigator.of(ctx).pop(item),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      }
    );
  }

  void _addItem() async {
    final selectedItem = await _selectProduct();
    if (selectedItem == null || !mounted) return;

    // Items with no variation properties skip the picker (it can never resolve
    // a leaf, so its Confirm button would stay disabled).
    VariationPathSelectionResult? variationResult;
    if (selectedItem.topLevelProperties.isNotEmpty) {
      variationResult = await showDialog<VariationPathSelectionResult>(
        context: context,
        builder: (ctx) {
          return Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            insetPadding: const EdgeInsets.all(24),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.7,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: VariationPathSelectorDialog(
                  item: selectedItem,
                  initialRootPropertyId: null,
                  initialValueNodeIds: const [],
                  useTilesForValues: false, // desktop dropdown on mobile: no keyboard until search is tapped
                  onCreateValue: ({required item, required propertyNodeId, required propertyLabel, required valueName}) {
                    return context.read<ItemsProvider>().appendVariationValue(
                      itemId: item.id,
                      propertyNodeId: propertyNodeId,
                      valueName: valueName,
                    );
                  },
                  isFavorite: (result) => context.read<FavoritesProvider>().isFavorite(selectedItem.id, result.valueNodeIds),
                  onFavoriteToggled: (result, isFav) {
                    final dummyItem = DeliveryChallanItem(
                      id: 0,
                      orderItemId: null,
                      productionRunId: null,
                      itemId: selectedItem.id,
                      variationLeafNodeId: result.leaf?.id ?? 0,
                      variationPathLabel: result.summaryLabel,
                      variationPathNodeIds: result.valueNodeIds,
                      particulars: selectedItem.displayName,
                      quantityPcs: '1',
                      weight: '0.0',
                      lineNo: 0,
                      hsnCode: '',
                      note: '',
                    );
                    context.read<FavoritesProvider>().toggleFavorite(dummyItem, isFav);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(isFav ? 'Variation saved to favorites' : 'Variation removed from favorites'),
                        behavior: SnackBarBehavior.floating,
                        margin: const EdgeInsets.only(top: 10, left: 10, right: 10),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        }
      );

      if (variationResult == null || !mounted) return;
    }

    _showQuantityBottomSheet(context, null, (qty, weight) {
      final newItem = DeliveryChallanItem(
        id: 0,
        orderItemId: null,
        productionRunId: null,
        itemId: selectedItem.id,
        variationLeafNodeId: variationResult?.leaf?.id ?? 0,
        variationPathLabel: variationResult?.summaryLabel ?? '',
        variationPathNodeIds: variationResult?.valueNodeIds ?? const <int>[],
        customVariationValues: variationResult?.customVariationValues ?? const <int, String>{},
        particulars: selectedItem.displayName,
        quantityPcs: qty,
        weight: weight,
        lineNo: _items.length + 1,
        hsnCode: '',
        note: '',
      );
      
      _items.add(newItem);
      _listKey.currentState?.insertItem(_items.length - 1, duration: const Duration(milliseconds: 400));
      setState(() {});
    });
  }

  void _reselectMainItem(int idx) async {
    final selectedItem = await _selectProduct();
    if (selectedItem == null || !mounted) return;

    VariationPathSelectionResult? variationResult;
    if (selectedItem.topLevelProperties.isNotEmpty) {
      variationResult = await showDialog<VariationPathSelectionResult>(
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
                item: selectedItem,
                initialRootPropertyId: null,
                initialValueNodeIds: const [],
                useTilesForValues: false, // desktop dropdown on mobile: no keyboard until search is tapped
                isFavorite: (result) => context.read<FavoritesProvider>().isFavorite(selectedItem.id, result.valueNodeIds),
                onFavoriteToggled: (result, isFav) {
                  final dummyItem = DeliveryChallanItem(
                    id: 0,
                    orderItemId: null,
                    productionRunId: null,
                    itemId: selectedItem.id,
                    variationLeafNodeId: result.leaf?.id ?? 0,
                    variationPathLabel: result.summaryLabel,
                    variationPathNodeIds: result.valueNodeIds,
                    particulars: selectedItem.displayName,
                    quantityPcs: '1',
                    weight: '0.0',
                    lineNo: 0,
                    hsnCode: '',
                    note: '',
                  );
                  context.read<FavoritesProvider>().toggleFavorite(dummyItem, isFav);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(isFav ? 'Variation saved to favorites' : 'Variation removed from favorites'),
                      behavior: SnackBarBehavior.floating,
                      margin: const EdgeInsets.only(top: 10, left: 10, right: 10),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      if (variationResult == null || !mounted) return;
    }

    final oldItem = _items[idx];
    setState(() {
      _items[idx] = DeliveryChallanItem(
        id: oldItem.id,
        orderItemId: oldItem.orderItemId,
        productionRunId: oldItem.productionRunId,
        itemId: selectedItem.id,
        variationLeafNodeId: variationResult?.leaf?.id ?? 0,
        variationPathLabel: variationResult?.summaryLabel ?? '',
        variationPathNodeIds: variationResult?.valueNodeIds ?? const <int>[],
        customVariationValues: variationResult?.customVariationValues ?? const <int, String>{},
        particulars: selectedItem.displayName,
        quantityPcs: oldItem.quantityPcs,
        weight: oldItem.weight,
        lineNo: oldItem.lineNo,
        hsnCode: oldItem.hsnCode,
        note: oldItem.note,
      );
    });
  }

  void _reselectVariation(int idx) async {
    final oldItem = _items[idx];
    final itemsProvider = context.read<ItemsProvider>();
    final selectedItem = itemsProvider.items.cast<ItemDefinition?>().firstWhere((i) => i?.id == oldItem.itemId, orElse: () => null);
    
    if (selectedItem == null || selectedItem.topLevelProperties.isEmpty) return;

    final variationResult = await showDialog<VariationPathSelectionResult>(
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
              item: selectedItem,
              initialRootPropertyId: null,
              initialValueNodeIds: oldItem.variationPathNodeIds,
              useTilesForValues: false, // desktop dropdown on mobile: no keyboard until search is tapped
              onCreateValue: ({required item, required propertyNodeId, required propertyLabel, required valueName}) {
                return context.read<ItemsProvider>().appendVariationValue(
                  itemId: item.id,
                  propertyNodeId: propertyNodeId,
                  valueName: valueName,
                );
              },
              isFavorite: (result) => context.read<FavoritesProvider>().isFavorite(selectedItem.id, result.valueNodeIds),
              onFavoriteToggled: (result, isFav) {
                final dummyItem = DeliveryChallanItem(
                  id: 0,
                  orderItemId: null,
                  productionRunId: null,
                  itemId: selectedItem.id,
                  variationLeafNodeId: result.leaf?.id ?? 0,
                  variationPathLabel: result.summaryLabel,
                  variationPathNodeIds: result.valueNodeIds,
                  particulars: selectedItem.displayName,
                  quantityPcs: '1',
                  weight: '0.0',
                  lineNo: 0,
                  hsnCode: '',
                  note: '',
                );
                context.read<FavoritesProvider>().toggleFavorite(dummyItem, isFav);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(isFav ? 'Variation saved to favorites' : 'Variation removed from favorites'),
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.only(top: 10, left: 10, right: 10),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    if (variationResult == null || !mounted) return;

    setState(() {
      _items[idx] = DeliveryChallanItem(
        id: oldItem.id,
        orderItemId: oldItem.orderItemId,
        productionRunId: oldItem.productionRunId,
        itemId: oldItem.itemId,
        variationLeafNodeId: variationResult.leaf?.id ?? 0,
        variationPathLabel: variationResult.summaryLabel,
        variationPathNodeIds: variationResult.valueNodeIds,
        customVariationValues: variationResult.customVariationValues,
        particulars: oldItem.particulars,
        quantityPcs: oldItem.quantityPcs,
        weight: oldItem.weight,
        lineNo: oldItem.lineNo,
        hsnCode: oldItem.hsnCode,
        note: oldItem.note,
      );
    });
  }

  Future<void> _submit() async {
    if (_isSaving) return; // guard against a double submit creating two challans
    if (!_formKey.currentState!.validate()) return;
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one item.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        )
      );
      return;
    }

    final genericAssets = <Map<String, dynamic>>[];
    if (_attachedImages.isNotEmpty) {
      setState(() => _isSaving = true);
      final assetService = context.read<GenericAssetService>();
      try {
        for (final img in _attachedImages) {
          final bytes = await img.readAsBytes();
          final fileExt = img.name.split('.').last;
          final contentType = 'image/$fileExt';
          
          final intent = await assetService.createUploadIntent(
            GenericAssetUploadIntentInput(
              fileName: img.name,
              contentType: contentType,
              sizeBytes: bytes.length,
              sha256: '', // Not strictly required
            )
          );
          
          // Upload to presigned URL
          await http.put(intent.uploadUrl, headers: intent.headers, body: bytes);
          
          genericAssets.add({
            'fileName': img.name,
            'contentType': contentType,
            'sizeBytes': bytes.length,
            'objectKey': intent.objectKey,
            'sha256': '',
          });
        }
      } catch (e) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload photos: $e'), backgroundColor: Colors.redAccent)
        );
        return;
      }
    }

    setState(() => _isSaving = true);
    final provider = context.read<DeliveryChallanProvider>();
    final client = _selectedClientId != null ? context.read<ClientsProvider>().clients.firstWhere((c) => c.id == _selectedClientId) : null;
    final vendor = _selectedVendorId != null ? context.read<VendorsProvider>().vendors.firstWhere((v) => v.id == _selectedVendorId) : null;

    final draft = DeliveryChallanDraftInput(
      type: _type,
      purpose: widget.initialOrderGroup != null ? ChallanPurpose.manufacturing : ChallanPurpose.trading,
      internalPurpose: widget.initialOrderGroup != null ? 'Consumption for order ${widget.initialOrderGroup!.orderNo}' : '',
      challanNo: _challanNoController.text, // User-entered or empty for auto-generate
      orderId: widget.initialOrderGroup?.items.firstOrNull?.id ?? 0,
      orderIds: widget.initialOrderGroup?.items.map((i) => i.id).toList(growable: false) ?? const [],
      vendorId: _selectedVendorId ?? 0,
      materialOwnerClientId: _selectedClientId,
      date: _challanDate,
      location: _locationController.text,
      sourceReference: '',
      notes: _notesController.text,
      maintainStocks: true,
      customerName: client?.name ?? '',
      customerGstin: client?.gstNumber ?? '',
      vendorName: vendor?.name ?? '',
      vendorGstin: vendor?.gstNumber ?? '',
      items: _items,
      genericAssets: genericAssets,
    );

    final result = await provider.createChallan(draft);
    if (!mounted) return;

    if (result == null) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage ?? 'Failed to create challan'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        )
      );
      return;
    }

    // Mobile submits an issued challan, not a draft: issue it right after
    // creation. If the backend rejects the issue (e.g. a delivery challan with
    // no linked order / customer), the challan is preserved as a draft and the
    // user is told why so it can be completed from the desktop — nothing is lost.
    final issued = await provider.issueChallan(result.id);
    if (!mounted) return;
    setState(() => _isSaving = false);

    if (issued != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Text('Issued Challan: ${issued.challanNo}', style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        )
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved draft ${result.challanNo} — could not issue: '
            '${provider.errorMessage ?? 'unknown error'}. Issue it from the desktop.',
          ),
          backgroundColor: Colors.orange.shade800,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        )
      );
    }

    // Review flow (Purchase): the challan is saved (issued or draft), so return
    // to the browse flow with `true` and let it clear the collected lines.
    if (widget.lockedType != null) {
      if (mounted) Navigator.of(context).pop(true);
      return;
    }

    // Standalone flow: the challan is saved either way — clear for next entry.
    setState(() {
      final count = _items.length;
      _items.clear();
      for (var i = 0; i < count; i++) {
        _listKey.currentState?.removeItem(0, (context, animation) => const SizedBox.shrink());
      }
      _notesController.clear();
    });
  }

  Future<void> _discardChallan() async {
    if (_isSaving) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete challan?', style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text('This challan and everything you added will be cleared.'),
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
    if (ok != true || !mounted) return;
    if (widget.lockedType != null) {
      // Purchase flow: exit all the way back to the Purchase/Sale start,
      // discarding the browse screens (and their collected cart) with it.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      setState(() {
        final count = _items.length;
        _items.clear();
        for (var i = 0; i < count; i++) {
          _listKey.currentState?.removeItem(0, (context, animation) => const SizedBox.shrink());
        }
        _notesController.clear();
      });
    }
  }

  int get _totalQty {
    return _items.fold(0, (t, i) => t + (int.tryParse(i.quantityPcs) ?? 0));
  }

  InputDecoration _glassInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: SoftErpTheme.textSecondary, fontWeight: FontWeight.w600),
      prefixIcon: Icon(icon, color: SoftErpTheme.accent),
      filled: true,
      fillColor: SoftErpTheme.shellSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: SoftErpTheme.accent, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
    );
  }

  void _handleBarcodeTap(DeliveryChallanItem item, int idx) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PieceBarcodeBottomSheet(
        item: item,
        orderOrigin: widget.initialOrderGroup?.toString() ?? '',
      ),
    );
  }

  void _removeItem(int idx) {
    if (idx < 0 || idx >= _items.length) return;
    final removedItem = _items.removeAt(idx);
    _listKey.currentState?.removeItem(
      idx, 
      (context, anim) => _buildItemTile(removedItem, idx, anim),
      duration: const Duration(milliseconds: 300)
    );
    setState(() {});
  }

  Widget _buildItemTile(DeliveryChallanItem item, int idx, Animation<double> animation) {
    return SizeTransition(
      sizeFactor: animation,
      child: FadeTransition(
        opacity: animation,
        child: Dismissible(
          key: ValueKey('${item.itemId}_${item.variationLeafNodeId}_${idx}_${DateTime.now().millisecondsSinceEpoch}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            decoration: BoxDecoration(
              color: Colors.red.shade400,
              borderRadius: BorderRadius.circular(20),
            ),
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: const Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 32),
          ),
          onDismissed: (_) => _removeItem(idx),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 4))
              ]
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  _showQuantityBottomSheet(context, item, (qty, weight) {
                    setState(() {
                      _items[idx] = DeliveryChallanItem(
                        id: item.id,
                        orderItemId: item.orderItemId,
                        productionRunId: item.productionRunId,
                        itemId: item.itemId,
                        variationLeafNodeId: item.variationLeafNodeId,
                        variationPathLabel: item.variationPathLabel,
                        variationPathNodeIds: item.variationPathNodeIds,
                        customVariationValues: item.customVariationValues,
                        particulars: item.particulars,
                        quantityPcs: qty,
                        weight: weight,
                        lineNo: item.lineNo,
                        hsnCode: item.hsnCode,
                        note: item.note,
                      );
                    });
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF5E49E6), Color(0xFF8B5CF6)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.inventory_2_rounded, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InkWell(
                              onTap: () => _reselectMainItem(idx),
                              child: Text(
                                item.particulars, 
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800, 
                                  fontSize: 16.0, 
                                  color: SoftErpTheme.accent,
                                  decoration: TextDecoration.underline,
                                  decorationColor: SoftErpTheme.accent,
                                )
                              ),
                            ),
                            const SizedBox(height: 4),
                            InkWell(
                              onTap: () => _reselectVariation(idx),
                              child: Text(
                                item.variationPathLabel.isEmpty 
                                    ? item.particulars
                                    : '${item.particulars} - ${item.variationPathLabel}', 
                                style: const TextStyle(
                                  color: SoftErpTheme.accent, 
                                  fontSize: 13.0,
                                  decoration: TextDecoration.underline,
                                  decorationColor: SoftErpTheme.accent,
                                )
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10)),
                                  child: Text('Qty: ${item.quantityPcs}', style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold, fontSize: 13)),
                                ),
                                const SizedBox(width: 8),
                                if (item.weight != '0' && item.weight != '0.0')
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10)),
                                    child: Text('Wt: ${item.weight} kg', style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold, fontSize: 13)),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.qr_code_2_rounded, color: SoftErpTheme.accent, size: 24),
                            onPressed: () => _handleBarcodeTap(item, idx),
                            tooltip: 'Print Barcode Tags',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 24),
                            onPressed: () => _removeItem(idx),
                            tooltip: 'Delete Item',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clients = context.watch<ClientsProvider>().clients;
    final vendors = context.watch<VendorsProvider>().vendors;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      floatingActionButton: AnimatedBuilder(
        animation: _fabAnimController,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: SoftErpTheme.accent.withOpacity(0.3 + (_fabAnimController.value * 0.3)),
                  blurRadius: 15 + (_fabAnimController.value * 10),
                  spreadRadius: 2 + (_fabAnimController.value * 4),
                )
              ]
            ),
            child: FloatingActionButton.extended(
              onPressed: _isSaving ? null : () {
                if (widget.lockedType != null) {
                  Navigator.of(context).pop(_items);
                } else {
                  _addItem();
                }
              },
              backgroundColor: SoftErpTheme.accent,
              foregroundColor: Colors.white,
              elevation: 0,
              icon: Icon(widget.lockedType != null ? Icons.add_shopping_cart_rounded : Icons.add_rounded, size: 24),
              label: Text(widget.lockedType != null ? 'Add More Items' : 'Add Item', style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5)),
            ),
          );
        }
      ),
      body: _isSaving 
        ? const Center(child: CircularProgressIndicator(color: SoftErpTheme.accent))
        : Form(
            key: _formKey,
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: 180.0,
                  floating: false,
                  pinned: true,
                  backgroundColor: SoftErpTheme.accent,
                  flexibleSpace: FlexibleSpaceBar(
                    titlePadding: const EdgeInsets.only(left: 24, bottom: 16),
                    title: const Text(
                      'Create Challan',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    background: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF3B2DB0), Color(0xFF7C3AED)],
                          begin: Alignment.bottomLeft,
                          end: Alignment.topRight,
                        ),
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            right: -50, top: -50,
                            child: CircleAvatar(radius: 100, backgroundColor: Colors.white.withOpacity(0.05)),
                          ),
                          Positioned(
                            left: -30, bottom: -20,
                            child: CircleAvatar(radius: 60, backgroundColor: Colors.white.withOpacity(0.05)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.only(right: 12.0),
                      child: Center(
                        child: IconButton(
                          icon: const Icon(Icons.camera_alt_rounded, color: SoftErpTheme.textPrimary),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            shadowColor: Colors.black.withOpacity(0.1),
                            elevation: 4,
                          ),
                          onPressed: _pickImage,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 24.0),
                      child: Center(
                        child: InkWell(
                          onTap: _discardChallan,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD64545),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)]
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.delete_outline_rounded, color: Colors.white, size: 18),
                                SizedBox(width: 8),
                                Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_items.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 16.0),
                        child: Center(
                          child: InkWell(
                            onTap: _submit,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)]
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.check_circle_rounded, color: SoftErpTheme.accent, size: 18),
                                  SizedBox(width: 8),
                                  Text('Submit', style: TextStyle(color: SoftErpTheme.accent, fontWeight: FontWeight.w800)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Party Details Glass Card
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 10))
                            ]
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: SoftErpTheme.accent.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.business_center_rounded, color: SoftErpTheme.accent, size: 20),
                                  ),
                                  const SizedBox(width: 16),
                                  const Text('Party Details', style: TextStyle(fontSize: 20.0, fontWeight: FontWeight.w900, color: SoftErpTheme.textPrimary)),
                                ],
                              ),
                              const SizedBox(height: 24),
                              if (widget.lockedType == null) ...[
                                DropdownButtonFormField<ChallanType>(
                                  value: _type,
                                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: SoftErpTheme.accent),
                                  decoration: _glassInputDecoration('Document Type', Icons.document_scanner_rounded),
                                  items: const [
                                    DropdownMenuItem(value: ChallanType.delivery, child: Text('DELIVERY CHALLAN', style: TextStyle(fontWeight: FontWeight.w700))),
                                    DropdownMenuItem(value: ChallanType.reception, child: Text('RECEPTION CHALLAN', style: TextStyle(fontWeight: FontWeight.w700))),
                                  ],
                                  onChanged: (v) { if (v != null) setState(() => _type = v); },
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (_type == ChallanType.delivery)
                                DropdownButtonFormField<int>(
                                  value: _selectedClientId,
                                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: SoftErpTheme.accent),
                                  decoration: _glassInputDecoration('Select Client', Icons.person_rounded),
                                  items: clients.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)))).toList(),
                                  onChanged: (v) => setState(() => _selectedClientId = v),
                                  validator: (v) => v == null ? 'Client is required' : null,
                                )
                              else if (_type == ChallanType.internal)
                                TextFormField(
                                  initialValue: widget.initialOrderGroup?.orderNo ?? 'Internal Use',
                                  readOnly: true,
                                  decoration: _glassInputDecoration('Order No.', Icons.assignment_rounded),
                                )
                              else
                                DropdownButtonFormField<int>(
                                  value: _selectedVendorId,
                                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: SoftErpTheme.accent),
                                  decoration: _glassInputDecoration('Select Supplier', Icons.storefront_rounded),
                                  items: vendors.map((v) => DropdownMenuItem(value: v.id, child: Text(v.name, style: const TextStyle(fontWeight: FontWeight.w600)))).toList(),
                                  onChanged: (v) => setState(() => _selectedVendorId = v),
                                  validator: (v) => v == null ? 'Supplier is required' : null,
                                ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _challanNoController,
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                      decoration: _glassInputDecoration('Challan No. (Auto)', Icons.numbers_rounded),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: InkWell(
                                      onTap: () async {
                                        final picked = await showDatePicker(
                                          context: context,
                                          initialDate: _challanDate,
                                          firstDate: DateTime(2000),
                                          lastDate: DateTime(2100),
                                        );
                                        if (picked != null) {
                                          setState(() => _challanDate = picked);
                                        }
                                      },
                                      child: InputDecorator(
                                        decoration: _glassInputDecoration('Date', Icons.calendar_today_rounded),
                                        child: Text(
                                          '${_challanDate.day}/${_challanDate.month}/${_challanDate.year}',
                                          style: const TextStyle(fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _locationController,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                                decoration: _glassInputDecoration('Delivery Location', Icons.location_on_rounded),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 32),
                        
                        // Items Header
                        if (_items.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16.0, left: 8, right: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Items (${_items.length})', style: const TextStyle(fontSize: 20.0, fontWeight: FontWeight.w900, color: SoftErpTheme.textPrimary)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: SoftErpTheme.accent,
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [BoxShadow(color: SoftErpTheme.accent.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))]
                                  ),
                                  child: Text('Total Qty: $_totalQty', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ),
                          
                        // Items List (Animated)
                        AnimatedList(
                          key: _listKey,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          initialItemCount: _items.length,
                          itemBuilder: (context, index, animation) {
                            return _buildItemTile(_items[index], index, animation);
                          },
                        ),
                        
                        if (_items.isEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 60),
                            alignment: Alignment.center,
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 30)]
                                  ),
                                  child: Icon(Icons.add_shopping_cart_rounded, size: 64, color: Colors.grey.shade300),
                                ),
                                const SizedBox(height: 24),
                                const Text('Cart is empty', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.grey)),
                                const SizedBox(height: 8),
                                Text('Tap the plus button to add items', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),

                        const SizedBox(height: 24),
                        
                        if (_attachedImages.isNotEmpty) ...[
                          const Text('Photos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: SoftErpTheme.textPrimary)),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 100,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _attachedImages.length,
                              itemBuilder: (context, index) {
                                final img = _attachedImages[index];
                                return Stack(
                                  children: [
                                    Container(
                                      margin: const EdgeInsets.only(right: 12),
                                      width: 100,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        image: DecorationImage(image: FileImage(File(img.path)), fit: BoxFit.cover),
                                      ),
                                    ),
                                    Positioned(
                                      top: 4, right: 16,
                                      child: InkWell(
                                        onTap: () => setState(() => _attachedImages.removeAt(index)),
                                        child: const CircleAvatar(radius: 12, backgroundColor: Colors.red, child: Icon(Icons.close, size: 16, color: Colors.white)),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],

                        // Additional Notes Card
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 10))
                            ]
                          ),
                          child: TextFormField(
                            controller: _notesController,
                            maxLines: 3,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                            decoration: const InputDecoration(
                              labelText: 'Additional Notes (Optional)',
                              labelStyle: TextStyle(color: SoftErpTheme.textSecondary, fontWeight: FontWeight.w600),
                              alignLabelWithHint: true,
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 100), // Padding for FAB
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
    );
  }
}

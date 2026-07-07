import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/features/delivery_challans/domain/delivery_challan.dart';
import 'package:core_erp/features/delivery_challans/data/delivery_challan_repository.dart';
import 'package:core_erp/features/delivery_challans/presentation/providers/delivery_challan_provider.dart';
import 'package:core_erp/features/clients/presentation/providers/clients_provider.dart';
import 'package:core_erp/features/vendors/presentation/providers/vendors_provider.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/widgets/variation_path_selector_dialog.dart';

class ChallanMobileEditorScreen extends StatefulWidget {
  const ChallanMobileEditorScreen({super.key});

  @override
  State<ChallanMobileEditorScreen> createState() => _ChallanMobileEditorScreenState();
}

class _ChallanMobileEditorScreenState extends State<ChallanMobileEditorScreen> {
  ChallanType _type = ChallanType.delivery;
  final _formKey = GlobalKey<FormState>();
  
  int? _selectedClientId;
  int? _selectedVendorId;
  final _locationController = TextEditingController(text: 'MAIN');
  final _notesController = TextEditingController();
  
  final List<DeliveryChallanItem> _items = [];
  bool _isSaving = false;

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
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxWidth: isTablet ? 500.0 : double.infinity,
      ),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final isTabletModal = MediaQuery.of(ctx).size.width >= 600;
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                left: 24, right: 24, top: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    existingItem == null ? 'Set Quantity' : 'Edit Quantity',
                    style: TextStyle(
                      fontSize: isTabletModal ? 24.0 : 20.0, 
                      fontWeight: FontWeight.bold
                    ),
                  ),
                  SizedBox(height: isTabletModal ? 32.0 : 24.0),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Quantity (Pcs)', 
                        style: TextStyle(fontSize: isTabletModal ? 18.0 : 16.0)
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                            iconSize: isTabletModal ? 36.0 : 28.0,
                            onPressed: qty > 1 ? () => setModalState(() => qty--) : null,
                          ),
                          Text(
                            '$qty', 
                            style: TextStyle(
                              fontSize: isTabletModal ? 24.0 : 18.0, 
                              fontWeight: FontWeight.bold
                            )
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                            iconSize: isTabletModal ? 36.0 : 28.0,
                            onPressed: () => setModalState(() => qty++),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: isTabletModal ? 24.0 : 16.0),
                  TextField(
                    style: TextStyle(fontSize: isTabletModal ? 18.0 : 14.0),
                    decoration: InputDecoration(
                      labelText: 'Weight (kg)',
                      labelStyle: TextStyle(fontSize: isTabletModal ? 18.0 : 14.0),
                      border: const OutlineInputBorder(),
                      prefixIcon: Icon(Icons.scale, size: isTabletModal ? 28.0 : 24.0),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: isTabletModal ? 20.0 : 12.0,
                        vertical: isTabletModal ? 20.0 : 12.0,
                      ),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    controller: TextEditingController(text: weight.toString())..selection = TextSelection.collapsed(offset: weight.toString().length),
                    onChanged: (v) {
                      weight = double.tryParse(v) ?? 0.0;
                    },
                  ),
                  SizedBox(height: isTabletModal ? 32.0 : 24.0),
                  SizedBox(
                    width: double.infinity,
                    height: isTabletModal ? 60.0 : 50.0,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        onConfirm(qty.toString(), weight.toString());
                      },
                      child: Text(
                        'Confirm', 
                        style: TextStyle(fontSize: isTabletModal ? 18.0 : 16.0)
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      }
    );
  }

  void _addItem() async {
    final itemsProvider = context.read<ItemsProvider>();
    if (itemsProvider.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No items loaded.')));
      return;
    }

    final isTablet = MediaQuery.of(context).size.width >= 600;

    // 1. Pick Item using BottomSheet
    final selectedItem = await showModalBottomSheet<ItemDefinition>(
      context: context,
      constraints: BoxConstraints(
        maxWidth: isTablet ? 500.0 : double.infinity,
      ),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final isTabletModal = MediaQuery.of(ctx).size.width >= 600;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Select Item', 
                style: TextStyle(
                  fontSize: isTabletModal ? 24.0 : 20.0, 
                  fontWeight: FontWeight.bold
                )
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: itemsProvider.items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final item = itemsProvider.items[i];
                  return ListTile(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: isTabletModal ? 24.0 : 16.0, 
                      vertical: isTabletModal ? 8.0 : 4.0
                    ),
                    leading: CircleAvatar(
                      radius: isTabletModal ? 28.0 : 20.0,
                      backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                      child: Icon(Icons.inventory_2, size: isTabletModal ? 28.0 : 20.0),
                    ),
                    title: Text(
                      item.displayName, 
                      style: TextStyle(
                        fontWeight: FontWeight.w500, 
                        fontSize: isTabletModal ? 18.0 : 15.0
                      )
                    ),
                    subtitle: Text(
                      'ID: ${item.id}', 
                      style: TextStyle(fontSize: isTabletModal ? 14.0 : 12.0)
                    ),
                    onTap: () => Navigator.of(ctx).pop(item),
                  );
                },
              ),
            ),
          ],
        );
      }
    );

    if (selectedItem == null || !mounted) return;

    // 2. Pick Variation
    final variationResult = await showDialog<VariationPathSelectionResult>(
      context: context,
      builder: (ctx) {
        final isTabletDialog = MediaQuery.of(ctx).size.width >= 600;
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          insetPadding: EdgeInsets.all(isTabletDialog ? 32.0 : 16.0),
          child: SizedBox(
            width: isTabletDialog ? 700.0 : 500.0,
            height: MediaQuery.of(context).size.height * (isTabletDialog ? 0.75 : 0.8),
            child: VariationPathSelectorDialog(
              item: selectedItem,
              initialRootPropertyId: null,
              initialValueNodeIds: const [],
            ),
          ),
        );
      }
    );

    if (variationResult == null || !mounted) return;

    // 3. Set Quantity & Weight
    _showQuantityBottomSheet(context, null, (qty, weight) {
      setState(() {
        _items.add(
          DeliveryChallanItem(
            id: 0,
            orderItemId: null,
            productionRunId: null,
            itemId: selectedItem.id,
            variationLeafNodeId: variationResult.leaf?.id ?? 0,
            variationPathLabel: variationResult.leaf?.displayName ?? '',
            variationPathNodeIds: variationResult.valueNodeIds,
            customVariationValues: variationResult.customVariationValues,
            particulars: selectedItem.displayName,
            quantityPcs: qty,
            weight: weight,
            lineNo: _items.length + 1,
            hsnCode: '',
            note: '',
          )
        );
      });
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one item.')));
      return;
    }

    setState(() => _isSaving = true);
    final provider = context.read<DeliveryChallanProvider>();
    final client = _selectedClientId != null ? context.read<ClientsProvider>().clients.firstWhere((c) => c.id == _selectedClientId) : null;
    final vendor = _selectedVendorId != null ? context.read<VendorsProvider>().vendors.firstWhere((v) => v.id == _selectedVendorId) : null;

    final draft = DeliveryChallanDraftInput(
      type: _type,
      purpose: ChallanPurpose.trading,
      challanNo: '', // Auto-generated
      orderId: 0,
      orderIds: [],
      vendorId: _selectedVendorId ?? 0,
      materialOwnerClientId: _selectedClientId,
      date: DateTime.now(),
      location: _locationController.text,
      sourceReference: '',
      notes: _notesController.text,
      maintainStocks: true,
      customerName: client?.name ?? '',
      customerGstin: client?.gstNumber ?? '',
      vendorName: vendor?.name ?? '',
      vendorGstin: vendor?.gstNumber ?? '',
      items: _items,
    );

    final result = await provider.createChallan(draft);
    if (mounted) {
      setState(() => _isSaving = false);
      if (result != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ Created Challan: ${result.challanNo}')));
        setState(() {
          _items.clear();
          _notesController.clear();
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(provider.errorMessage ?? 'Failed to create challan')));
      }
    }
  }

  int get _totalQty {
    int t = 0;
    for (var i in _items) {
      t += int.tryParse(i.quantityPcs) ?? 0;
    }
    return t;
  }

  InputDecoration _responsiveDecoration({
    required BuildContext context,
    required String label,
    required IconData prefixIcon,
    required bool isTablet,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(fontSize: isTablet ? 18.0 : 14.0),
      prefixIcon: Icon(prefixIcon, size: isTablet ? 28.0 : 24.0),
      contentPadding: EdgeInsets.symmetric(
        horizontal: isTablet ? 20.0 : 12.0,
        vertical: isTablet ? 20.0 : 12.0,
      ),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clients = context.watch<ClientsProvider>().clients;
    final vendors = context.watch<VendorsProvider>().vendors;
    final isTablet = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(
          'New Challan', 
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: isTablet ? 24.0 : 20.0,
          )
        ),
        centerTitle: true,
        elevation: 0,
        actions: [
          if (_items.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(right: isTablet ? 16.0 : 8.0),
              child: _isSaving
                ? const SizedBox.shrink()
                : TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: SoftErpTheme.accent,
                      textStyle: TextStyle(
                        fontSize: isTablet ? 18.0 : 14.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    icon: Icon(Icons.check, size: isTablet ? 24.0 : 20.0),
                    label: const Text('Submit'),
                    onPressed: _submit,
                  ),
            )
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addItem,
        icon: Icon(Icons.add, size: isTablet ? 28.0 : 24.0),
        label: Text(
          'Add Item', 
          style: TextStyle(
            fontSize: isTablet ? 18.0 : 14.0, 
            fontWeight: FontWeight.bold
          )
        ),
        extendedPadding: EdgeInsets.symmetric(
          horizontal: isTablet ? 24.0 : 16.0, 
        ),
      ),
      body: _isSaving 
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _formKey,
            child: Center(
              child: Container(
                constraints: BoxConstraints(maxWidth: isTablet ? 720.0 : double.infinity),
                child: ListView(
                  padding: EdgeInsets.only(
                    bottom: isTablet ? 120.0 : 100.0,
                    left: isTablet ? 24.0 : 0,
                    right: isTablet ? 24.0 : 0,
                  ),
                  children: [
                    // 1. Details Card
                    Card(
                      margin: EdgeInsets.all(isTablet ? 8.0 : 16.0),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 2,
                      child: Padding(
                        padding: EdgeInsets.all(isTablet ? 24.0 : 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Party Details', 
                              style: TextStyle(
                                fontSize: isTablet ? 22.0 : 18.0, 
                                fontWeight: FontWeight.bold, 
                                color: Colors.black87
                              )
                            ),
                            SizedBox(height: isTablet ? 24.0 : 16.0),
                            DropdownButtonFormField<ChallanType>(
                              value: _type,
                              style: TextStyle(
                                fontSize: isTablet ? 18.0 : 15.0,
                                color: Colors.black87,
                              ),
                              decoration: _responsiveDecoration(
                                context: context, 
                                label: 'Type', 
                                prefixIcon: Icons.local_shipping_outlined, 
                                isTablet: isTablet
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: ChallanType.delivery, 
                                  child: Text('DELIVERY', style: TextStyle(fontSize: isTablet ? 18.0 : 15.0))
                                ),
                                DropdownMenuItem(
                                  value: ChallanType.reception, 
                                  child: Text('RECEPTION', style: TextStyle(fontSize: isTablet ? 18.0 : 15.0))
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) setState(() => _type = v);
                              },
                            ),
                            SizedBox(height: isTablet ? 24.0 : 16.0),
                            if (_type == ChallanType.delivery)
                              DropdownButtonFormField<int>(
                                value: _selectedClientId,
                                style: TextStyle(
                                  fontSize: isTablet ? 18.0 : 15.0,
                                  color: Colors.black87,
                                ),
                                decoration: _responsiveDecoration(
                                  context: context, 
                                  label: 'Client', 
                                  prefixIcon: Icons.person_outline, 
                                  isTablet: isTablet
                                ),
                                items: clients.map((c) => DropdownMenuItem(
                                  value: c.id, 
                                  child: Text(c.name, style: TextStyle(fontSize: isTablet ? 18.0 : 15.0))
                                )).toList(),
                                onChanged: (v) => setState(() => _selectedClientId = v),
                                validator: (v) => v == null ? 'Select Client' : null,
                              )
                            else
                              DropdownButtonFormField<int>(
                                value: _selectedVendorId,
                                style: TextStyle(
                                  fontSize: isTablet ? 18.0 : 15.0,
                                  color: Colors.black87,
                                ),
                                decoration: _responsiveDecoration(
                                  context: context, 
                                  label: 'Vendor', 
                                  prefixIcon: Icons.business_outlined, 
                                  isTablet: isTablet
                                ),
                                items: vendors.map((v) => DropdownMenuItem(
                                  value: v.id, 
                                  child: Text(v.name, style: TextStyle(fontSize: isTablet ? 18.0 : 15.0))
                                )).toList(),
                                onChanged: (v) => setState(() => _selectedVendorId = v),
                                validator: (v) => v == null ? 'Select Vendor' : null,
                              ),
                            SizedBox(height: isTablet ? 24.0 : 16.0),
                            TextFormField(
                              controller: _locationController,
                              style: TextStyle(fontSize: isTablet ? 18.0 : 15.0),
                              decoration: _responsiveDecoration(
                                context: context, 
                                label: 'Location', 
                                prefixIcon: Icons.location_on_outlined, 
                                isTablet: isTablet
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 2. Items List
                    if (_items.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isTablet ? 12.0 : 20.0, 
                          vertical: isTablet ? 16.0 : 8.0
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Added Items (${_items.length})', 
                              style: TextStyle(
                                fontSize: isTablet ? 18.0 : 16.0, 
                                fontWeight: FontWeight.bold, 
                                color: Colors.black54
                              )
                            ),
                            Text(
                              'Total Qty: $_totalQty', 
                              style: TextStyle(
                                fontSize: isTablet ? 18.0 : 16.0, 
                                fontWeight: FontWeight.bold, 
                                color: Colors.blue
                              )
                            ),
                          ],
                        ),
                      ),

                    if (_items.isEmpty)
                      Padding(
                        padding: EdgeInsets.all(isTablet ? 48.0 : 32.0),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.inventory_2_outlined, size: isTablet ? 96.0 : 64.0, color: Colors.grey[400]),
                              SizedBox(height: isTablet ? 24.0 : 16.0),
                              Text(
                                'No items added yet', 
                                style: TextStyle(
                                  color: Colors.grey[600], 
                                  fontSize: isTablet ? 18.0 : 16.0
                                )
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Tap the + button to add items', 
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: isTablet ? 15.0 : 14.0
                                )
                              ),
                            ],
                          ),
                        ),
                      ),

                    ..._items.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final item = entry.value;
                      return Dismissible(
                        key: ValueKey('${item.itemId}_${item.variationLeafNodeId}_$idx'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          color: Colors.red,
                          margin: EdgeInsets.symmetric(
                            horizontal: isTablet ? 8.0 : 16.0, 
                            vertical: 4
                          ),
                          child: Icon(Icons.delete, color: Colors.white, size: isTablet ? 28.0 : 24.0),
                        ),
                        onDismissed: (_) {
                          setState(() => _items.removeAt(idx));
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('${item.particulars} removed'),
                            duration: const Duration(seconds: 2),
                          ));
                        },
                        child: Card(
                          margin: EdgeInsets.symmetric(
                            horizontal: isTablet ? 8.0 : 16.0, 
                            vertical: isTablet ? 8.0 : 6.0
                          ),
                          elevation: 1,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            contentPadding: EdgeInsets.all(isTablet ? 18.0 : 12.0),
                            leading: CircleAvatar(
                              radius: isTablet ? 28.0 : 20.0,
                              backgroundColor: Colors.blue.withValues(alpha: 0.1),
                              child: Icon(Icons.category, color: Colors.blue, size: isTablet ? 28.0 : 20.0),
                            ),
                            title: Text(
                              item.particulars, 
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: isTablet ? 18.0 : 15.0
                              )
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Variation: ${item.variationPathLabel}', 
                                    style: TextStyle(
                                      color: Colors.grey[700],
                                      fontSize: isTablet ? 15.0 : 13.0
                                    )
                                  ),
                                  SizedBox(height: isTablet ? 8.0 : 4.0),
                                  Row(
                                    children: [
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: isTablet ? 12.0 : 8.0, 
                                          vertical: isTablet ? 6.0 : 4.0
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withValues(alpha: 0.1), 
                                          borderRadius: BorderRadius.circular(8)
                                        ),
                                        child: Text(
                                          'Qty: ${item.quantityPcs}', 
                                          style: TextStyle(
                                            color: Colors.green, 
                                            fontWeight: FontWeight.bold,
                                            fontSize: isTablet ? 15.0 : 13.0
                                          )
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (item.weight != '0' && item.weight != '0.0')
                                        Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: isTablet ? 12.0 : 8.0, 
                                            vertical: isTablet ? 6.0 : 4.0
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.withValues(alpha: 0.1), 
                                            borderRadius: BorderRadius.circular(8)
                                          ),
                                          child: Text(
                                            'Wt: ${item.weight} kg', 
                                            style: TextStyle(
                                              color: Colors.orange, 
                                              fontWeight: FontWeight.bold,
                                              fontSize: isTablet ? 15.0 : 13.0
                                            )
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            onTap: () {
                              // Edit existing item
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
                          ),
                        ),
                      );
                    }),

                    // 3. Notes Card
                    Card(
                      margin: EdgeInsets.all(isTablet ? 8.0 : 16.0),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 2,
                      child: Padding(
                        padding: EdgeInsets.all(isTablet ? 20.0 : 16.0),
                        child: TextFormField(
                          controller: _notesController,
                          style: TextStyle(fontSize: isTablet ? 18.0 : 14.0),
                          decoration: InputDecoration(
                            labelText: 'Additional Notes',
                            labelStyle: TextStyle(fontSize: isTablet ? 18.0 : 14.0),
                            prefixIcon: Icon(Icons.note_alt_outlined, size: isTablet ? 28.0 : 24.0),
                            border: InputBorder.none,
                          ),
                          maxLines: 3,
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
    );
  }
}

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
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
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
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Quantity (Pcs)', style: TextStyle(fontSize: 16)),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                            onPressed: qty > 1 ? () => setModalState(() => qty--) : null,
                          ),
                          Text('$qty', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                            onPressed: () => setModalState(() => qty++),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Weight (kg)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.scale),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    controller: TextEditingController(text: weight.toString())..selection = TextSelection.collapsed(offset: weight.toString().length),
                    onChanged: (v) {
                      weight = double.tryParse(v) ?? 0.0;
                    },
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      onPressed: () {
                        Navigator.pop(ctx);
                        onConfirm(qty.toString(), weight.toString());
                      },
                      child: const Text('Confirm', style: TextStyle(fontSize: 16)),
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

    // 1. Pick Item using BottomSheet
    final selectedItem = await showModalBottomSheet<ItemDefinition>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('Select Item', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: itemsProvider.items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final item = itemsProvider.items[i];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                      child: const Icon(Icons.inventory_2),
                    ),
                    title: Text(item.displayName, style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Text('ID: ${item.id}'),
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
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 600,
          height: MediaQuery.of(context).size.height * 0.8,
          child: VariationPathSelectorDialog(
            item: selectedItem,
            initialRootPropertyId: null,
            initialValueNodeIds: const [],
          ),
        ),
      ),
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

  @override
  Widget build(BuildContext context) {
    final clients = context.watch<ClientsProvider>().clients;
    final vendors = context.watch<VendorsProvider>().vendors;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('New Challan', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _isSaving ? null : _submit,
              tooltip: 'Submit',
            )
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addItem,
        icon: const Icon(Icons.add),
        label: const Text('Add Item'),
      ),
      body: _isSaving 
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 100), // Space for FAB
              children: [
                // 1. Details Card
                Card(
                  margin: const EdgeInsets.all(16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Party Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<ChallanType>(
                          value: _type,
                          decoration: const InputDecoration(
                            labelText: 'Type',
                            prefixIcon: Icon(Icons.local_shipping_outlined),
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: ChallanType.delivery, child: Text('DELIVERY')),
                            DropdownMenuItem(value: ChallanType.reception, child: Text('RECEPTION')),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _type = v);
                          },
                        ),
                        const SizedBox(height: 16),
                        if (_type == ChallanType.delivery)
                          DropdownButtonFormField<int>(
                            value: _selectedClientId,
                            decoration: const InputDecoration(
                              labelText: 'Client',
                              prefixIcon: Icon(Icons.person_outline),
                              border: OutlineInputBorder(),
                            ),
                            items: clients.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                            onChanged: (v) => setState(() => _selectedClientId = v),
                            validator: (v) => v == null ? 'Select Client' : null,
                          )
                        else
                          DropdownButtonFormField<int>(
                            value: _selectedVendorId,
                            decoration: const InputDecoration(
                              labelText: 'Vendor',
                              prefixIcon: Icon(Icons.business_outlined),
                              border: OutlineInputBorder(),
                            ),
                            items: vendors.map((v) => DropdownMenuItem(value: v.id, child: Text(v.name))).toList(),
                            onChanged: (v) => setState(() => _selectedVendorId = v),
                            validator: (v) => v == null ? 'Select Vendor' : null,
                          ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _locationController,
                          decoration: const InputDecoration(
                            labelText: 'Location',
                            prefixIcon: Icon(Icons.location_on_outlined),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 2. Items List
                if (_items.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Added Items (${_items.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black54)),
                        Text('Total Qty: $_totalQty', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue)),
                      ],
                    ),
                  ),

                if (_items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text('No items added yet', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                          const SizedBox(height: 8),
                          const Text('Tap the + button to add items', style: TextStyle(color: Colors.grey)),
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
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (_) {
                      setState(() => _items.removeAt(idx));
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('${item.particulars} removed'),
                        duration: const Duration(seconds: 2),
                      ));
                    },
                    child: Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(12),
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue.withOpacity(0.1),
                          child: const Icon(Icons.category, color: Colors.blue),
                        ),
                        title: Text(item.particulars, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Variation: ${item.variationPathLabel}', style: TextStyle(color: Colors.grey[700])),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                    child: Text('Qty: ${item.quantityPcs}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: 8),
                                  if (item.weight != '0' && item.weight != '0.0')
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                      child: Text('Wt: ${item.weight} kg', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
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
                  margin: const EdgeInsets.all(16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TextFormField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        labelText: 'Additional Notes',
                        prefixIcon: Icon(Icons.note_alt_outlined),
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
    );
  }
}

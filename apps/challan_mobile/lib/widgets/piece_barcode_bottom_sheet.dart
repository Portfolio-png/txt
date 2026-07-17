import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:core_erp/features/delivery_challans/domain/delivery_challan.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../services/network_discovery_service.dart';

class PieceBarcodeBottomSheet extends StatefulWidget {
  final DeliveryChallanItem item;
  final String orderOrigin;
  final Function(List<Map<String, dynamic>>)? onBarcodesGenerated;

  const PieceBarcodeBottomSheet({
    super.key,
    required this.item,
    required this.orderOrigin,
    this.onBarcodesGenerated,
  });

  @override
  State<PieceBarcodeBottomSheet> createState() =>
      _PieceBarcodeBottomSheetState();
}

class _PieceBarcodeBottomSheetState extends State<PieceBarcodeBottomSheet> {
  final _shortCodeController = TextEditingController();
  bool _isSavingShortCode = false;
  bool _isGenerating = false;
  late List<Map<String, dynamic>> _generatedBarcodes;

  @override
  void initState() {
    super.initState();
    _generatedBarcodes = List.from(widget.item.pieceBarcodes);
  }

  ItemDefinition? _getItemDefinition() {
    final items = context.read<ItemsProvider>().items;
    try {
      return items.firstWhere((i) => i.id == widget.item.itemId);
    } catch (e) {
      return null;
    }
  }

  Future<void> _saveShortCode(ItemDefinition itemDef) async {
    final newCode = _shortCodeController.text.trim().toUpperCase();
    if (newCode.isEmpty || newCode.length > 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Short code must be 1-5 characters.')),
      );
      return;
    }

    setState(() => _isSavingShortCode = true);
    try {
      await context.read<ItemsProvider>().updateShortCode(itemDef.id, newCode);
      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    } finally {
      if (mounted) setState(() => _isSavingShortCode = false);
    }
  }

  void _generateBarcodes(ItemDefinition itemDef) {
    final qtyDouble = double.tryParse(widget.item.quantityPcs) ?? 0;
    final qty = qtyDouble.toInt();
    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quantity must be greater than 0.')),
      );
      return;
    }

    setState(() => _isGenerating = true);
    try {
      final stagePrefix = _getStagePrefix();
      final dateStr = DateFormat('ddMMyy').format(DateTime.now());
      final orderOrigin = widget.orderOrigin.isEmpty
          ? 'UNK'
          : widget.orderOrigin.replaceAll(RegExp(r'[^A-Z0-9]'), '');

      final generated = <Map<String, dynamic>>[];
      final rng = math.Random();
      for (var i = 1; i <= qty; i++) {
        final pieceIndex = i.toString().padLeft(2, '0');
        final childCode =
            '$stagePrefix${itemDef.shortCode}-$orderOrigin-$dateStr-$pieceIndex';

        const chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
        final randomPart = List.generate(
          6,
          (index) => chars[rng.nextInt(chars.length)],
        ).join();
        final parentCode = 'PC-$dateStr-$randomPart-$pieceIndex';

        generated.add({
          'challanItemId': widget.item.id,
          'parentCode': parentCode,
          'childCode': childCode,
        });
      }

      setState(() {
        _generatedBarcodes = generated;
      });
      if (widget.onBarcodesGenerated != null) {
        widget.onBarcodesGenerated!(generated);
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error generating barcodes: $e')));
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  (Color, Color) _getColorsForStage(String stagePrefix) {
    switch (stagePrefix) {
      case 'P1':
        return (Colors.blue.shade100, Colors.blue.shade900); // Slating
      case 'P2':
        return (Colors.purple.shade100, Colors.purple.shade900); // Progressive
      case 'P3':
        return (Colors.red.shade100, Colors.red.shade900); // Cutting
      default:
        return (Colors.grey.shade200, Colors.grey.shade900); // Unknown
    }
  }

  String _getStagePrefix() {
    final lowerName = widget.item.particulars.toLowerCase();
    if (lowerName.contains('slate') || lowerName.contains('slating'))
      return 'P1';
    if (lowerName.contains('progressive')) return 'P2';
    if (lowerName.contains('cut')) return 'P3';
    return 'XX';
  }

  @override
  Widget build(BuildContext context) {
    final itemDef = _getItemDefinition();

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 24,
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Piece-Level Barcodes',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: SoftErpTheme.accent,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.item.particulars,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
          const SizedBox(height: 24),

          if (itemDef == null)
            const Center(child: Text('Item definition not found.'))
          else if (itemDef.shortCode.isEmpty)
            _buildShortCodePrompt(itemDef)
          else if (_generatedBarcodes.isEmpty)
            _buildGenerateButton(itemDef)
          else
            _buildBarcodesList(itemDef),
        ],
      ),
    );
  }

  Widget _buildGenerateButton(ItemDefinition itemDef) {
    return Center(
      child: ElevatedButton.icon(
        icon: _isGenerating
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.qr_code),
        label: const Text('Generate Parent & Child Codes'),
        onPressed: _isGenerating ? null : () => _generateBarcodes(itemDef),
        style: ElevatedButton.styleFrom(
          backgroundColor: SoftErpTheme.accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
        ),
      ),
    );
  }

  Widget _buildShortCodePrompt(ItemDefinition itemDef) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange.shade800,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Missing Short Code',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'This item does not have a short code assigned. Please enter a 2-5 letter code to generate piece barcodes.',
                style: TextStyle(color: Colors.orange.shade900),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _shortCodeController,
          textCapitalization: TextCapitalization.characters,
          maxLength: 5,
          decoration: InputDecoration(
            labelText: 'Item Short Code',
            hintText: 'e.g. CKB',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _isSavingShortCode ? null : () => _saveShortCode(itemDef),
          style: ElevatedButton.styleFrom(
            backgroundColor: SoftErpTheme.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _isSavingShortCode
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text('Save Code'),
        ),
      ],
    );
  }

  Widget _buildBarcodesList(ItemDefinition itemDef) {
    final qty = _generatedBarcodes.length;
    final stage = _getStagePrefix();
    final (bgColor, fgColor) = _getColorsForStage(stage);

    return Flexible(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Generated Tags ($qty)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                icon: const Icon(Icons.print_rounded),
                label: const Text('Print All'),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Sent to printer!')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: qty,
              itemBuilder: (context, index) {
                final barcodeData = _generatedBarcodes[index];
                final childCode = barcodeData['childCode'] as String;
                final parentCode = barcodeData['parentCode'] as String;
                final pieceIndex = (index + 1).toString().padLeft(2, '0');

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Piece $pieceIndex',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: fgColor,
                            ),
                          ),
                          Text(
                            stage,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: fgColor,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        childCode,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: fgColor,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: BarcodeWidget(
                          barcode: Barcode.code128(),
                          data: parentCode,
                          height: 60,
                          style: const TextStyle(
                            fontSize: 10,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

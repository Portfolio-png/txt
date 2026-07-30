import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:intl/intl.dart';
import 'package:core_erp/features/delivery_challans/domain/delivery_challan.dart';
import 'package:core_erp/features/delivery_challans/presentation/utils/sheet_tag_printer.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/core/theme/soft_erp_theme.dart';

/// Stage prefix (colour-coded on the tag) derived from the line's name.
String sheetBarcodeStagePrefix(String particulars) {
  final name = particulars.toLowerCase();
  if (name.contains('slate') || name.contains('slating')) return 'P1';
  if (name.contains('progressive')) return 'P2';
  if (name.contains('cut')) return 'P3';
  return 'XX';
}

/// The item's short code IS its name — sanitised (uppercase A–Z0–9, capped) for
/// the barcode payload. Falls back to `ITEM` for an empty name.
String sheetBarcodeShortCode(String itemName) {
  final cleaned = itemName.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (cleaned.isEmpty) return 'ITEM';
  return cleaned.length > 8 ? cleaned.substring(0, 8) : cleaned;
}

/// Generates one parent/child barcode per sheet. Each map carries
/// `challanItemId`, `parentCode`, `childCode`, and the sheet's `weight` (from
/// [sheetWeights] when available). The child code encodes stage + item name +
/// challan origin + date + sheet index; the parent code is a random scan token.
List<Map<String, dynamic>> generateSheetPieceBarcodes({
  required int challanItemId,
  required String itemName,
  required String particulars,
  required String orderOrigin,
  required int qty,
  List<double> sheetWeights = const <double>[],
}) {
  final stagePrefix = sheetBarcodeStagePrefix(particulars);
  final shortCode = sheetBarcodeShortCode(itemName);
  final dateStr = DateFormat('ddMMyy').format(DateTime.now());
  final origin = orderOrigin.isEmpty
      ? 'UNK'
      : orderOrigin.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  const chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  final rng = math.Random();

  final generated = <Map<String, dynamic>>[];
  for (var i = 1; i <= qty; i++) {
    final pieceIndex = i.toString().padLeft(2, '0');
    final childCode = '$stagePrefix$shortCode-$origin-$dateStr-$pieceIndex';
    final randomPart =
        List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
    final parentCode = 'PC-$dateStr-$randomPart-$pieceIndex';
    final weight = (i - 1) < sheetWeights.length ? sheetWeights[i - 1] : 0.0;
    generated.add({
      'challanItemId': challanItemId,
      'parentCode': parentCode,
      'childCode': childCode,
      'weight': weight,
    });
  }
  return generated;
}

/// Maps generated barcode maps to printable [SheetTag]s.
List<SheetTag> sheetTagsFromBarcodes(List<Map<String, dynamic>> barcodes) {
  return List<SheetTag>.generate(barcodes.length, (i) {
    final b = barcodes[i];
    return SheetTag(
      index: i + 1,
      weight: (b['weight'] as num?)?.toDouble() ?? 0.0,
      parentCode: (b['parentCode'] ?? b['parent_code'] ?? '') as String,
      childCode: (b['childCode'] ?? b['child_code'] ?? '') as String,
    );
  });
}

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
  bool _isGenerating = false;
  late List<Map<String, dynamic>> _generatedBarcodes;

  @override
  void initState() {
    super.initState();
    _generatedBarcodes = List.from(widget.item.pieceBarcodes);
  }

  String get _itemName {
    final items = context.read<ItemsProvider>().items;
    final idx = items.indexWhere((i) => i.id == widget.item.itemId);
    if (idx >= 0) {
      final def = items[idx];
      return def.name.isNotEmpty ? def.name : def.displayName;
    }
    return widget.item.particulars;
  }

  void _generateBarcodes() {
    final qty = (double.tryParse(widget.item.quantityPcs) ?? 0).toInt();
    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quantity must be greater than 0.')),
      );
      return;
    }
    setState(() => _isGenerating = true);
    try {
      final generated = generateSheetPieceBarcodes(
        challanItemId: widget.item.id,
        itemName: _itemName,
        particulars: widget.item.particulars,
        orderOrigin: widget.orderOrigin,
        qty: qty,
        sheetWeights: widget.item.sheetWeights,
      );
      setState(() => _generatedBarcodes = generated);
      widget.onBarcodesGenerated?.call(generated);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error generating barcodes: $e')));
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _printAll() async {
    try {
      await SheetTagPrinter.printTags(
        itemName: _itemName,
        challanNo: widget.orderOrigin,
        tags: sheetTagsFromBarcodes(_generatedBarcodes),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to print: $e')));
      }
    }
  }

  (Color, Color) _colorsForStage(String stagePrefix) {
    switch (stagePrefix) {
      case 'P1':
        return (Colors.blue.shade100, Colors.blue.shade900);
      case 'P2':
        return (Colors.purple.shade100, Colors.purple.shade900);
      case 'P3':
        return (Colors.red.shade100, Colors.red.shade900);
      default:
        return (Colors.grey.shade200, Colors.grey.shade900);
    }
  }

  @override
  Widget build(BuildContext context) {
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
          const Text(
            'Sheet Barcodes',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: SoftErpTheme.accent,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _itemName,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
          const SizedBox(height: 24),
          if (_generatedBarcodes.isEmpty)
            _buildGenerateButton()
          else
            _buildBarcodesList(),
        ],
      ),
    );
  }

  Widget _buildGenerateButton() {
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
        label: const Text('Generate Sheet Tags'),
        onPressed: _isGenerating ? null : _generateBarcodes,
        style: ElevatedButton.styleFrom(
          backgroundColor: SoftErpTheme.accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
        ),
      ),
    );
  }

  Widget _buildBarcodesList() {
    final qty = _generatedBarcodes.length;
    final stage = sheetBarcodeStagePrefix(widget.item.particulars);
    final (bgColor, fgColor) = _colorsForStage(stage);

    return Flexible(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Sheet Tags ($qty)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                icon: const Icon(Icons.print_rounded),
                label: const Text('Print All'),
                onPressed: _printAll,
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
                final weight = (barcodeData['weight'] as num?)?.toDouble() ?? 0.0;
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
                            'Sheet ${index + 1}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: fgColor,
                            ),
                          ),
                          Row(
                            children: [
                              if (weight > 0)
                                Padding(
                                  padding: const EdgeInsets.only(right: 10),
                                  child: Text(
                                    '${_fmtWeight(weight)} kg',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: fgColor,
                                    ),
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

  String _fmtWeight(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }
}

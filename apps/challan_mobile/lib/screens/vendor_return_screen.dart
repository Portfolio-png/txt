import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/core/widgets/app_toast.dart';
import 'package:core_erp/features/delivery_challans/data/delivery_challan_repository.dart';
import 'package:core_erp/features/delivery_challans/domain/delivery_challan.dart';
import 'package:core_erp/features/delivery_challans/presentation/providers/delivery_challan_provider.dart';

/// Vendor Return: scan a received sheet tag, resolve its origin (item / weight /
/// vendor) via `/api/barcode/lookup`, then log it back to the vendor as an
/// internal `vendor_return` challan. Issuing deducts the sheet's weight from
/// stock and flags the sheet returned (the backend rejects a double return).
class VendorReturnScreen extends StatefulWidget {
  const VendorReturnScreen({super.key});

  @override
  State<VendorReturnScreen> createState() => _VendorReturnScreenState();
}

class _VendorReturnScreenState extends State<VendorReturnScreen> {
  final _codeController = TextEditingController();
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _resolved;
  String _scannedCode = '';

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  String get _vendorName => (_resolved?['vendor_name'] as String?) ?? '';
  int get _vendorId => (_resolved?['vendor_id'] as num?)?.toInt() ?? 0;
  String get _itemName => (_resolved?['item_name'] as String?) ?? 'Sheet';
  double get _sheetWeight => (_resolved?['weight'] as num?)?.toDouble() ?? 0.0;
  bool get _alreadyReturned =>
      _resolved?['returned_at'] != null &&
      '${_resolved?['returned_at']}'.isNotEmpty;

  Future<void> _lookup(String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _resolved = null;
      _scannedCode = code;
    });
    try {
      final result = await context
          .read<DeliveryChallanProvider>()
          .repository
          .lookupSheetBarcode(code);
      if (!mounted) return;
      if (result == null) {
        setState(() => _error = 'No sheet found for "$code".');
      } else if ((result['challan_type'] as String?) != 'reception') {
        // Only inbound (reception) sheets belong to a vendor.
        setState(() => _error = 'That barcode is not a received vendor sheet.');
      } else {
        setState(() => _resolved = result);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openScanner() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Scan sheet tag',
                style: TextStyle(fontWeight: FontWeight.bold)),
            elevation: 0,
          ),
          body: MobileScanner(
            onDetect: (capture) {
              final barcodes = capture.barcodes;
              if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                final val = barcodes.first.rawValue!;
                Navigator.of(context).pop();
                _codeController.text = val;
                _lookup(val);
              }
            },
          ),
        ),
      ),
    );
  }

  Future<void> _confirmReturn() async {
    if (_resolved == null || _busy) return;
    if (_vendorId <= 0) {
      showAppToast(context, 'This sheet has no vendor on record.',
          kind: AppToastKind.error);
      return;
    }
    setState(() => _busy = true);
    final provider = context.read<DeliveryChallanProvider>();
    final line = DeliveryChallanItem(
      id: 0,
      orderItemId: null,
      productionRunId: null,
      itemId: (_resolved!['item_id'] as num?)?.toInt(),
      variationLeafNodeId:
          (_resolved!['variation_leaf_node_id'] as num?)?.toInt() ?? 0,
      lineNo: 1,
      particulars: _itemName,
      hsnCode: '',
      variationPathLabel: (_resolved!['variation_path_label'] as String?) ?? '',
      note: 'Vendor return of sheet $_scannedCode',
      quantityPcs: '1',
      weight: _sheetWeight > 0 ? '$_sheetWeight' : '0.0',
    );
    final draft = DeliveryChallanDraftInput(
      type: ChallanType.internal,
      purpose: ChallanPurpose.trading,
      internalPurpose: 'Vendor return',
      internalSubtype: 'vendor_return',
      returnedSheetCodes: [_scannedCode],
      challanNo: '',
      orderId: 0,
      orderIds: const [],
      vendorId: _vendorId,
      materialOwnerClientId: null,
      date: DateTime.now(),
      location: 'MAIN',
      sourceReference: 'Vendor return',
      notes: 'Vendor return of sheet $_scannedCode',
      maintainStocks: true,
      customerName: '',
      customerGstin: '',
      vendorName: _vendorName,
      vendorGstin: (_resolved!['vendor_gstin'] as String?) ?? '',
      items: [line],
    );

    final created = await provider.createChallan(draft);
    if (!mounted) return;
    if (created == null) {
      setState(() => _busy = false);
      showAppToast(context, provider.errorMessage ?? 'Failed to create return.',
          kind: AppToastKind.error);
      return;
    }
    final issued = await provider.issueChallan(created.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (issued == null) {
      showAppToast(
        context,
        'Could not issue: ${provider.errorMessage ?? 'unknown error'}',
        kind: AppToastKind.error,
      );
      return;
    }
    showAppToast(context, 'Sheet returned to $_vendorName (${issued.challanNo}).',
        kind: AppToastKind.success);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SoftErpTheme.shellSurface,
      appBar: AppBar(
        title: const Text('Vendor Return',
            style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: SoftErpTheme.accent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                ),
                onPressed: _busy ? null : _openScanner,
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Scan sheet tag',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _codeController,
                      textInputAction: TextInputAction.search,
                      inputFormatters: [
                        FilteringTextInputFormatter.deny(RegExp(r'\s')),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Or enter sheet code',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: _lookup,
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(64, 56),
                      backgroundColor: SoftErpTheme.accent.withValues(alpha: 0.12),
                      foregroundColor: SoftErpTheme.accent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed:
                        _busy ? null : () => _lookup(_codeController.text),
                    child: const Text('Look up',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (_busy)
                const Center(
                    child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ))
              else if (_error != null)
                _MessageCard(
                  color: Colors.red,
                  icon: Icons.error_outline_rounded,
                  title: 'Not found',
                  message: _error!,
                )
              else if (_resolved != null)
                _resultCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultCard() {
    if (_alreadyReturned) {
      return _MessageCard(
        color: Colors.orange,
        icon: Icons.assignment_turned_in_rounded,
        title: 'Already returned',
        message:
            'Sheet $_scannedCode was already returned to its vendor and cannot be returned again.',
      );
    }
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8ECF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_itemName,
              style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: SoftErpTheme.textPrimary)),
          const SizedBox(height: 12),
          _kv('Sheet', _scannedCode),
          _kv('Weight', _sheetWeight > 0 ? '$_sheetWeight kg' : '—'),
          _kv('Vendor', _vendorName.isEmpty ? '—' : _vendorName),
          if ((_resolved?['order_no'] as String?)?.isNotEmpty ?? false)
            _kv('From challan', '${_resolved?['order_no']}'),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: const Color(0xFFC2410C),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: _busy ? null : _confirmReturn,
            icon: const Icon(Icons.assignment_return_rounded),
            label: const Text('Confirm return to vendor',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(k,
                style: const TextStyle(
                    color: SoftErpTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          ),
          Expanded(
            child: Text(v,
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: SoftErpTheme.textPrimary)),
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.message,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.w800, color: color)),
                const SizedBox(height: 4),
                Text(message,
                    style: const TextStyle(
                        color: SoftErpTheme.textPrimary, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

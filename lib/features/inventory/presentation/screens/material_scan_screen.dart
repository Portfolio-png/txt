import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_info_panel.dart';
import '../../../../core/widgets/app_section_title.dart';
import '../../domain/material_record.dart';
import '../providers/inventory_provider.dart';

class MaterialScanScreen extends StatefulWidget {
  const MaterialScanScreen({super.key, this.popOnSuccess = false});

  final bool popOnSuccess;

  @override
  State<MaterialScanScreen> createState() => _MaterialScanScreenState();
}

class _MaterialScanScreenState extends State<MaterialScanScreen>
    with WidgetsBindingObserver {
  final TextEditingController _manualController = TextEditingController();
  MobileScannerController? _controller;
  StreamSubscription<BarcodeCapture>? _barcodeSubscription;
  MaterialRecord? _scanResult;
  String? _lastAttemptedBarcode;
  String? _notFoundMessage;
  bool _scannerPaused = false;

  bool get _isAndroidPlatform => !kIsWeb && Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_isAndroidPlatform) {
      _controller = MobileScannerController(
        autoStart: false,
        detectionSpeed: DetectionSpeed.noDuplicates,
      );
      _barcodeSubscription = _controller!.barcodes.listen(_handleBarcode);
      unawaited(_startScanner());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_cancelBarcodeSubscription());
    unawaited(_disposeScannerController());
    _manualController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isAndroidPlatform || _controller == null) {
      return;
    }

    switch (state) {
      case AppLifecycleState.resumed:
        if (!_scannerPaused && _scanResult == null) {
          unawaited(_startScanner());
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        unawaited(_stopScanner());
    }
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final isNarrow = MediaQuery.of(context).size.width < 960;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionTitle(
            title: 'Material Scan',
            subtitle:
                'Android uses the live camera scanner. Desktop and web use manual barcode lookup.',
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _notFoundMessage != null
                ? _LookupFailurePane(
                    scannedBarcode: _lastAttemptedBarcode ?? '',
                    message: _notFoundMessage!,
                    onRetry: _resetScanner,
                  )
                : _scanResult != null
                ? _ScanResultPane(
                    result: _scanResult!,
                    onRetry: _resetScanner,
                    onResetTrace: _resetTrace,
                    stacked: isNarrow,
                  )
                : _isAndroidPlatform
                ? _AndroidScannerLayout(
                    controller: _controller!,
                    isLoading: inventory.isLoading,
                    paused: _scannerPaused,
                  )
                : _ManualLookupLayout(
                    controller: _manualController,
                    isLoading: inventory.isLoading,
                    onLookup: () =>
                        _performLookup(_manualController.text.trim()),
                    stacked: isNarrow,
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleBarcode(BarcodeCapture capture) async {
    if (_scannerPaused) {
      return;
    }

    final barcode = capture.barcodes.firstOrNull?.rawValue;
    if (barcode == null || barcode.isEmpty) {
      return;
    }

    setState(() {
      _scannerPaused = true;
    });
    await _stopScanner();
    await _performLookup(barcode);
  }

  Future<void> _performLookup(String barcode) async {
    if (barcode.isEmpty) {
      return;
    }

    final cleanedBarcode = barcode.trim();
    _manualController.text = cleanedBarcode;
    _lastAttemptedBarcode = cleanedBarcode;
    _notFoundMessage = null;

    final provider = context.read<InventoryProvider>();
    final record = await provider.lookupBarcode(cleanedBarcode);
    if (!mounted) {
      return;
    }

    if (record != null && widget.popOnSuccess) {
      Navigator.of(context).pop(record);
      return;
    }

    setState(() {
      _scanResult = record;
      _notFoundMessage = record == null ? provider.errorMessage : null;
    });
  }

  Future<void> _resetScanner() async {
    _manualController.clear();
    context.read<InventoryProvider>().clearError();
    setState(() {
      _scanResult = null;
      _lastAttemptedBarcode = null;
      _notFoundMessage = null;
      _scannerPaused = false;
    });
    if (_isAndroidPlatform) {
      await _startScanner();
    }
  }

  Future<void> _resetTrace() async {
    final current = _scanResult;
    if (current == null) {
      return;
    }

    await context.read<InventoryProvider>().resetScanTrace(current.barcode);
    if (!mounted) {
      return;
    }

    setState(() {
      _scanResult = context.read<InventoryProvider>().selectedMaterial;
    });
  }

  Future<void> _startScanner() async {
    if (_controller == null) {
      return;
    }

    try {
      await _controller!.start();
    } catch (_) {
      // Ignore non-fatal lifecycle start errors from the scanner plugin.
    }
  }

  Future<void> _stopScanner() async {
    if (_controller == null) {
      return;
    }

    try {
      await _controller!.stop();
    } catch (_) {
      // Ignore non-fatal lifecycle stop errors from the scanner plugin.
    }
  }

  Future<void> _cancelBarcodeSubscription() async {
    try {
      await _barcodeSubscription?.cancel();
    } catch (_) {
      // Swallow stream cancellation races during teardown.
    } finally {
      _barcodeSubscription = null;
    }
  }

  Future<void> _disposeScannerController() async {
    if (_controller == null) {
      return;
    }

    try {
      await _controller!.dispose();
    } catch (_) {
      // Swallow non-fatal plugin disposal races.
    } finally {
      _controller = null;
    }
  }
}

class _AndroidScannerLayout extends StatelessWidget {
  const _AndroidScannerLayout({
    required this.controller,
    required this.isLoading,
    required this.paused,
  });

  final MobileScannerController controller;
  final bool isLoading;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: AppCard(
            padding: EdgeInsets.zero,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: MobileScanner(controller: controller),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0x99FFFFFF),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xB3121620),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      paused
                          ? 'Barcode captured. Loading details...'
                          : 'Align a barcode inside the frame.',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isLoading)
          const Positioned(
            top: 16,
            right: 16,
            child: Card(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text('Looking up barcode...'),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ManualLookupLayout extends StatelessWidget {
  const _ManualLookupLayout({
    required this.controller,
    required this.isLoading,
    required this.onLookup,
    required this.stacked,
  });

  final TextEditingController controller;
  final bool isLoading;
  final VoidCallback onLookup;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    if (stacked) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(8),
        children: [
          _ManualLookupPane(
            controller: controller,
            isLoading: isLoading,
            onLookup: onLookup,
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: _ManualLookupPane(
            controller: controller,
            isLoading: isLoading,
            onLookup: onLookup,
          ),
        ),
      ],
    );
  }
}

class _ManualLookupPane extends StatelessWidget {
  const _ManualLookupPane({
    required this.controller,
    required this.isLoading,
    required this.onLookup,
  });

  final TextEditingController controller;
  final bool isLoading;
  final VoidCallback onLookup;

  @override
  Widget build(BuildContext context) {
    final error = context.watch<InventoryProvider>().errorMessage;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Manual lookup',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Desktop and web use manual lookup only. Android uses the camera scanner.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF6B7280)),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: 'Barcode',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onSubmitted: (_) => onLookup(),
          ),
          const SizedBox(height: 16),
          AppButton(
            label: 'Lookup Barcode',
            icon: Icons.search,
            isLoading: isLoading,
            onPressed: onLookup,
          ),
          if (error != null) ...[
            const SizedBox(height: 14),
            Text(
              error,
              style: const TextStyle(
                color: Color(0xFFB91C1C),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LookupFailurePane extends StatelessWidget {
  const _LookupFailurePane({
    required this.scannedBarcode,
    required this.message,
    required this.onRetry,
  });

  final String scannedBarcode;
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(8),
      children: [
        AppCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Barcode not found',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Scanned value: $scannedBarcode',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              AppButton(
                label: 'Try Again',
                icon: Icons.refresh,
                variant: AppButtonVariant.secondary,
                onPressed: () {
                  onRetry();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScanResultPane extends StatelessWidget {
  const _ScanResultPane({
    required this.result,
    required this.onRetry,
    required this.onResetTrace,
    required this.stacked,
  });

  final MaterialRecord result;
  final Future<void> Function() onRetry;
  final Future<void> Function() onResetTrace;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final detailPanel = AppInfoPanel(
      title: result.name,
      subtitle: 'Barcode matched successfully',
      headerTrailing: _ScanTraceBadge(scanCount: result.scanCount),
      rows: [
        AppInfoRow(label: 'Barcode', value: result.barcode),
        AppInfoRow(label: 'Type', value: result.type),
        AppInfoRow(label: 'Grade', value: result.grade),
        AppInfoRow(label: 'Thickness', value: result.thickness),
        AppInfoRow(label: 'Supplier', value: result.supplier),
        AppInfoRow(
          label: 'Relationship',
          value: result.isParent
              ? 'Parent of ${result.numberOfChildren} children'
              : 'Child of ${result.parentBarcode}',
        ),
        AppInfoRow(
          label: 'Scan trace',
          value: 'Scanned ${result.scanCount} times',
        ),
      ],
      footer: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            AppButton(
              label: 'Retry Scan',
              icon: Icons.refresh,
              variant: AppButtonVariant.secondary,
              onPressed: () {
                onRetry();
              },
            ),
            if (kDebugMode)
              AppButton(
                label: 'Reset Trace',
                icon: Icons.restore,
                variant: AppButtonVariant.secondary,
                onPressed: () {
                  onResetTrace();
                },
              ),
          ],
        ),
      ),
    );

    final tracePanel = AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Scan trace',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            'Scanned ${result.scanCount} times',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Color(0xFF6C63FF),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Every successful lookup increments the count and stores a history event.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF6B7280)),
          ),
        ],
      ),
    );

    if (stacked) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(8),
        children: [detailPanel, const SizedBox(height: 16), tracePanel],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: detailPanel),
        const SizedBox(width: 20),
        Expanded(flex: 2, child: tracePanel),
      ],
    );
  }
}

class _ScanTraceBadge extends StatelessWidget {
  const _ScanTraceBadge({required this.scanCount});

  final int scanCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEEEAFE),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Scanned $scanCount times',
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFF5B4FE6),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

extension on Iterable<Barcode> {
  Barcode? get firstOrNull => isEmpty ? null : first;
}

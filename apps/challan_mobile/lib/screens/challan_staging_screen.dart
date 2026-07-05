import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:core_erp/core/theme/soft_erp_theme.dart';
import '../services/socket_service.dart';

class ChallanStagingScreen extends StatefulWidget {
  const ChallanStagingScreen({super.key});

  @override
  State<ChallanStagingScreen> createState() => _ChallanStagingScreenState();
}

class _ChallanStagingScreenState extends State<ChallanStagingScreen> {
  final FocusNode _scannerFocusNode = FocusNode();
  final TextEditingController _scannerController = TextEditingController();
  
  final List<Map<String, dynamic>> _stagedItems = [];

  @override
  void initState() {
    super.initState();
    // Always keep focus on the text field for the HID scanner
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scannerFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _scannerFocusNode.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  void _handleBarcodeScanned(String barcode) {
    final trimmed = barcode.trim();
    if (trimmed.isEmpty) return;

    // Haptic feedback for the worker
    HapticFeedback.heavyImpact();

    final itemData = {
      'barcode': trimmed,
      'timestamp': DateTime.now().toIso8601String(),
    };

    setState(() {
      _stagedItems.insert(0, itemData); // Add to top of local list
    });

    // Send to Node.js backend
    context.read<SocketService>().stageItem(itemData);

    // Clear and refocus
    _scannerController.clear();
    _scannerFocusNode.requestFocus();
  }

  void _openCameraScanner() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Scan Barcode')),
        body: MobileScanner(
          onDetect: (capture) {
            final List<Barcode> barcodes = capture.barcodes;
            if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
              final val = barcodes.first.rawValue!;
              Navigator.of(context).pop();
              _handleBarcodeScanned(val);
            }
          },
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final socketService = context.watch<SocketService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Dock Staging'),
        backgroundColor: socketService.isConnected ? SoftErpTheme.accent : Colors.red,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt),
            onPressed: _openCameraScanner,
            tooltip: 'Camera Scanner (Fallback)',
          )
        ],
      ),
      body: GestureDetector(
        // Tapping anywhere refocuses the hidden input
        onTap: () => _scannerFocusNode.requestFocus(),
        child: Column(
          children: [
            // Connection Status Banner
            if (!socketService.isConnected)
              Container(
                width: double.infinity,
                color: Colors.red.shade100,
                padding: const EdgeInsets.all(8.0),
                child: const Text(
                  'Offline - Scans are saved locally',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
              ),
              
            // The Summary View
            Expanded(
              child: _stagedItems.isEmpty
                  ? Center(
                      child: Text(
                        'Ready to Scan\n\n(Waiting for Bluetooth Scanner)',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 18),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _stagedItems.length,
                      itemBuilder: (context, index) {
                        final item = _stagedItems[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: SoftErpTheme.accent,
                              child: Icon(Icons.qr_code, color: Colors.white),
                            ),
                            title: Text('Barcode: ${item['barcode']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                            subtitle: Text('Scanned at: ${DateTime.parse(item['timestamp']).toLocal().toString().split('.')[0]}'),
                            trailing: const Icon(Icons.check_circle, color: Colors.green),
                          ),
                        );
                      },
                    ),
            ),
            
            // Hidden Input Field
            Opacity(
              opacity: 0,
              child: SizedBox(
                height: 0,
                child: TextField(
                  controller: _scannerController,
                  focusNode: _scannerFocusNode,
                  autofocus: true,
                  onSubmitted: _handleBarcodeScanned,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
    final isTablet = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Live Dock Staging',
          style: TextStyle(
            fontSize: isTablet ? 24.0 : 20.0,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: socketService.isConnected ? SoftErpTheme.accent : Colors.red,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.camera_alt, size: isTablet ? 28.0 : 24.0),
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
                padding: EdgeInsets.all(isTablet ? 12.0 : 8.0),
                child: Text(
                  'Offline - Scans are saved locally',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.red, 
                    fontWeight: FontWeight.bold,
                    fontSize: isTablet ? 16.0 : 14.0,
                  ),
                ),
              ),
              
            // The Summary View
            Expanded(
              child: _stagedItems.isEmpty
                  ? Center(
                      child: Text(
                        'Ready to Scan\n\n(Waiting for Bluetooth Scanner)',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade600, 
                          fontSize: isTablet ? 22.0 : 18.0
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _stagedItems.length,
                      itemBuilder: (context, index) {
                        final item = _stagedItems[index];
                        return Center(
                          child: Container(
                            constraints: BoxConstraints(maxWidth: isTablet ? 720.0 : double.infinity),
                            child: Card(
                              margin: EdgeInsets.symmetric(
                                horizontal: isTablet ? 24.0 : 16.0, 
                                vertical: isTablet ? 10.0 : 8.0
                              ),
                              child: ListTile(
                                contentPadding: EdgeInsets.all(isTablet ? 18.0 : 12.0),
                                leading: CircleAvatar(
                                  radius: isTablet ? 28.0 : 20.0,
                                  backgroundColor: SoftErpTheme.accent,
                                  child: Icon(Icons.qr_code, color: Colors.white, size: isTablet ? 28.0 : 20.0),
                                ),
                                title: Text(
                                  'Barcode: ${item['barcode']}', 
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold, 
                                    fontSize: isTablet ? 22.0 : 18.0
                                  )
                                ),
                                subtitle: Text(
                                  'Scanned at: ${DateTime.parse(item['timestamp']).toLocal().toString().split('.')[0]}',
                                  style: TextStyle(fontSize: isTablet ? 15.0 : 13.0),
                                ),
                                trailing: Icon(
                                  Icons.check_circle, 
                                  color: Colors.green, 
                                  size: isTablet ? 28.0 : 24.0
                                ),
                              ),
                            ),
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

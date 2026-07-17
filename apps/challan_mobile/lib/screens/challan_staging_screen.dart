import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:core_erp/core/theme/soft_erp_theme.dart';
import '../services/socket_service.dart';
import 'production_screen.dart';

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

  Future<void> _handleBarcodeScanned(String barcode) async {
    final trimmed = barcode.trim();
    if (trimmed.isEmpty) return;

    HapticFeedback.heavyImpact();

    final itemData = {
      'barcode': trimmed,
      'timestamp': DateTime.now().toIso8601String(),
    };

    final socketService = context.read<SocketService>();
    final materialDetail = await socketService.fetchMaterialDetail(trimmed);

    if (materialDetail != null && materialDetail['activePipelineRun'] != null) {
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (context) => ProductionScreen(
          materialBarcode: trimmed,
          pipelineRun: materialDetail['activePipelineRun'],
        ),
      ));
      _scannerController.clear();
      _scannerFocusNode.requestFocus();
      return;
    }

    setState(() {
      _stagedItems.insert(0, itemData);
    });

    socketService.stageItem(itemData);

    _scannerController.clear();
    _scannerFocusNode.requestFocus();
  }

  void _openCameraScanner() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: const Text('Scan Barcode', style: TextStyle(fontWeight: FontWeight.bold)),
          elevation: 0,
        ),
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
      backgroundColor: SoftErpTheme.shellSurface,
      appBar: AppBar(
        title: Text(
          'Live Dock Staging',
          style: TextStyle(
            fontSize: isTablet ? 24.0 : 20.0,
            fontWeight: FontWeight.bold,
            color: SoftErpTheme.textPrimary,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: SoftErpTheme.border, height: 1.0),
        ),
        actions: [
          Row(
            children: [
              Text(
                socketService.isConnected ? 'Connected' : 'Offline',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: socketService.isConnected ? Colors.green.shade700 : Colors.red.shade700,
                ),
              ),
              const SizedBox(width: 8),
              PulsingStatusWidget(isConnected: socketService.isConnected),
              const SizedBox(width: 12),
            ],
          ),
          IconButton(
            icon: Icon(Icons.camera_alt, color: SoftErpTheme.textPrimary, size: isTablet ? 28.0 : 24.0),
            onPressed: _openCameraScanner,
            tooltip: 'Camera Scanner',
          ),
          TextButton(
            onPressed: () async {
              final barcode = await socketService.seedDemoManufacturing();
              if (barcode != null) {
                _handleBarcodeScanned(barcode);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Failed to seed demo data.')),
                );
              }
            },
            child: const Text('demo-prod', style: TextStyle(fontWeight: FontWeight.bold, color: SoftErpTheme.accent)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: GestureDetector(
        onTap: () => _scannerFocusNode.requestFocus(),
        child: Column(
          children: [
            // Connection Warning Banner (if offline)
            if (!socketService.isConnected)
              Container(
                width: double.infinity,
                color: Colors.red.shade50,
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off, color: Colors.red, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Offline Mode — Scans will sync automatically once connected.',
                        style: TextStyle(
                          color: Colors.red.shade900,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Staging Stats Dashboard
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isTablet ? 24.0 : 16.0,
                vertical: 16.0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      title: 'Dock Health',
                      value: socketService.isConnected ? 'Active & Syncing' : 'Caching Locally',
                      icon: socketService.isConnected ? Icons.cloud_done : Icons.storage,
                      iconColor: socketService.isConnected ? Colors.green : Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      title: 'Session Scans',
                      value: '${_stagedItems.length} Items',
                      icon: Icons.qr_code_scanner,
                      iconColor: SoftErpTheme.accent,
                    ),
                  ),
                ],
              ),
            ),
              
            // The Summary View
            Expanded(
              child: _stagedItems.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const PulsingRadarWidget(),
                          const SizedBox(height: 32),
                          Text(
                            'Ready to Scan',
                            style: TextStyle(
                              color: SoftErpTheme.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: isTablet ? 24.0 : 20.0,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Aim Bluetooth scanner at the barcode tag',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: SoftErpTheme.textSecondary,
                              fontSize: isTablet ? 16.0 : 14.0,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _stagedItems.length,
                      padding: const EdgeInsets.only(bottom: 100),
                      itemBuilder: (context, index) {
                        final item = _stagedItems[index];
                        final timeStr = DateTime.parse(item['timestamp'])
                            .toLocal()
                            .toString()
                            .split(' ')[1]
                            .substring(0, 8);
                            
                        return Center(
                          child: Container(
                            constraints: BoxConstraints(maxWidth: isTablet ? 720.0 : double.infinity),
                            child: Container(
                              margin: EdgeInsets.symmetric(
                                horizontal: isTablet ? 24.0 : 16.0, 
                                vertical: 6.0,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: SoftErpTheme.subtleShadow,
                                border: Border.all(color: SoftErpTheme.border),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  decoration: const BoxDecoration(
                                    border: Border(
                                      left: BorderSide(
                                        color: SoftErpTheme.accent,
                                        width: 5,
                                      ),
                                    ),
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.all(16.0),
                                    leading: CircleAvatar(
                                      radius: 22,
                                      backgroundColor: SoftErpTheme.accentSoft,
                                      child: const Icon(Icons.qr_code, color: SoftErpTheme.accent, size: 22),
                                    ),
                                    title: Text(
                                      item['barcode'],
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold, 
                                        fontSize: 16.0,
                                        color: SoftErpTheme.textPrimary,
                                      ),
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 4.0),
                                      child: Text(
                                        'Scanned at $timeStr',
                                        style: const TextStyle(
                                          fontSize: 13.0,
                                          color: SoftErpTheme.textSecondary,
                                        ),
                                      ),
                                    ),
                                    trailing: const Icon(
                                      Icons.check_circle, 
                                      color: Colors.green, 
                                      size: 24,
                                    ),
                                  ),
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

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SoftErpTheme.border),
        boxShadow: SoftErpTheme.subtleShadow,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: SoftErpTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    color: SoftErpTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PulsingStatusWidget extends StatefulWidget {
  final bool isConnected;
  const PulsingStatusWidget({super.key, required this.isConnected});

  @override
  State<PulsingStatusWidget> createState() => _PulsingStatusWidgetState();
}

class _PulsingStatusWidgetState extends State<PulsingStatusWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isConnected ? Colors.green : Colors.red;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.15 + (_controller.value * 0.2)),
          ),
          child: Center(
            child: Container(
              width: 8 + (_controller.value * 3),
              height: 8 + (_controller.value * 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.5),
                    blurRadius: 4 + (_controller.value * 4),
                    spreadRadius: 1 + (_controller.value * 1),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class PulsingRadarWidget extends StatefulWidget {
  const PulsingRadarWidget({super.key});

  @override
  State<PulsingRadarWidget> createState() => _PulsingRadarWidgetState();
}

class _PulsingRadarWidgetState extends State<PulsingRadarWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer wave 2
            Container(
              width: 140 * _controller.value,
              height: 140 * _controller.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: SoftErpTheme.accent.withValues(alpha: 0.12 * (1.0 - _controller.value)),
              ),
            ),
            // Outer wave 1
            Container(
              width: 200 * _controller.value,
              height: 200 * _controller.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: SoftErpTheme.accent.withValues(alpha: 0.06 * (1.0 - _controller.value)),
              ),
            ),
            // Center circle
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: SoftErpTheme.accent.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.qr_code_scanner,
                size: 38,
                color: SoftErpTheme.accent,
              ),
            ),
          ],
        );
      },
    );
  }
}

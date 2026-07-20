import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:provider/provider.dart';
import '../services/socket_service.dart';
import 'inventory_stock_screen.dart';
import 'orders_list_screen.dart';

class ProductionScreen extends StatelessWidget {
  const ProductionScreen({
    super.key,
    required this.materialBarcode,
    required this.pipelineRun,
  });

  final String materialBarcode;
  final Map<String, dynamic> pipelineRun;

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      backgroundColor: SoftErpTheme.shellSurface,
      appBar: AppBar(
        centerTitle: true,
        titleSpacing: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                pipelineRun['name'] ?? 'Production Line',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: isTablet ? 24.0 : 20.0,
                  fontWeight: FontWeight.bold,
                  color: SoftErpTheme.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 20),
            _buildPipelineProgress(),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: IconThemeData(color: SoftErpTheme.textPrimary),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final useColumns = constraints.maxWidth >= 600;
              final leftCol = _buildLeftColumn(context);
              final rightCol = _buildRightColumn(context);

              if (useColumns) {
                return SingleChildScrollView(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 1,
                        child: leftCol,
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        flex: 2,
                        child: rightCol,
                      ),
                    ],
                  ),
                );
              } else {
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      leftCol,
                      const SizedBox(height: 24),
                      rightCol,
                    ],
                  ),
                );
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLeftColumn(BuildContext context) {
    final machine = pipelineRun['machine'];
    final photoUrls = machine?['photoUrls'] as List<dynamic>?;
    final rawPhotoUrl = (photoUrls != null && photoUrls.isNotEmpty) ? photoUrls.first.toString() : null;
    
    String? photoUrl = rawPhotoUrl;
    if (photoUrl != null && photoUrl.startsWith('/')) {
      final baseUrl = context.read<SocketService>().baseUrl?.replaceAll(RegExp(r'/$'), '') ?? '';
      photoUrl = '$baseUrl$photoUrl';
    }

    return Card(
      elevation: 0,
      color: const Color(0xFFFDF8F3), // Pale orange/yellow
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: SoftErpTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE2C281),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Machine: ${machine?['name'] ?? 'Unknown'}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _networkImage(context, url: photoUrl, height: 300, fit: BoxFit.cover),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Photo upload is coming soon'),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(milliseconds: 1200),
                  ),
                );
              },
              icon: const Icon(Icons.add_a_photo),
              label: const Text('Add/Update Photo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: SoftErpTheme.accent,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(String text, {double height = 300, double radius = 12}) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_not_supported, size: height > 200 ? 64 : 40, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              text,
              style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  /// Network image with rounded corners, a loading spinner, a unified error /
  /// missing placeholder, and tap-to-zoom into a fullscreen pinch-zoom viewer.
  Widget _networkImage(
    BuildContext context, {
    required String? url,
    required double height,
    BoxFit fit = BoxFit.cover,
    double radius = 12,
  }) {
    if (url == null || url.isEmpty) {
      return _buildPlaceholder('Image Missing', height: height, radius: radius);
    }
    final tag = 'photo::$url';
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        PageRouteBuilder<void>(
          opaque: false,
          barrierColor: Colors.black87,
          pageBuilder: (_, _, _) => _ImageViewer(url: url, heroTag: tag),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          children: [
            Hero(
              tag: tag,
              child: Image.network(
                url,
                height: height,
                width: double.infinity,
                fit: fit,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    height: height,
                    color: Colors.grey.shade100,
                    child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                },
                errorBuilder: (context, error, stackTrace) =>
                    _buildPlaceholder('Error loading image', height: height, radius: radius),
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.45),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.zoom_out_map_rounded, color: Colors.white, size: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A monospace "code chip" for scannable identifiers (barcodes, tool codes)
  /// with a copy button. Monospace avoids 0/O and 1/l misreads on the floor.
  Widget _codeChip({required IconData icon, required String value}) {
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 4, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: SoftErpTheme.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                letterSpacing: 0.3,
              ),
            ),
          ),
          Builder(
            builder: (context) => IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Copy',
              icon: Icon(Icons.copy_rounded, size: 18, color: SoftErpTheme.textSecondary),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                HapticFeedback.selectionClick();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Copied to clipboard'),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(milliseconds: 900),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _labeledCode({required String label, required IconData icon, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: SoftErpTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        _codeChip(icon: icon, value: value),
      ],
    );
  }

  Widget _buildRightColumn(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInfoCard(
          title: 'Raw Material Details',
          dotColor: const Color(0xFFE25363), // red/pink
          bgColor: const Color(0xFFFCF1F3), // pale red/pink
          child: _labeledCode(
            label: 'SCANNED BARCODE',
            icon: Icons.qr_code_2_rounded,
            value: materialBarcode,
          ),
        ),
        const SizedBox(height: 16),
        _buildDieDetails(context),
        const SizedBox(height: 16),
        _buildLinksCard(context),
        const SizedBox(height: 16),
        _buildPipelineStatus(),
      ],
    );
  }

  Widget _buildDieDetails(BuildContext context) {
    final die = pipelineRun['die'];
    final photoUrls = die?['photoUrls'] as List<dynamic>?;
    final rawPhotoUrl = (photoUrls != null && photoUrls.isNotEmpty) ? photoUrls.first.toString() : null;
    
    String? photoUrl = rawPhotoUrl;
    if (photoUrl != null && photoUrl.startsWith('/')) {
      final baseUrl = context.read<SocketService>().baseUrl?.replaceAll(RegExp(r'/$'), '') ?? '';
      photoUrl = '$baseUrl$photoUrl';
    }

    return _buildInfoCard(
      title: 'Die Assigned',
      dotColor: const Color(0xFFA5A9B1), // gray
      bgColor: const Color(0xFFF7F7F7), // pale gray
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _labeledCode(
            label: 'TOOL CODE',
            icon: Icons.build_rounded,
            value: die?['toolCode']?.toString() ?? 'Unknown',
          ),
          const SizedBox(height: 12),
          _networkImage(context, url: photoUrl, height: 180, fit: BoxFit.contain, radius: 10),
        ],
      ),
    );
  }

  Widget _buildLinksCard(BuildContext context) {
    final orderIds = pipelineRun['orderIds'] as List<dynamic>? ?? [];
    
    return _buildInfoCard(
      title: 'Related Links',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => const InventoryStockScreen(),
              ));
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                children: [
                  Icon(Icons.inventory_2, color: SoftErpTheme.accent),
                  SizedBox(width: 8),
                  Text(
                    'Output in Inventory',
                    style: TextStyle(
                      fontSize: 16,
                      color: SoftErpTheme.accent,
                      decoration: TextDecoration.underline,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(),
          if (orderIds.isNotEmpty)
            ...orderIds.map((orderId) => InkWell(
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (context) => const OrdersListScreen(),
                    ));
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      children: [
                        const Icon(Icons.receipt_long, color: SoftErpTheme.accent),
                        const SizedBox(width: 8),
                        Text(
                          'Order ID: $orderId',
                          style: const TextStyle(
                            fontSize: 16,
                            color: SoftErpTheme.accent,
                            decoration: TextDecoration.underline,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ))
          else
            const Text('No assigned orders', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  // Rendered inline in the AppBar title, on the same row as the run name.
  // Shows the stage dots plus a pill naming the *current* stage — a worker
  // cares which operation they're on, not just "1/1".
  Widget _buildPipelineProgress() {
    final nodes = pipelineRun['nodes'] as List<dynamic>? ?? [];
    final labels = pipelineRun['stageLabels'] as List<dynamic>? ?? [];
    final currentNodeId = pipelineRun['currentNodeId'];

    if (nodes.isEmpty) return const SizedBox.shrink();

    int currentIndex = nodes.indexWhere((n) => n['id'] == currentNodeId);
    if (currentIndex == -1) currentIndex = 0; // fallback if not found

    final stageName = (currentIndex >= 0 && currentIndex < labels.length)
        ? labels[currentIndex].toString()
        : null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(nodes.length, (index) {
          final isDone = index <= currentIndex;
          final isCurrent = index == currentIndex;

          final color = isDone ? SoftErpTheme.accent : const Color(0xFFD8DEE6);

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: isCurrent ? 13 : 11,
                height: isCurrent ? 13 : 11,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: isCurrent
                      ? [BoxShadow(color: color.withOpacity(0.45), blurRadius: 5, spreadRadius: 1)]
                      : null,
                ),
              ),
              if (index < nodes.length - 1)
                Container(width: 16, height: 3, color: color),
            ],
          );
        }),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: SoftErpTheme.accent.withOpacity(0.10),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Stage ${currentIndex + 1}/${nodes.length}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: SoftErpTheme.accent,
                ),
              ),
              if (stageName != null && stageName.isNotEmpty) ...[
                Text(
                  '  ·  ',
                  style: TextStyle(fontSize: 13, color: SoftErpTheme.accent.withOpacity(0.5)),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    stageName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: SoftErpTheme.accent,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPipelineStatus() {
    final stages = pipelineRun['stages'] as List<dynamic>? ?? [];
    final nodes = pipelineRun['nodes'] as List<dynamic>? ?? [];
    final labels = pipelineRun['stageLabels'] as List<dynamic>? ?? [];

    return _buildInfoCard(
      title: 'Line Status',
      dotColor: const Color(0xFF3EA34D), // green
      bgColor: const Color(0xFFF0F9F1), // pale green
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: stages.map((stage) {
          final nodeId = stage['nodeId'];
          final producedQty = stage['producedQty'] ?? 0;
          
          String stageName = 'Unknown Stage';
          // Match nodeId to nodes array to find index, then map to labels
          final nodeIndex = nodes.indexWhere((n) => n['id'] == nodeId);
          if (nodeIndex >= 0 && nodeIndex < labels.length) {
            stageName = labels[nodeIndex].toString();
          }

          final isCurrent = pipelineRun['currentNodeId'] == nodeId;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isCurrent ? SoftErpTheme.accent.withOpacity(0.1) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isCurrent ? SoftErpTheme.accent : Colors.grey.shade200,
                width: isCurrent ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  stageName,
                  style: TextStyle(
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                    fontSize: 16,
                    color: isCurrent ? SoftErpTheme.accent : SoftErpTheme.textPrimary,
                  ),
                ),
                Text(
                  '$producedQty Produced',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required Widget child,
    Color? dotColor,
    Color? bgColor,
  }) {
    return Card(
      elevation: 0,
      color: bgColor ?? Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: SoftErpTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (dotColor != null) ...[
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

/// Fullscreen, pinch-to-zoom viewer for a machine/die photo. Tap the backdrop
/// or the close button to dismiss; the image animates via a shared Hero.
class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.url, required this.heroTag});

  final String url;
  final String heroTag;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5,
                child: Center(
                  child: Hero(
                    tag: heroTag,
                    child: Image.network(url, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 12,
            child: Material(
              color: Colors.black.withOpacity(0.4),
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

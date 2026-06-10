import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/production_provider.dart';
import '../providers/production_run_provider.dart';
import '../../production_pipelines/data/repositories/pipeline_run_repository.dart';
import '../../production_pipelines/domain/node_run_status.dart';
import '../../production_pipelines/domain/process_node.dart';
import 'package:core_erp/features/auth/presentation/providers/auth_provider.dart';
import 'package:core_erp/core/network/authenticated_http_client.dart';

class ProductionTestPanel extends StatefulWidget {
  const ProductionTestPanel({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  State<ProductionTestPanel> createState() => _ProductionTestPanelState();
}

class _ProductionTestPanelState extends State<ProductionTestPanel> {
  final _qtyController = TextEditingController(text: '100.0');
  bool _isLoading = false;
  String? _statusMessage;
  bool _isSuccess = false;

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  Future<void> _runSimulationAction(Future<void> Function() action) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _statusMessage = null;
      _isSuccess = false;
    });

    try {
      await action();
      setState(() {
        _isSuccess = true;
        _statusMessage = 'Action completed successfully!';
      });
    } catch (e) {
      setState(() {
        _isSuccess = false;
        _statusMessage = 'Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final productionProvider = context.watch<ProductionProvider>();
    final runProvider = context.watch<ProductionRunProvider>();
    final auth = context.read<AuthProvider>();

    final selectedNode = productionProvider.selectedNode;
    final runId = runProvider.runId;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: 380,
          decoration: BoxDecoration(
            color: const Color(0xCC1E293B), // Premium dark slate glass
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x33FFFFFF), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0x22FFFFFF))),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.science_rounded, color: Color(0xFF60A5FA), size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'PRODUCTION SIMULATOR',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: widget.onClose,
                      child: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                    ),
                  ],
                ),
              ),

              if (runId == null) ...[
                const Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Text(
                    'No active production run detected. Select or start a production run first.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ] else if (selectedNode == null) ...[
                const Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Text(
                    'Please select a production stage/node on the canvas to configure and test.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ] else ...[
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Selected Stage Info
                        _buildSectionHeader('Selected Stage'),
                        _buildStageInfoCard(selectedNode, runProvider),
                        const SizedBox(height: 18),

                        // Section 1: Asset Lock Setup Bypass
                        _buildSectionHeader('1. Quick Setup Verification'),
                        _buildBypassCard(selectedNode, productionProvider, runProvider),
                        const SizedBox(height: 18),

                        // Section 2: Mock Stock Seed & Assign
                        _buildSectionHeader('2. Seed & Auto-Assign Material'),
                        _buildSeedMaterialCard(selectedNode, runProvider, auth),
                        const SizedBox(height: 18),

                        // Section 3: Run Stage Transitions
                        _buildSectionHeader('3. Advance Stage Node'),
                        _buildNodeTransitionsCard(selectedNode, runProvider, productionProvider),
                        const SizedBox(height: 18),
                      ],
                    ),
                  ),
                ),

                // Status Message Footer
                if (_statusMessage != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: _isSuccess
                        ? const Color(0x3310B981)
                        : const Color(0x33EF4444),
                    child: Text(
                      _statusMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _isSuccess ? const Color(0xFF34D399) : const Color(0xFFF87171),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                // Loading Indicator overlay
                if (_isLoading)
                  const LinearProgressIndicator(
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF60A5FA)),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF94A3B8),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildStageInfoCard(ProcessNode node, ProductionRunProvider runProvider) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x11FFFFFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            node.name,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Type: ${node.processType}',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: node.statusColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  node.status.toUpperCase(),
                  style: TextStyle(color: node.statusColor, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBypassCard(ProcessNode node, ProductionProvider prodProvider, ProductionRunProvider runProvider) {
    final hasMachine = node.machine.trim().isNotEmpty;
    final hasDie = node.dieId.trim().isNotEmpty;

    final machineScanned = runProvider.scannedMachineId != null;
    final dieScanned = runProvider.scannedDieId != null;

    final allVerified = (!hasMachine || machineScanned) && (!hasDie || dieScanned);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x11FFFFFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasMachine)
            _buildBypassIndicator(
              label: 'Machine lock: "${node.machine}"',
              isVerified: machineScanned,
            ),
          if (hasDie) ...[
            if (hasMachine) const SizedBox(height: 6),
            _buildBypassIndicator(
              label: 'Die lock: "${node.dieId}"',
              isVerified: dieScanned,
            ),
          ],
          if (!hasMachine && !hasDie)
            const Text(
              'No machine or die locks setup required.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            icon: const Icon(Icons.qr_code_scanner_rounded, size: 16),
            label: Text(allVerified ? 'Verified' : 'Bypass Locks & Verify'),
            onPressed: allVerified
                ? null
                : () => _runSimulationAction(() async {
                      if (hasMachine) {
                        prodProvider.verifySetup(node.machine, node.dieId);
                        runProvider.verifyScannedAsset(node.machine);
                      }
                      if (hasDie) {
                        runProvider.verifyScannedAsset(node.dieId);
                      }
                    }),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBypassIndicator({required String label, required bool isVerified}) {
    return Row(
      children: [
        Icon(
          isVerified ? Icons.check_circle_rounded : Icons.pending_rounded,
          color: isVerified ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
          size: 14,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: isVerified ? Colors.white70 : Colors.white,
              fontSize: 12,
              decoration: isVerified ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSeedMaterialCard(ProcessNode node, ProductionRunProvider runProvider, AuthProvider auth) {
    final inputItem = node.inputItem;
    if (inputItem == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0x11FFFFFF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x1AFFFFFF)),
        ),
        child: const Text(
          'This stage does not expect any linked input items.',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x11FFFFFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Expected Item: ${inputItem.itemName}',
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          ),
          Text(
            'Item ID: ${inputItem.itemId} | Unit: ${inputItem.unitLabel}',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(
                flex: 2,
                child: Text(
                  'Assign Qty:',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _qtyController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0x15FFFFFF),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            icon: const Icon(Icons.add_shopping_cart_rounded, size: 16),
            label: const Text('Seed & Link Material'),
            onPressed: () => _runSimulationAction(() async {
              final quantity = double.tryParse(_qtyController.text) ?? 100.0;
              final repo = context.read<PipelineRunRepository>();

              // Determine Base URL
              String baseUrl = 'http://localhost:18080';
              if (repo is ApiPipelineRunRepository) {
                baseUrl = repo.baseUrl;
              }

              // Create authenticated HTTP client
              final client = AuthenticatedHttpClient(tokenResolver: () => auth.token);

              // 1. Seed Parent Material
              final seedResponse = await client.post(
                Uri.parse('$baseUrl/api/materials/parent'),
                headers: const {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'name': 'Seed Stock ${inputItem.itemName}',
                  'type': 'Lot',
                  'numberOfChildren': 1,
                  'unit': inputItem.unitLabel,
                  'unitId': inputItem.unitId,
                }),
              );

              if (seedResponse.statusCode >= 300) {
                throw Exception('Seed material API failed: ${seedResponse.body}');
              }

              final seedBody = jsonDecode(seedResponse.body) as Map<String, dynamic>;
              if (seedBody['success'] != true) {
                throw Exception('Seed failed: ${seedBody['error']}');
              }

              final material = seedBody['material'] as Map<String, dynamic>;
              final childBarcodes = List<String>.from(material['linkedChildBarcodes'] ?? const []);
              if (childBarcodes.isEmpty) {
                throw Exception('Created parent lot has no child barcodes.');
              }
              final childBarcode = childBarcodes.first;

              // 2. Link item ID to child barcode
              final linkResponse = await client.patch(
                Uri.parse('$baseUrl/api/materials/$childBarcode/link-item'),
                headers: const {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'itemId': inputItem.itemId,
                  'variationLeafNodeId': 0,
                }),
              );

              if (linkResponse.statusCode >= 300) {
                throw Exception('Link item API failed: ${linkResponse.body}');
              }

              final linkBody = jsonDecode(linkResponse.body) as Map<String, dynamic>;
              if (linkBody['success'] != true) {
                throw Exception('Link item failed: ${linkBody['error']}');
              }

              // 3. Attach barcode to current run node
              await repo.attachBarcodeToRunNode(
                runId: runProvider.runId!,
                nodeId: node.id,
                barcode: childBarcode,
                quantity: quantity,
              );

              runProvider.triggerRefresh();
            }),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeTransitionsCard(
    ProcessNode node,
    ProductionRunProvider runProvider,
    ProductionProvider prodProvider,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x11FFFFFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildTransitionButton(
                  label: 'ACTIVE',
                  color: const Color(0xFF2563EB),
                  onTap: () => _updateNodeRunStatus(node, NodeRunStatus.active, runProvider, prodProvider),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTransitionButton(
                  label: 'SKIP',
                  color: const Color(0xFF64748B),
                  onTap: () => _updateNodeRunStatus(node, NodeRunStatus.skipped, runProvider, prodProvider),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTransitionButton(
                  label: 'DONE',
                  color: const Color(0xFF10B981),
                  onTap: () => _updateNodeRunStatus(node, NodeRunStatus.done, runProvider, prodProvider),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTransitionButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }

  Future<void> _updateNodeRunStatus(
    ProcessNode node,
    NodeRunStatus newStatus,
    ProductionRunProvider runProvider,
    ProductionProvider prodProvider,
  ) async {
    await _runSimulationAction(() async {
      final repo = context.read<PipelineRunRepository>();
      final runId = runProvider.runId!;

      await repo.updateNodeStatus(
        runId: runId,
        nodeId: node.id,
        status: newStatus,
      );

      // Synced state updates to providers
      if (newStatus == NodeRunStatus.active) {
        prodProvider.startRun();
        runProvider.startRun(runId: runId);
      } else if (newStatus == NodeRunStatus.skipped) {
        prodProvider.skipNode(node.id);
      } else if (newStatus == NodeRunStatus.done) {
        // Mock yields
        prodProvider.incrementYield(1);
        await runProvider.completeStage();
        prodProvider.initiateClosure();
        prodProvider.completeClosure();
      }

      runProvider.triggerRefresh();
    });
  }
}

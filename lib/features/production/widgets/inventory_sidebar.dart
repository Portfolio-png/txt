import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:core_erp/features/inventory/domain/material_record.dart';
import 'package:core_erp/features/inventory/domain/inventory_control_tower.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import '../../production_pipelines/domain/material_batch.dart' show fmtQty;
import '../providers/production_run_provider.dart';
import '../providers/production_provider.dart';
import '../providers/batch_flow_provider.dart';
import 'stage_reconciliation_dialog.dart';
import '../../production_pipelines/domain/process_node.dart';
import '../../production_pipelines/data/repositories/pipeline_run_repository.dart';
import '../../production_pipelines/domain/pipeline_run.dart';
import '../../production_pipelines/domain/node_run_status.dart';
import 'package:collection/collection.dart';

class InventorySidebar extends StatefulWidget {
  const InventorySidebar({super.key});

  @override
  State<InventorySidebar> createState() => _InventorySidebarState();
}

class _InventorySidebarState extends State<InventorySidebar> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  int _activeTab = 0; // 0: Assign Stock, 1: Reconcile
  String? _lastSelectedNodeId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<InventoryProvider>().initialize();
        context.read<GroupsProvider>().initialize();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchChanged(String value) {
    setState(() => _query = value.trim().toLowerCase());
  }

  void _clearSearch() {
    _searchController.clear();
    _handleSearchChanged('');
  }

  bool _matchesSearch(MaterialRecord material) {
    if (_query.isEmpty) return true;

    final searchableText = [
      material.barcode,
      material.name,
      material.type,
      material.grade,
      material.thickness,
      material.supplier,
      material.location,
      material.unit,
      material.notes,
      material.displayStock,
      material.createdBy,
      material.workflowStatus,
      material.kind,
      material.parentBarcode ?? '',
      material.linkedChildBarcodes.join(' '),
    ].join(' ').toLowerCase();

    return searchableText.contains(_query);
  }

  @override
  Widget build(BuildContext context) {
    final prodProvider = context.watch<ProductionProvider>();
    if (prodProvider.selectedNodeId != _lastSelectedNodeId) {
      _lastSelectedNodeId = prodProvider.selectedNodeId;
      if (_lastSelectedNodeId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _activeTab != 1) setState(() => _activeTab = 1);
        });
      }
    }

    final provider = context.watch<InventoryProvider>();
    final groupsProvider = context.watch<GroupsProvider>();
    
    // Only groups and sub groups of raw materials
    final availableMaterials = provider.materials
        .where((m) => m.onHand > 0 && m.materialClass == MaterialClass.rawMaterial)
        .toList();
    final materials = availableMaterials.where(_matchesSearch).toList();
    final isSearching = _query.isNotEmpty;

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(left: BorderSide(color: Color(0xFFE2E8F0))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(-2, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                _buildTab(0, 'Assign Stock', Icons.inventory_2_rounded),
                const SizedBox(width: 4),
                _buildTab(1, 'Reconcile', Icons.fact_check_rounded),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          Expanded(
            child: _activeTab == 0
                ? _buildAssignStockTab(provider, groupsProvider, materials, availableMaterials, isSearching)
                : _buildReconcileTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignStockTab(
    InventoryProvider provider,
    GroupsProvider groupsProvider,
    List<MaterialRecord> materials,
    List<MaterialRecord> availableMaterials,
    bool isSearching,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: _buildSearchField(isSearching),
        ),
        Expanded(
          child: _buildStockContent(provider, groupsProvider, materials, availableMaterials),
        ),
      ],
    );
  }

  Widget _buildReconcileTab() {
    final runProvider = context.watch<ProductionRunProvider>();
    final prodProvider = context.watch<ProductionProvider>();
    final selectedNodeId = prodProvider.selectedNodeId;

    if (selectedNodeId == null || runProvider.runId == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Select a stage to reconcile',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
          ),
        ),
      );
    }
    
    // Find the node
    final node = prodProvider.template.nodes.firstWhere((n) => n.id == selectedNodeId);
    
    return _ReconcilePanel(node: node);
  }


  Widget _buildTab(int index, String label, IconData icon) {
    final isActive = _activeTab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _activeTab = index),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFFEFF4FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isActive ? const Color(0xFF3B82F6) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isActive ? const Color(0xFF2563EB) : const Color(0xFF64748B)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                    color: isActive ? const Color(0xFF1E3A8A) : const Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(bool isSearching) {
    return SizedBox(
      height: 42,
      child: TextField(
        key: const ValueKey('assign-stock-search-field'),
        controller: _searchController,
        onChanged: _handleSearchChanged,
        textInputAction: TextInputAction.search,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF0F172A),
        ),
        decoration: InputDecoration(
          hintText: 'Search stock, barcode, supplier',
          hintStyle: const TextStyle(
            color: Color(0xFF94A3B8),
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 18,
            color: Color(0xFF64748B),
          ),
          suffixIcon: isSearching
              ? IconButton(
                  tooltip: 'Clear stock search',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: const Color(0xFF64748B),
                  onPressed: _clearSearch,
                )
              : null,
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.4),
          ),
        ),
      ),
    );
  }

  Widget _buildStockContent(
    InventoryProvider provider,
    GroupsProvider groupsProvider,
    List<MaterialRecord> materials,
    List<MaterialRecord> availableMaterials,
  ) {
    if (provider.isLoading || groupsProvider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (materials.isEmpty) {
      return Center(
        child: Text(
          availableMaterials.isEmpty
              ? 'No available stock.'
              : 'No stock matches this search.',
          style: const TextStyle(color: Color(0xFF94A3B8)),
        ),
      );
    }
    
    final grouped = <String, List<MaterialRecord>>{};
    for (final m in materials) {
      final groupName = m.linkedGroupId != null
          ? groupsProvider.findById(m.linkedGroupId)?.name ?? 'Ungrouped'
          : m.type.isNotEmpty ? m.type : 'Ungrouped';
      grouped.putIfAbsent(groupName, () => []).add(m);
    }
    final sortedGroups = grouped.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final groupName in sortedGroups) ...[
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 12, bottom: 8),
            child: Text(
              groupName.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF64748B),
                letterSpacing: 0.6,
              ),
            ),
          ),
          for (final material in grouped[groupName]!) ...[
            Draggable<MaterialRecord>(
              data: material,
              feedback: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(8),
                child: Opacity(
                  opacity: 0.85,
                  child: SizedBox(
                    width: 280,
                    child: _MaterialCard(material: material),
                  ),
                ),
              ),
              childWhenDragging: Opacity(
                opacity: 0.3,
                child: _MaterialCard(material: material),
              ),
              child: _MaterialCard(material: material),
            ),
          ],
        ],
      ],
    );
  }
}

class _ReconcilePanel extends StatelessWidget {
  const _ReconcilePanel({required this.node});

  final ProcessNode node;

  @override
  Widget build(BuildContext context) {
    final runProvider = context.watch<ProductionRunProvider>();
    final repo = context.read<PipelineRunRepository>();
    final isDone = node.status.toLowerCase() == 'done' || node.status.toLowerCase() == 'completed';
    final isStarted = node.status.toLowerCase() == 'active' || node.status.toLowerCase() == 'running';

    return Column(
      children: [
        if (!isDone && node.processType != 'Input' && node.processType != 'Output')
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: isStarted
                    ? null
                    : () async {
                        try {
                          await repo.updateNodeStatus(
                            runId: runProvider.runId!,
                            nodeId: node.id,
                            status: NodeRunStatus.active,
                          );
                          runProvider.triggerRefresh();
                          if (context.mounted) {
                            context.read<ProductionProvider>().setNodeStatus(node.id, 'Active');
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed to start: $e'), backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: Text(isStarted ? 'Stage Started' : 'Start Stage'),
                style: FilledButton.styleFrom(
                  backgroundColor: isStarted ? Colors.grey : const Color(0xFF2563EB),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
        Expanded(
          child: StageReconciliationDialog(
      // Removed dynamic key to preserve state between node switches
      node: node,
      runId: runProvider.runId!,
      // Pass null to onClose to render inline
      onClose: () {}, 
      onCommitted: (result) async {
        try {
          final template = context.read<ProductionProvider>().template;
          final nextFlow = template.flows.firstWhereOrNull((f) => f.fromNodeId == node.id);
          final batchProvider = context.read<BatchFlowProvider>();
          batchProvider.autoAdvanceBatches(
            runId: runProvider.runId!,
            nodeId: node.id,
            loss: result.loss,
            scrap: result.scrapLogged,
            leftover: result.leftoverReturned,
            output: result.output,
            nextNodeId: nextFlow?.toNodeId,
          );

          await repo.saveBatches(
            runId: runProvider.runId!,
            batches: batchProvider.batchesForRun(runProvider.runId!),
          );

          await repo.updateNodeStatus(
            runId: runProvider.runId!,
            nodeId: node.id,
            status: NodeRunStatus.done,
          );
          runProvider.triggerRefresh();
          if (context.mounted) {
            context.read<ProductionProvider>().setNodeStatus(node.id, 'Done');
          }
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Stage marked as done')),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to update stage: $e'), backgroundColor: Colors.red),
            );
          }
        }
      },
    ),
  ),
      ],
    );
  }
}

class _MaterialCard extends StatelessWidget {
  const _MaterialCard({required this.material});

  final MaterialRecord material;

  @override
  Widget build(BuildContext context) {
    final inPipeline = material.linkedPipelineCount > 0;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFEFF4FF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: inPipeline ? const Color(0xFFFBBF24) : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: const Icon(
            Icons.inventory_2_rounded,
            size: 18,
            color: Color(0xFF3B82F6),
          ),
        ),
        title: Text(
          material.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0F172A),
          ),
        ),
        subtitle: Row(
          children: [
            Flexible(
              child: Text(
                material.barcode,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF64748B),
                  fontFamily: 'monospace',
                ),
              ),
            ),
            if (inPipeline) ...[
              const SizedBox(width: 6),
              const _PipelinePill(),
            ],
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${fmtQty(material.onHand)} ${material.unit}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
        ),
      ),
    );
  }
}

class _PipelinePill extends StatelessWidget {
  const _PipelinePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFFFBBF24).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'In use',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: Color(0xFFB45309),
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}







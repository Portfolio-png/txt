import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:core_erp/features/inventory/domain/material_record.dart';
import '../../production_pipelines/domain/material_batch.dart' show fmtQty;
import '../providers/production_run_provider.dart';
import 'stage_reconciliation_dialog.dart';

class InventorySidebar extends StatefulWidget {
  const InventorySidebar({super.key, this.reconcile});

  /// When set, the reconcile form docks into this sidebar (SolidWorks-style)
  /// above the stock list instead of opening a centred dialog. The owning
  /// screen sources it from [ProductionRunProvider.reconcileRequest].
  final ReconcileRequest? reconcile;

  @override
  State<InventorySidebar> createState() => _InventorySidebarState();
}

class _InventorySidebarState extends State<InventorySidebar> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InventoryProvider>().initialize();
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
    final provider = context.watch<InventoryProvider>();
    final reconcile = widget.reconcile;
    final availableMaterials = provider.materials
        .where((m) => m.onHand > 0)
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Assign Stock',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Drag materials to pipeline stages to assign specific inventory.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          // SolidWorks-style feature tree: collapsible sections, each its own
          // task. The whole tree scrolls so sections size to their content.
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                if (reconcile != null)
                  _SidebarSection(
                    title: 'Reconcile',
                    icon: Icons.fact_check_rounded,
                    child: _ReconcilePanel(request: reconcile),
                  ),
                _SidebarSection(
                  title: 'Stock',
                  icon: Icons.inventory_2_rounded,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSearchField(isSearching),
                      const SizedBox(height: 12),
                      _buildStockContent(provider, materials, availableMaterials),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
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
    List<MaterialRecord> materials,
    List<MaterialRecord> availableMaterials,
  ) {
    if (provider.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (materials.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            availableMaterials.isEmpty
                ? 'No available stock.'
                : 'No stock matches this search.',
            style: const TextStyle(color: Color(0xFF94A3B8)),
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final material in materials) ...[
          Draggable<MaterialRecord>(
            data: material,
            feedback: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
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
          if (material != materials.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// A collapsible feature-tree section (SolidWorks-style) with a header row and
/// a chevron. Built on the native [ExpansionTile] — no custom accordion.
class _SidebarSection extends StatelessWidget {
  const _SidebarSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(
      // Drop the default top/bottom dividers ExpansionTile draws when open.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: true,
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: Icon(icon, size: 18, color: const Color(0xFF64748B)),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
            letterSpacing: 0.3,
          ),
        ),
        children: [child],
      ),
    );
  }
}

/// Hosts the [StageReconciliationDialog] inline (no Dialog chrome) and wires its
/// commit/cancel back to the run provider that opened the request.
class _ReconcilePanel extends StatelessWidget {
  const _ReconcilePanel({required this.request});

  final ReconcileRequest request;

  @override
  Widget build(BuildContext context) {
    final runProvider = context.read<ProductionRunProvider>();
    return StageReconciliationDialog(
      key: ValueKey(
        'reconcile-${request.node.id}-'
        '${request.batchBarcode ?? 'stage'}-${request.runId}',
      ),
      node: request.node,
      runId: request.runId,
      batchOutput: request.batchOutput,
      batchAllottedMax: request.batchAllottedMax,
      batchReconcileQty: request.batchReconcileQty,
      batchUnit: request.batchUnit,
      batchBarcode: request.batchBarcode,
      batchLabel: request.batchLabel,
      onCommitted: runProvider.submitReconcile,
      onClose: runProvider.cancelReconcile,
    );
  }
}

class _MaterialCard extends StatelessWidget {
  const _MaterialCard({required this.material});

  final MaterialRecord material;

  @override
  Widget build(BuildContext context) {
    // Stock attached to one or more pipeline runs stays watchable here but is
    // flagged yellow so it's obvious it's already committed.
    final inPipeline = material.linkedPipelineCount > 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: inPipeline ? const Color(0xFFFBBF24) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF4FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.inventory_2_rounded,
              size: 18,
              color: Color(0xFF3B82F6),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  material.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        material.barcode,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
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
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
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
        ],
      ),
    );
  }
}

/// Small yellow pill marking stock already committed to a pipeline run.
class _PipelinePill extends StatelessWidget {
  const _PipelinePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFBBF24),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'In pipeline',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: Color(0xFF78350F),
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:core_erp/features/inventory/domain/material_record.dart';

class InventorySidebar extends StatefulWidget {
  const InventorySidebar({super.key});

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
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Assign Stock',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Drag materials to pipeline stages to assign specific inventory.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 14),
                SizedBox(
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
                        borderSide: const BorderSide(
                          color: Color(0xFF2563EB),
                          width: 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          Expanded(
            child: provider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : materials.isEmpty
                ? Center(
                    child: Text(
                      availableMaterials.isEmpty
                          ? 'No available stock.'
                          : 'No stock matches this search.',
                      style: const TextStyle(color: Color(0xFF94A3B8)),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.85,
                        ),
                    itemCount: materials.length,
                    itemBuilder: (context, index) {
                      final material = materials[index];
                      return Draggable<MaterialRecord>(
                        data: material,
                        feedback: Material(
                          elevation: 8,
                          borderRadius: BorderRadius.circular(12),
                          child: Opacity(
                            opacity: 0.8,
                            child: SizedBox(
                              width: 140,
                              height: 160,
                              child: _MaterialCard(material: material),
                            ),
                          ),
                        ),
                        childWhenDragging: Opacity(
                          opacity: 0.3,
                          child: _MaterialCard(material: material),
                        ),
                        child: _MaterialCard(material: material),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _MaterialCard extends StatelessWidget {
  const _MaterialCard({required this.material});

  final MaterialRecord material;

  @override
  Widget build(BuildContext context) {
    // Stock attached to one or more pipeline runs stays watchable here but is
    // flagged with a yellow headband so it's obvious it's already committed.
    final inPipeline = material.linkedPipelineCount > 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: inPipeline ? const Color(0xFFFBBF24) : const Color(0xFFE2E8F0),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (inPipeline)
            _PipelineHeadband(count: material.linkedPipelineCount),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.inventory_2_rounded,
                        size: 16,
                        color: Color(0xFF3B82F6),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          material.barcode,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF64748B),
                            fontFamily: 'monospace',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Text(
                      material.name,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.layers_rounded,
                          size: 12,
                          color: Color(0xFF64748B),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${material.onHand} ${material.unit}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The yellow strip across the top of an inventory card that marks stock as
/// committed to one or more pipeline runs.
class _PipelineHeadband extends StatelessWidget {
  const _PipelineHeadband({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      color: const Color(0xFFFBBF24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.account_tree_rounded,
            size: 11,
            color: Color(0xFF78350F),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              count > 1 ? 'In $count pipelines' : 'In pipeline',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF78350F),
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

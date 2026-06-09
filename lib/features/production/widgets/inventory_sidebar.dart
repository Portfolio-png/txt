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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InventoryProvider>().initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    final materials = provider.materials.where((m) => m.onHand > 0).toList();

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
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(20.0),
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
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
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
                    ? const Center(
                        child: Text(
                          'No available stock.',
                          style: TextStyle(color: Color(0xFF94A3B8)),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_rounded, size: 16, color: Color(0xFF3B82F6)),
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
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.layers_rounded, size: 12, color: Color(0xFF64748B)),
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
    );
  }
}

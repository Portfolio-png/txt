import 'package:flutter/material.dart';
import 'package:core_erp/core/theme/soft_erp_theme.dart';
import '../item_master_controller.dart';
import '../sheet_engine.dart';

class ItemMasterSidebar extends StatelessWidget {
  const ItemMasterSidebar({
    super.key,
    required this.controller,
    required this.onSelectSection,
  });

  final ItemMasterController controller;
  final ValueChanged<String> onSelectSection;

  @override
  Widget build(BuildContext context) {
    final groupDraft = controller.groupItemController.draft;
    final groupSheet = controller.groupItemController.sheetDef;

    final itemName = groupDraft.get(3)?.optionLabel ??
        groupDraft.get(3)?.textValue ??
        'New Item';

    final groupPath = SheetEngine.groupPathString(
      groupSheet,
      groupDraft,
      3,
    );

    final partCode = groupDraft.get(5)?.textValue ?? '—';
    final clientName = controller.clientVendorController.draft.get(20)?.optionLabel ?? 'Gold Medal';
    final developedFor = controller.isExternal
        ? 'Developed for: $clientName'
        : 'Developed for: Self';

    return Container(
      width: 268,
      decoration: const BoxDecoration(
        color: Color(0xFFFFFFFF),
        border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Live Identity Summary Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  SoftErpTheme.accent.withValues(alpha: 0.08),
                  const Color(0xFFFFFFFF),
                ],
              ),
              border: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: controller.isSaved
                            ? const Color(0xFFD1FAE5)
                            : const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        controller.isSaved
                            ? 'SAVED #${controller.savedItemId}'
                            : 'NEW RECORD',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: controller.isSaved
                              ? const Color(0xFF065F46)
                              : const Color(0xFF92400E),
                        ),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        partCode,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: SoftErpTheme.accent,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  itemName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  groupPath.isEmpty ? 'Identity under root group' : groupPath,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      controller.isExternal ? Icons.business_rounded : Icons.home_work_rounded,
                      size: 13,
                      color: const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        developedFor,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 2. Sections Navigator
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: const Text(
              'SECTIONS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Color(0xFF94A3B8),
                letterSpacing: 0.8,
              ),
            ),
          ),
          _buildSectionNavTile(
            id: 'group_item',
            title: 'Group Item',
            subtitle: 'Identity, hierarchy & properties',
            icon: Icons.table_rows_rounded,
            isSelected: controller.activeSection == 'group_item',
          ),
          if (controller.isExternal)
            _buildSectionNavTile(
              id: 'client_vendor',
              title: 'Client / Vendor',
              subtitle: 'Party, contact & quotation',
              icon: Icons.storefront_rounded,
              isSelected: controller.activeSection == 'client_vendor',
            ),
          _buildSectionNavTile(
            id: 'die_master',
            title: 'Die Process Master',
            subtitle: 'Press tooling & progressive dies',
            icon: Icons.precision_manufacturing_rounded,
            isSelected: controller.activeSection == 'die_master',
          ),
          _buildSectionNavTile(
            id: 'machine_master',
            title: 'Machines & Routing',
            subtitle: 'Shop floor routing & specs',
            icon: Icons.settings_suggest_rounded,
            isSelected: controller.activeSection == 'machine_master',
          ),

          const Divider(height: 24, thickness: 1, color: Color(0xFFF1F5F9)),

          // 3. Live Column Tree
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'COLUMN TREE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF94A3B8),
                    letterSpacing: 0.8,
                  ),
                ),
                Text(
                  '${groupSheet.columns.length} columns',
                  style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                _buildTreeBranch(
                  label: 'Group: ${groupDraft.get(1)?.optionLabel ?? "—"}',
                  depth: 0,
                  isBold: true,
                ),
                _buildTreeBranch(
                  label: 'Type: ${groupDraft.get(2)?.optionLabel ?? "—"}',
                  depth: 1,
                  isBold: true,
                ),
                _buildTreeBranch(
                  label: 'Part Name: ${groupDraft.get(3)?.optionLabel ?? "—"}',
                  depth: 2,
                  isBold: true,
                  color: SoftErpTheme.accent,
                ),
                _buildTreeBranch(
                  label: 'Part No: ${groupDraft.get(4)?.intValue ?? "—"} (Seq)',
                  depth: 3,
                ),
                _buildTreeBranch(
                  label: 'Code: ${groupDraft.get(5)?.textValue ?? "—"}',
                  depth: 3,
                ),
                const SizedBox(height: 8),
                _buildTreeBranch(
                  label: 'Alloy: ${groupDraft.get(6)?.optionLabel ?? "—"}',
                  depth: 0,
                ),
                _buildTreeBranch(
                  label: 'Thickness: ${groupDraft.get(7)?.textValue ?? "—"}',
                  depth: 0,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionNavTile({
    required String id,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? SoftErpTheme.accent.withValues(alpha: 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(
          icon,
          size: 18,
          color: isSelected ? SoftErpTheme.accent : const Color(0xFF64748B),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? SoftErpTheme.accent : const Color(0xFF1E293B),
          ),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
        ),
        onTap: () => onSelectSection(id),
      ),
    );
  }

  Widget _buildTreeBranch({
    required String label,
    required int depth,
    bool isBold = false,
    Color? color,
  }) {
    return Padding(
      padding: EdgeInsets.only(left: depth * 14.0, top: 3, bottom: 3),
      child: Row(
        children: [
          Icon(
            depth == 0 ? Icons.folder_open_rounded : Icons.subdirectory_arrow_right_rounded,
            size: 13,
            color: color ?? const Color(0xFF94A3B8),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
                color: color ?? const Color(0xFF334155),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../sheet/column_def.dart';
import '../../../../sheet/sheet_binding.dart';
import '../../../../sheet/sheet_controller.dart';
import '../../../../sheet/sheet_draft.dart';
import '../../../../sheet/sheet_engine.dart';
import '../../../../sheet/widgets/part_tabs.dart';
import '../../../groups/presentation/providers/groups_provider.dart';
import '../../domain/item_definition.dart';

/// The user's choice when a save encounters an existing part or duplicate.
enum ExistingPartConflictAction {
  switchToTab,
  useNextPartNo,
  openExistingPart,
  cancel,
}

/// A rich conflict card / dialog presented when attempting to save a part that:
/// 1. Is already open in another tab on the sheet, or
/// 2. Already exists in the Item Master / database (e.g. duplicate identity or
///    Part No collision like "Part No 2 is already used within action › dolly › fd").
///
/// Displays:
/// - Open tab switch action (if open in another tab)
/// - Item Master details (Name, Code, Part No, Group, Material specs: Alloy, Thickness, etc.)
/// - Photo preview / gallery
/// - Creator information (User name, role, timestamp)
/// - Die Process Master details (Linked dies: tool code, die type, maker, where kept)
/// - Machine Master details (Linked machines: asset ID, name, make, capacity)
/// - Action to auto-advance to the next available Part No and save cleanly.
class ExistingPartConflictDialog extends StatelessWidget {
  const ExistingPartConflictDialog({
    super.key,
    this.part,
    required this.draft,
    required this.sheet,
    this.openInTabRow,
    this.nextPartNo,
    this.creatorName,
    this.creatorRole,
    this.conflictMessage,
    this.groupPath,
  });

  final ItemDefinition? part;
  final SheetDraft draft;
  final SheetController sheet;
  final int? openInTabRow;
  final int? nextPartNo;
  final String? creatorName;
  final String? creatorRole;
  final String? conflictMessage;
  final String? groupPath;

  static String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${two(local.day)} ${months[local.month - 1]} ${local.year}, '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Map<String, String> _itemProperties(ItemDefinition? item) {
    if (item == null) return const {};
    final result = <String, String>{};
    for (final node in item.variationTree) {
      if (node.kind == ItemVariationNodeKind.property && !node.isArchived) {
        final values = [
          for (final c in node.children)
            if (!c.isArchived && c.name.trim().isNotEmpty) c.name.trim(),
        ];
        if (values.isNotEmpty) {
          result[node.name.trim()] = values.join(' / ');
        }
      }
    }
    return result;
  }

  Map<String, String> _draftProperties() {
    final result = <String, String>{};
    for (final col in sheet.sheetDef.columns) {
      if (SheetBindsTo.isVariation(col.bindsTo)) {
        final label = SheetEngine.cellLabel(draft, col.id).trim();
        if (label.isNotEmpty) {
          result[col.label.trim()] = label;
        }
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final draftTitle = PartTabs.titleOf(sheet, draft);
    final draftCode = PartTabs.codeOf(sheet, draft);
    final partName = (part?.displayName.trim().isNotEmpty ?? false)
        ? part!.displayName.trim()
        : ((part?.name.trim().isNotEmpty ?? false)
            ? part!.name.trim()
            : draftTitle);
    final partCode = (part?.partCode.trim().isNotEmpty ?? false)
        ? part!.partCode.trim()
        : draftCode;
    final partNo = part?.partNo ??
        sheet.sheetDef.columns
            .where((c) => c.kind == ColumnKind.seq)
            .map((c) => draft.get(c.id)?.intValue)
            .firstOrNull;

    final resolvedGroupPath = groupPath ??
        (part != null
            ? (context.read<GroupsProvider?>()?.findById(part!.groupId)?.name ?? '')
            : '');

    var specs = _itemProperties(part);
    if (specs.isEmpty) {
      specs = _draftProperties();
    }

    final hasTabOpen = openInTabRow != null;
    final otherTabDraft = hasTabOpen ? sheet.draftAt(openInTabRow!) : null;
    final otherTabTitle = hasTabOpen
        ? (otherTabDraft != null
            ? PartTabs.titleOf(sheet, otherTabDraft)
            : 'Tab ${openInTabRow! + 1}')
        : '';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 680,
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header bar
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 20, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFFD97706),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFFDE68A)),
                              ),
                              child: Text(
                                hasTabOpen ? 'TAB ALREADY OPEN' : 'PART ALREADY EXISTS',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFB45309),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          hasTabOpen
                              ? 'This Part is Already Open'
                              : 'Part already exists in Item Master',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: SoftErpTheme.textPrimary,
                          ),
                        ),
                        if (conflictMessage != null && conflictMessage!.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            conflictMessage!,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: SoftErpTheme.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: 'Close',
                    color: const Color(0xFF64748B),
                    onPressed: () => Navigator.of(context).pop(ExistingPartConflictAction.cancel),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: Color(0xFFF1F5F9)),

            // Content body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Banner: If open in another tab
                    if (hasTabOpen) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFC7D2FE)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.tab_rounded, color: Color(0xFF4F46E5), size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Tab ${openInTabRow! + 1} ($otherTabTitle)',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF312E81),
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Tab ${openInTabRow! + 1} holds this exact part in this sheet. You can switch to it directly to avoid duplicate entries.',
                                    style: const TextStyle(
                                      color: Color(0xFF4338CA),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            AppButton(
                              key: const ValueKey('conflict_switch_tab_btn'),
                              label: 'Switch to Tab ${openInTabRow! + 1}',
                              icon: Icons.arrow_forward_rounded,
                              dense: true,
                              onPressed: () => Navigator.of(context).pop(
                                ExistingPartConflictAction.switchToTab,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Card 1: Item Master Details
                    _buildSectionCard(
                      icon: Icons.inventory_2_outlined,
                      iconColor: const Color(0xFF4F46E5),
                      title: 'Item Master Details',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Photo / Thumbnail
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: (part?.photoUrl.isNotEmpty ?? false)
                                      ? Image.network(
                                          part!.photoUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => const Center(
                                            child: Icon(
                                              Icons.broken_image_outlined,
                                              size: 28,
                                              color: Color(0xFF94A3B8),
                                            ),
                                          ),
                                        )
                                      : const Center(
                                          child: Icon(
                                            Icons.inventory_2_outlined,
                                            size: 32,
                                            color: Color(0xFF94A3B8),
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            partName,
                                            style: const TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w800,
                                              color: SoftErpTheme.textPrimary,
                                            ),
                                          ),
                                        ),
                                        if (part != null)
                                          Text(
                                            'Item #${part!.id}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF64748B),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        if (partCode.isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF3E8FF),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: const Color(0xFFE9D5FF)),
                                            ),
                                            child: Text(
                                              partCode,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
                                                color: Color(0xFF6B21A8),
                                              ),
                                            ),
                                          ),
                                        if (partNo != null)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFEFF6FF),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: const Color(0xFFBFDBFE)),
                                            ),
                                            child: Text(
                                              'Part #$partNo',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF1D4ED8),
                                              ),
                                            ),
                                          ),
                                        if (resolvedGroupPath.isNotEmpty)
                                          Text(
                                            resolvedGroupPath,
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                              color: SoftErpTheme.textSecondary,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    // Creator line
                                    Row(
                                      children: [
                                        const Icon(Icons.account_circle_outlined, size: 15, color: Color(0xFF64748B)),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            'Created by: ${creatorName ?? 'Operator'}'
                                            '${creatorRole != null && creatorRole!.isNotEmpty ? ' ($creatorRole)' : ''}'
                                            '${part?.createdAt != null ? ' · ${_formatDate(part!.createdAt)}' : ''}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF64748B),
                                              fontWeight: FontWeight.w500,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          if (specs.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            const Divider(height: 1, color: Color(0xFFE2E8F0)),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final entry in specs.entries)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFFCBD5E1)),
                                    ),
                                    child: Text.rich(
                                      TextSpan(
                                        style: const TextStyle(fontSize: 12, color: SoftErpTheme.textPrimary),
                                        children: [
                                          TextSpan(
                                            text: '${entry.key}: ',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF475569),
                                            ),
                                          ),
                                          TextSpan(
                                            text: entry.value,
                                            style: const TextStyle(fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Card 2: Die Process Master Details
                    _buildSectionCard(
                      icon: Icons.build_circle_outlined,
                      iconColor: const Color(0xFF0F766E),
                      title: 'Die Process Master Details',
                      trailing: part != null
                          ? Text(
                              '${part!.dies.length} ${part!.dies.length == 1 ? 'die' : 'dies'}',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                            )
                          : null,
                      child: (part != null && part!.dies.isNotEmpty)
                          ? Column(
                              children: [
                                for (int i = 0; i < part!.dies.length; i++) ...[
                                  if (i > 0) const Divider(height: 12, color: Color(0xFFE2E8F0)),
                                  _buildDieItem(part!.dies[i]),
                                ],
                              ],
                            )
                          : const Padding(
                              padding: EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                'No dies currently attached to this part in Die Process Master.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Color(0xFF94A3B8),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                    ),

                    const SizedBox(height: 14),

                    // Card 3: Machine Master Details
                    _buildSectionCard(
                      icon: Icons.precision_manufacturing_outlined,
                      iconColor: const Color(0xFF0284C7),
                      title: 'Machine Master Details',
                      trailing: part != null
                          ? Text(
                              '${part!.machines.length} ${part!.machines.length == 1 ? 'machine' : 'machines'}',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                            )
                          : null,
                      child: (part != null && part!.machines.isNotEmpty)
                          ? Column(
                              children: [
                                for (int i = 0; i < part!.machines.length; i++) ...[
                                  if (i > 0) const Divider(height: 12, color: Color(0xFFE2E8F0)),
                                  _buildMachineItem(part!.machines[i]),
                                ],
                              ],
                            )
                          : const Padding(
                              padding: EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                'No machines currently assigned to this part in Machine Master.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Color(0xFF94A3B8),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),

            const Divider(height: 1, color: Color(0xFFF1F5F9)),

            // Action bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: [
                  AppButton(
                    key: const ValueKey('conflict_cancel_btn'),
                    label: 'Cancel',
                    variant: AppButtonVariant.secondary,
                    dense: true,
                    onPressed: () => Navigator.of(context).pop(ExistingPartConflictAction.cancel),
                  ),
                  const SizedBox(width: 12),
                  // All the room left of Cancel, buttons to the right; they
                  // fold onto a second line in a narrow window, never clipped.
                  // (A Spacer beside a Flexible gave them only half the room.)
                  Expanded(
                    child: Wrap(
                        alignment: WrapAlignment.end,
                        runSpacing: 8,
                        children: [
                          if (part != null && !hasTabOpen) ...[
                            AppButton(
                              key: const ValueKey('conflict_open_part_btn'),
                              label: 'Open in Sheet',
                              icon: Icons.open_in_new_rounded,
                              variant: AppButtonVariant.secondary,
                              dense: true,
                              onPressed: () => Navigator.of(context).pop(
                                ExistingPartConflictAction.openExistingPart,
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          if (nextPartNo != null) ...[
                            AppButton(
                              key: const ValueKey('conflict_use_next_no_btn'),
                              label: 'Use Next Part No ($nextPartNo)',
                              icon: Icons.auto_awesome_rounded,
                              variant: AppButtonVariant.primary,
                              dense: true,
                              onPressed: () => Navigator.of(context).pop(
                                ExistingPartConflictAction.useNextPartNo,
                              ),
                            ),
                          ] else if (hasTabOpen) ...[
                            AppButton(
                              key: const ValueKey('conflict_primary_switch_btn'),
                              label: 'Switch to Tab ${openInTabRow! + 1}',
                              icon: Icons.arrow_forward_rounded,
                              variant: AppButtonVariant.primary,
                              dense: true,
                              onPressed: () => Navigator.of(context).pop(
                                ExistingPartConflictAction.switchToTab,
                              ),
                            ),
                          ],
                        ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    Widget? trailing,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: SoftErpTheme.textPrimary,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildDieItem(ItemDieLink die) {
    final type = die.dieTypeLabel.isNotEmpty
        ? die.dieTypeLabel
        : (die.dieType.isNotEmpty ? die.dieType : 'General');
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFCCFBF1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF99F6E4)),
          ),
          child: Text(
            die.toolCode.isNotEmpty ? die.toolCode : 'Die #${die.id}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F766E),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Type: $type · Maker: ${die.madeBy.isNotEmpty ? die.madeBy : 'In-house'}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: SoftErpTheme.textPrimary,
                ),
              ),
              if (die.whereKept.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  'Location: ${die.whereKept}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMachineItem(ItemMachineLink machine) {
    final label = machine.name.isNotEmpty
        ? machine.name
        : (machine.machineType.isNotEmpty ? machine.machineType : 'Machine');
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFE0F2FE),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFBAE6FD)),
          ),
          child: Text(
            machine.assetId.isNotEmpty ? machine.assetId : 'Mach #${machine.id}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0369A1),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$label · ${machine.machineMake.isNotEmpty ? machine.machineMake : 'Standard'}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: SoftErpTheme.textPrimary,
                ),
              ),
              if (machine.capacityKgf != null && machine.capacityKgf! > 0) ...[
                const SizedBox(height: 2),
                Text(
                  'Capacity: ${(machine.capacityKgf! / 1000).toStringAsFixed(1)} T · SPM: ${machine.strokesPerMinute ?? '-'}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

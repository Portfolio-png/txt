import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/core/widgets/app_button.dart';
import 'package:core_erp/core/widgets/app_empty_state.dart';
import 'package:core_erp/core/widgets/soft_master_data.dart';
import 'package:core_erp/core/widgets/soft_primitives.dart';
import '../../domain/die.dart';
import '../providers/die_provider.dart';
import 'die_form_screen.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';

class DiesScreen extends StatefulWidget {
  const DiesScreen({super.key});

  static void openDieEditor(BuildContext context, {Die? die}) {
    showDieFormDialog(context, die: die);
  }

  @override
  State<DiesScreen> createState() => _DiesScreenState();
}

class _DiesScreenState extends State<DiesScreen> {
  bool _isGridView = false;
  double _cardScale = 1.0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isGridView = prefs.getBool('dies_grid_view') ?? false;
        _cardScale = prefs.getDouble('dies_card_scale') ?? 1.0;
      });
    }
  }

  Future<void> _saveGridView(bool val) async {
    setState(() => _isGridView = val);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dies_grid_view', val);
  }

  Future<void> _saveCardScale(double val) async {
    setState(() => _cardScale = val);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('dies_card_scale', val);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<DiesProvider, GroupsProvider>(
      builder: (context, provider, groupsProvider, _) {
        if (provider.isLoading && provider.dies.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        final groupNames = <int, String>{
          for (final g in groupsProvider.groups) g.id: g.name,
        };
        final dies = provider.filteredDiesWithGroups(groupNames);

        return SoftMasterDataPage(
          title: 'Dies & Tooling',
          subtitle: 'Manage dies, lifecycle strokes, and machine compatibilities.',
          action: AppButton(
            label: 'Add Die',
            icon: Icons.add,
            onPressed: () => DiesScreen.openDieEditor(context),
          ),
          toolbar: _DiesToolbar(
            isGridView: _isGridView,
            cardScale: _cardScale,
            onToggleView: () => _saveGridView(!_isGridView),
            onCardScaleChanged: _saveCardScale,
          ),
          body: dies.isEmpty
              ? const AppEmptyState(
                  title: 'No dies found',
                  message: 'Add your first die to track tooling.',
                  icon: Icons.build_circle_outlined,
                )
              : _isGridView
                  ? _DiesGrid(dies: dies, scale: _cardScale)
                  : _DiesTable(dies: dies),
        );
      },
    );
  }
}

// ─── Toolbar ───────────────────────────────────────────────────────────────────

class _DiesToolbar extends StatelessWidget {
  const _DiesToolbar({
    required this.isGridView,
    required this.cardScale,
    required this.onToggleView,
    required this.onCardScaleChanged,
  });

  final bool isGridView;
  final double cardScale;
  final VoidCallback onToggleView;
  final ValueChanged<double> onCardScaleChanged;

  @override
  Widget build(BuildContext context) {
    return SoftMasterToolbar(
      children: [
        _ViewToggleButton(isGridView: isGridView, onTap: onToggleView),
        if (isGridView)
          _CardScaleControl(scale: cardScale, onChanged: onCardScaleChanged),
      ],
    );
  }
}

class _ViewToggleButton extends StatelessWidget {
  const _ViewToggleButton({required this.isGridView, required this.onTap});
  final bool isGridView;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: SoftErpTheme.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: SoftErpTheme.border),
            boxShadow: SoftErpTheme.insetShadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isGridView ? Icons.view_headline_rounded : Icons.grid_view_rounded,
                size: 18,
                color: SoftErpTheme.textPrimary,
              ),
              const SizedBox(width: 10),
              Text(
                isGridView ? 'List View' : 'Card View',
                style: const TextStyle(
                    color: SoftErpTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardScaleControl extends StatelessWidget {
  const _CardScaleControl({required this.scale, required this.onChanged});
  final double scale;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: SizedBox(
        width: 160,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_size_select_large_rounded,
                size: 18, color: SoftErpTheme.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: const Color(0xFF2563EB),
                  thumbColor: const Color(0xFF2563EB),
                  overlayColor: const Color(0xFF2563EB).withValues(alpha: 0.18),
                  inactiveTrackColor: const Color(0xFFE2E8F0),
                  trackHeight: 2.5,
                ),
                child: Slider.adaptive(
                  value: scale,
                  min: 0.5,
                  max: 2.0,
                  onChanged: onChanged,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Grid ──────────────────────────────────────────────────────────────────────

class _DiesGrid extends StatelessWidget {
  const _DiesGrid({required this.dies, required this.scale});
  final List<Die> dies;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = 260.0 * scale;
        final cardHeight = 290.0 * scale;
        final spacing = constraints.maxWidth >= 1200 ? 18.0 : 14.0;

        return GridView.builder(
          padding: const EdgeInsets.only(bottom: 12),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: cardWidth,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: cardWidth / cardHeight,
          ),
          itemCount: dies.length,
          itemBuilder: (context, index) => _DieCard(die: dies[index]),
        );
      },
    );
  }
}

class _DieCard extends StatefulWidget {
  const _DieCard({required this.die});
  final Die die;

  @override
  State<_DieCard> createState() => _DieCardState();
}

class _DieCardState extends State<_DieCard> {
  bool _hovered = false;

  Die get die => widget.die;

  void _duplicate(BuildContext context) {
    final cloned = Die(
      id: '',
      name: '${die.name} (Copy)',
      toolCode: '${die.toolCode} (Copy)',
      photoUrls: List.from(die.photoUrls),
      operationalNotes: die.operationalNotes,
      compatibleMachineGroupIds: List.from(die.compatibleMachineGroupIds),
      storageLocation: die.storageLocation,
      numberOfCavities: die.numberOfCavities,
      strokeCount: 0,
      maxStrokes: die.maxStrokes,
      physicalSpecs: List.from(die.physicalSpecs),
      status: die.status,
      ownership: die.ownership,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    DiesScreen.openDieEditor(context, die: cloned);
  }

  void _edit(BuildContext context) => DiesScreen.openDieEditor(context, die: die);

  void _delete(BuildContext context) =>
      context.read<DiesProvider>().deleteDie(die.id);

  @override
  Widget build(BuildContext context) {
    final statusColors = _dieStatusColors(die.status);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyD, control: true): () =>
              _duplicate(context),
        },
        child: Focus(
          child: GestureDetector(
            onTap: () => _edit(context),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _hovered
                      ? SoftErpTheme.accent.withValues(alpha: 0.5)
                      : const Color(0xFFE6E8F0),
                  width: _hovered ? 1.5 : 1.0,
                ),
                boxShadow: _hovered
                    ? [
                        BoxShadow(
                          color: SoftErpTheme.accent.withValues(alpha: 0.08),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : [
                        const BoxShadow(
                          color: Color(0x10000000),
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 3,
                          child: die.photoUrls.isNotEmpty
                              ? Image.network(
                                  die.photoUrls.first,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, _) =>
                                      _buildPlaceholder(),
                                )
                              : _buildPlaceholder(),
                        ),
                        Container(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                          color: const Color(0xFFF8F8FC),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                die.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                  color: SoftErpTheme.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                die.toolCode,
                                style: const TextStyle(
                                  color: SoftErpTheme.textSecondary,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              SoftStatusPill(
                                label: die.status.name.toUpperCase(),
                                background: statusColors.$1,
                                textColor: statusColors.$2,
                                borderColor: statusColors.$3,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Positioned(
                      right: 8,
                      bottom: 48,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 150),
                        opacity: _hovered ? 1.0 : 0.0,
                        child: _CardMoreButton(
                          onEdit: () => _edit(context),
                          onDuplicate: () => _duplicate(context),
                          onDelete: () => _delete(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFFF3F4F6),
      child: const Center(
        child: Icon(Icons.build_circle_outlined,
            color: Color(0xFF9CA3AF), size: 48),
      ),
    );
  }
}

(Color, Color, Color) _dieStatusColors(DieStatus status) {
  return switch (status) {
    DieStatus.ready => (
        const Color(0xFFECFDF5),
        const Color(0xFF0F766E),
        const Color(0xFFBFEAD8),
      ),
    DieStatus.inProduction => (
        const Color(0xFFEFF6FF),
        const Color(0xFF1D4ED8),
        const Color(0xFFBFDBFE),
      ),
    DieStatus.needsRepair => (
        const Color(0xFFFEF2F2),
        const Color(0xFF991B1B),
        const Color(0xFFFECACA),
      ),
    DieStatus.obsolete => (
        const Color(0xFFF3F4F6),
        const Color(0xFF4B5563),
        const Color(0xFFE5E7EB),
      ),
  };
}

class _CardMoreButton extends StatelessWidget {
  const _CardMoreButton({
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
  });

  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_CardAction>(
      onSelected: (action) {
        switch (action) {
          case _CardAction.edit:
            onEdit();
          case _CardAction.duplicate:
            onDuplicate();
          case _CardAction.delete:
            onDelete();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: _CardAction.edit,
          child: _MenuEntry(icon: Icons.edit_outlined, label: 'Edit'),
        ),
        const PopupMenuItem(
          value: _CardAction.duplicate,
          child: _MenuEntry(
              icon: Icons.copy_outlined,
              label: 'Duplicate',
              hint: 'Ctrl+D'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _CardAction.delete,
          child: _MenuEntry(
              icon: Icons.delete_outline,
              label: 'Delete',
              destructive: true),
        ),
      ],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 4,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(Icons.more_horiz_rounded,
            size: 16, color: SoftErpTheme.textPrimary),
      ),
    );
  }
}

enum _CardAction { edit, duplicate, delete }

class _MenuEntry extends StatelessWidget {
  const _MenuEntry({
    required this.icon,
    required this.label,
    this.hint,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final String? hint;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color =
        destructive ? const Color(0xFFDC2626) : SoftErpTheme.textPrimary;
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: color)),
        ),
        if (hint != null)
          Text(hint!,
              style: const TextStyle(
                  fontSize: 11,
                  color: SoftErpTheme.textSecondary,
                  fontWeight: FontWeight.w500)),
      ],
    );
  }
}

// ─── Table ─────────────────────────────────────────────────────────────────────

class _DiesTable extends StatelessWidget {
  const _DiesTable({required this.dies});
  final List<Die> dies;

  @override
  Widget build(BuildContext context) {
    return SoftMasterTable(
      minWidth: 1080,
      columns: const [
        SoftTableColumn('Photo', flex: 1),
        SoftTableColumn('Die Name', flex: 2),
        SoftTableColumn('Tool Code', flex: 2),
        SoftTableColumn('Lifecycle', flex: 2),
        SoftTableColumn('Status', flex: 1),
        SoftTableColumn('Actions', flex: 2),
      ],
      itemCount: dies.length,
      rowBuilder: (context, index) => _DieRow(die: dies[index]),
    );
  }
}

class _DieRow extends StatelessWidget {
  const _DieRow({required this.die});
  final Die die;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<DiesProvider>();
    final statusColors = _dieStatusColors(die.status);

    return SoftMasterRow(
      children: [
        Expanded(
          flex: 1,
          child: die.photoUrls.isNotEmpty
              ? Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.centerLeft,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      die.photoUrls.first,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, _) => _buildThumb(),
                    ),
                  ),
                )
              : Container(
                  alignment: Alignment.centerLeft, child: _buildThumb()),
        ),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SoftInlineText(die.name, weight: FontWeight.w700),
              if (die.ownership == DieOwnership.customerOwned) ...[
                const SizedBox(height: 4),
                const SoftInlineText('Customer Owned',
                    color: Color(0xFF6B7280), weight: FontWeight.w600),
              ],
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: SoftInlineText(die.toolCode),
        ),
        // Lifecycle / stroke progress bar
        Expanded(
          flex: 2,
          child: _StrokeBar(strokeCount: die.strokeCount, maxStrokes: die.maxStrokes),
        ),
        Expanded(
          flex: 1,
          child: Align(
            alignment: Alignment.centerLeft,
            child: SoftStatusPill(
              label: die.status.name.toUpperCase(),
              background: statusColors.$1,
              textColor: statusColors.$2,
              borderColor: statusColors.$3,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SoftActionLink(
                label: 'Duplicate',
                onTap: () {
                  final cloned = Die(
                    id: '',
                    name: '${die.name} (Copy)',
                    toolCode: '${die.toolCode} (Copy)',
                    photoUrls: List.from(die.photoUrls),
                    operationalNotes: die.operationalNotes,
                    compatibleMachineGroupIds:
                        List.from(die.compatibleMachineGroupIds),
                    storageLocation: die.storageLocation,
                    numberOfCavities: die.numberOfCavities,
                    strokeCount: 0,
                    maxStrokes: die.maxStrokes,
                    physicalSpecs: List.from(die.physicalSpecs),
                    status: die.status,
                    ownership: die.ownership,
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                  );
                  DiesScreen.openDieEditor(context, die: cloned);
                },
              ),
              SoftActionLink(
                label: 'Edit',
                onTap: () => DiesScreen.openDieEditor(context, die: die),
              ),
              SoftActionLink(
                label: 'Delete',
                onTap: () async => provider.deleteDie(die.id),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildThumb() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: const Icon(Icons.build_circle_outlined,
          color: Color(0xFF9CA3AF), size: 24),
    );
  }
}

/// Stroke lifecycle bar. Shows usage progress and count/max label.
class _StrokeBar extends StatelessWidget {
  const _StrokeBar({this.strokeCount, this.maxStrokes});

  final int? strokeCount;
  final int? maxStrokes;

  @override
  Widget build(BuildContext context) {
    if (strokeCount == null && maxStrokes == null) {
      return const SoftInlineText('—');
    }

    final count = strokeCount ?? 0;
    final max = maxStrokes;
    final fraction = (max != null && max > 0)
        ? (count / max).clamp(0.0, 1.0)
        : null;

    // Pick color based on wear level
    final barColor = fraction == null
        ? const Color(0xFF94A3B8)
        : fraction >= 0.9
            ? const Color(0xFFDC2626)
            : fraction >= 0.7
                ? const Color(0xFFD97706)
                : const Color(0xFF2563EB);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          max != null ? '$count / $max' : '$count',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: SoftErpTheme.textPrimary,
          ),
        ),
        if (fraction != null) ...[
          const SizedBox(height: 5),
          LayoutBuilder(
            builder: (context, constraints) => Container(
              height: 5,
              width: constraints.maxWidth * 0.85,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(4),
              ),
              child: FractionallySizedBox(
                widthFactor: fraction,
                alignment: Alignment.centerLeft,
                child: Container(
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${(fraction * 100).toStringAsFixed(0)}% used',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: barColor,
            ),
          ),
        ],
      ],
    );
  }
}

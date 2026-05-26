import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/soft_master_data.dart';
import '../../../../core/widgets/soft_primitives.dart';
import '../../domain/machine.dart';
import '../providers/machine_provider.dart';
import 'machine_form_screen.dart';
import '../../../../features/groups/presentation/providers/groups_provider.dart';

class MachinesScreen extends StatefulWidget {
  const MachinesScreen({super.key});

  static void openMachineEditor(BuildContext context, {Machine? machine}) {
    showMachineFormDialog(context, machine: machine);
  }

  @override
  State<MachinesScreen> createState() => _MachinesScreenState();
}

class _MachinesScreenState extends State<MachinesScreen> {
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
        _isGridView = prefs.getBool('machines_grid_view') ?? false;
        _cardScale = prefs.getDouble('machines_card_scale') ?? 1.0;
      });
    }
  }

  Future<void> _saveGridView(bool val) async {
    setState(() => _isGridView = val);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('machines_grid_view', val);
  }

  Future<void> _saveCardScale(double val) async {
    setState(() => _cardScale = val);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('machines_card_scale', val);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<MachinesProvider, GroupsProvider>(
      builder: (context, provider, groupsProvider, _) {
        if (provider.isLoading && provider.machines.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        // Build group name lookup map for search
        final groupNames = <int, String>{
          for (final g in groupsProvider.groups) g.id: g.name,
        };
        final machines = provider.filteredMachinesWithGroups(groupNames);

        return SoftMasterDataPage(
          title: 'Machines',
          subtitle: 'Manage machine masters, properties, and groupings.',
          action: AppButton(
            label: 'Add Machine',
            icon: Icons.add,
            onPressed: () => MachinesScreen.openMachineEditor(context),
          ),
          toolbar: _MachinesToolbar(
            isGridView: _isGridView,
            cardScale: _cardScale,
            onToggleView: () => _saveGridView(!_isGridView),
            onCardScaleChanged: _saveCardScale,
          ),
          body: machines.isEmpty
              ? const AppEmptyState(
                  title: 'No machines found',
                  message: 'Add your first machine to track equipment on the shop floor.',
                  icon: Icons.precision_manufacturing_outlined,
                )
              : _isGridView
                  ? _MachinesGrid(machines: machines, scale: _cardScale)
                  : _MachinesTable(machines: machines),
        );
      },
    );
  }
}

class _MachinesToolbar extends StatelessWidget {
  const _MachinesToolbar({
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
                  fontWeight: FontWeight.w700,
                ),
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

class _MachinesGrid extends StatelessWidget {
  const _MachinesGrid({required this.machines, required this.scale});

  final List<Machine> machines;
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
          itemCount: machines.length,
          itemBuilder: (context, index) => _MachineCard(machine: machines[index]),
        );
      },
    );
  }
}

class _MachineCard extends StatefulWidget {
  const _MachineCard({required this.machine});
  final Machine machine;

  @override
  State<_MachineCard> createState() => _MachineCardState();
}

class _MachineCardState extends State<_MachineCard> {
  bool _hovered = false;

  Machine get machine => widget.machine;

  void _duplicate(BuildContext context) {
    final cloned = Machine(
      id: '',
      name: '${machine.name} (Copy)',
      assetId: '',
      primaryPhotoUrl: machine.primaryPhotoUrl,
      groupId: machine.groupId,
      makeModel: machine.makeModel,
      serialNumber: '',
      location: machine.location,
      installationDate: machine.installationDate,
      status: machine.status,
      customProperties: List.from(machine.customProperties),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    MachinesScreen.openMachineEditor(context, machine: cloned);
  }

  void _edit(BuildContext context) =>
      MachinesScreen.openMachineEditor(context, machine: machine);

  void _delete(BuildContext context) =>
      context.read<MachinesProvider>().deleteMachine(machine.id);

  @override
  Widget build(BuildContext context) {
    final groups = context.watch<GroupsProvider>();
    final groupName = machine.groupId != null
        ? (groups.findById(machine.groupId!)?.name ?? 'Unknown Group')
        : 'No Group';

    final statusColor = _statusColors(machine.status);

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
                        // Photo area
                        Expanded(
                          flex: 3,
                          child: machine.primaryPhotoUrl.isNotEmpty
                              ? Image.network(
                                  machine.primaryPhotoUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, _) =>
                                      _buildPlaceholder(),
                                )
                              : _buildPlaceholder(),
                        ),
                        // Footer
                        Container(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                          color: const Color(0xFFF8F8FC),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                machine.name,
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
                                machine.makeModel.isNotEmpty
                                    ? machine.makeModel
                                    : groupName,
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
                                label: machine.status.name.toUpperCase(),
                                background: statusColor.$1,
                                textColor: statusColor.$2,
                                borderColor: statusColor.$3,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    // Hover overlay: `...` button
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
        child: Icon(Icons.precision_manufacturing_outlined,
            color: Color(0xFF9CA3AF), size: 48),
      ),
    );
  }
}

(Color, Color, Color) _statusColors(MachineStatus status) {
  return switch (status) {
    MachineStatus.active => (
        const Color(0xFFECFDF5),
        const Color(0xFF0F766E),
        const Color(0xFFBFEAD8),
      ),
    MachineStatus.maintenance => (
        const Color(0xFFFFFBEB),
        const Color(0xFFB45309),
        const Color(0xFFFEF3C7),
      ),
    MachineStatus.decommissioned => (
        const Color(0xFFF3F4F6),
        const Color(0xFF4B5563),
        const Color(0xFFE5E7EB),
      ),
  };
}

/// Three-dot more button shown on card hover.
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
    final color = destructive ? const Color(0xFFDC2626) : SoftErpTheme.textPrimary;
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

class _MachinesTable extends StatelessWidget {
  const _MachinesTable({required this.machines});
  final List<Machine> machines;

  @override
  Widget build(BuildContext context) {
    return SoftMasterTable(
      minWidth: 1080,
      columns: const [
        SoftTableColumn('Photo', flex: 1),
        SoftTableColumn('Name & Model', flex: 3),
        SoftTableColumn('Group', flex: 2),
        SoftTableColumn('Status', flex: 2),
        SoftTableColumn('Actions', flex: 2),
      ],
      itemCount: machines.length,
      rowBuilder: (context, index) => _MachineRow(machine: machines[index]),
    );
  }
}

class _MachineRow extends StatelessWidget {
  const _MachineRow({required this.machine});
  final Machine machine;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<MachinesProvider>();
    final groups = context.watch<GroupsProvider>();
    final groupName = machine.groupId != null
        ? (groups.findById(machine.groupId!)?.name ?? 'Unknown Group')
        : '—';
    final statusColors = _statusColors(machine.status);

    return SoftMasterRow(
      children: [
        Expanded(
          flex: 1,
          child: machine.primaryPhotoUrl.isNotEmpty
              ? Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.centerLeft,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      machine.primaryPhotoUrl,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, _) => _buildThumb(),
                    ),
                  ),
                )
              : Container(alignment: Alignment.centerLeft, child: _buildThumb()),
        ),
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SoftInlineText(machine.name, weight: FontWeight.w700),
              if (machine.makeModel.isNotEmpty) ...[
                const SizedBox(height: 4),
                SoftInlineText(machine.makeModel,
                    color: const Color(0xFF6B7280), weight: FontWeight.w500),
              ],
            ],
          ),
        ),
        Expanded(flex: 2, child: SoftInlineText(groupName)),
        Expanded(
          flex: 2,
          child: Align(
            alignment: Alignment.centerLeft,
            child: SoftStatusPill(
              label: machine.status.name.toUpperCase(),
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
                  final cloned = Machine(
                    id: '',
                    name: '${machine.name} (Copy)',
                    assetId: '',
                    primaryPhotoUrl: machine.primaryPhotoUrl,
                    groupId: machine.groupId,
                    makeModel: machine.makeModel,
                    serialNumber: '',
                    location: machine.location,
                    installationDate: machine.installationDate,
                    status: machine.status,
                    customProperties: List.from(machine.customProperties),
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                  );
                  MachinesScreen.openMachineEditor(context, machine: cloned);
                },
              ),
              SoftActionLink(
                label: 'Edit',
                onTap: () => MachinesScreen.openMachineEditor(context,
                    machine: machine),
              ),
              SoftActionLink(
                label: 'Delete',
                onTap: () async => provider.deleteMachine(machine.id),
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
      child: const Icon(Icons.precision_manufacturing_outlined,
          color: Color(0xFF9CA3AF), size: 24),
    );
  }
}

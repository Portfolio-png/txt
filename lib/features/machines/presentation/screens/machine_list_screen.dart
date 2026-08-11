import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/core/widgets/material_barcode_toolkit.dart';
import 'package:core_erp/core/widgets/app_button.dart';
import 'package:core_erp/core/widgets/app_empty_state.dart';
import 'package:core_erp/core/widgets/soft_master_data.dart';
import 'package:core_erp/core/widgets/soft_primitives.dart';
import 'package:core_erp/core/navigation/app_navigation.dart';
import 'package:core_erp/features/groups/presentation/screens/groups_screen.dart';
import '../../domain/machine.dart';
import '../providers/machine_provider.dart';
import 'machine_form_screen.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';

class MachinesScreen extends StatefulWidget {
  const MachinesScreen({super.key, this.initialTab = 0});

  final int initialTab;

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
    if (widget.initialTab == 1) {
      return const GroupsScreen(mode: 'machines');
    }

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
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    final tabSegment = SoftSegmentedFilter<String>(
      selected: 'machines',
      onChanged: (value) {
        if (value == 'groups') {
          try {
            context.read<AppNavigation>().select('configurator_machine_groups');
          } catch (_) {}
        }
      },
      options: const [
        SoftSegmentOption<String>(
          value: 'machines',
          label: 'Machines Catalog',
        ),
        SoftSegmentOption<String>(
          value: 'groups',
          label: 'Machine Groups',
        ),
      ],
    );

    return SoftMasterToolbar(
      children: [
        tabSegment,
        if (isDesktop)
          Container(
            width: 1,
            height: 28,
            color: SoftErpTheme.border,
            margin: const EdgeInsets.symmetric(horizontal: 4),
          ),
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
                                  errorBuilder: (_, _, _) =>
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
                              if (machine.capabilities.isNotEmpty) ...[
                                Row(
                                  children: [
                                    const Icon(Icons.settings_suggest_outlined, size: 12, color: SoftErpTheme.textSecondary),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        '${machine.capabilities.first.processType} · ${machine.capabilities.first.inputMaterialName} → ${machine.capabilities.first.outputMaterialName}',
                                        style: const TextStyle(
                                          color: SoftErpTheme.textSecondary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                              ],
                              Row(
                                children: [
                                  SoftStatusPill(
                                    label: machine.status.name.toUpperCase(),
                                    background: statusColor.$1,
                                    textColor: statusColor.$2,
                                    borderColor: statusColor.$3,
                                  ),
                                  const Spacer(),
                                  _MachineQueueBattery(
                                    machineId: machine.id,
                                    machineName: machine.name,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              _MachineBarcodeChip(machine: machine),
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
/// Compact scannable barcode chip on the machine card. Tapping enlarges it so an
/// operator can scan the machine to load its queue or log a process.
class _MachineBarcodeChip extends StatelessWidget {
  const _MachineBarcodeChip({required this.machine});

  final Machine machine;

  String get _code =>
      machine.barcode.isNotEmpty ? machine.barcode : machine.assetId;

  void _showEnlarged(BuildContext context) {
    if (_code.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(32),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                machine.name,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                _code,
                style: const TextStyle(color: SoftErpTheme.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 16),
              InlineBarcodePreview(value: _code),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_code.isEmpty) return const SizedBox.shrink();
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _showEnlarged(context),
      child: Tooltip(
        message: 'Machine barcode — tap to enlarge / scan',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 24,
              width: 88,
              child: BarcodeWidget(
                barcode: Barcode.code128(),
                data: _code,
                drawText: false,
                color: SoftErpTheme.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _code,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.4,
                  color: SoftErpTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Battery-level indicator of a machine's pending run queue. Empty = idle, low
/// (amber) = 1-2 queued, full (red) = 3+ queued (bottleneck). Tap opens the
/// queue list. Loads its count lazily on first build.
class _MachineQueueBattery extends StatefulWidget {
  const _MachineQueueBattery({required this.machineId, required this.machineName});

  final String machineId;
  final String machineName;

  @override
  State<_MachineQueueBattery> createState() => _MachineQueueBatteryState();
}

class _MachineQueueBatteryState extends State<_MachineQueueBattery> {
  List<MachineQueueItem>? _queue;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final q = await context
          .read<MachinesProvider>()
          .fetchMachineQueue(widget.machineId);
      if (mounted) setState(() { _queue = q; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _queue = const []; _loading = false; });
    }
  }

  int get _count => _queue?.length ?? 0;

  (IconData, Color) get _battery {
    if (_count >= 3) return (Icons.battery_full, Colors.red.shade600);
    if (_count >= 1) return (Icons.battery_3_bar, Colors.orange.shade700);
    return (Icons.battery_0_bar, SoftErpTheme.textSecondary);
  }

  void _openQueue() {
    showDialog<void>(
      context: context,
      builder: (_) => _MachineQueueDialog(
        machineName: widget.machineName,
        queue: _queue ?? const [],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: Padding(
          padding: EdgeInsets.all(2),
          child: CircularProgressIndicator(strokeWidth: 1.5),
        ),
      );
    }
    final (icon, color) = _battery;
    return Tooltip(
      message:
          'Active workload queue: $_count run${_count == 1 ? '' : 's'}. Tap to inspect pending batches.',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: _openQueue,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 2),
            Text('$_count',
                style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }
}

class _MachineQueueDialog extends StatelessWidget {
  const _MachineQueueDialog({required this.machineName, required this.queue});

  final String machineName;
  final List<MachineQueueItem> queue;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$machineName · Queue',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 2),
              Text(
                  '${queue.length} pending run${queue.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                      color: SoftErpTheme.textSecondary, fontSize: 12)),
              const SizedBox(height: 16),
              if (queue.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('No pending runs.',
                      style: TextStyle(color: SoftErpTheme.textSecondary)),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: queue.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _queueRow(queue[i]),
                  ),
                ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _queueRow(MachineQueueItem q) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8ECF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(q.runName,
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: SoftErpTheme.textPrimary)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              if (q.orderNo.isNotEmpty) _meta('Order', q.orderNo),
              if (q.clientName.isNotEmpty) _meta('Client', q.clientName),
              _meta('Created by', (q.createdBy ?? '').isEmpty ? '—' : q.createdBy!),
              if (q.weightKg > 0)
                _meta('Weight', '${q.weightKg.toStringAsFixed(q.weightKg == q.weightKg.roundToDouble() ? 0 : 2)} kg'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _meta(String k, String v) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 12, color: SoftErpTheme.textPrimary),
        children: [
          TextSpan(
              text: '$k: ',
              style: const TextStyle(
                  color: SoftErpTheme.textSecondary,
                  fontWeight: FontWeight.w500)),
          TextSpan(text: v, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
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
      minWidth: 1200,
      columns: const [
        SoftTableColumn('Photo', flex: 1),
        SoftTableColumn('Name & Model', flex: 3),
        SoftTableColumn('Group', flex: 2),
        SoftTableColumn('Capabilities', flex: 2),
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
                      errorBuilder: (_, _, _) => _buildThumb(),
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
          child: machine.capabilities.isEmpty
              ? const SoftInlineText('—')
              : Wrap(
                  children: machine.capabilities.map((c) => Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${c.processType}: ${c.inputMaterialName}→${c.outputMaterialName}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )).toList(),
                ),
        ),
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

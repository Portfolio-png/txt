import 'package:core_erp/core/widgets/app_toast.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/links/presentation/widgets/ecosystem_inspector.dart';
import 'package:core_erp/features/links/presentation/widgets/linked_ecosystem_ribbon.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/machine.dart';
import '../providers/machine_provider.dart';
import '../screens/machine_list_screen.dart';

/// A machine, read without being opened for editing. See `DieInspectorPanel`
/// for why this lives in the host app.
class MachineInspectorPanel extends StatefulWidget {
  const MachineInspectorPanel({super.key, required this.machineId});

  final String machineId;

  @override
  State<MachineInspectorPanel> createState() => _MachineInspectorPanelState();
}

class _MachineInspectorPanelState extends State<MachineInspectorPanel> {
  Machine? _machine;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final provider = context.read<MachinesProvider>();
    await provider.initialize();
    if (!mounted) return;
    setState(() {
      _machine = provider.machines
          .where((machine) => machine.id == widget.machineId)
          .firstOrNull;
      _loading = false;
    });
  }

  List<(String, String)> _facts(Machine machine) {
    final facts = <(String, String)>[];
    if (machine.assetId.trim().isNotEmpty) {
      facts.add(('Machine no.', machine.assetId));
    }
    facts.add(('Status', _statusLabel(machine.status)));
    // The machine's type is its group, resolved through the groups master —
    // `groupId` is nullable and an unresolved one is left out rather than
    // shown as a bare number.
    final groupId = machine.groupId;
    if (groupId != null) {
      final group = context.read<GroupsProvider>().findById(groupId);
      if (group != null) facts.add(('Type', group.name));
    }
    // Integer kilograms-force per the units contract; shown with its unit and
    // never converted here.
    final capacity = machine.capacityKgf;
    if (capacity != null) {
      final kind = machine.capacityKind.trim();
      facts.add((
        'Capacity',
        kind.isEmpty ? '$capacity kgf' : '$capacity kgf · $kind',
      ));
    }
    if (machine.strokesPerMinute != null) {
      facts.add(('Strokes/min', '${machine.strokesPerMinute}'));
    }
    if (machine.dieFeedType.trim().isNotEmpty) {
      facts.add(('Die feed', machine.dieFeedType));
    }
    if (machine.machineMake.trim().isNotEmpty) {
      facts.add(('Make', machine.machineMake));
    }
    if (machine.manufacturedYear != null) {
      facts.add(('Year', '${machine.manufacturedYear}'));
    }
    if ((machine.location ?? '').trim().isNotEmpty) {
      facts.add(('Where', machine.location!));
    }
    if (machine.runningHours != null) {
      facts.add(('Running hours', '${machine.runningHours}'));
    }
    return facts;
  }

  static String _statusLabel(MachineStatus status) => switch (status) {
    MachineStatus.active => 'Active',
    MachineStatus.maintenance => 'Maintenance',
    MachineStatus.decommissioned => 'Decommissioned',
  };

  @override
  Widget build(BuildContext context) {
    final machine = _machine;
    if (_loading) {
      return const EcosystemInspectorSheet(
        title: 'Machine',
        subtitle: 'Loading',
        facts: <(String, String)>[],
        ribbon: SizedBox.shrink(),
      );
    }
    if (machine == null) {
      return const EcosystemInspectorSheet(
        title: 'Machine',
        subtitle: 'Not found',
        facts: <(String, String)>[],
        ribbon: SizedBox.shrink(),
        missing: true,
      );
    }
    return EcosystemInspectorSheet(
      title: machine.name.trim().isEmpty ? machine.assetId : machine.name,
      subtitle: 'Machine',
      facts: _facts(machine),
      ribbon: LinkedEcosystemRibbon(
        type: 'machine',
        id: machine.id,
        heading: 'Runs',
        onOpen: (ref) => pivotEcosystemInspector(context, ref),
      ),
      onEdit: () async {
        final saved = await MachinesScreen.openMachineEditor(
          context,
          machine: machine,
        );
        if (saved != null) {
          if (!mounted) return;
          showAppToast(context, 'Saved ${saved.name}.');
        }
      },
    );
  }
}

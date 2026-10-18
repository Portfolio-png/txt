import 'package:core_erp/core/widgets/app_toast.dart';
import 'package:core_erp/features/links/presentation/widgets/ecosystem_inspector.dart';
import 'package:core_erp/features/links/presentation/widgets/linked_ecosystem_ribbon.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/die.dart';
import '../providers/die_provider.dart';
import '../screens/die_list_screen.dart';

/// A die, read without being opened for editing.
///
/// Lives in the host app because `Die` does — `core_erp` cannot see the type,
/// which is why the ecosystem ribbon can name a die but not describe one. This
/// is the body behind `AppFlowHooks.dieInspector`.
///
/// Reading never writes. Editing is one explicit button that closes this panel
/// first and then opens the real editor.
class DieInspectorPanel extends StatefulWidget {
  const DieInspectorPanel({super.key, required this.dieId});

  final String dieId;

  @override
  State<DieInspectorPanel> createState() => _DieInspectorPanelState();
}

class _DieInspectorPanelState extends State<DieInspectorPanel> {
  Die? _die;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  /// `DiesProvider` has no `findById`, so this is the idiom the shell's own
  /// hooks use: make sure the list is loaded, then look in it. `initialize()`
  /// is guarded and a no-op the second time.
  Future<void> _resolve() async {
    final provider = context.read<DiesProvider>();
    await provider.initialize();
    if (!mounted) return;
    setState(() {
      _die = provider.dies.where((die) => die.id == widget.dieId).firstOrNull;
      _loading = false;
    });
  }

  /// Only the facts this die actually carries. A blank row would read as "set
  /// to nothing", which is a different claim from "not recorded".
  List<(String, String)> _facts(Die die) {
    final facts = <(String, String)>[];
    if (die.toolCode.trim().isNotEmpty) facts.add(('Tool code', die.toolCode));
    facts.add(('Status', _statusLabel(die.status)));
    facts.add(('Ownership', _ownershipLabel(die.ownership)));
    if (die.dieType.trim().isNotEmpty) facts.add(('Type', die.dieType));
    final where = [die.storeArea, die.rackNo]
        .where((part) => part.trim().isNotEmpty)
        .join(' · ');
    if (where.isNotEmpty) {
      facts.add(('Where', where));
    } else if ((die.storageLocation ?? '').trim().isNotEmpty) {
      facts.add(('Where', die.storageLocation!));
    }
    if (die.numberOfCavities != null) {
      facts.add(('Cavities', '${die.numberOfCavities}'));
    }
    final strokes = die.strokeCount;
    if (strokes != null) {
      final max = die.maxStrokes;
      facts.add((
        'Strokes',
        max != null && max > 0 ? '$strokes / $max' : '$strokes',
      ));
    }
    if (die.noOfSet != null) facts.add(('Sets', '${die.noOfSet}'));
    if (die.madeBy.trim().isNotEmpty) facts.add(('Made by', die.madeBy));
    // Stored in nanometres per the units contract; shown in the unit the die
    // records, and never converted here.
    final liner = die.linerSizeNm;
    if (liner != null) {
      facts.add(('Liner', '$liner ${die.linerSizeUnit}'));
    }
    return facts;
  }

  static String _statusLabel(DieStatus status) => switch (status) {
    DieStatus.ready => 'Ready',
    DieStatus.inProduction => 'In production',
    DieStatus.needsRepair => 'Needs repair',
    DieStatus.obsolete => 'Obsolete',
  };

  static String _ownershipLabel(DieOwnership ownership) => switch (ownership) {
    DieOwnership.inHouse => 'In house',
    DieOwnership.customerOwned => 'Customer owned',
  };

  @override
  Widget build(BuildContext context) {
    final die = _die;
    if (_loading) {
      return const EcosystemInspectorSheet(
        title: 'Die',
        subtitle: 'Loading',
        facts: <(String, String)>[],
        ribbon: SizedBox.shrink(),
      );
    }
    if (die == null) {
      return const EcosystemInspectorSheet(
        title: 'Die',
        subtitle: 'Not found',
        facts: <(String, String)>[],
        ribbon: SizedBox.shrink(),
        missing: true,
      );
    }
    return EcosystemInspectorSheet(
      title: die.name.trim().isEmpty ? die.toolCode : die.name,
      subtitle: 'Die',
      facts: _facts(die),
      // Its own ribbon, so the cluster is walkable from this end too: a die
      // lists the parts it cuts from the same rows an item reads.
      ribbon: LinkedEcosystemRibbon(
        type: 'die',
        id: die.id,
        heading: 'Used by',
        onOpen: (ref) => pivotEcosystemInspector(context, ref),
      ),
      onEdit: () async {
        final saved = await DiesScreen.openDieEditor(context, die: die);
        if (saved != null) {
          if (!mounted) return;
          showAppToast(context, 'Saved ${saved.name}.');
        }
      },
    );
  }
}

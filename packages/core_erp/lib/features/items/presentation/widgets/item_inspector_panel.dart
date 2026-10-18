import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/widgets/app_toast.dart';
import '../../../groups/presentation/providers/groups_provider.dart';
import '../../../links/presentation/widgets/ecosystem_inspector.dart';
import '../../../links/presentation/widgets/linked_ecosystem_ribbon.dart';
import '../../../units/presentation/providers/units_provider.dart';
import '../../domain/item_definition.dart';
import '../providers/items_provider.dart';
import '../screens/items_screen.dart';

/// A part (item), read without being opened for editing.
///
/// Mirrors `DieInspectorPanel` and `MachineInspectorPanel` so walking the
/// link graph from a die or machine back to a part opens the same slide-over
/// inspector sheet, without jumping to the full item workspace.
class ItemInspectorPanel extends StatefulWidget {
  const ItemInspectorPanel({super.key, required this.itemId});

  final String itemId;

  @override
  State<ItemInspectorPanel> createState() => _ItemInspectorPanelState();
}

class _ItemInspectorPanelState extends State<ItemInspectorPanel> {
  ItemDefinition? _item;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final parsedId = int.tryParse(widget.itemId);
    if (parsedId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final provider = context.read<ItemsProvider>();
    var found = provider.items.where((i) => i.id == parsedId).firstOrNull;
    if (found == null) {
      await provider.refresh();
      if (!mounted) return;
      found = provider.items.where((i) => i.id == parsedId).firstOrNull;
    }
    if (!mounted) return;
    setState(() {
      _item = found;
      _loading = false;
    });
  }

  static List<(String, String)> _facts(
    BuildContext context,
    ItemDefinition item,
  ) {
    final facts = <(String, String)>[];
    if (item.partCode.trim().isNotEmpty) {
      facts.add(('Part code', item.partCode));
    } else if (item.partNo != null) {
      facts.add(('Part no', '${item.partNo}'));
    }
    try {
      final groups = context.read<GroupsProvider>();
      final group = groups.findById(item.groupId);
      if (group != null && group.name.trim().isNotEmpty) {
        facts.add(('Group', group.name));
      }
    } catch (_) {}
    try {
      final units = context.read<UnitsProvider>();
      final unit = units.units.where((u) => u.id == item.unitId).firstOrNull;
      if (unit != null && unit.symbol.trim().isNotEmpty) {
        facts.add(('Unit', unit.symbol));
      }
    } catch (_) {}
    if (item.developedForClientName.trim().isNotEmpty) {
      facts.add(('Developed for', item.developedForClientName));
    }
    if (item.blankWidthMm > 0 && item.blankHeightMm > 0) {
      facts.add(('Blank', '${item.blankWidthMm} × ${item.blankHeightMm} mm'));
    }
    if (item.alias.trim().isNotEmpty) {
      facts.add(('Alias', item.alias));
    }
    return facts;
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    if (_loading) {
      return const EcosystemInspectorSheet(
        title: 'Part',
        subtitle: 'Loading',
        facts: <(String, String)>[],
        ribbon: SizedBox.shrink(),
      );
    }
    if (item == null) {
      return const EcosystemInspectorSheet(
        title: 'Part',
        subtitle: 'Not found',
        facts: <(String, String)>[],
        ribbon: SizedBox.shrink(),
        missing: true,
      );
    }
    final rawTitle =
        item.displayName.trim().isEmpty ? item.name : item.displayName;
    final title = rawTitle.trim().isEmpty
        ? (item.partCode.trim().isEmpty ? 'Part ${item.id}' : item.partCode)
        : rawTitle;

    return EcosystemInspectorSheet(
      title: title,
      subtitle: 'Part',
      facts: _facts(context, item),
      ribbon: LinkedEcosystemRibbon(
        type: 'item',
        id: '${item.id}',
        heading: 'Works with',
        onOpen: (ref) => pivotEcosystemInspector(context, ref),
      ),
      onEdit: () async {
        final navigator = Navigator.of(context);
        navigator.maybePop();
        final saved = await ItemsScreen.openEditor(context, item: item);
        if (saved != null) {
          if (!mounted) return;
          showAppToast(context, 'Saved ${saved.displayName}.');
        }
      },
    );
  }
}

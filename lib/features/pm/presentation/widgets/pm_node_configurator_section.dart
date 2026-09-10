import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/core/widgets/app_button.dart';
import 'package:core_erp/core/widgets/app_card.dart';
import 'package:core_erp/core/widgets/app_section_title.dart';
import 'package:flutter/material.dart';

import '../node_configurator/domain/node_blueprint.dart';
import '../node_configurator/node_configurator_screen.dart';
import '../node_configurator/widgets/slot_controls.dart';

/// The PM tab's door into the Node Configurator.
///
/// Carries the tone legend rather than an explanation, because the legend *is*
/// the argument: two of these four states leave the field blank and mean
/// opposite things.
class PMNodeConfiguratorSection extends StatelessWidget {
  const PMNodeConfiguratorSection({super.key});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionTitle(
            title: 'Node configurator',
            subtitle:
                'Reusable pipeline nodes: what runs it, what it mounts, where '
                'the loss goes.',
            trailing: AppButton(
              label: 'Open',
              icon: Icons.open_in_new,
              onPressed: () => NodeConfiguratorScreen.open(context),
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 20,
            runSpacing: 12,
            children: [
              for (final entry in _legend)
                SizedBox(width: 190, child: _LegendItem(entry: entry)),
            ],
          ),
        ],
      ),
    );
  }

  static const List<_LegendEntry> _legend = [
    _LegendEntry(
      tone: SlotTone.absent,
      icon: Icons.layers_clear,
      chip: 'No die',
      meaning: 'Never uses one.',
    ),
    _LegendEntry(
      tone: SlotTone.bound,
      icon: Icons.precision_manufacturing,
      chip: 'PN-07',
      meaning: 'Pinned to one asset.',
    ),
    _LegendEntry(
      tone: SlotTone.pooled,
      icon: Icons.workspaces,
      chip: 'Any Punching',
      meaning: 'Picked from a fenced pool.',
    ),
    _LegendEntry(
      tone: SlotTone.deferred,
      icon: Icons.schedule,
      chip: 'At run time',
      meaning: 'Needed, unanswered. Blocks the start.',
    ),
  ];
}

class _LegendEntry {
  const _LegendEntry({
    required this.tone,
    required this.icon,
    required this.chip,
    required this.meaning,
  });

  final SlotTone tone;
  final IconData icon;
  final String chip;
  final String meaning;
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.entry});

  final _LegendEntry entry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SlotChip(
            icon: entry.icon,
            label: entry.chip,
            tone: entry.tone,
            dense: true,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          entry.meaning,
          style: const TextStyle(
            fontSize: 11.5,
            height: 1.35,
            color: SoftErpTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}

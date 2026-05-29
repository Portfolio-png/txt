import 'package:flutter/material.dart';
import 'package:core_erp/core/widgets/app_card.dart';
import 'package:core_erp/core/widgets/app_info_panel.dart';
import 'package:core_erp/core/widgets/app_section_title.dart';

class PMInventoryUxExplorationSection extends StatelessWidget {
  const PMInventoryUxExplorationSection({
    super.key,
    required this.selectedFamily,
    required this.selectedMethod,
    required this.onFamilyChanged,
    required this.onMethodChanged,
  });

  final String selectedFamily;
  final String selectedMethod;
  final ValueChanged<String> onFamilyChanged;
  final ValueChanged<String> onMethodChanged;

  @override
  Widget build(BuildContext context) {
    final families = <_PMUxFamily>[
      const _PMUxFamily(
        id: 'context',
        title: 'Keep inventory context visible',
        description:
            'Good when users need to compare the new group against existing rows while they build it.',
        methods: [
          _PMUxMethod(
            id: 'workspace',
            eyebrow: 'Method 01',
            title: 'Split workspace',
            description:
                'Builder on one side, summary on the other. Strong for comparison and confidence.',
            accent: Color(0xFFEEF2FF),
            mock: _PMSplitWorkspaceMock(),
          ),
          _PMUxMethod(
            id: 'drawer',
            eyebrow: 'Method 02',
            title: 'Right-side drawer',
            description:
                'A side panel that keeps the table visible underneath.',
            accent: Color(0xFFEFF6FF),
            mock: _PMDrawerMock(),
          ),
        ],
      ),
      const _PMUxFamily(
        id: 'guided',
        title: 'Guide the user step by step',
        description:
            'Good when the form feels intimidating or when users need help sequencing decisions.',
        methods: [
          _PMUxMethod(
            id: 'stepper',
            eyebrow: 'Method 03',
            title: 'Stepper flow',
            description:
                'Breaks the form into a sequence so users focus on one layer at a time.',
            accent: Color(0xFFECFDF3),
            mock: _PMStepperMock(),
          ),
        ],
      ),
      const _PMUxFamily(
        id: 'fast',
        title: 'Create quickly and move on',
        description:
            'Good when operators create similar groups often and want speed over explanation.',
        methods: [
          _PMUxMethod(
            id: 'sheet',
            eyebrow: 'Method 04',
            title: 'Command sheet',
            description: 'A compact quick-create panel for repetitive entry.',
            accent: Color(0xFFFFF7ED),
            mock: _PMCommandSheetMock(),
          ),
        ],
      ),
    ];
    final family =
        families.where((item) => item.id == selectedFamily).firstOrNull ??
        families.first;
    final method =
        family.methods.where((item) => item.id == selectedMethod).firstOrNull ??
        family.methods.first;

    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionTitle(
            title: 'Inventory group UX explorations',
            subtitle:
                'Grouped by UX intent, so you can cluster related methods first and compare variants inside each cluster later.',
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: families
                .map(
                  (item) => _PMChoiceChip(
                    label: item.title,
                    selected: item.id == family.id,
                    onTap: () => onFamilyChanged(item.id),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  family.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  family.description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: family.methods
                      .map(
                        (item) => _PMChoiceChip(
                          label: item.title,
                          selected: item.id == method.id,
                          onTap: () => onMethodChanged(item.id),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _PMUxConceptCard(
            eyebrow: method.eyebrow,
            title: method.title,
            description: method.description,
            accent: method.accent,
            child: method.mock,
          ),
          const SizedBox(height: 18),
          AppInfoPanel(
            title: 'How to club these later',
            subtitle:
                'Think in families first, then decide which visual method should represent each family in the product.',
            rows: [
              const AppInfoRow(
                label: 'Context family',
                value:
                    'Workspace and drawer both belong together because they preserve the surrounding inventory view.',
              ),
              const AppInfoRow(
                label: 'Guided family',
                value:
                    'Stepper belongs here because its main job is sequencing and reducing decision overload.',
              ),
              const AppInfoRow(
                label: 'Fast-entry family',
                value:
                    'Command sheet belongs here because its main job is quick repetitive creation.',
              ),
              AppInfoRow(
                label: 'Current selection',
                value:
                    '${family.title} -> ${method.title}. This makes it easier to test one family at a time.',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PMUxFamily {
  const _PMUxFamily({
    required this.id,
    required this.title,
    required this.description,
    required this.methods,
  });

  final String id;
  final String title;
  final String description;
  final List<_PMUxMethod> methods;
}

class _PMUxMethod {
  const _PMUxMethod({
    required this.id,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.accent,
    required this.mock,
  });

  final String id;
  final String eyebrow;
  final String title;
  final String description;
  final Color accent;
  final Widget mock;
}

class _PMChoiceChip extends StatelessWidget {
  const _PMChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEEF2FF) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? const Color(0xFF6C63FF) : const Color(0xFFE5E7EB),
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected ? const Color(0xFF4338CA) : const Color(0xFF374151),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _PMUxConceptCard extends StatelessWidget {
  const _PMUxConceptCard({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.accent,
    required this.child,
  });

  final String eyebrow;
  final String title;
  final String description;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              eyebrow,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: const Color(0xFF111827),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF6B7280)),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _PMSplitWorkspaceMock extends StatelessWidget {
  const _PMSplitWorkspaceMock();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: const [
          _PMMockField(label: 'Group name', value: 'Paper Cone'),
          SizedBox(height: 10),
          _PMMockField(label: 'Group type', value: 'Primary'),
          SizedBox(height: 12),
          _PMMockToggle(label: 'Attach sub-group', enabled: true),
          SizedBox(height: 8),
          _PMMockToggle(label: 'Attach item', enabled: false),
          SizedBox(height: 12),
          _PMMockPreviewCard(
            title: 'Live summary',
            lines: ['1 child relation', '2 properties', 'Notes generated'],
          ),
        ],
      ),
    );
  }
}

class _PMStepperMock extends StatelessWidget {
  const _PMStepperMock();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: const [
          _PMStepRow(index: 1, title: 'Name and type', active: true),
          SizedBox(height: 10),
          _PMStepRow(index: 2, title: 'Attach sub-groups or items'),
          SizedBox(height: 10),
          _PMStepRow(index: 3, title: 'Add properties'),
          SizedBox(height: 10),
          _PMStepRow(index: 4, title: 'Review and create'),
        ],
      ),
    );
  }
}

class _PMCommandSheetMock extends StatelessWidget {
  const _PMCommandSheetMock();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _PMSheetPill(label: 'Quick Create Group'),
          SizedBox(height: 12),
          _PMDarkField(label: 'Name', value: 'Paper Cone'),
          SizedBox(height: 10),
          _PMDarkField(label: 'Type', value: 'Primary'),
          SizedBox(height: 10),
          _PMDarkField(label: 'Properties', value: 'GSM, Width'),
          SizedBox(height: 12),
          Row(
            children: [
              _PMMiniAction(label: 'Cancel'),
              SizedBox(width: 8),
              _PMMiniAction(label: 'Create', primary: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _PMDrawerMock extends StatelessWidget {
  const _PMDrawerMock();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: const [
                  _PMGhostRow(widthFactor: 1),
                  SizedBox(height: 8),
                  _PMGhostRow(widthFactor: 0.82),
                  SizedBox(height: 8),
                  _PMGhostRow(widthFactor: 0.9),
                ],
              ),
            ),
          ),
          Container(
            width: 150,
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.horizontal(right: Radius.circular(16)),
              border: Border(left: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'New Group',
                  style: TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 10),
                _PMGhostRow(widthFactor: 1),
                SizedBox(height: 8),
                _PMGhostRow(widthFactor: 1),
                SizedBox(height: 8),
                _PMGhostRow(widthFactor: 0.74),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PMMockField extends StatelessWidget {
  const _PMMockField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: const Color(0xFF6B7280),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFD7DEEA)),
          ),
          child: Text(value),
        ),
      ],
    );
  }
}

class _PMMockToggle extends StatelessWidget {
  const _PMMockToggle({required this.label, required this.enabled});

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: enabled ? const Color(0xFFF3F0FF) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: enabled ? const Color(0xFFC4B5FD) : const Color(0xFFE5E7EB),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Container(
            width: 36,
            height: 22,
            decoration: BoxDecoration(
              color: enabled
                  ? const Color(0xFF6C63FF)
                  : const Color(0xFFD1D5DB),
              borderRadius: BorderRadius.circular(999),
            ),
            alignment: enabled ? Alignment.centerRight : Alignment.centerLeft,
            padding: const EdgeInsets.all(2),
            child: Container(
              width: 18,
              height: 18,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PMMockPreviewCard extends StatelessWidget {
  const _PMMockPreviewCard({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                line,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFF6B7280)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PMStepRow extends StatelessWidget {
  const _PMStepRow({
    required this.index,
    required this.title,
    this.active = false,
  });

  final int index;
  final String title;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: active ? const Color(0xFF6C63FF) : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: active ? const Color(0xFF6C63FF) : const Color(0xFFD1D5DB),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            '$index',
            style: TextStyle(
              color: active ? Colors.white : const Color(0xFF6B7280),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: active ? FontWeight.w700 : FontWeight.w600,
              color: active ? const Color(0xFF111827) : const Color(0xFF6B7280),
            ),
          ),
        ),
      ],
    );
  }
}

class _PMSheetPill extends StatelessWidget {
  const _PMSheetPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PMDarkField extends StatelessWidget {
  const _PMDarkField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: const Color(0xFFCBD5E1),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _PMMiniAction extends StatelessWidget {
  const _PMMiniAction({required this.label, this.primary = false});

  final String label;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: primary
            ? const Color(0xFF6C63FF)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: primary
              ? const Color(0xFF6C63FF)
              : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PMGhostRow extends StatelessWidget {
  const _PMGhostRow({required this.widthFactor});

  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: 18,
        decoration: BoxDecoration(
          color: const Color(0xFFE5E7EB),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

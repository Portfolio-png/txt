import 'package:flutter/material.dart';
import 'package:core_erp/core/widgets/app_button.dart';
import 'package:core_erp/core/widgets/app_card.dart';
import 'package:core_erp/core/widgets/app_info_panel.dart';
import 'package:core_erp/core/widgets/app_section_title.dart';

class PMInventorySandboxSection extends StatelessWidget {
  const PMInventorySandboxSection({
    super.key,
    required this.nameController,
    required this.propertyController,
    required this.groupType,
    required this.addSubGroup,
    required this.addItem,
    required this.addProperties,
    required this.selectedSubGroup,
    required this.selectedItem,
    required this.properties,
    required this.layout,
    required this.onLayoutChanged,
    required this.onGroupTypeChanged,
    required this.onAddSubGroupChanged,
    required this.onAddItemChanged,
    required this.onAddPropertiesChanged,
    required this.onSubGroupChanged,
    required this.onItemChanged,
    required this.onQuickAddItem,
    required this.onAddProperty,
    required this.onRemoveProperty,
    required this.onReset,
  });

  final TextEditingController nameController;
  final TextEditingController propertyController;
  final String groupType;
  final bool addSubGroup;
  final bool addItem;
  final bool addProperties;
  final String? selectedSubGroup;
  final String? selectedItem;
  final List<String> properties;
  final String layout;
  final ValueChanged<String> onLayoutChanged;
  final ValueChanged<String> onGroupTypeChanged;
  final ValueChanged<bool> onAddSubGroupChanged;
  final ValueChanged<bool> onAddItemChanged;
  final ValueChanged<bool> onAddPropertiesChanged;
  final ValueChanged<String?> onSubGroupChanged;
  final ValueChanged<String?> onItemChanged;
  final VoidCallback onQuickAddItem;
  final VoidCallback onAddProperty;
  final ValueChanged<String> onRemoveProperty;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final notes = <String>[
      'Group Type: $groupType',
      if (addSubGroup && selectedSubGroup != null)
        'Sub-Group: $selectedSubGroup',
      if (addItem && selectedItem != null) 'Item: $selectedItem',
      if (addProperties && properties.isNotEmpty)
        'Properties: ${properties.join(', ')}',
    ];

    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionTitle(
            title: 'Inventory group sandbox',
            subtitle:
                'Interactive, but fake. Tinker with the same form ideas here without touching the real database.',
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _PMChoiceChip(
                label: 'Split workspace',
                selected: layout == 'workspace',
                onTap: () => onLayoutChanged('workspace'),
              ),
              _PMChoiceChip(
                label: 'Stepper',
                selected: layout == 'stepper',
                onTap: () => onLayoutChanged('stepper'),
              ),
              _PMChoiceChip(
                label: 'Drawer',
                selected: layout == 'drawer',
                onTap: () => onLayoutChanged('drawer'),
              ),
              AppButton(
                label: 'Reset Sandbox',
                onPressed: onReset,
                variant: AppButtonVariant.secondary,
              ),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 980;
              final form = _PMSandboxEditor(
                nameController: nameController,
                propertyController: propertyController,
                groupType: groupType,
                addSubGroup: addSubGroup,
                addItem: addItem,
                addProperties: addProperties,
                selectedSubGroup: selectedSubGroup,
                selectedItem: selectedItem,
                properties: properties,
                onGroupTypeChanged: onGroupTypeChanged,
                onAddSubGroupChanged: onAddSubGroupChanged,
                onAddItemChanged: onAddItemChanged,
                onAddPropertiesChanged: onAddPropertiesChanged,
                onSubGroupChanged: onSubGroupChanged,
                onItemChanged: onItemChanged,
                onQuickAddItem: onQuickAddItem,
                onAddProperty: onAddProperty,
                onRemoveProperty: onRemoveProperty,
              );
              final preview = _PMSandboxPreview(
                name: nameController.text.trim(),
                groupType: groupType,
                addSubGroup: addSubGroup,
                addItem: addItem,
                selectedSubGroup: selectedSubGroup,
                selectedItem: selectedItem,
                properties: properties,
                notes: notes,
                layout: layout,
              );

              if (isNarrow) {
                return Column(
                  children: [form, const SizedBox(height: 16), preview],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: form),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: preview),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PMSandboxEditor extends StatelessWidget {
  const _PMSandboxEditor({
    required this.nameController,
    required this.propertyController,
    required this.groupType,
    required this.addSubGroup,
    required this.addItem,
    required this.addProperties,
    required this.selectedSubGroup,
    required this.selectedItem,
    required this.properties,
    required this.onGroupTypeChanged,
    required this.onAddSubGroupChanged,
    required this.onAddItemChanged,
    required this.onAddPropertiesChanged,
    required this.onSubGroupChanged,
    required this.onItemChanged,
    required this.onQuickAddItem,
    required this.onAddProperty,
    required this.onRemoveProperty,
  });

  final TextEditingController nameController;
  final TextEditingController propertyController;
  final String groupType;
  final bool addSubGroup;
  final bool addItem;
  final bool addProperties;
  final String? selectedSubGroup;
  final String? selectedItem;
  final List<String> properties;
  final ValueChanged<String> onGroupTypeChanged;
  final ValueChanged<bool> onAddSubGroupChanged;
  final ValueChanged<bool> onAddItemChanged;
  final ValueChanged<bool> onAddPropertiesChanged;
  final ValueChanged<String?> onSubGroupChanged;
  final ValueChanged<String?> onItemChanged;
  final VoidCallback onQuickAddItem;
  final VoidCallback onAddProperty;
  final ValueChanged<String> onRemoveProperty;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sandbox editor',
            style: TextStyle(
              color: Color(0xFF111827),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          _PMFieldLabel(label: 'Group name'),
          const SizedBox(height: 6),
          TextField(
            controller: nameController,
            decoration: _pmInputDecoration('Enter group name'),
          ),
          const SizedBox(height: 14),
          _PMFieldLabel(label: 'Group type'),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            key: ValueKey<String>('type-$groupType'),
            initialValue: groupType,
            decoration: _pmInputDecoration('Select type'),
            items: const ['Primary', 'Secondary', 'Material', 'Assembly']
                .map(
                  (option) =>
                      DropdownMenuItem(value: option, child: Text(option)),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value != null) {
                onGroupTypeChanged(value);
              }
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _PMSandboxToggleCard(
                  label: 'Sub-group',
                  value: addSubGroup,
                  onChanged: onAddSubGroupChanged,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey<String>('sub-$selectedSubGroup-$addSubGroup'),
                    initialValue: selectedSubGroup,
                    decoration: _pmInputDecoration('Choose sub-group'),
                    items: const ['Cone', 'Tube', 'Core']
                        .map(
                          (option) => DropdownMenuItem(
                            value: option,
                            child: Text(option),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: addSubGroup ? onSubGroupChanged : null,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PMSandboxToggleCard(
                  label: 'Item',
                  value: addItem,
                  onChanged: onAddItemChanged,
                  headerAction: _PMInlineAddAction(
                    label: '+ Add Item',
                    onTap: onQuickAddItem,
                  ),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey<String>('item-$selectedItem-$addItem'),
                    initialValue: selectedItem,
                    decoration: _pmInputDecoration('Choose item'),
                    items: const ['Funnel Small', 'Funnel Large', 'Insert']
                        .map(
                          (option) => DropdownMenuItem(
                            value: option,
                            child: Text(option),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: addItem ? onItemChanged : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _PMSandboxToggleCard(
            label: 'Properties',
            value: addProperties,
            onChanged: onAddPropertiesChanged,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: propertyController,
                        enabled: addProperties,
                        decoration: _pmInputDecoration('Enter property'),
                        onSubmitted: (_) => onAddProperty(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    AppButton(
                      label: 'Add',
                      onPressed: addProperties ? onAddProperty : null,
                      variant: AppButtonVariant.secondary,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: properties
                      .map(
                        (property) => _PMPropertyPill(
                          label: property,
                          onRemove: () => onRemoveProperty(property),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PMSandboxPreview extends StatelessWidget {
  const _PMSandboxPreview({
    required this.name,
    required this.groupType,
    required this.addSubGroup,
    required this.addItem,
    required this.selectedSubGroup,
    required this.selectedItem,
    required this.properties,
    required this.notes,
    required this.layout,
  });

  final String name;
  final String groupType;
  final bool addSubGroup;
  final bool addItem;
  final String? selectedSubGroup;
  final String? selectedItem;
  final List<String> properties;
  final List<String> notes;
  final String layout;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppInfoPanel(
          title: 'Local preview only',
          subtitle:
              'This section responds to your changes, but it does not touch the database.',
          rows: [
            AppInfoRow(label: 'Layout mode', value: layout),
            AppInfoRow(label: 'Name', value: name.isEmpty ? 'Untitled' : name),
            AppInfoRow(label: 'Type', value: groupType),
            AppInfoRow(
              label: 'Sub-group',
              value: addSubGroup ? (selectedSubGroup ?? 'Not selected') : 'Off',
            ),
            AppInfoRow(
              label: 'Item',
              value: addItem ? (selectedItem ?? 'Not selected') : 'Off',
            ),
            AppInfoRow(
              label: 'Properties',
              value: properties.isEmpty ? 'None' : properties.join(', '),
            ),
            AppInfoRow(label: 'Generated notes', value: notes.join('\n')),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'How to use this sandbox',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              ...const [
                'Change the layout chip to compare presentation styles.',
                'Edit fields and toggles to feel how the same information behaves in each mode.',
                'Use this to decide UX direction before we wire anything real.',
              ].map(
                (line) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    line,
                    style: const TextStyle(color: Color(0xFFCBD5E1), height: 1.4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
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

class _PMFieldLabel extends StatelessWidget {
  const _PMFieldLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: const Color(0xFF374151),
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _PMSandboxToggleCard extends StatelessWidget {
  const _PMSandboxToggleCard({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.child,
    this.headerAction,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget child;
  final Widget? headerAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: value ? const Color(0xFFC4B5FD) : const Color(0xFFE5E7EB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (headerAction != null) ...[
                const SizedBox(width: 8),
                headerAction!,
              ],
              Switch.adaptive(
                value: value,
                onChanged: onChanged,
                activeThumbColor: const Color(0xFF6C63FF),
                activeTrackColor: const Color(0xFFC4B5FD),
              ),
            ],
          ),
          Opacity(
            opacity: value ? 1 : 0.5,
            child: IgnorePointer(ignoring: !value, child: child),
          ),
        ],
      ),
    );
  }
}

class _PMInlineAddAction extends StatelessWidget {
  const _PMInlineAddAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFEEF2FF),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFC7D2FE)),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: const Color(0xFF4338CA),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _PMPropertyPill extends StatelessWidget {
  const _PMPropertyPill({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 6, top: 6, bottom: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEDE9FE),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF5B21B6),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: onRemove,
            child: const Icon(
              Icons.close_rounded,
              size: 16,
              color: Color(0xFF5B21B6),
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration _pmInputDecoration(String hintText) {
  return InputDecoration(
    hintText: hintText,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFD7DEEA)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFD7DEEA)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFF6C63FF), width: 1.4),
    ),
  );
}

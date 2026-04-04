import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_section_title.dart';
import '../../domain/unit_definition.dart';
import '../../domain/unit_inputs.dart';
import '../providers/units_provider.dart';

class UnitsScreen extends StatelessWidget {
  const UnitsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<UnitsProvider>(
      builder: (context, units, _) {
        if (units.isLoading && units.units.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSectionTitle(
                title: 'Units',
                subtitle:
                    'Create the measurement units and symbols your team uses across materials and configurator flows.',
                trailing: AppButton(
                  label: 'Add Unit',
                  icon: Icons.add,
                  isLoading: units.isSaving,
                  onPressed: () => _openUnitEditor(context),
                ),
              ),
              const SizedBox(height: 20),
              _UnitsToolbar(),
              if (units.errorMessage != null) ...[
                const SizedBox(height: 12),
                _UnitsMessageBanner(
                  message: units.errorMessage!,
                  isError: true,
                ),
              ],
              const SizedBox(height: 20),
              Expanded(
                child: units.filteredUnits.isEmpty
                    ? const AppEmptyState(
                        title: 'No units found',
                        message:
                            'Create a unit like Kilogram or Bundle to reuse it across inventory forms.',
                        icon: Icons.straighten_outlined,
                      )
                    : _UnitsTable(units: units.filteredUnits),
              ),
            ],
          ),
        );
      },
    );
  }

  static Future<UnitDefinition?> openEditor(
    BuildContext context, {
    UnitDefinition? unit,
    String initialName = '',
  }) {
    final isNarrow = MediaQuery.of(context).size.width < 900;
    final body = _UnitEditorSheet(unit: unit, initialName: initialName);
    if (isNarrow) {
      return showModalBottomSheet<UnitDefinition?>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: body,
        ),
      );
    }

    return showDialog<UnitDefinition?>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: body,
        ),
      ),
    );
  }

  static Future<UnitDefinition?> _openUnitEditor(
    BuildContext context, {
    UnitDefinition? unit,
    String initialName = '',
  }) {
    return openEditor(context, unit: unit, initialName: initialName);
  }
}

class _UnitsToolbar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UnitsProvider>();
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (!isDesktop)
          SizedBox(
            width: 280,
            child: TextField(
              onChanged: provider.setSearchQuery,
              decoration: InputDecoration(
                hintText: 'Search units or symbols',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
                ),
              ),
            ),
          ),
        SegmentedButton<UnitStatusFilter>(
          segments: const [
            ButtonSegment<UnitStatusFilter>(
              value: UnitStatusFilter.active,
              label: Text('Active'),
            ),
            ButtonSegment<UnitStatusFilter>(
              value: UnitStatusFilter.archived,
              label: Text('Archived'),
            ),
            ButtonSegment<UnitStatusFilter>(
              value: UnitStatusFilter.all,
              label: Text('All'),
            ),
          ],
          selected: {provider.statusFilter},
          onSelectionChanged: (selection) {
            provider.setStatusFilter(selection.first);
          },
        ),
      ],
    );
  }
}

class _UnitsTable extends StatelessWidget {
  const _UnitsTable({required this.units});

  final List<UnitDefinition> units;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE5E7F0))),
            ),
            child: const Row(
              children: [
                Expanded(flex: 3, child: _HeaderText('Name')),
                Expanded(flex: 2, child: _HeaderText('Symbol')),
                Expanded(flex: 1, child: _HeaderText('Used In')),
                Expanded(flex: 1, child: _HeaderText('Status')),
                Expanded(flex: 2, child: _HeaderText('Actions')),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: units.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, color: Color(0xFFF1F2F7)),
              itemBuilder: (context, index) => _UnitRow(unit: units[index]),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderText extends StatelessWidget {
  const _HeaderText(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: const Color(0xFF6B7280),
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _UnitRow extends StatelessWidget {
  const _UnitRow({required this.unit});

  final UnitDefinition unit;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UnitsProvider>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unit.name,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (unit.notes.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    unit.notes,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(flex: 2, child: Text(unit.symbol)),
          Expanded(flex: 1, child: Text('${unit.usageCount}')),
          Expanded(
            flex: 1,
            child: _StatusChip(
              label: unit.isArchived ? 'Archived' : 'Active',
              color: unit.isArchived
                  ? const Color(0xFF9CA3AF)
                  : const Color(0xFF0F766E),
              background: unit.isArchived
                  ? const Color(0xFFF3F4F6)
                  : const Color(0xFFECFDF5),
            ),
          ),
          Expanded(
            flex: 2,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ActionLink(
                  label: unit.isUsed ? 'View' : 'Edit',
                  onTap: () => UnitsScreen.openEditor(context, unit: unit),
                ),
                _ActionLink(
                  label: unit.isArchived ? 'Restore' : 'Archive',
                  onTap: provider.isSaving
                      ? null
                      : () {
                          if (unit.isArchived) {
                            provider.restoreUnit(unit.id);
                          } else {
                            provider.archiveUnit(unit.id);
                          }
                        },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.color,
    required this.background,
  });

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ActionLink extends StatelessWidget {
  const _ActionLink({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF6C63FF),
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label),
    );
  }
}

class _UnitEditorSheet extends StatefulWidget {
  const _UnitEditorSheet({this.unit, this.initialName = ''});

  final UnitDefinition? unit;
  final String initialName;

  @override
  State<_UnitEditorSheet> createState() => _UnitEditorSheetState();
}

class _UnitEditorSheetState extends State<_UnitEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _symbolController;
  late final TextEditingController _notesController;
  String? _localError;

  bool get _isReadOnly => widget.unit?.isUsed ?? false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.unit?.name ?? widget.initialName,
    );
    _symbolController = TextEditingController(text: widget.unit?.symbol ?? '');
    _notesController = TextEditingController(text: widget.unit?.notes ?? '');
    _nameController.addListener(_handleChange);
    _symbolController.addListener(_handleChange);
  }

  void _handleChange() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _nameController.removeListener(_handleChange);
    _symbolController.removeListener(_handleChange);
    _nameController.dispose();
    _symbolController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UnitsProvider>();
    final title = widget.unit == null
        ? 'Create Unit'
        : _isReadOnly
        ? 'View Unit'
        : 'Edit Unit';

    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AppSectionTitle(
                          title: title,
                          subtitle: _isReadOnly
                              ? 'This unit is already used in materials, so its details are locked.'
                              : 'Define the reusable name and symbol your team will pick in transaction forms.',
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  if (_localError != null) ...[
                    const SizedBox(height: 12),
                    _UnitsMessageBanner(message: _localError!, isError: true),
                  ],
                  if (provider.errorMessage != null &&
                      provider.isSaving == false) ...[
                    const SizedBox(height: 12),
                    _UnitsMessageBanner(
                      message: provider.errorMessage!,
                      isError: true,
                    ),
                  ],
                  const SizedBox(height: 16),
                  _UnitTextField(
                    controller: _nameController,
                    label: 'Unit name',
                    helper: 'Shown in pickers and configurator lists',
                    readOnly: _isReadOnly,
                  ),
                  const SizedBox(height: 12),
                  _UnitTextField(
                    controller: _symbolController,
                    label: 'Symbol',
                    helper: 'Shown beside quantities and on material records',
                    readOnly: _isReadOnly,
                  ),
                  const SizedBox(height: 12),
                  _UnitTextField(
                    controller: _notesController,
                    label: 'Notes',
                    helper: 'Optional context for operators',
                    readOnly: _isReadOnly,
                    maxLines: 3,
                    required: false,
                  ),
                  const SizedBox(height: 16),
                  _PreviewCard(
                    name: _nameController.text.trim(),
                    symbol: _symbolController.text.trim(),
                  ),
                  const SizedBox(height: 16),
                  _WarningText(
                    warning: provider
                        .checkDuplicate(
                          name: _nameController.text,
                          symbol: _symbolController.text,
                          excludeId: widget.unit?.id,
                        )
                        .warning,
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (!_isReadOnly)
                        AppButton(
                          label: widget.unit == null
                              ? 'Create Unit'
                              : 'Save Changes',
                          isLoading: provider.isSaving,
                          onPressed: () => _submit(context),
                        ),
                      if (widget.unit != null)
                        AppButton(
                          label: widget.unit!.isArchived
                              ? 'Restore'
                              : 'Archive',
                          variant: AppButtonVariant.secondary,
                          isLoading: provider.isSaving,
                          onPressed: () async {
                            final result = widget.unit!.isArchived
                                ? await provider.restoreUnit(widget.unit!.id)
                                : await provider.archiveUnit(widget.unit!.id);
                            if (context.mounted && result != null) {
                              Navigator.of(context).pop(result);
                            }
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit(BuildContext context) async {
    if (_isReadOnly) {
      return;
    }
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final provider = context.read<UnitsProvider>();
    final duplicate = provider.checkDuplicate(
      name: _nameController.text,
      symbol: _symbolController.text,
      excludeId: widget.unit?.id,
    );
    if (duplicate.blockingDuplicate) {
      setState(() {
        _localError = 'A unit with the same name and symbol already exists.';
      });
      return;
    }

    setState(() {
      _localError = null;
    });

    final result = widget.unit == null
        ? await provider.createUnit(
            CreateUnitInput(
              name: _nameController.text.trim(),
              symbol: _symbolController.text.trim(),
              notes: _notesController.text.trim(),
            ),
          )
        : await provider.updateUnit(
            UpdateUnitInput(
              id: widget.unit!.id,
              name: _nameController.text.trim(),
              symbol: _symbolController.text.trim(),
              notes: _notesController.text.trim(),
            ),
          );

    if (context.mounted && result != null) {
      Navigator.of(context).pop(result);
    }
  }
}

class _UnitTextField extends StatelessWidget {
  const _UnitTextField({
    required this.controller,
    required this.label,
    required this.helper,
    required this.readOnly,
    this.maxLines = 1,
    this.required = true,
  });

  final TextEditingController controller;
  final String label;
  final String helper;
  final bool readOnly;
  final int maxLines;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        filled: true,
        fillColor: readOnly ? const Color(0xFFF3F4F6) : const Color(0xFFF9FAFB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
        ),
      ),
      validator: (value) {
        if (!required) {
          return null;
        }
        if ((value ?? '').trim().isEmpty) {
          return 'Required';
        }
        return null;
      },
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.name, required this.symbol});

  final String name;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final previewName = name.isEmpty ? 'Unit name' : name;
    final previewSymbol = symbol.isEmpty ? 'sym' : symbol;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Preview',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF6B7280),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text('12 $previewSymbol'),
          const SizedBox(height: 4),
          Text(
            '$previewName ($previewSymbol)',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF475569)),
          ),
        ],
      ),
    );
  }
}

class _WarningText extends StatelessWidget {
  const _WarningText({required this.warning});

  final UnitDuplicateWarning warning;

  @override
  Widget build(BuildContext context) {
    final message = switch (warning) {
      UnitDuplicateWarning.none => null,
      UnitDuplicateWarning.nameOnly =>
        'A unit with the same name already exists. You can still save if the symbol is intentionally different.',
      UnitDuplicateWarning.symbolOnly =>
        'A unit with the same symbol already exists. You can still save if this reuse is intentional.',
      UnitDuplicateWarning.nameAndSymbol =>
        'A unit with this exact name and symbol already exists.',
    };
    if (message == null) {
      return const SizedBox.shrink();
    }
    return Text(
      message,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: warning == UnitDuplicateWarning.nameAndSymbol
            ? const Color(0xFFB91C1C)
            : const Color(0xFF92400E),
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _UnitsMessageBanner extends StatelessWidget {
  const _UnitsMessageBanner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFFFEF2F2) : const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isError ? const Color(0xFFFECACA) : const Color(0xFFA7F3D0),
        ),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: isError ? const Color(0xFFB91C1C) : const Color(0xFF047857),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

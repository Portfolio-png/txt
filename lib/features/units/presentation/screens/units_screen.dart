import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/searchable_select.dart';
import '../../../../core/widgets/soft_master_data.dart';
import '../../../../core/widgets/soft_primitives.dart';
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

        return SoftMasterDataPage(
          title: 'Units',
          subtitle:
              'Create the measurement units and symbols your team uses across materials and configurator flows.',
          action: AppButton(
            label: 'Add Unit',
            icon: Icons.add,
            isLoading: units.isSaving,
            onPressed: () => _openUnitEditor(context),
          ),
          toolbar: const _UnitsToolbar(),
          messages: [
            if (units.errorMessage != null)
              _UnitsMessageBanner(message: units.errorMessage!, isError: true),
          ],
          body: units.filteredUnits.isEmpty
              ? const AppEmptyState(
                  title: 'No units found',
                  message:
                      'Create a unit like Kilogram or Bundle to reuse it across inventory forms.',
                  icon: Icons.straighten_outlined,
                )
              : _UnitsTable(units: units.filteredUnits),
        );
      },
    );
  }

  static Future<UnitDefinition?> openEditor(
    BuildContext context, {
    UnitDefinition? unit,
    String initialName = '',
    String initialGroupName = '',
    int? initialConversionBaseUnitId,
  }) {
    final isNarrow = MediaQuery.of(context).size.width < 900;
    final body = _UnitEditorSheet(
      unit: unit,
      initialName: initialName,
      initialGroupName: initialGroupName,
      initialConversionBaseUnitId: initialConversionBaseUnitId,
    );
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
          constraints: BoxConstraints(maxWidth: unit == null ? 460 : 520),
          child: body,
        ),
      ),
    );
  }

  static Future<UnitDefinition?> _openUnitEditor(
    BuildContext context, {
    UnitDefinition? unit,
    String initialName = '',
    String initialGroupName = '',
    int? initialConversionBaseUnitId,
  }) {
    return openEditor(
      context,
      unit: unit,
      initialName: initialName,
      initialGroupName: initialGroupName,
      initialConversionBaseUnitId: initialConversionBaseUnitId,
    );
  }
}

class _UnitsToolbar extends StatelessWidget {
  const _UnitsToolbar();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UnitsProvider>();
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    return SoftMasterToolbar(
      children: [
        if (!isDesktop)
          SoftMasterSearchField(
            width: 300,
            hintText: 'Search units or symbols',
            onChanged: provider.setSearchQuery,
          ),
        SoftSegmentedFilter<UnitStatusFilter>(
          selected: provider.statusFilter,
          onChanged: provider.setStatusFilter,
          options: const [
            SoftSegmentOption<UnitStatusFilter>(
              value: UnitStatusFilter.active,
              label: 'Active',
            ),
            SoftSegmentOption<UnitStatusFilter>(
              value: UnitStatusFilter.archived,
              label: 'Archived',
            ),
            SoftSegmentOption<UnitStatusFilter>(
              value: UnitStatusFilter.all,
              label: 'All',
            ),
          ],
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
    return SoftMasterTable(
      minWidth: 1120,
      columns: const [
        SoftTableColumn('Name', flex: 3),
        SoftTableColumn('Symbol', flex: 2),
        SoftTableColumn('Group', flex: 2),
        SoftTableColumn('Conversion', flex: 1),
        SoftTableColumn('Used In', flex: 1),
        SoftTableColumn('Status', flex: 1),
        SoftTableColumn('Actions', flex: 2),
      ],
      itemCount: units.length,
      rowBuilder: (context, index) => _UnitRow(unit: units[index]),
    );
  }
}

class _UnitRow extends StatelessWidget {
  const _UnitRow({required this.unit});

  final UnitDefinition unit;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UnitsProvider>();
    return SoftMasterRow(
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SoftInlineText(unit.name, weight: FontWeight.w700),
              if (unit.notes.isNotEmpty) ...[
                const SizedBox(height: 4),
                SoftInlineText(unit.notes, color: SoftErpTheme.textSecondary),
              ],
            ],
          ),
        ),
        Expanded(flex: 2, child: SoftInlineText(unit.symbol)),
        Expanded(
          flex: 2,
          child: SoftInlineText(
            unit.unitGroupName ?? 'Individual',
            color: unit.isGrouped
                ? SoftErpTheme.textPrimary
                : SoftErpTheme.textSecondary,
            weight: unit.isGrouped ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        Expanded(
          flex: 1,
          child: SoftInlineText(
            unit.isGrouped
                ? (unit.isBaseUnit ? 'Base' : '${unit.conversionFactor}x')
                : '-',
          ),
        ),
        Expanded(flex: 1, child: SoftInlineText('${unit.usageCount}')),
        Expanded(
          flex: 1,
          child: SoftStatusPill(
            label: unit.isArchived ? 'Archived' : 'Active',
            background: unit.isArchived
                ? const Color(0xFFF3F4F6)
                : const Color(0xFFECFDF5),
            textColor: unit.isArchived
                ? const Color(0xFF6B7280)
                : const Color(0xFF0F766E),
            borderColor: unit.isArchived
                ? const Color(0xFFE5E7EB)
                : const Color(0xFFBFEAD8),
          ),
        ),
        Expanded(
          flex: 2,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SoftActionLink(
                label: unit.isUsed ? 'View' : 'Edit',
                onTap: () => UnitsScreen.openEditor(context, unit: unit),
              ),
              SoftActionLink(
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
    );
  }
}

class _UnitEditorSheet extends StatefulWidget {
  const _UnitEditorSheet({
    this.unit,
    this.initialName = '',
    this.initialGroupName = '',
    this.initialConversionBaseUnitId,
  });

  final UnitDefinition? unit;
  final String initialName;
  final String initialGroupName;
  final int? initialConversionBaseUnitId;

  @override
  State<_UnitEditorSheet> createState() => _UnitEditorSheetState();
}

enum _UnitGroupingMode { individual, existingFamily, newFamily }

class _UnitEditorSheetState extends State<_UnitEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _symbolController;
  late final TextEditingController _notesController;
  late final TextEditingController _groupController;
  late final TextEditingController _conversionController;
  String? _localError;
  int? _selectedExistingFamilyUnitId;
  late _UnitGroupingMode _groupingMode;

  bool get _isDetailsLocked => widget.unit?.isUsed ?? false;
  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.unit?.name ?? widget.initialName,
    );
    _symbolController = TextEditingController(text: widget.unit?.symbol ?? '');
    _notesController = TextEditingController(text: widget.unit?.notes ?? '');
    _groupController = TextEditingController(
      text: widget.unit?.unitGroupName ?? widget.initialGroupName,
    );
    _conversionController = TextEditingController(
      text: widget.unit?.conversionFactor.toString() ?? '1',
    );
    _selectedExistingFamilyUnitId = widget.initialConversionBaseUnitId;
    _nameController.addListener(_handleChange);
    _symbolController.addListener(_handleChange);
    _groupController.addListener(_handleChange);
    _conversionController.addListener(_handleChange);
    _groupingMode = _initialGroupingMode();
  }

  _UnitGroupingMode _initialGroupingMode() {
    if (widget.unit == null && widget.initialConversionBaseUnitId != null) {
      return _UnitGroupingMode.existingFamily;
    }
    if (widget.unit == null && widget.initialGroupName.trim().isNotEmpty) {
      return _UnitGroupingMode.existingFamily;
    }
    if (_groupController.text.trim().isEmpty) {
      return _UnitGroupingMode.individual;
    }
    if (widget.unit?.conversionBaseUnitId == null) {
      return _UnitGroupingMode.newFamily;
    }
    return _UnitGroupingMode.existingFamily;
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
    _groupController.removeListener(_handleChange);
    _conversionController.removeListener(_handleChange);
    _nameController.dispose();
    _symbolController.dispose();
    _notesController.dispose();
    _groupController.dispose();
    _conversionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UnitsProvider>();
    final isNarrow = MediaQuery.of(context).size.width < 900;
    final isCreateMode = widget.unit == null;
    final groupName = _resolvedGroupName(provider);
    final baseUnit = _resolvedBaseUnit(provider, groupName);
    final existingFamilyBaseUnits =
        provider.activeUnits
            .where(
              (unit) =>
                  !unit.isArchived &&
                  (widget.unit == null || unit.id != widget.unit!.id),
            )
            .toList(growable: false)
          ..sort(
            (a, b) => _existingFamilyLabel(
              a,
            ).toLowerCase().compareTo(_existingFamilyLabel(b).toLowerCase()),
          );
    final requiresConversion =
        _groupingMode == _UnitGroupingMode.existingFamily && baseUnit != null;
    final title = widget.unit == null
        ? 'Create Unit'
        : _isDetailsLocked
        ? 'Update Unit Group'
        : 'Edit Unit';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(isNarrow ? 28 : 32),
      child: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.fromLTRB(
                    28,
                    24,
                    20,
                    isCreateMode ? 18 : 24,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFE6EAF4)),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isCreateMode) ...[
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF6C63FF), Color(0xFF8B5CF6)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x336C63FF),
                                blurRadius: 20,
                                offset: Offset(0, 10),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.straighten_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 16),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isCreateMode) ...[
                              _DialogEyebrow(
                                icon: Icons.tune_rounded,
                                label: _isDetailsLocked
                                    ? 'Used unit'
                                    : 'Reusable unit',
                              ),
                              const SizedBox(height: 12),
                            ],
                            Text(
                              title,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF1E293B),
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              isCreateMode
                                  ? 'Create the unit you need now. You can refine the rest later in Masters.'
                                  : _isDetailsLocked
                                  ? 'This unit is already used in materials. Core details stay locked, but you can still reorganize its family and compatibility.'
                                  : 'Shape how this unit appears in forms, where it belongs, and how it converts inside a broader unit family.',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: const Color(0xFF667085),
                                    height: 1.45,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFF8FAFC),
                          foregroundColor: const Color(0xFF334155),
                          side: const BorderSide(color: Color(0xFFD9E2F2)),
                        ),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_localError != null) ...[
                        _UnitsMessageBanner(
                          message: _localError!,
                          isError: true,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (provider.errorMessage != null &&
                          provider.isSaving == false) ...[
                        _UnitsMessageBanner(
                          message: provider.errorMessage!,
                          isError: true,
                        ),
                        const SizedBox(height: 16),
                      ],
                      _EditorSectionCard(
                        icon: Icons.edit_note_rounded,
                        title: 'Unit basics',
                        subtitle: isCreateMode
                            ? 'Only the essentials needed to use this unit immediately.'
                            : 'Give the unit a clear label and symbol your team will recognize at a glance.',
                        child: Column(
                          children: [
                            _UnitTextField(
                              controller: _nameController,
                              label: 'Unit name',
                              helper: 'Shown in pickers and configurator lists',
                              readOnly: _isDetailsLocked,
                            ),
                            const SizedBox(height: 14),
                            _UnitTextField(
                              controller: _symbolController,
                              label: 'Symbol',
                              helper:
                                  'Shown beside quantities and on material records',
                              readOnly: _isDetailsLocked,
                            ),
                            if (!_isDetailsLocked) ...[
                              if (!isCreateMode) ...[
                                const SizedBox(height: 14),
                                _UnitTextField(
                                  controller: _notesController,
                                  label: 'Notes',
                                  helper: 'Optional context for operators',
                                  readOnly: _isDetailsLocked,
                                  maxLines: 3,
                                  required: false,
                                ),
                              ],
                              const SizedBox(height: 14),
                              _WarningText(
                                warning: provider
                                    .checkDuplicate(
                                      name: _nameController.text,
                                      symbol: _symbolController.text,
                                      excludeId: widget.unit?.id,
                                    )
                                    .warning,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      _EditorSectionCard(
                        icon: Icons.account_tree_outlined,
                        title: 'Usage and family',
                        subtitle: isCreateMode
                            ? 'Choose whether the unit stays standalone or belongs to a family.'
                            : 'Decide whether this unit stays independent or belongs to a group with shared compatibility.',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _UnitGroupingSection(
                              mode: _groupingMode,
                              onModeChanged: (mode) {
                                setState(() {
                                  _groupingMode = mode;
                                  if (mode == _UnitGroupingMode.individual) {
                                    _groupController.text = '';
                                    _conversionController.text = '1';
                                    _selectedExistingFamilyUnitId = null;
                                  } else if (mode ==
                                          _UnitGroupingMode.newFamily &&
                                      _groupController.text.trim().isEmpty) {
                                    _groupController.text = _nameController.text
                                        .trim();
                                    _conversionController.text = '1';
                                    _selectedExistingFamilyUnitId = null;
                                  }
                                });
                              },
                              controller: _groupController,
                              suggestions: provider.availableGroupNames,
                              existingFamilyBaseUnits: existingFamilyBaseUnits,
                              selectedExistingFamilyUnitId:
                                  _selectedExistingFamilyUnitId ?? baseUnit?.id,
                              onExistingFamilySelected: (unit) {
                                setState(() {
                                  _selectedExistingFamilyUnitId = unit.id;
                                  _groupController.text =
                                      (unit.unitGroupName ?? '').trim().isEmpty
                                      ? unit.name
                                      : unit.unitGroupName!.trim();
                                });
                              },
                              currentUnitName: _nameController.text.trim(),
                              compact: isCreateMode,
                            ),
                            if (_groupingMode !=
                                _UnitGroupingMode.individual) ...[
                              const SizedBox(height: 16),
                              _ConversionField(
                                controller: _conversionController,
                                readOnly: !requiresConversion,
                                helper: baseUnit == null
                                    ? 'This unit becomes the base unit for the new family. Conversion stays 1.'
                                    : '1 ${_symbolController.text.trim().isEmpty ? 'unit' : _symbolController.text.trim()} = this many ${baseUnit.symbol}.',
                              ),
                              const SizedBox(height: 10),
                              Text(
                                _groupingMode == _UnitGroupingMode.newFamily
                                    ? 'This creates a new unit family with this unit as the reference point.'
                                    : 'Units in the same family can be used interchangeably anywhere that family is allowed.',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: const Color(0xFF475569),
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (!isCreateMode) ...[
                        const SizedBox(height: 18),
                        _EditorSectionCard(
                          icon: Icons.visibility_outlined,
                          title: 'Live preview',
                          subtitle:
                              'A quick glance at how this unit will read inside forms and records.',
                          child: _PreviewCard(
                            name: _nameController.text.trim(),
                            symbol: _symbolController.text.trim(),
                            groupName: groupName,
                            conversionText:
                                _groupingMode == _UnitGroupingMode.individual
                                ? null
                                : (baseUnit == null
                                      ? 'Base unit (1x)'
                                      : '${_conversionController.text.trim().isEmpty ? '1' : _conversionController.text.trim()}x of ${baseUnit.symbol}'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(28, 18, 28, 28),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFCFCFF),
                    border: Border(top: BorderSide(color: Color(0xFFE7EAF3))),
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    runAlignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      Text(
                        widget.unit == null
                            ? 'This unit will be available immediately after save.'
                            : _isDetailsLocked
                            ? 'Core details are locked because this unit is already in use.'
                            : 'Changes apply anywhere this unit is available.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          if (widget.unit != null)
                            AppButton(
                              label: widget.unit!.isArchived
                                  ? 'Restore'
                                  : 'Archive',
                              variant: AppButtonVariant.secondary,
                              isLoading: provider.isSaving,
                              onPressed: () async {
                                final result = widget.unit!.isArchived
                                    ? await provider.restoreUnit(
                                        widget.unit!.id,
                                      )
                                    : await provider.archiveUnit(
                                        widget.unit!.id,
                                      );
                                if (context.mounted && result != null) {
                                  Navigator.of(context).pop(result);
                                }
                              },
                            ),
                          AppButton(
                            label: widget.unit == null
                                ? 'Create Unit'
                                : _isDetailsLocked
                                ? 'Update Group'
                                : 'Save Changes',
                            isLoading: provider.isSaving,
                            onPressed: () => _submit(context),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit(BuildContext context) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final provider = context.read<UnitsProvider>();
    final groupName = _resolvedGroupName(provider);
    final baseUnit = _resolvedBaseUnit(provider, groupName);
    final conversionFactor =
        double.tryParse(_conversionController.text.trim()) ?? 0;
    if (_groupingMode == _UnitGroupingMode.existingFamily &&
        baseUnit != null &&
        conversionFactor <= 0) {
      setState(() {
        _localError = 'Enter a conversion factor greater than 0.';
      });
      return;
    }
    if (!_isDetailsLocked) {
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
              unitGroupName: groupName,
              conversionFactor: baseUnit == null ? 1 : conversionFactor,
            ),
          )
        : await provider.updateUnit(
            UpdateUnitInput(
              id: widget.unit!.id,
              name: _nameController.text.trim(),
              symbol: _symbolController.text.trim(),
              notes: _notesController.text.trim(),
              unitGroupName: groupName,
              conversionFactor: baseUnit == null ? 1 : conversionFactor,
            ),
          );

    if (context.mounted && result != null) {
      Navigator.of(context).pop(result);
    }
  }

  UnitDefinition? _resolvedBaseUnit(UnitsProvider provider, String groupName) {
    if (_groupingMode != _UnitGroupingMode.existingFamily) {
      return null;
    }
    final selectedBaseUnitId = _selectedExistingFamilyUnitId;
    if (selectedBaseUnitId != null) {
      final baseUnit = provider.findById(selectedBaseUnitId);
      if (baseUnit != null) {
        return baseUnit;
      }
    }
    final initialBaseUnitId = widget.initialConversionBaseUnitId;
    if (widget.unit == null && initialBaseUnitId != null) {
      final baseUnit = provider.findById(initialBaseUnitId);
      if (baseUnit != null) {
        return baseUnit;
      }
    }
    return provider.findBaseUnitForGroupName(
      groupName,
      excludeId: widget.unit?.id,
    );
  }

  String _resolvedGroupName([UnitsProvider? provider]) {
    if (_groupingMode == _UnitGroupingMode.individual) {
      return '';
    }
    final explicitGroupName = _groupController.text.trim();
    if (explicitGroupName.isNotEmpty) {
      return explicitGroupName;
    }
    final selectedBaseUnitId = _selectedExistingFamilyUnitId;
    if (provider != null && selectedBaseUnitId != null) {
      final baseUnit = provider.findById(selectedBaseUnitId);
      if (baseUnit != null) {
        final unitGroupName = (baseUnit.unitGroupName ?? '').trim();
        return unitGroupName.isNotEmpty ? unitGroupName : baseUnit.name;
      }
    }
    final initialBaseUnitId = widget.initialConversionBaseUnitId;
    if (provider != null && widget.unit == null && initialBaseUnitId != null) {
      final baseUnit = provider.findById(initialBaseUnitId);
      if (baseUnit != null) {
        final unitGroupName = (baseUnit.unitGroupName ?? '').trim();
        return unitGroupName.isNotEmpty ? unitGroupName : baseUnit.name;
      }
    }
    return '';
  }

  String _existingFamilyLabel(UnitDefinition unit) {
    final familyName = (unit.unitGroupName ?? '').trim();
    if (familyName.isNotEmpty) {
      return '$familyName · Base ${unit.displayLabel}';
    }
    return '${unit.name} · Standalone base ${unit.symbol}';
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF6C63FF), width: 1.4),
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
  const _PreviewCard({
    required this.name,
    required this.symbol,
    required this.groupName,
    required this.conversionText,
  });

  final String name;
  final String symbol;
  final String groupName;
  final String? conversionText;

  @override
  Widget build(BuildContext context) {
    final previewName = name.isEmpty ? 'Unit name' : name;
    final previewSymbol = symbol.isEmpty ? 'sym' : symbol;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF8FAFF), Color(0xFFF7F7FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFDCE3F1)),
                ),
                child: Text(
                  'Preview',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF5B5BD6),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.visibility_outlined,
                color: Color(0xFF94A3B8),
                size: 18,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '12 $previewSymbol',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: const Color(0xFF1E293B),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$previewName ($previewSymbol)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF475569),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _PreviewMetaPill(
                label: groupName.isEmpty ? 'Mode' : 'Family',
                value: groupName.isEmpty ? 'Individual' : groupName,
              ),
              if (conversionText != null)
                _PreviewMetaPill(label: 'Conversion', value: conversionText!),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConversionField extends StatelessWidget {
  const _ConversionField({
    required this.controller,
    required this.readOnly,
    required this.helper,
  });

  final TextEditingController controller;
  final bool readOnly;
  final String helper;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: 'Conversion to group base',
        helperText: helper,
        filled: true,
        fillColor: readOnly ? const Color(0xFFF3F4F6) : const Color(0xFFF9FAFB),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF6C63FF), width: 1.4),
        ),
      ),
      validator: (value) {
        if (readOnly) {
          return null;
        }
        final parsed = double.tryParse((value ?? '').trim());
        if (parsed == null || parsed <= 0) {
          return 'Enter a number greater than 0';
        }
        return null;
      },
    );
  }
}

class _UnitGroupField extends StatelessWidget {
  const _UnitGroupField({
    required this.controller,
    required this.readOnly,
    required this.suggestions,
    this.label = 'Unit group',
    this.helper =
        'Optional. Type an existing group or a new one. Clear the field to make this unit individual.',
  });

  final TextEditingController controller;
  final bool readOnly;
  final List<String> suggestions;
  final String label;
  final String helper;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: controller,
          readOnly: readOnly,
          decoration: InputDecoration(
            labelText: label,
            helperText: helper,
            filled: true,
            fillColor: const Color(0xFFF9FAFB),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 18,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(
                color: Color(0xFF6C63FF),
                width: 1.4,
              ),
            ),
          ),
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: suggestions
                .where((name) => name != controller.text.trim())
                .take(6)
                .map(
                  (name) => InkWell(
                    onTap: () => controller.text = name,
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Text(
                        name,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }
}

class _UnitGroupingSection extends StatelessWidget {
  const _UnitGroupingSection({
    required this.mode,
    required this.onModeChanged,
    required this.controller,
    required this.suggestions,
    required this.existingFamilyBaseUnits,
    required this.selectedExistingFamilyUnitId,
    required this.onExistingFamilySelected,
    required this.currentUnitName,
    this.compact = false,
  });

  final _UnitGroupingMode mode;
  final ValueChanged<_UnitGroupingMode> onModeChanged;
  final TextEditingController controller;
  final List<String> suggestions;
  final List<UnitDefinition> existingFamilyBaseUnits;
  final int? selectedExistingFamilyUnitId;
  final ValueChanged<UnitDefinition> onExistingFamilySelected;
  final String currentUnitName;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How should this unit be used?',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF1F2937),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          compact
              ? 'Keep it standalone, join an existing family, or start a new one.'
              : 'Pick the simplest behavior first. You can keep it standalone, join an existing family, or start a new one.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: const Color(0xFF667085),
            height: 1.45,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ModeChip(
              label: compact ? 'Individual' : 'Keep individual',
              subtitle: compact ? 'Standalone' : 'Use it as a standalone unit',
              icon: Icons.looks_one_outlined,
              selected: mode == _UnitGroupingMode.individual,
              onTap: () => onModeChanged(_UnitGroupingMode.individual),
            ),
            _ModeChip(
              label: compact ? 'Existing family' : 'Use existing family',
              subtitle: compact ? 'Join one' : 'Join a family already in use',
              icon: Icons.merge_type_rounded,
              selected: mode == _UnitGroupingMode.existingFamily,
              onTap: () => onModeChanged(_UnitGroupingMode.existingFamily),
            ),
            _ModeChip(
              label: compact ? 'New family' : 'Start new family',
              subtitle: compact
                  ? 'Create one'
                  : 'Create a new compatibility set',
              icon: Icons.add_chart_rounded,
              selected: mode == _UnitGroupingMode.newFamily,
              onTap: () => onModeChanged(_UnitGroupingMode.newFamily),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (mode == _UnitGroupingMode.existingFamily)
          SearchableSelectField<int>(
            tapTargetKey: const ValueKey<String>('unit-existing-family-field'),
            value:
                existingFamilyBaseUnits.any(
                  (unit) => unit.id == selectedExistingFamilyUnitId,
                )
                ? selectedExistingFamilyUnitId
                : null,
            decoration: _unitFamilySelectDecoration(
              label: 'Existing family',
              helper:
                  'Search an existing base unit/family. This unit will convert into that base.',
            ),
            dialogTitle: 'Existing family',
            searchHintText: 'Search unit family',
            emptyText: 'No unit families found',
            options: existingFamilyBaseUnits
                .map(
                  (unit) => SearchableSelectOption<int>(
                    value: unit.id,
                    label: _existingFamilyOptionLabel(unit),
                    searchText:
                        '${unit.name} ${unit.symbol} ${unit.unitGroupName ?? ''}',
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              final selected = existingFamilyBaseUnits
                  .where((unit) => unit.id == value)
                  .firstOrNull;
              if (selected != null) {
                onExistingFamilySelected(selected);
              }
            },
          ),
        if (mode == _UnitGroupingMode.newFamily)
          _UnitGroupField(
            controller: controller,
            readOnly: false,
            suggestions: const [],
            label: 'New family name',
            helper: currentUnitName.isEmpty
                ? 'Give this new family a name like Length, Mass, or Quantity.'
                : 'A simple family name like "$currentUnitName" or "Length" works well.',
          ),
      ],
    );
  }

  InputDecoration _unitFamilySelectDecoration({
    required String label,
    required String helper,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helper,
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF6C63FF), width: 1.4),
      ),
    );
  }

  String _existingFamilyOptionLabel(UnitDefinition unit) {
    final familyName = (unit.unitGroupName ?? '').trim();
    if (familyName.isNotEmpty) {
      return '$familyName · Base ${unit.displayLabel}';
    }
    return '${unit.name} · Standalone base ${unit.symbol}';
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        constraints: const BoxConstraints(minWidth: 180, maxWidth: 220),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEEF2FF) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFF6C63FF) : const Color(0xFFD7DBE7),
          ),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x1A6C63FF),
                    blurRadius: 16,
                    offset: Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: selected ? Colors.white : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 18,
                color: selected
                    ? const Color(0xFF5145E5)
                    : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: selected
                          ? const Color(0xFF4338CA)
                          : const Color(0xFF0F172A),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: selected
                          ? const Color(0xFF5B5BD6)
                          : const Color(0xFF64748B),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorSectionCard extends StatelessWidget {
  const _EditorSectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFCFF),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE5EAF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: const Color(0xFF5145E5), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF1E293B),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF667085),
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _DialogEyebrow extends StatelessWidget {
  const _DialogEyebrow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD9E2F2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF5145E5)),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF4F46E5),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewMetaPill extends StatelessWidget {
  const _PreviewMetaPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCE3F1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF1E293B),
              fontWeight: FontWeight.w800,
            ),
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

import 'package:flutter/material.dart';
import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/core/widgets/searchable_select.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/features/items/presentation/screens/items_screen.dart';
import 'package:core_erp/features/units/domain/unit_definition.dart';
import 'package:core_erp/features/units/presentation/providers/units_provider.dart';
import 'package:provider/provider.dart';

import '../../production_pipelines/data/repositories/pipeline_run_repository.dart';
import '../../production_pipelines/domain/pipeline_item_endpoint.dart';
import '../../production_pipelines/domain/pipeline_template.dart';
import '../../production_pipelines/domain/process_node.dart';
import '../domain/default_floor_context.dart';
import '../providers/pipeline_editor_provider.dart';
import '../providers/production_provider.dart';
import 'live_production_monitor_screen.dart';
import 'pipeline_builder_screen.dart';

class PipelinesScreen extends StatefulWidget {
  const PipelinesScreen({
    super.key,
    this.factoryId = defaultProductionFactoryId,
    this.shopFloorId = defaultProductionShopFloorId,
  });

  final String factoryId;
  final String shopFloorId;

  @override
  State<PipelinesScreen> createState() => _PipelinesScreenState();
}

class _PipelinesScreenState extends State<PipelinesScreen> {
  bool _isLoading = true;
  List<PipelineTemplate> _templates = [];
  PipelineTemplate? _editingTemplate;
  PipelineTemplateStatus _filterStatus = PipelineTemplateStatus.active;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initializeItemMasterData();
      }
    });
    _loadTemplates();
  }

  @override
  void didUpdateWidget(covariant PipelinesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shopFloorId != widget.shopFloorId) {
      _editingTemplate = null;
      _loadTemplates();
    }
  }

  Future<void> _initializeItemMasterData() async {
    final futures = <Future<void>>[];
    try {
      futures.add(context.read<ItemsProvider>().initialize());
    } catch (_) {}
    try {
      futures.add(context.read<UnitsProvider>().initialize());
    } catch (_) {}
    await Future.wait(futures);
  }

  Future<void> _loadTemplates() async {
    setState(() => _isLoading = true);
    try {
      final repo = context.read<PipelineRunRepository>();
      final allTemplates = await repo.getTemplates();
      final floorTemplates = allTemplates
          .where(_belongsToActiveFloor)
          .toList(growable: false);
      if (!mounted) return;
      setState(() => _templates = floorTemplates);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createNew() async {
    await _initializeItemMasterData();
    if (!mounted) {
      return;
    }
    final nameCtrl = TextEditingController(text: 'New Pipeline');
    final descCtrl = TextEditingController();
    final items = _activeItemsFromContext(context);
    final units = _activeUnitsFromContext(context);
    int? inputItemId = items.isNotEmpty ? items.first.id : null;
    int? outputItemId = items.length > 1 ? items[1].id : inputItemId;

    final formKey = GlobalKey<FormState>();

    final result = await showDialog<PipelineTemplate>(
      context: context,
      builder: (dialogContext) {
        var currentItems = items;
        var currentUnits = units;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Create New Pipeline'),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: nameCtrl,
                          decoration: _softInputDecoration(
                            label: 'Pipeline Name',
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Name is required'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: descCtrl,
                          decoration: _softInputDecoration(
                            label: 'Description (Optional)',
                          ),
                          minLines: 2,
                          maxLines: 3,
                        ),
                        const SizedBox(height: 12),
                        _PipelineItemSelectField(
                          tapTargetKey: const ValueKey(
                            'create-pipeline-input-item-field',
                          ),
                          label: 'Input Material',
                          dialogTitle: 'Input Material',
                          selectedItemId: inputItemId,
                          items: currentItems,
                          units: currentUnits,
                          onChanged: (item) {
                            setDialogState(() {
                              inputItemId = item.id;
                            });
                          },
                          onCreated: (item) {
                            setDialogState(() {
                              currentItems = _activeItemsFromContext(context);
                              currentUnits = _activeUnitsFromContext(context);
                              inputItemId = item.id;
                            });
                          },
                          validator: (value) => value == null
                              ? 'Input material is required'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        _PipelineItemSelectField(
                          tapTargetKey: const ValueKey(
                            'create-pipeline-output-item-field',
                          ),
                          label: 'Output Material',
                          dialogTitle: 'Output Material',
                          selectedItemId: outputItemId,
                          items: currentItems,
                          units: currentUnits,
                          onChanged: (item) {
                            setDialogState(() {
                              outputItemId = item.id;
                            });
                          },
                          onCreated: (item) {
                            setDialogState(() {
                              currentItems = _activeItemsFromContext(context);
                              currentUnits = _activeUnitsFromContext(context);
                              outputItemId = item.id;
                            });
                          },
                          validator: (value) => value == null
                              ? 'Output material is required'
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    if (formKey.currentState?.validate() == true) {
                      final name = nameCtrl.text.trim();
                      final desc = descCtrl.text.trim();
                      final inputItem = _itemById(currentItems, inputItemId);
                      final outputItem = _itemById(currentItems, outputItemId);
                      if (inputItem == null || outputItem == null) {
                        return;
                      }
                      final inputEndpoint = _endpointForItem(
                        inputItem,
                        currentUnits,
                      );
                      final outputEndpoint = _endpointForItem(
                        outputItem,
                        currentUnits,
                      );
                      final input = inputEndpoint.itemName;
                      final output = outputEndpoint.itemName;
                      final now = DateTime.now().microsecondsSinceEpoch;
                      final id = 'tpl-$now';

                      final inputNode = ProcessNode(
                        id: 'node-input-$now',
                        name: 'Input Stage',
                        processType: 'Input',
                        stageIndex: 0,
                        laneIndex: 0,
                        inputs: [input],
                        outputs: [input],
                        machine: 'Input Stage',
                        dieId: '',
                        durationHours: 0.25,
                        status: 'Ready',
                        isIntermediate: false,
                        inputItem: inputEndpoint,
                        outputItem: inputEndpoint,
                      );

                      final outputNode = ProcessNode(
                        id: 'node-output-${now + 1}',
                        name: 'Output Stage',
                        processType: 'Output',
                        stageIndex: 1,
                        laneIndex: 0,
                        inputs: [output],
                        outputs: [output],
                        machine: 'Output Stage',
                        dieId: '',
                        durationHours: 0.25,
                        status: 'Queued',
                        isIntermediate: false,
                        inputItem: outputEndpoint,
                        outputItem: outputEndpoint,
                      );

                      Navigator.pop(
                        context,
                        PipelineTemplate(
                          id: id,
                          factoryId: widget.factoryId,
                          shopFloorId: widget.shopFloorId,
                          name: name,
                          description: desc,
                          stageLabels: const ['Input', 'Output'],
                          laneLabels: const ['Main'],
                          nodes: [inputNode, outputNode],
                          flows: const [],
                          inputMaterial: input,
                          outputMaterial: output,
                        ),
                      );
                    }
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null && mounted) {
      setState(() {
        _editingTemplate = result;
      });
    }
    // Delay controller disposal to allow the dialog pop animation to finish completely
    Future.delayed(const Duration(milliseconds: 500), () {
      nameCtrl.dispose();
      descCtrl.dispose();
    });
  }

  Future<void> _duplicateTemplate(PipelineTemplate template) async {
    setState(() => _isLoading = true);
    try {
      final repo = context.read<PipelineRunRepository>();
      final now = DateTime.now().microsecondsSinceEpoch;
      
      final duplicate = template.copyWith(
        id: 'tpl-$now',
        name: '${template.name} (Copy)',
        status: PipelineTemplateStatus.draft,
      );
      
      await repo.createTemplate(duplicate);
      await _loadTemplates();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _edit(PipelineTemplate template) {
    setState(() => _editingTemplate = template);
  }

  void _run(PipelineTemplate template) {
    context.read<ProductionProvider>().loadTemplate(template);

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LiveProductionMonitorScreen()),
    );
  }

  Future<void> _closeEditorAndReload() async {
    setState(() => _editingTemplate = null);
    await _loadTemplates();
  }

  @override
  Widget build(BuildContext context) {
    final editingTemplate = _editingTemplate;
    if (editingTemplate != null) {
      return _PipelineEditorShell(
        templateName: editingTemplate.name,
        onBack: _closeEditorAndReload,
        child: ChangeNotifierProvider(
          create: (_) => PipelineEditorProvider(template: editingTemplate),
          child: PipelineBuilderScreen(
            factoryId: widget.factoryId,
            shopFloorId: widget.shopFloorId,
          ),
        ),
      );
    }

    final filteredTemplates = _templates.where((t) => t.status == _filterStatus).toList();

    return _PipelineLibraryShell(
      title: 'Floor Pipelines',
      subtitle: 'Build and run production routes on the unified floor map.',
      actionLabel: 'New Pipeline',
      onAction: _createNew,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: SegmentedButton<PipelineTemplateStatus>(
              segments: const [
                ButtonSegment(value: PipelineTemplateStatus.active, label: Text('Active')),
                ButtonSegment(value: PipelineTemplateStatus.draft, label: Text('Drafts')),
                ButtonSegment(value: PipelineTemplateStatus.archived, label: Text('Archived')),
              ],
              selected: {_filterStatus},
              onSelectionChanged: (Set<PipelineTemplateStatus> newSelection) {
                setState(() => _filterStatus = newSelection.first);
              },
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _isLoading
                  ? const _PipelineLoading(label: 'Loading pipelines')
                  : filteredTemplates.isEmpty
                  ? _PipelineEmptyState(
                      title: 'No pipelines found',
                      message: 'No pipelines match the current status filter.',
                      actionLabel: 'Create Pipeline',
                      onAction: _createNew,
                    )
                  : _PipelineTemplateList(
                      templates: filteredTemplates,
                      onEdit: _edit,
                      onRun: _run,
                      onDuplicate: _duplicateTemplate,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  bool _belongsToActiveFloor(PipelineTemplate template) {
    if (widget.shopFloorId == defaultProductionShopFloorId) {
      return true;
    }
    if (template.shopFloorId == widget.shopFloorId) {
      return true;
    }
    return belongsToDefaultFloor(template.shopFloorId);
  }
}

class _PipelineItemSelectField extends StatelessWidget {
  const _PipelineItemSelectField({
    required this.tapTargetKey,
    required this.label,
    required this.dialogTitle,
    required this.selectedItemId,
    required this.items,
    required this.units,
    required this.onChanged,
    required this.onCreated,
    required this.validator,
  });

  final Key tapTargetKey;
  final String label;
  final String dialogTitle;
  final int? selectedItemId;
  final List<ItemDefinition> items;
  final List<UnitDefinition> units;
  final ValueChanged<ItemDefinition> onChanged;
  final ValueChanged<ItemDefinition> onCreated;
  final FormFieldValidator<int> validator;

  @override
  Widget build(BuildContext context) {
    final hasSelection = items.any((item) => item.id == selectedItemId);
    final options = items
        .map(
          (item) => SearchableSelectOption<int>(
            value: item.id,
            label: _materialOptionLabel(item, units),
            searchText: _materialOptionSearchText(item, units),
          ),
        )
        .toList(growable: false);

    return SearchableSelectField<int>(
      tapTargetKey: tapTargetKey,
      value: hasSelection ? selectedItemId : null,
      decoration: _softInputDecoration(
        label: label,
        helper: 'Search item masters or create a new item.',
      ),
      dialogTitle: dialogTitle,
      searchHintText: 'Search item master',
      emptyText: 'No item masters found',
      options: options,
      canCreateOption: (query, allOptions) {
        final normalized = query.trim().toLowerCase();
        return normalized.isNotEmpty &&
            items.every(
              (item) => _itemName(item).trim().toLowerCase() != normalized,
            );
      },
      onCreateOption: (query) async {
        final created = await ItemsScreen.openEditor(
          context,
          initialName: query.trim(),
        );
        if (!context.mounted || created == null) {
          return null;
        }
        try {
          await context.read<ItemsProvider>().refresh();
        } catch (_) {}
        if (!context.mounted) {
          return null;
        }
        final refreshedUnits = _activeUnitsFromContext(context);
        onCreated(created);
        return SearchableSelectOption<int>(
          value: created.id,
          label: _materialOptionLabel(created, refreshedUnits),
          searchText: _materialOptionSearchText(created, refreshedUnits),
        );
      },
      createOptionLabelBuilder: (query) => 'Create item "$query"',
      onChanged: (value) {
        final item = _itemById(items, value);
        if (item != null) {
          onChanged(item);
        }
      },
      validator: validator,
    );
  }
}

InputDecoration _softInputDecoration({required String label, String? helper}) {
  return InputDecoration(
    labelText: label,
    helperText: helper,
    filled: true,
    fillColor: SoftErpTheme.cardSurfaceAlt,
    labelStyle: const TextStyle(
      color: SoftErpTheme.textSecondary,
      fontWeight: FontWeight.w700,
    ),
    helperStyle: const TextStyle(
      color: SoftErpTheme.textSecondary,
      fontWeight: FontWeight.w600,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: SoftErpTheme.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: SoftErpTheme.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: SoftErpTheme.accent, width: 1.4),
    ),
  );
}

List<ItemDefinition> _activeItemsFromContext(BuildContext context) {
  try {
    return context
        .read<ItemsProvider>()
        .items
        .where((item) => !item.isArchived)
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}

List<UnitDefinition> _activeUnitsFromContext(BuildContext context) {
  try {
    return context.read<UnitsProvider>().activeUnits;
  } catch (_) {
    return const [];
  }
}

ItemDefinition? _itemById(List<ItemDefinition> items, int? id) {
  if (id == null) {
    return null;
  }
  for (final item in items) {
    if (item.id == id) {
      return item;
    }
  }
  return null;
}

String _itemName(ItemDefinition item) {
  final displayName = item.displayName.trim();
  return displayName.isNotEmpty ? displayName : item.name;
}

String _materialOptionLabel(ItemDefinition item, List<UnitDefinition> units) {
  return '${_itemName(item)} (${_unitLabel(item.unitId, units)})';
}

String _materialOptionSearchText(
  ItemDefinition item,
  List<UnitDefinition> units,
) {
  return [
    item.name,
    item.displayName,
    item.alias,
    _unitLabel(item.unitId, units),
  ].where((part) => part.trim().isNotEmpty).join(' ');
}

String _unitLabel(int unitId, List<UnitDefinition> units) {
  for (final unit in units) {
    if (unit.id == unitId) {
      final symbol = unit.symbol.trim();
      if (symbol.isNotEmpty) {
        return symbol;
      }
      return unit.name;
    }
  }
  return 'Unit #$unitId';
}

PipelineItemEndpoint _endpointForItem(
  ItemDefinition item,
  List<UnitDefinition> units,
) {
  UnitDefinition? unit;
  for (final candidate in units) {
    if (candidate.id == item.unitId) {
      unit = candidate;
      break;
    }
  }
  return PipelineItemEndpoint(
    itemId: item.id,
    itemName: _itemName(item),
    unitId: item.unitId,
    unitName: unit?.name ?? '',
    unitSymbol: unit?.symbol ?? '',
  );
}

class _PipelineEditorShell extends StatelessWidget {
  const _PipelineEditorShell({
    required this.templateName,
    required this.onBack,
    required this.child,
  });

  final String templateName;
  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.84),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Back to pipelines'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF3B82F6),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    templateName.trim().isEmpty
                        ? 'Pipeline Builder'
                        : templateName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF1E293B),
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const _RouteBadge(label: 'Builder', value: 'Edit mode'),
              ],
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _PipelineTemplateList extends StatelessWidget {
  const _PipelineTemplateList({
    required this.templates,
    required this.onEdit,
    required this.onRun,
    required this.onDuplicate,
  });

  final List<PipelineTemplate> templates;
  final ValueChanged<PipelineTemplate> onEdit;
  final ValueChanged<PipelineTemplate> onRun;
  final ValueChanged<PipelineTemplate> onDuplicate;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _PipelineListHeader(),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: templates.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final template = templates[index];
              return _PipelineTemplateCard(
                template: template,
                onEdit: () => onEdit(template),
                onRun: () => onRun(template),
                onDuplicate: () => onDuplicate(template),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PipelineListHeader extends StatelessWidget {
  const _PipelineListHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: const Color(0xFFE9EEF9).withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Row(
        children: [
          _PipelineHeaderCell(label: 'Pipeline', flex: 4),
          _PipelineHeaderCell(label: 'Material Flow', flex: 3),
          _PipelineHeaderCell(label: 'Stages', flex: 1),
          _PipelineHeaderCell(label: 'Nodes', flex: 1),
          _PipelineHeaderCell(label: 'Flows', flex: 1),
          _PipelineHeaderCell(label: 'Status', flex: 1),
          _PipelineHeaderCell(label: 'Actions', flex: 2),
        ],
      ),
    );
  }
}

class _PipelineHeaderCell extends StatelessWidget {
  const _PipelineHeaderCell({required this.label, required this.flex});

  final String label;
  final int flex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF1E293B),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _PipelineTemplateCard extends StatelessWidget {
  const _PipelineTemplateCard({
    required this.template,
    required this.onEdit,
    required this.onRun,
    required this.onDuplicate,
  });

  final PipelineTemplate template;
  final VoidCallback onEdit;
  final VoidCallback onRun;
  final VoidCallback onDuplicate;

  @override
  Widget build(BuildContext context) {
    final nodeCount = template.nodes.length;
    final flowCount = template.flows.length;
    final stageCount = template.stageLabels.length;
    final hasRunnableRoute = nodeCount > 0;
    final routeText = [
      template.inputMaterial.trim().isEmpty
          ? 'Input material'
          : template.inputMaterial,
      template.outputMaterial.trim().isEmpty
          ? 'Output material'
          : template.outputMaterial,
    ].join(' -> ');

    final sortedNodes = template.nodes.toList()..sort((a, b) => a.stageIndex.compareTo(b.stageIndex));
    final miniFlow = sortedNodes.map((n) => n.processType).join(' ➔ ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          constraints: const BoxConstraints(minHeight: 86),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE5EAF4)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0C000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Row(
                  children: [
                    SizedBox(
                      width: 112,
                      height: 54,
                      child: CustomPaint(
                        painter: _PipelineCardPainter(
                          nodeCount: nodeCount,
                          flowCount: flowCount,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            template.name.trim().isEmpty
                                ? 'Unnamed pipeline'
                                : template.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF1E293B),
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            template.description.trim().isEmpty
                                ? 'Production route for the unified floor map'
                                : template.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _PipelineCardCell(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      routeText,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (miniFlow.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        miniFlow,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _PipelineMetricCell(value: '$stageCount'),
              _PipelineMetricCell(value: '$nodeCount'),
              _PipelineMetricCell(value: '$flowCount'),
              _PipelineCardCell(
                flex: 1,
                child: _PipelineStatusBadge(
                  label: template.status.name.toUpperCase(),
                  active: template.status == PipelineTemplateStatus.active,
                ),
              ),
              Expanded(
                flex: 2,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.copy, size: 20, color: Color(0xFF64748B)),
                      onPressed: onDuplicate,
                      tooltip: 'Duplicate Pipeline',
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.edit_rounded,
                        size: 20,
                        color: Color(0xFF64748B),
                      ),
                      onPressed: onEdit,
                      tooltip: 'Edit pipeline',
                    ),
                    const SizedBox(width: 4),
                    if (template.status == PipelineTemplateStatus.active)
                      FilledButton.icon(
                        onPressed: hasRunnableRoute ? onRun : null,
                        icon: const Icon(Icons.play_arrow_rounded, size: 16),
                        label: const Text('Run'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PipelineCardCell extends StatelessWidget {
  const _PipelineCardCell({required this.flex, required this.child});
  final int flex;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Expanded(flex: flex, child: Align(alignment: Alignment.centerLeft, child: child));
  }
}

class _PipelineMetricCell extends StatelessWidget {
  const _PipelineMetricCell({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: 1,
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF1E293B),
          fontSize: 14,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _PipelineActionButton extends StatelessWidget {
  const _PipelineActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.filled,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: filled
          ? (enabled ? const Color(0xFF3B82F6) : const Color(0xFFE1E5DF))
          : const Color(0xFFF1F3FF),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: filled
                    ? (enabled ? Colors.white : const Color(0xFF8A948F))
                    : const Color(0xFF4F46E5),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: filled
                      ? (enabled ? Colors.white : const Color(0xFF8A948F))
                      : const Color(0xFF4F46E5),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PipelineStatusBadge extends StatelessWidget {
  const _PipelineStatusBadge({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? const Color(0xFF1D4ED8) : const Color(0xFF64748B),
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _RouteBadge extends StatelessWidget {
  const _RouteBadge({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9).withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF1E293B),
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PipelineCardPainter extends CustomPainter {
  const _PipelineCardPainter({
    required this.nodeCount,
    required this.flowCount,
  });

  final int nodeCount;
  final int flowCount;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0).withValues(alpha: 0.34)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 32) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y < size.height; y += 32) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final routePaint = Paint()
      ..color = const Color(0xFF3B82F6).withValues(alpha: 0.42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final route = Path()
      ..moveTo(size.width * 0.12, size.height * 0.42)
      ..cubicTo(
        size.width * 0.30,
        size.height * 0.18,
        size.width * 0.44,
        size.height * 0.72,
        size.width * 0.62,
        size.height * 0.48,
      )
      ..quadraticBezierTo(
        size.width * 0.78,
        size.height * 0.30,
        size.width * 0.92,
        size.height * 0.54,
      );
    canvas.drawPath(route, routePaint);

    final nodePaint = Paint()
      ..color = nodeCount > 0
          ? const Color(0xFF3B82F6)
          : const Color(0xFFCBD5E1);
    final ringPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final point in [
      Offset(size.width * 0.12, size.height * 0.42),
      Offset(size.width * 0.38, size.height * 0.48),
      Offset(size.width * 0.62, size.height * 0.48),
      Offset(size.width * 0.92, size.height * 0.54),
    ]) {
      canvas.drawCircle(point, 5, nodePaint);
      canvas.drawCircle(point, 5, ringPaint);
    }

    if (flowCount == 0) {
      final draftPaint = Paint()
        ..color = const Color(0xFFF4B860).withValues(alpha: 0.26)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(size.width * 0.72, size.height * 0.30),
        16,
        draftPaint,
      );
      canvas.drawCircle(
        Offset(size.width * 0.72, size.height * 0.30),
        5,
        Paint()..color = const Color(0xFFD78D18),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PipelineCardPainter oldDelegate) {
    return oldDelegate.nodeCount != nodeCount ||
        oldDelegate.flowCount != flowCount;
  }
}

class _PipelineLibraryShell extends StatelessWidget {
  const _PipelineLibraryShell({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
    required this.child,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF1E293B),
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(actionLabel),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _PipelineEmptyState extends StatelessWidget {
  const _PipelineEmptyState({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 460,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.account_tree_rounded,
              color: Color(0xFF3B82F6),
              size: 38,
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF1E293B),
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _PipelineLoading extends StatelessWidget {
  const _PipelineLoading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/soft_erp_theme.dart';
import '../providers/production_provider.dart';

class PipelineBuilderScreen extends StatefulWidget {
  const PipelineBuilderScreen({super.key});

  @override
  State<PipelineBuilderScreen> createState() => _PipelineBuilderScreenState();
}

class _PipelineBuilderScreenState extends State<PipelineBuilderScreen> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'pipeline_builder');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProductionProvider>();
    final selectedStage = provider.selectedStage;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyN): () {
          context.read<ProductionProvider>().appendStage();
        },
        const SingleActivator(LogicalKeyboardKey.delete): () {
          final removed = context
              .read<ProductionProvider>()
              .deleteSelectedStage();
          if (removed == null) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${removed.name} removed.'),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: context
                    .read<ProductionProvider>()
                    .undoLastStageDelete,
              ),
            ),
          );
        },
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BuilderHeader(provider: provider),
              const SizedBox(height: 16),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 980;
                    return isWide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Expanded(child: _PipelineCanvas()),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                width: selectedStage == null ? 0 : 420,
                                child: selectedStage == null
                                    ? const SizedBox.shrink()
                                    : _StageInspector(stage: selectedStage),
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              const Expanded(child: _PipelineCanvas()),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                height: selectedStage == null ? 0 : 440,
                                child: selectedStage == null
                                    ? const SizedBox.shrink()
                                    : _StageInspector(stage: selectedStage),
                              ),
                            ],
                          );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BuilderHeader extends StatelessWidget {
  const _BuilderHeader({required this.provider});

  final ProductionProvider provider;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                provider.blueprint.name,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: SoftErpTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Production transformation chain: inputs, machine actions, die settings, outputs, and scrap.',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: SoftErpTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        _ProductionActionButton(
          icon: Icons.add_circle_outline,
          label: 'Add Stage',
          onPressed: context.read<ProductionProvider>().appendStage,
        ),
      ],
    );
  }
}

class _PipelineCanvas extends StatefulWidget {
  const _PipelineCanvas();

  @override
  State<_PipelineCanvas> createState() => _PipelineCanvasState();
}

class _PipelineCanvasState extends State<_PipelineCanvas> {
  final ScrollController _verticalController = ScrollController();

  @override
  void dispose() {
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stages = context.select<ProductionProvider, List<PipelineStage>>(
      (provider) => provider.blueprint.stages,
    );

    return DecoratedBox(
      decoration: const BoxDecoration(color: Colors.white),
      child: Scrollbar(
        controller: _verticalController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _verticalController,
          primary: false,
          padding: const EdgeInsets.all(24),
          child: Container(
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Color(0xFFE5E7EB), width: 1),
                left: BorderSide(color: Color(0xFFE5E7EB), width: 1),
              ),
            ),
            height: 280,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              itemCount: stages.length,
              onReorder: (oldIndex, newIndex) {
                context.read<ProductionProvider>().reorderStages(
                  oldIndex,
                  newIndex,
                );
              },
              itemBuilder: (context, index) {
                final stage = stages[index];
                return _PipelineNode(
                  key: ValueKey(stage.id),
                  stage: stage,
                  index: index,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PipelineNode extends StatelessWidget {
  const _PipelineNode({super.key, required this.stage, required this.index});

  final PipelineStage stage;
  final int index;

  @override
  Widget build(BuildContext context) {
    final selectedId = context.select<ProductionProvider, String?>(
      (provider) => provider.selectedStageId,
    );
    final isSelected = selectedId == stage.id;
    final rpm = 1200 + index * 150;
    final temp = 75 + index * 3;
    final telemetryText =
        '[${stage.machineId.toUpperCase()}] ${stage.machineAction.replaceAll(RegExp(r"\s+"), "_").toUpperCase()} // RPM: ${rpm.toString().replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]},")} // TEMP: ${temp}C // DIE_ID: #${stage.dieId.toUpperCase()}';

    return SizedBox(
      width: 360,
      child: InkWell(
        onTap: () => context.read<ProductionProvider>().selectStage(stage.id),
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFF3F4F6) : Colors.white,
            border: const Border(
              right: BorderSide(color: Color(0xFFE5E7EB), width: 1),
              bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1),
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${(index + 1).toString().padLeft(2, '0')}  ${stage.name}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF09090B),
                    ),
                  ),
                  Row(
                    children: [
                      if (isSelected) ...[
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF10B981),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      ReorderableDragStartListener(
                        index: index,
                        child: const MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: Icon(
                            Icons.drag_indicator_rounded,
                            size: 18,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                telemetryText,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF4B5563),
                ),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              const SizedBox(height: 8),
              _buildLedgerRow('INLET', stage.inputMaterial),
              _buildLedgerRow('OUTLET', stage.outputMaterial),
              _buildLedgerRow('SCRAP', stage.scrapPolicy),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLedgerRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.toUpperCase(),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1F2937),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StageInspector extends StatelessWidget {
  const _StageInspector({required this.stage});

  final PipelineStage stage;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProductionProvider>();
    final draft = provider.draftFor(stage.id);
    if (draft == null) {
      return const SizedBox.shrink();
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: Color(0xFFE4E4E7))),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 0, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Stage Inspector',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            _InspectorField(label: 'Stage name', controller: draft.name),
            _InspectorField(
              label: 'Machine asset ID',
              controller: draft.machineId,
            ),
            _InspectorField(label: 'Die asset ID', controller: draft.dieId),
            _InspectorField(
              label: 'Input material',
              controller: draft.inputMaterial,
            ),
            _InspectorField(
              label: 'Machine action',
              controller: draft.machineAction,
            ),
            _InspectorField(
              label: 'Target output',
              controller: draft.outputMaterial,
            ),
            _InspectorField(
              label: 'Scrap policy',
              controller: draft.scrapPolicy,
            ),
            _InspectorField(
              label: 'Target output units',
              controller: draft.targetOutputUnits,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 54,
              width: double.infinity,
              child: _ProductionActionButton(
                onPressed: () => provider.saveStageDraft(stage.id),
                icon: Icons.save_outlined,
                label: 'Save Stage Draft',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InspectorField extends StatelessWidget {
  const _InspectorField({
    required this.label,
    required this.controller,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            style: const TextStyle(
              color: Color(0xFF09090B),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
            decoration: InputDecoration(
              labelText: label.toUpperCase(),
              labelStyle: const TextStyle(
                color: Color(0xFFA1A1AA),
                fontFamily: 'monospace',
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductionActionButton extends StatelessWidget {
  const _ProductionActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF09090B),
      child: InkWell(
        onTap: onPressed,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF09090B)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 9),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

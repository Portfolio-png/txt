import 'package:flutter/material.dart';

import '../../domain/pipeline_run.dart';
import '../../presentation/pipelines_provider.dart';

class PipelineModeDropdown extends StatelessWidget {
  const PipelineModeDropdown({
    super.key,
    required this.mode,
    required this.runs,
    required this.activeRunId,
    required this.onTemplateSelected,
    required this.onRunSelected,
    required this.onStartRun,
  });

  final PipelineMode mode;
  final List<PipelineRun> runs;
  final String? activeRunId;
  final VoidCallback onTemplateSelected;
  final ValueChanged<String> onRunSelected;
  final VoidCallback onStartRun;

  @override
  Widget build(BuildContext context) {
    final activeValue = mode == PipelineMode.template
        ? '__template__'
        : activeRunId ?? '__template__';

    return DropdownButtonFormField<String>(
      initialValue: activeValue,
      decoration: InputDecoration(
        labelText: 'Canvas Context',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: mode == PipelineMode.run
                ? const Color(0xFF16A34A)
                : const Color(0xFFD8DCE8),
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
      items: [
        const DropdownMenuItem<String>(
          value: '__template__',
          child: Text('Edit template'),
        ),
        ...runs.map(
          (run) =>
              DropdownMenuItem<String>(value: run.id, child: Text(run.name)),
        ),
        const DropdownMenuItem<String>(
          value: '__start__',
          child: Text('+ Start new run'),
        ),
      ],
      onChanged: (value) {
        if (value == null) {
          return;
        }
        if (value == '__template__') {
          onTemplateSelected();
          return;
        }
        if (value == '__start__') {
          onStartRun();
          return;
        }
        onRunSelected(value);
      },
    );
  }
}

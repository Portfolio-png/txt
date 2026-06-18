import 'package:flutter/material.dart';
import 'package:core_erp/core/widgets/app_toast.dart';
import 'package:provider/provider.dart';
import '../../production_pipelines/data/repositories/pipeline_run_repository.dart';
import '../providers/production_run_provider.dart';

class EditableMetricBox extends StatefulWidget {
  const EditableMetricBox({
    super.key,
    required this.nodeId,
    required this.metricKey,
    required this.label,
    this.flex = 1,
  });

  final String nodeId;
  final String metricKey; // 'remaining' or 'scrap'
  final String label;
  final int flex;

  @override
  State<EditableMetricBox> createState() => _EditableMetricBoxState();
}

class _EditableMetricBoxState extends State<EditableMetricBox> {
  Future<void> _editValue(BuildContext context, double currentValue) async {
    final runId = context.read<ProductionRunProvider>().runId;
    final controller = TextEditingController(text: currentValue.toString());
    final newValueStr = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit \${widget.label}'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(suffixText: 'Kg'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newValueStr != null && context.mounted && runId != null) {
      final val = double.tryParse(newValueStr);
      if (val != null) {
        try {
          await context.read<PipelineRunRepository>().updateNodeMetrics(
            runId: runId,
            nodeId: widget.nodeId,
            metrics: {widget.metricKey: val},
          );
          // Re-pull shared run so this and every other watcher updates.
          if (context.mounted) {
            context.read<ProductionRunProvider>().triggerRefresh();
          }
        } catch (e) {
          if (context.mounted) {
            showAppSnack(SnackBar(content: Text('Error: \$e')));
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Reads the shared run published by the canvas poll, so the value tracks
    // server truth live (including other clients' reconciliations).
    final run = context.watch<ProductionRunProvider>().currentRun;
    if (run == null) return _buildStatic('—');

    final nodeMetrics = run.nodeMetrics[widget.nodeId] ?? {};
    final metricVal = (nodeMetrics[widget.metricKey] as num?)?.toDouble() ?? 0.0;
    final valStr = '$metricVal Kg';

    return Expanded(
      flex: widget.flex,
      child: InkWell(
        onTap: () => _editValue(context, metricVal),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    widget.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF94A3B8),
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.edit, size: 10, color: Color(0xFF94A3B8)),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              valStr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatic(String val) {
    return Expanded(
      flex: widget.flex,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFF94A3B8),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            val,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../production_pipelines/data/repositories/pipeline_run_repository.dart';
import '../../production_pipelines/domain/pipeline_run.dart';
import '../providers/production_run_provider.dart';

class EditableMetricBox extends StatefulWidget {
  const EditableMetricBox({
    super.key,
    required this.nodeId,
    required this.metricKey,
    required this.label,
  });

  final String nodeId;
  final String metricKey; // 'remaining' or 'scrap'
  final String label;

  @override
  State<EditableMetricBox> createState() => _EditableMetricBoxState();
}

class _EditableMetricBoxState extends State<EditableMetricBox> {
  Future<PipelineRun?>? _runFuture;
  String? _lastRunId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final runProvider = Provider.of<ProductionRunProvider>(context);
    final runId = runProvider.runId;

    if (runId != _lastRunId) {
      _lastRunId = runId;
      if (runId != null) {
        _runFuture = context.read<PipelineRunRepository>().getRun(runId);
      } else {
        _runFuture = null;
      }
    }
  }

  Future<void> _editValue(BuildContext context, double currentValue) async {
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

    if (newValueStr != null && context.mounted && _lastRunId != null) {
      final val = double.tryParse(newValueStr);
      if (val != null) {
        try {
          await context.read<PipelineRunRepository>().updateNodeMetrics(
            runId: _lastRunId!,
            nodeId: widget.nodeId,
            metrics: {widget.metricKey: val},
          );
          // Trigger refresh local future
          setState(() {
            _runFuture = context.read<PipelineRunRepository>().getRun(_lastRunId!);
          });
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: \$e')));
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_runFuture == null) return _buildStatic('—');

    return FutureBuilder<PipelineRun?>(
      future: _runFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildStatic('...');
        }
        final run = snapshot.data;
        if (run == null) return _buildStatic('—');
        
        final nodeMetrics = run.nodeMetrics[widget.nodeId] ?? {};
        final metricVal = (nodeMetrics[widget.metricKey] as num?)?.toDouble() ?? 0.0;
        final valStr = '\${metricVal} Kg';

        return Expanded(
          child: InkWell(
            onTap: () => _editValue(context, metricVal),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      widget.label,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF94A3B8),
                        letterSpacing: 0.8,
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
      },
    );
  }

  Widget _buildStatic(String val) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
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

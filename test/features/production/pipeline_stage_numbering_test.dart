import 'package:flutter_test/flutter_test.dart';
import 'package:paper/features/production/providers/pipeline_editor_provider.dart';
import 'package:paper/features/production_pipelines/domain/pipeline_template.dart';
import 'package:paper/features/production_pipelines/domain/process_node.dart';

PipelineTemplate _template(
  List<String> stageLabels, {
  List<ProcessNode> nodes = const [],
}) =>
    PipelineTemplate(
      id: 'tpl-test',
      name: 'Test',
      description: '',
      stageLabels: stageLabels,
      laneLabels: const ['Main'],
      nodes: nodes,
      flows: const [],
    );

ProcessNode _node(String name, int stageIndex) => ProcessNode(
      id: 'node-$name-$stageIndex',
      name: name,
      processType: stageIndex == 0 ? 'Input' : 'Action',
      stageIndex: stageIndex,
      laneIndex: 0,
      inputs: const ['Input'],
      outputs: const ['Output'],
      machine: 'MC',
      dieId: '',
      durationHours: 1,
      status: 'Queued',
      isIntermediate: stageIndex != 0,
    );

void main() {
  group('auto stage numbering', () {
    test('added stage continues the sequence instead of jumping past endpoints',
        () {
      // Input/Output count toward length, so the old code named this "Stage 4".
      final p = PipelineEditorProvider(
        template: _template(['Input', 'Stage 1', 'Output']),
      );
      p.addStage();
      expect(p.template.stageLabels, ['Input', 'Stage 1', 'Output', 'Stage 2']);
    });

    test('adding a stage heals existing gaps, leaving custom labels alone', () {
      final p = PipelineEditorProvider(
        template: _template(
          ['Input', 'Stage 1', 'Stage 4', 'Stage 5', 'Output'],
        ),
      );
      p.addStage();
      expect(p.template.stageLabels,
          ['Input', 'Stage 1', 'Stage 2', 'Stage 3', 'Output', 'Stage 4']);
    });
  });

  group('auto stage node names', () {
    test('new node name continues the sequence instead of counting endpoints',
        () {
      final p = PipelineEditorProvider(
        template: _template(
          ['Input', 'Stage 1', 'Output'],
          nodes: [_node('Input', 0), _node('Stage 1', 1), _node('Output', 2)],
        ),
      );
      // Old code named this "Stage 4" (3 existing nodes + 1).
      p.addNode(3, 0);
      final added = p.template.nodes.firstWhere((n) => n.stageIndex == 3);
      expect(added.name, 'Stage 2');
    });

    test('adding a node heals gapped/out-of-order node names', () {
      final p = PipelineEditorProvider(
        template: _template(
          ['Input', 'Stage 1', 'Stage 2', 'Stage 3', 'Output'],
          nodes: [
            _node('Input', 0),
            _node('Stage 1', 1),
            _node('Stage 5', 2),
            _node('Stage 4', 3),
            _node('Output', 4),
          ],
        ),
      );
      p.addNode(5, 0);
      String nameAt(int s) =>
          p.template.nodes.firstWhere((n) => n.stageIndex == s).name;
      expect(nameAt(1), 'Stage 1');
      expect(nameAt(2), 'Stage 2');
      expect(nameAt(3), 'Stage 3');
      expect(nameAt(5), 'Stage 4');
    });
  });
}

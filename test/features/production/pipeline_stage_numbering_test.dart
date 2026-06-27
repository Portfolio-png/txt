import 'package:flutter_test/flutter_test.dart';
import 'package:paper/features/production/providers/pipeline_editor_provider.dart';
import 'package:paper/features/production_pipelines/domain/pipeline_template.dart';

PipelineTemplate _template(List<String> stageLabels) => PipelineTemplate(
      id: 'tpl-test',
      name: 'Test',
      description: '',
      stageLabels: stageLabels,
      laneLabels: const ['Main'],
      nodes: const [],
      flows: const [],
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
}

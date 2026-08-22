import 'package:core_erp/features/production_pipelines/domain/pen_paper_baseline.dart';
import 'package:core_erp/features/production_pipelines/domain/pipeline_stage_node.dart';
import 'package:flutter_test/flutter_test.dart';

// Stage-by-stage Master Data titles a row per pipeline node, so the names have
// to come off the nodes — in the order material passes through them, and keyed
// by node id so a rename on the board carries its recorded weights along.

void main() {
  group('PipelineStageNode.listFromJson', () {
    test('reads the node names, in stage order', () {
      final nodes = PipelineStageNode.listFromJson(<dynamic>[
        <String, dynamic>{
          'id': 'n-pierce',
          'name': 'Piercing',
          'stageIndex': 2,
          'laneIndex': 0,
        },
        <String, dynamic>{
          'id': 'n-in',
          'name': 'Sheet Metal Input',
          'stageIndex': 0,
          'laneIndex': 0,
        },
        <String, dynamic>{
          'id': 'n-cut',
          'name': 'Blank Cutting',
          'stageIndex': 1,
          'laneIndex': 0,
        },
      ]);

      expect(nodes.map((node) => node.name).toList(), <String>[
        'Sheet Metal Input',
        'Blank Cutting',
        'Piercing',
      ]);
      expect(nodes.first.id, 'n-in');
    });

    test('lanes order within a stage, not across it', () {
      final nodes = PipelineStageNode.listFromJson(<dynamic>[
        <String, dynamic>{'id': 'b', 'name': 'B', 'stageIndex': 0, 'laneIndex': 1},
        <String, dynamic>{'id': 'c', 'name': 'C', 'stageIndex': 1, 'laneIndex': 0},
        <String, dynamic>{'id': 'a', 'name': 'A', 'stageIndex': 0, 'laneIndex': 0},
      ]);

      expect(nodes.map((node) => node.name).toList(), <String>['A', 'B', 'C']);
    });

    test('an unnamed node falls back to its process type, then its position', () {
      final nodes = PipelineStageNode.listFromJson(<dynamic>[
        <String, dynamic>{'id': 'x', 'name': '  ', 'processType': 'Deburring'},
        <String, dynamic>{'id': 'y', 'stageIndex': 1},
      ]);

      expect(nodes[0].name, 'Deburring');
      expect(nodes[1].name, 'Stage 2');
    });

    test('a node with no id of its own still gets a stable key', () {
      final nodes = PipelineStageNode.listFromJson(<dynamic>[
        <String, dynamic>{'name': 'Cutting'},
      ]);

      expect(nodes.single.id, 'stage-1');
    });

    test('empty and malformed payloads yield nothing rather than throwing', () {
      expect(PipelineStageNode.listFromJson(null), isEmpty);
      expect(PipelineStageNode.listFromJson(const <dynamic>[]), isEmpty);
      expect(
        PipelineStageNode.listFromJson(<dynamic>['not a node', 42]),
        isEmpty,
      );
    });
  });

  group('createDefaultForStages', () {
    test('builds one row per node, named and keyed from it', () {
      final baseline = PenPaperBaseline.createDefaultForStages(
        const <PipelineStageNode>[
          PipelineStageNode(id: 'n-cut', name: 'Blank Cutting'),
          PipelineStageNode(id: 'n-pierce', name: 'Piercing', stageIndex: 1),
        ],
      );

      expect(baseline.stageReconciliations.length, 2);
      expect(
        baseline.stageReconciliations.map((row) => row.stageName).toList(),
        <String>['Blank Cutting', 'Piercing'],
      );
      // The node's id, not a positional 'stage-1' — that is what lets a row
      // stay attached to its node across a rename.
      expect(
        baseline.stageReconciliations.map((row) => row.stageId).toList(),
        <String>['n-cut', 'n-pierce'],
      );
    });

    test('a pipeline with no nodes still produces a usable table', () {
      final baseline = PenPaperBaseline.createDefaultForStages();

      expect(baseline.stageReconciliations.length, 3);
      expect(baseline.stageReconciliations.first.stageName, 'Raw Preparation');
    });

    test('each stage feeds the next, so the chain reconciles', () {
      final baseline = PenPaperBaseline.createDefaultForStages(
        const <PipelineStageNode>[
          PipelineStageNode(id: 'a', name: 'A'),
          PipelineStageNode(id: 'b', name: 'B', stageIndex: 1),
          PipelineStageNode(id: 'c', name: 'C', stageIndex: 2),
        ],
      );
      final rows = baseline.stageReconciliations;

      for (var i = 1; i < rows.length; i++) {
        expect(
          rows[i].inputKg,
          rows[i - 1].outputKg,
          reason: 'stage ${i + 1} takes in what stage $i put out',
        );
      }
    });
  });
}

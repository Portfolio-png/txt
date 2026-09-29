import '../../production_pipelines/domain/pipeline_run.dart';
import '../../production_pipelines/domain/pipeline_template.dart';

/// Produce is a UI-only duplicate of the Production tab: it renders the same
/// screen against hand-written rows so the layout can be reworked without a
/// repository, a provider, or a single backend call behind it. Swap these
/// builders for the real repository when the tab is wired up.

Map<String, dynamic> _node(
  String id,
  String name, {
  required int stageIndex,
  String processType = 'process',
}) {
  return <String, dynamic>{
    'id': id,
    'name': name,
    'processType': processType,
    'stageIndex': stageIndex,
    'laneIndex': 0,
  };
}

Map<String, dynamic> _metrics({
  required double input,
  required double output,
  double scrap = 0,
  double rejection = 0,
}) {
  return <String, dynamic>{
    'inputQty': input,
    'outputQty': output,
    'scrapQty': scrap,
    'rejectionQty': rejection,
  };
}

String _iso(int daysAgo, {int hour = 9}) {
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day, hour)
      .subtract(Duration(days: daysAgo));
  return day.toIso8601String();
}

List<PipelineTemplate> buildProduceSampleTemplates() {
  return <PipelineTemplate>[
    PipelineTemplate.fromJson(<String, dynamic>{
      'id': 'tpl-carton',
      'name': 'Sheet → Carton Line',
      'description': 'Board in, printed and pasted cartons out.',
      'status': 'active',
      'stageLabels': <String>['Input', 'Cut', 'Print', 'Paste', 'Pack'],
      'laneLabels': <String>['Line A'],
      'nodes': <Map<String, dynamic>>[
        _node('carton-input', 'Input Stage', stageIndex: 0, processType: 'input'),
        _node('carton-cut', 'Cutting', stageIndex: 1),
        _node('carton-print', 'Printing', stageIndex: 2),
        _node('carton-paste', 'Pasting', stageIndex: 3),
        _node('carton-pack', 'Packing', stageIndex: 4),
      ],
      'flows': <Map<String, dynamic>>[],
    }),
    PipelineTemplate.fromJson(<String, dynamic>{
      'id': 'tpl-wire',
      'name': 'Wire Drawing Line',
      'description': 'Rod in, annealed coils out.',
      'status': 'active',
      'stageLabels': <String>['Input', 'Draw', 'Anneal', 'Coil'],
      'laneLabels': <String>['Line B'],
      'nodes': <Map<String, dynamic>>[
        _node('wire-input', 'Input Stage', stageIndex: 0, processType: 'input'),
        _node('wire-draw', 'Drawing', stageIndex: 1),
        _node('wire-anneal', 'Annealing', stageIndex: 2),
        _node('wire-coil', 'Coiling', stageIndex: 3),
      ],
      'flows': <Map<String, dynamic>>[],
    }),
    PipelineTemplate.fromJson(<String, dynamic>{
      'id': 'tpl-foil',
      'name': 'Legacy Foil Line',
      'description': 'Retired — kept for history only.',
      'status': 'archived',
      'stageLabels': <String>['Input', 'Slit'],
      'laneLabels': <String>['Line C'],
      'nodes': <Map<String, dynamic>>[
        _node('foil-input', 'Input Stage', stageIndex: 0, processType: 'input'),
        _node('foil-slit', 'Slitting', stageIndex: 1),
      ],
      'flows': <Map<String, dynamic>>[],
    }),
  ];
}

List<PipelineRun> buildProduceSampleRuns() {
  return <PipelineRun>[
    PipelineRun.fromJson(<String, dynamic>{
      'id': 'run-sample-1',
      'templateId': 'tpl-carton',
      'templateVersion': 1,
      'name': 'Carton run — ORD-2041',
      'status': 'running',
      'orderNo': 'ORD-2041',
      'clientName': 'Nashik Packaging',
      'createdAt': _iso(2),
      'startedAt': _iso(2, hour: 10),
      'nodeStatuses': <String, dynamic>{
        'carton-input': 'done',
        'carton-cut': 'done',
        'carton-print': 'active',
        'carton-paste': 'pending',
        'carton-pack': 'pending',
      },
      'nodeMetrics': <String, dynamic>{
        'carton-input': _metrics(input: 820, output: 820),
        'carton-cut': _metrics(input: 820, output: 786, scrap: 34),
        'carton-print': _metrics(input: 786, output: 742, rejection: 18),
      },
    }),
    PipelineRun.fromJson(<String, dynamic>{
      'id': 'run-sample-2',
      'templateId': 'tpl-carton',
      'templateVersion': 1,
      'name': 'Carton run — ORD-2044',
      'status': 'running',
      'orderNo': 'ORD-2044',
      'clientName': 'Pune Cartons',
      'createdAt': _iso(1),
      'nodeStatuses': <String, dynamic>{
        'carton-input': 'pending',
        'carton-cut': 'pending',
        'carton-print': 'pending',
        'carton-paste': 'pending',
        'carton-pack': 'pending',
      },
    }),
    PipelineRun.fromJson(<String, dynamic>{
      'id': 'run-sample-3',
      'templateId': 'tpl-wire',
      'templateVersion': 1,
      'name': 'Wire run — ad-hoc',
      'status': 'running',
      'createdAt': _iso(4),
      'startedAt': _iso(4, hour: 11),
      'nodeStatuses': <String, dynamic>{
        'wire-input': 'done',
        'wire-draw': 'active',
        'wire-anneal': 'pending',
        'wire-coil': 'pending',
      },
      'nodeMetrics': <String, dynamic>{
        'wire-input': _metrics(input: 1200, output: 1200),
        'wire-draw': _metrics(input: 1200, output: 1124, scrap: 51, rejection: 25),
      },
    }),
    PipelineRun.fromJson(<String, dynamic>{
      'id': 'run-sample-4',
      'templateId': 'tpl-wire',
      'templateVersion': 1,
      'name': 'Wire run — ORD-2019',
      'status': 'completed',
      'orderNo': 'ORD-2019',
      'clientName': 'Igatpuri Steel',
      'createdAt': _iso(12),
      'startedAt': _iso(12, hour: 10),
      'completedAt': _iso(9, hour: 17),
      'nodeStatuses': <String, dynamic>{
        'wire-input': 'done',
        'wire-draw': 'done',
        'wire-anneal': 'done',
        'wire-coil': 'done',
      },
      'nodeMetrics': <String, dynamic>{
        'wire-input': _metrics(input: 2400, output: 2400),
        'wire-draw': _metrics(input: 2400, output: 2282, scrap: 84, rejection: 34),
        'wire-anneal': _metrics(input: 2282, output: 2251, scrap: 31),
        'wire-coil': _metrics(input: 2251, output: 2240, rejection: 11),
      },
    }),
    PipelineRun.fromJson(<String, dynamic>{
      'id': 'run-sample-5',
      'templateId': 'tpl-carton',
      'templateVersion': 1,
      'name': 'Carton run — ORD-2032',
      'status': 'completed',
      'orderNo': 'ORD-2032',
      'clientName': 'Nashik Packaging',
      'createdAt': _iso(26),
      'startedAt': _iso(26, hour: 9),
      'completedAt': _iso(22, hour: 16),
      'nodeStatuses': <String, dynamic>{
        'carton-input': 'done',
        'carton-cut': 'done',
        'carton-print': 'done',
        'carton-paste': 'skipped',
        'carton-pack': 'done',
      },
      'nodeMetrics': <String, dynamic>{
        'carton-input': _metrics(input: 640, output: 640),
        'carton-cut': _metrics(input: 640, output: 612, scrap: 28),
        'carton-print': _metrics(input: 612, output: 588, rejection: 24),
        'carton-pack': _metrics(input: 588, output: 588),
      },
    }),
  ];
}

/// Stands in for the inventory lookup the real Production tab runs to decide
/// whether a run's input stage is starved of material.
const Set<String> produceSampleStalledRunIds = <String>{'run-sample-2'};

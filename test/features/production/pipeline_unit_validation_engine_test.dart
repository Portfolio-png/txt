import 'package:core_erp/features/units/domain/unit_definition.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paper/features/production/providers/pipeline_editor_provider.dart';
import 'package:paper/features/production_pipelines/domain/material_flow.dart';
import 'package:paper/features/production_pipelines/domain/pipeline_item_endpoint.dart';
import 'package:paper/features/production_pipelines/domain/pipeline_template.dart';
import 'package:paper/features/production_pipelines/domain/pipeline_unit_validation_engine.dart';
import 'package:paper/features/production_pipelines/domain/process_node.dart';

void main() {
  group('ProcessNode item endpoints', () {
    test('fromJson tolerates legacy nodes without endpoint fields', () {
      final node = ProcessNode.fromJson({
        'id': 'legacy',
        'name': 'Legacy Cut',
        'processType': 'Cutting',
        'stageIndex': 0,
        'laneIndex': 0,
        'inputs': ['Sheet'],
        'outputs': ['Blank'],
        'machine': 'LC-01',
        'dieId': '',
        'durationHours': 1,
        'status': 'Ready',
        'isIntermediate': false,
      });

      expect(node.inputItem, isNull);
      expect(node.outputItem, isNull);
      expect(node.unitConversionMultiplier, isNull);
    });

    test('toJson persists endpoint metadata and conversion multiplier', () {
      final node = _node(
        id: 'convert',
        name: 'Convert kg to g',
        inputItem: _endpoint(1, 'Steel Sheet', 1, 'kg'),
        outputItem: _endpoint(2, 'Steel Blank', 2, 'g'),
      ).copyWith(unitConversionMultiplier: 1000);

      final restored = ProcessNode.fromJson(node.toJson());

      expect(restored.inputItem?.itemName, 'Steel Sheet');
      expect(restored.outputItem?.unitSymbol, 'g');
      expect(restored.unitConversionMultiplier, 1000);
    });
  });

  group('PipelineUnitValidationEngine', () {
    const engine = PipelineUnitValidationEngine();

    test('same unit produces no bridge issue', () {
      final result = engine.validate(
        _template(
          sourceOutput: _endpoint(1, 'Steel Sheet', 1, 'kg'),
          targetInput: _endpoint(2, 'Steel Blank', 1, 'kg'),
        ),
        _units(),
      );

      expect(result.issues, isEmpty);
    });

    test('same unit group creates unit conversion issue with multiplier', () {
      final result = engine.validate(
        _template(
          sourceOutput: _endpoint(1, 'Steel Sheet', 1, 'kg'),
          targetInput: _endpoint(2, 'Steel Blank', 2, 'g'),
        ),
        _units(),
      );

      expect(
        result.bridgeIssues.single.kind,
        PipelineUnitIssueKind.unitConversion,
      );
      expect(result.bridgeIssues.single.multiplier, 1000);
    });

    test('different unit groups creates material transform issue', () {
      final result = engine.validate(
        _template(
          sourceOutput: _endpoint(1, 'Steel Sheet', 1, 'kg'),
          targetInput: _endpoint(3, 'Finished Part', 3, 'pcs'),
        ),
        _units(),
      );

      expect(
        result.bridgeIssues.single.kind,
        PipelineUnitIssueKind.materialTransform,
      );
    });

    test('missing metadata returns warning only', () {
      final result = engine.validate(
        _template(
          sourceOutput: null,
          targetInput: _endpoint(2, 'Blank', 2, 'g'),
        ),
        _units(),
      );

      expect(result.issues.single.kind, PipelineUnitIssueKind.missingMetadata);
      expect(result.bridgeIssues, isEmpty);
    });
  });

  group('PipelineEditorProvider unit auto-fix', () {
    test(
      'updateNodeItems mirrors item names into visible inputs and outputs',
      () {
        final editor = PipelineEditorProvider(template: _template());
        addTearDown(editor.dispose);

        editor.updateNodeItems(
          nodeId: 'source',
          inputItem: _endpoint(4, 'Raw Coil', 1, 'kg'),
          outputItem: _endpoint(1, 'Steel Sheet', 1, 'kg'),
        );

        final source = editor.template.nodes.first;
        expect(source.inputItem?.itemName, 'Raw Coil');
        expect(source.outputItem?.itemName, 'Steel Sheet');
        expect(source.inputs, ['Raw Coil']);
        expect(source.outputs, ['Steel Sheet']);
      },
    );

    test(
      'connection auto-fix inserts converter, shifts target, and replaces flow',
      () {
        final editor = PipelineEditorProvider(
          template: _template(
            sourceOutput: _endpoint(1, 'Steel Sheet', 1, 'kg'),
            targetInput: _endpoint(2, 'Steel Blank', 2, 'g'),
            includeFlow: false,
          ),
        );
        addTearDown(editor.dispose);

        editor.beginConnecting('source');
        editor.selectNode('target', units: _units());

        final bridge = editor.template.nodes.singleWhere(
          (node) => node.processType == 'Unit Conversion',
        );
        final target = editor.template.nodes.singleWhere(
          (node) => node.id == 'target',
        );

        expect(bridge.stageIndex, 1);
        expect(target.stageIndex, 2);
        expect(bridge.unitConversionMultiplier, 1000);
        expect(
          editor.template.flows.any(
            (flow) => flow.fromNodeId == 'source' && flow.toNodeId == 'target',
          ),
          isFalse,
        );
        expect(
          editor.template.flows.any(
            (flow) => flow.fromNodeId == 'source' && flow.toNodeId == bridge.id,
          ),
          isTrue,
        );
        expect(
          editor.template.flows.any(
            (flow) => flow.fromNodeId == bridge.id && flow.toNodeId == 'target',
          ),
          isTrue,
        );
      },
    );

    test('repeated auto-fix does not duplicate bridge nodes', () {
      final editor = PipelineEditorProvider(
        template: _template(
          sourceOutput: _endpoint(1, 'Steel Sheet', 1, 'kg'),
          targetInput: _endpoint(2, 'Steel Blank', 2, 'g'),
        ),
      );
      addTearDown(editor.dispose);

      editor.applyUnitContinuityAutoFixes(_units());
      editor.applyUnitContinuityAutoFixes(_units());

      expect(
        editor.template.nodes
            .where((node) => node.processType == 'Unit Conversion')
            .length,
        1,
      );
    });
  });
}

PipelineTemplate _template({
  PipelineItemEndpoint? sourceOutput,
  PipelineItemEndpoint? targetInput,
  bool includeFlow = true,
}) {
  return PipelineTemplate(
    id: 'tpl-units',
    name: 'Unit Test Pipeline',
    description: '',
    stageLabels: const ['Source', 'Target'],
    laneLabels: const ['Main'],
    nodes: [
      _node(
        id: 'source',
        name: 'Source',
        outputItem: sourceOutput,
        outputs: sourceOutput == null
            ? const ['Output']
            : [sourceOutput.itemName],
      ),
      _node(
        id: 'target',
        name: 'Target',
        stageIndex: 1,
        inputItem: targetInput,
        inputs: targetInput == null ? const ['Input'] : [targetInput.itemName],
      ),
    ],
    flows: includeFlow
        ? const [
            MaterialFlow(
              id: 'flow-source-target',
              fromNodeId: 'source',
              toNodeId: 'target',
              materialName: 'Material',
            ),
          ]
        : const [],
  );
}

ProcessNode _node({
  required String id,
  required String name,
  int stageIndex = 0,
  PipelineItemEndpoint? inputItem,
  PipelineItemEndpoint? outputItem,
  List<String> inputs = const ['Input'],
  List<String> outputs = const ['Output'],
}) {
  return ProcessNode(
    id: id,
    name: name,
    processType: 'Action',
    stageIndex: stageIndex,
    laneIndex: 0,
    inputs: inputs,
    outputs: outputs,
    machine: 'MC-01',
    dieId: '',
    durationHours: 1,
    status: 'Ready',
    isIntermediate: false,
    inputItem: inputItem,
    outputItem: outputItem,
  );
}

PipelineItemEndpoint _endpoint(
  int itemId,
  String itemName,
  int unitId,
  String unitSymbol,
) {
  return PipelineItemEndpoint(
    itemId: itemId,
    itemName: itemName,
    unitId: unitId,
    unitName: unitSymbol,
    unitSymbol: unitSymbol,
  );
}

List<UnitDefinition> _units() {
  final now = DateTime(2026);
  return [
    UnitDefinition(
      id: 1,
      name: 'Kilogram',
      symbol: 'kg',
      notes: '',
      unitGroupId: 1,
      unitGroupName: 'Mass',
      conversionFactor: 1,
      conversionBaseUnitId: null,
      conversionBaseUnitName: null,
      isArchived: false,
      usageCount: 0,
      createdAt: now,
      updatedAt: now,
    ),
    UnitDefinition(
      id: 2,
      name: 'Gram',
      symbol: 'g',
      notes: '',
      unitGroupId: 1,
      unitGroupName: 'Mass',
      conversionFactor: 0.001,
      conversionBaseUnitId: 1,
      conversionBaseUnitName: 'Kilogram',
      isArchived: false,
      usageCount: 0,
      createdAt: now,
      updatedAt: now,
    ),
    UnitDefinition(
      id: 3,
      name: 'Pieces',
      symbol: 'pcs',
      notes: '',
      unitGroupId: 2,
      unitGroupName: 'Count',
      conversionFactor: 1,
      conversionBaseUnitId: null,
      conversionBaseUnitName: null,
      isArchived: false,
      usageCount: 0,
      createdAt: now,
      updatedAt: now,
    ),
  ];
}

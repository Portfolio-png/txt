import 'package:flutter_test/flutter_test.dart';
import 'package:paper/features/production_pipelines/domain/pipeline_item_endpoint.dart';
import 'package:paper/features/production_pipelines/domain/process_node.dart';

ProcessNode _node({List<ScrapItemRef> scrapItems = const []}) => ProcessNode(
      id: 'n1',
      name: 'Cutting',
      processType: 'cut',
      stageIndex: 0,
      laneIndex: 0,
      inputs: const [],
      outputs: const [],
      machine: '',
      dieId: '',
      durationHours: 0,
      status: 'Queued',
      isIntermediate: false,
      scrapItems: scrapItems,
    );

void main() {
  test('legacy single scrapItemId json migrates into scrapItems', () {
    final node = ProcessNode.fromJson({
      'id': 'n1',
      'scrapItemId': 7,
      'scrapItemName': 'Brass',
    });
    expect(node.scrapItems, hasLength(1));
    expect(node.scrapItemId, 7);
    expect(node.scrapItemName, 'Brass');
  });

  test('multiple scrap items round-trip and mirror legacy keys', () {
    final node = _node(
      scrapItems: const [
        ScrapItemRef(id: 7, name: 'Brass'),
        ScrapItemRef(id: 9, name: 'Aluminium'),
      ],
    );
    final json = node.toJson();
    expect(json['scrapItemId'], 7, reason: 'legacy mirror = first item');
    expect(json['scrapItemName'], 'Brass');

    final restored = ProcessNode.fromJson(json);
    expect(restored.scrapItems, hasLength(2));
    expect(restored.scrapItems[1].name, 'Aluminium');
  });

  test('endpoint variation path round-trips and defaults to any', () {
    const endpoint = PipelineItemEndpoint(
      itemId: 3,
      itemName: 'Bottle Carton',
      unitId: 1,
      unitName: 'Pieces',
      unitSymbol: 'pcs',
      variationLeafNodeId: 42,
      variationPathLabel: 'Bottle Carton 100 Black Matte',
    );
    final restored = PipelineItemEndpoint.fromJson(endpoint.toJson());
    expect(restored.variationLeafNodeId, 42);
    expect(restored.displayLabel, 'Bottle Carton 100 Black Matte');

    final legacy = PipelineItemEndpoint.fromJson({'itemId': 3, 'itemName': 'X'});
    expect(legacy.variationLeafNodeId, 0);
    expect(legacy.hasVariation, isFalse);
    expect(legacy.displayLabel, 'X');
  });

  test('copyWith replaces and clears scrap items', () {
    final node = _node(scrapItems: const [ScrapItemRef(id: 7, name: 'Brass')]);
    final cleared = node.copyWith(scrapItems: const <ScrapItemRef>[]);
    expect(cleared.scrapItems, isEmpty);
    expect(cleared.scrapItemId, isNull);
    expect(node.copyWith().scrapItems, hasLength(1), reason: 'unset keeps');
  });
}

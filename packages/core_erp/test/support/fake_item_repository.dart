import 'package:core_erp/features/items/data/models/item_api_models.dart';
import 'package:core_erp/features/items/data/repositories/item_repository.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/domain/item_asset.dart';
import 'package:core_erp/features/items/domain/item_inputs.dart';
import 'package:core_erp/features/items/domain/item_master_data.dart';
import 'package:core_erp/features/items/domain/item_usage_record.dart';
import 'package:core_erp/features/production_pipelines/domain/pen_paper_baseline.dart';
import 'package:core_erp/features/production_pipelines/domain/pipeline_stage_node.dart';

/// A stand-in for the network repository.
///
/// Counts the calls that should NOT happen when the replica can answer, which
/// is the property the local-first path exists for.
class FakeItemRepository implements ItemRepository {
  List<ItemDefinition> items = const <ItemDefinition>[];
  int getItemsCalls = 0;
  int getItemCalls = 0;
  final List<int> deleteCalls = <int>[];

  @override
  Future<void> init() async {}

  @override
  Future<List<ItemDefinition>> getItems() async {
    getItemsCalls += 1;
    return items;
  }

  @override
  Future<ItemDefinition?> getItem(int id) async {
    getItemCalls += 1;
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  @override
  Future<void> deleteItem(int id) async {
    deleteCalls.add(id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} should not be reached');
}

/// Parses a server payload the way the app does.
extension ItemDtoParse on ItemDto {
  static ItemDefinition parse(Map<String, dynamic> payload) =>
      ItemDto.fromJson(payload).toDomain();
}

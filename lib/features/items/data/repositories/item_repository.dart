import '../../domain/item_definition.dart';
import '../../domain/item_inputs.dart';

abstract class ItemRepository {
  Future<void> init();
  Future<List<ItemDefinition>> getItems();
  Future<ItemDefinition> createItem(CreateItemInput input);
  Future<ItemDefinition> updateItem(UpdateItemInput input);
  Future<ItemDefinition> archiveItem(int id);
  Future<ItemDefinition> restoreItem(int id);
}

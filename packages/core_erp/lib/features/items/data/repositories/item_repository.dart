import '../../domain/item_definition.dart';
import '../../domain/item_inputs.dart';
import '../../domain/item_asset.dart';
import '../../domain/item_usage_record.dart';
abstract class ItemRepository {
  Future<void> init();
  Future<List<ItemDefinition>> getItems();
  Future<ItemDefinition> createItem(CreateItemInput input);
  Future<ItemDefinition> updateItem(UpdateItemInput input);
  Future<ItemDefinition> archiveItem(int id);
  Future<ItemDefinition> restoreItem(int id);
  Future<List<ItemAsset>> getItemAssets(int itemId);
  Future<ItemAssetUploadIntent> createAssetUploadIntent(
    ItemAssetUploadIntentInput input,
  );
  Future<ItemAsset> completeAssetUpload(CompleteItemAssetUploadInput input);
  Future<ItemAsset> setPrimaryAsset(int assetId);
  Future<void> deleteAsset(int assetId);
  Future<List<ItemUsageRecord>> getItemUsage(int itemId);
  Future<List<Map<String, String>>> getPipelineTemplates();
}

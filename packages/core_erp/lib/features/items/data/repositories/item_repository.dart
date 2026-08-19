import '../../domain/item_definition.dart';
import '../../domain/item_inputs.dart';
import '../../domain/item_asset.dart';
import '../../domain/item_usage_record.dart';

abstract class ItemRepository {
  Future<void> init();
  Future<List<ItemDefinition>> getItems();
  Future<ItemDefinition?> getItem(int id);
  Future<ItemDefinition> createItem(CreateItemInput input);
  Future<ItemDefinition> updateItem(UpdateItemInput input);
  Future<ItemDefinition> updateShortCode(int id, String shortCode);

  Future<void> deleteItem(int id);
  Future<ItemDefinition> reassignItemGroup(int id, int groupId);
  /// Mints a fresh, short-lived download link for the item's CAD file. The item
  /// stores a permanent object key, so the link is signed per request.
  Future<Uri> createCadFileReadUrl(int itemId);

  /// Same as [createCadFileReadUrl], for one of the item's extra named files.
  Future<Uri> createAttachmentReadUrl(int itemId, int attachmentId);
  Future<List<ItemAsset>> getItemAssets(int itemId);
  Future<ItemAssetUploadIntent> createAssetUploadIntent(
    ItemAssetUploadIntentInput input,
  );
  Future<ItemAsset> completeAssetUpload(CompleteItemAssetUploadInput input);
  Future<ItemAsset> setPrimaryAsset(int assetId);
  Future<void> deleteAsset(int assetId);
  Future<List<ItemUsageRecord>> getItemUsage(int itemId);
  Future<List<Map<String, String>>> getPipelineTemplates();

  /// Stage labels per pipeline template id, so a sample baseline recorded
  /// against a pipeline can use that pipeline's real stages.
  Future<Map<String, List<String>>> getPipelineStageLabels();
}

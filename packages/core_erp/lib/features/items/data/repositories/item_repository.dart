import '../../../production_pipelines/domain/pen_paper_baseline.dart';
import '../../../production_pipelines/domain/pipeline_stage_node.dart';
import '../../domain/item_definition.dart';
import '../../domain/item_master_data.dart';
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

  /// The process nodes of each pipeline template, in reading order, keyed by
  /// template id. Stage-by-stage Master Data titles its rows from these — the
  /// node names are the work ("Piercing"), where the board's column labels are
  /// only positions ("Stage 2").
  Future<Map<String, List<PipelineStageNode>>> getPipelineStageNodes();

  // --- Master Data, keyed by (variant, pipeline) ---------------------------
  //
  // A pipeline is shared across many variants, so it holds one Master Data
  // record per variant that runs through it rather than a single baseline. The
  // resolve call is the distinction: an exact pair, else the variant's own
  // record, else the pipeline's, else new data.

  /// The baseline for one pair, and which step answered.
  Future<MasterDataResolution> resolveMasterData({
    required int itemId,
    String? pipelineId,
    bool adopt = false,
  });

  /// Every record for one item, one per pipeline it runs on.
  Future<List<ItemMasterDataRecord>> getItemMasterData(int itemId);

  /// Records the baseline against this pair. Origin becomes 'manual' — it was
  /// typed here, whatever it was inherited from before.
  Future<ItemMasterDataRecord> saveMasterData({
    required int itemId,
    required String pipelineId,
    required PenPaperBaseline baseline,
  });

  Future<void> deleteMasterData({
    required int itemId,
    required String pipelineId,
  });

  /// Every variant's Master Data on one pipeline — the insight view.
  Future<PipelineMasterDataRoster> getPipelineMasterData(String pipelineId);
}

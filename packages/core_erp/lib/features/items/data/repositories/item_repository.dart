import '../../../production_pipelines/domain/pen_paper_baseline.dart';
import '../../../production_pipelines/domain/pipeline_stage_node.dart';
import '../../domain/item_definition.dart';
import '../../domain/item_master_data.dart';
import '../../domain/item_inputs.dart';
import '../../domain/part_code.dart';
import '../../domain/item_asset.dart';
import '../../domain/item_usage_record.dart';

abstract class ItemRepository {
  Future<void> init();
  Future<List<ItemDefinition>> getItems();
  Future<ItemDefinition?> getItem(int id);

  /// [getItem] from the server itself, never a local copy. For answering a
  /// change event: a replica applies the same event later, so reading it then
  /// returns the state before the change.
  Future<ItemDefinition?> getItemFresh(int id);
  Future<ItemDefinition> createItem(CreateItemInput input);
  Future<ItemDefinition> updateItem(UpdateItemInput input);

  /// Saves how the part's item sheet is nested (section → parent). The server
  /// re-links the part's client, dies and machines to match (migration 057).
  Future<ItemDefinition> saveSectionTree(int itemId, Map<String, String> tree);
  Future<ItemDefinition> updateShortCode(int id, String shortCode);

  /// Which sets hold this part, one row per line.
  ///
  /// Asked of the server because nothing else answers it: the usage endpoint
  /// covers orders, challans, BOM requirements, materials and group links, and
  /// set lines are in none of them.
  Future<List<ItemSetMembership>> itemSets(int itemId);

  /// The number and code the next part in this scope should carry.
  ///
  /// Asked of the server rather than worked out here: the sequence is the
  /// backend's rule, and a scope spanning items, sets and set membership is
  /// not something a dialog can compute correctly from what it happens to
  /// have loaded.
  Future<PartIdentitySuggestion> nextPartIdentity({
    required int groupId,
    int? setId,
    bool setPending = false,
    String setName = '',
    String name = '',
  });

  Future<void> deleteItem(int id);

  /// Archives a part: kept, restorable, out of every picker. Refused (as an
  /// [Exception] with the server's reason) while orders or challans use it.
  Future<void> archiveItem(int id);
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

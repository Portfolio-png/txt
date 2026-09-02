import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../core/sync/replica_reader.dart';

import '../../../production_pipelines/domain/pen_paper_baseline.dart';
import '../../../production_pipelines/domain/pipeline_stage_node.dart';
import '../../domain/item_asset.dart';
import '../../domain/item_definition.dart';
import '../../domain/item_inputs.dart';
import '../../domain/item_master_data.dart';
import '../../domain/item_usage_record.dart';
import '../models/item_api_models.dart';
import 'item_repository.dart';

/// Serves item reads from the local replica, everything else from the network.
///
/// A decorator rather than a replacement, deliberately. Of the twenty-three
/// methods on [ItemRepository], three can be answered from a mirror of the list
/// endpoint; the rest are writes, signed-URL mints, asset uploads and usage
/// reports that only the server can do. Wrapping means those keep working
/// untouched, and the local path is a strict addition that can be removed by
/// deleting one line of wiring.
///
/// **The payload is returned verbatim.** `ItemDto` has `fromJson` and no
/// `toJson`, and `updateItem` sends the whole variation tree as a destructive
/// replace — so an item reconstructed from the replica's extracted columns and
/// then saved would delete every variation the reconstruction missed. What is
/// stored is exactly what the server sent, and what is returned is that map
/// parsed by the same `fromJson` the network path uses.
class LocalFirstItemRepository implements ItemRepository {
  LocalFirstItemRepository({
    required ItemRepository remote,
    required Future<Database?> Function() replica,
    required bool Function() isHydrated,
  }) : _remote = remote,
       _reader = ReplicaReader(replica: replica, isHydrated: isHydrated);

  final ItemRepository _remote;
  final ReplicaReader _reader;

  @override
  Future<void> init() => _remote.init();

  @override
  Future<List<ItemDefinition>> getItems() async {
    // The server's ordering exactly: `ORDER BY items.is_archived ASC,
    // LOWER(items.name) ASC`. Archived items are RETURNED, not filtered —
    // getItemsWithUsage has no WHERE clause — so a local `WHERE is_archived = 0`
    // would quietly drop rows the app expects to render.
    final local = await _reader.readAll<ItemDefinition>(
      'local_items',
      orderBy: 'is_archived ASC, LOWER(name) ASC',
      fromJson: (json) => ItemDto.fromJson(json).toDomain(),
    );
    return local ?? _remote.getItems();
  }

  @override
  Future<ItemDefinition?> getItem(int id) async {
    final local = await _reader.readOne<ItemDefinition>(
      'local_items',
      keyColumn: 'id',
      key: id,
      fromJson: (json) => ItemDto.fromJson(json).toDomain(),
    );
    // A miss is not proof of absence: the replica may not have caught up with a
    // just-created item. Asking is cheap and being wrong here is not.
    return local ?? _remote.getItem(id);
  }

  // --- everything below only the server can do -------------------------------

  @override
  Future<ItemDefinition> createItem(CreateItemInput input) => _remote.createItem(input);

  @override
  Future<ItemDefinition> updateItem(UpdateItemInput input) => _remote.updateItem(input);

  @override
  Future<ItemDefinition> updateShortCode(int id, String shortCode) =>
      _remote.updateShortCode(id, shortCode);

  @override
  Future<void> deleteItem(int id) => _remote.deleteItem(id);

  @override
  Future<ItemDefinition> reassignItemGroup(int id, int groupId) =>
      _remote.reassignItemGroup(id, groupId);

  @override
  Future<Uri> createCadFileReadUrl(int itemId) => _remote.createCadFileReadUrl(itemId);

  @override
  Future<Uri> createAttachmentReadUrl(int itemId, int attachmentId) =>
      _remote.createAttachmentReadUrl(itemId, attachmentId);

  @override
  Future<List<ItemAsset>> getItemAssets(int itemId) => _remote.getItemAssets(itemId);

  @override
  Future<ItemAssetUploadIntent> createAssetUploadIntent(
    ItemAssetUploadIntentInput input,
  ) => _remote.createAssetUploadIntent(input);

  @override
  Future<ItemAsset> completeAssetUpload(CompleteItemAssetUploadInput input) =>
      _remote.completeAssetUpload(input);

  @override
  Future<ItemAsset> setPrimaryAsset(int assetId) => _remote.setPrimaryAsset(assetId);

  @override
  Future<void> deleteAsset(int assetId) => _remote.deleteAsset(assetId);

  @override
  Future<List<ItemUsageRecord>> getItemUsage(int itemId) => _remote.getItemUsage(itemId);

  @override
  Future<List<Map<String, String>>> getPipelineTemplates() => _remote.getPipelineTemplates();

  @override
  Future<Map<String, List<PipelineStageNode>>> getPipelineStageNodes() =>
      _remote.getPipelineStageNodes();

  @override
  Future<MasterDataResolution> resolveMasterData({
    required int itemId,
    String? pipelineId,
    bool adopt = false,
  }) => _remote.resolveMasterData(
    itemId: itemId,
    pipelineId: pipelineId,
    adopt: adopt,
  );

  @override
  Future<List<ItemMasterDataRecord>> getItemMasterData(int itemId) =>
      _remote.getItemMasterData(itemId);

  @override
  Future<ItemMasterDataRecord> saveMasterData({
    required int itemId,
    required String pipelineId,
    required PenPaperBaseline baseline,
  }) => _remote.saveMasterData(
    itemId: itemId,
    pipelineId: pipelineId,
    baseline: baseline,
  );

  @override
  Future<void> deleteMasterData({
    required int itemId,
    required String pipelineId,
  }) => _remote.deleteMasterData(itemId: itemId, pipelineId: pipelineId);

  @override
  Future<PipelineMasterDataRoster> getPipelineMasterData(String pipelineId) =>
      _remote.getPipelineMasterData(pipelineId);
}

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../core/sync/replica_reader.dart';
import '../../domain/create_parent_material_input.dart';
import '../../domain/effective_group_schema.dart';
import '../../domain/group_property_draft.dart';
import '../../domain/inventory_control_tower.dart';
import '../../domain/inventory_set_definition.dart';
import '../../domain/material_activity_event.dart';
import '../../domain/material_control_tower_detail.dart';
import '../../domain/material_group_configuration.dart';
import '../../domain/material_inputs.dart';
import '../../domain/material_record.dart';
import '../../domain/variation_stock_record.dart';
import '../models/api_models.dart';
import 'inventory_repository.dart';

/// Serves the materials list from the local replica.
///
/// The most valuable of the decorators on the live path, and not because of its
/// size. `InventoryProvider` subscribes `inventory_updated`, `challan_updated`
/// *and* `challan_generated_ok` to a full `refresh()`, and that re-issues four
/// requests — so **every challan write anywhere in the workspace has been
/// costing every connected client about 20 KB**. Reading the materials list off
/// disk removes the largest of those four.
///
/// Only the list is local. Stock positions, sets and health have no local
/// tables — no endpoint even emits an `inventory_stock_positions` id, so a delta
/// could not address one — and every write still goes to the server.
class LocalFirstInventoryRepository implements InventoryRepository {
  LocalFirstInventoryRepository({
    required InventoryRepository remote,
    required Future<Database?> Function() replica,
    required bool Function() isHydrated,
  }) : _remote = remote,
       _reader = ReplicaReader(replica: replica, isHydrated: isHydrated);

  final InventoryRepository _remote;
  final ReplicaReader _reader;

  @override
  Future<List<MaterialRecord>> getAllMaterials() async {
    // `ORDER BY kind ASC, created_at DESC, barcode ASC`, which is why the
    // replica stores `kind` at all — the endpoint sorted by a column it did not
    // expose until this needed it.
    final local = await _reader.readAll<MaterialRecord>(
      'local_materials',
      orderBy: 'kind ASC, created_at DESC, barcode ASC',
      fromJson: (json) => MaterialDto.fromJson(json).toRecord(),
    );
    return local ?? _remote.getAllMaterials();
  }

  @override
  Future<MaterialRecord?> getMaterialByBarcode(String barcode) async {
    final local = await _reader.readOne<MaterialRecord>(
      'local_materials',
      keyColumn: 'barcode',
      key: barcode,
      fromJson: (json) => MaterialDto.fromJson(json).toRecord(),
    );
    // A miss means "not replicated yet", not "does not exist" — and a scanned
    // barcode that the app says is unknown is the worst answer it could give.
    return local ?? _remote.getMaterialByBarcode(barcode);
  }

  // --- everything below only the server can answer --------------------------

  @override
  Future<void> init() => _remote.init();

  @override
  Future<void> seedIfEmpty() => _remote.seedIfEmpty();

  @override
  Future<List<VariationStockRecord>> getVariationStock() => _remote.getVariationStock();

  @override
  Future<SaveParentResult> saveParentWithChildren(CreateParentMaterialInput input) =>
      _remote.saveParentWithChildren(input);

  @override
  Future<MaterialRecord?> incrementScanCount(String barcode) =>
      _remote.incrementScanCount(barcode);

  @override
  Future<MaterialRecord?> resetScanTrace(String barcode) => _remote.resetScanTrace(barcode);

  @override
  Future<MaterialRecord> createChildMaterial(CreateChildMaterialInput input) =>
      _remote.createChildMaterial(input);

  @override
  Future<MaterialRecord> updateMaterial(UpdateMaterialInput input) =>
      _remote.updateMaterial(input);

  @override
  Future<void> deleteMaterial(String barcode) => _remote.deleteMaterial(barcode);

  @override
  Future<MaterialRecord> linkMaterialToGroup(String barcode, int groupId) =>
      _remote.linkMaterialToGroup(barcode, groupId);

  @override
  Future<MaterialRecord> linkMaterialToItem(
    String barcode,
    int itemId, {
    int? variationLeafNodeId,
  }) => _remote.linkMaterialToItem(
    barcode,
    itemId,
    variationLeafNodeId: variationLeafNodeId,
  );

  @override
  Future<MaterialRecord> unlinkMaterial(String barcode) => _remote.unlinkMaterial(barcode);

  @override
  Future<List<MaterialActivityEvent>> getMaterialActivity(String barcode) =>
      _remote.getMaterialActivity(barcode);

  @override
  Future<InventoryHealthSnapshot> getInventoryHealth() => _remote.getInventoryHealth();

  @override
  Future<MaterialControlTowerDetail?> getMaterialControlTowerDetail(String barcode) =>
      _remote.getMaterialControlTowerDetail(barcode);

  @override
  Future<MaterialControlTowerDetail> createInventoryMovement(
    CreateInventoryMovementInput input,
  ) => _remote.createInventoryMovement(input);

  @override
  Future<MaterialGroupConfiguration> getGroupConfiguration(String barcode) =>
      _remote.getGroupConfiguration(barcode);

  @override
  Future<EffectiveGroupSchema> getEffectiveSchema(int groupId) =>
      _remote.getEffectiveSchema(groupId);

  @override
  Future<MaterialGroupConfiguration> updateGroupConfiguration(
    String barcode, {
    required bool inheritanceEnabled,
    required List<int> selectedItemIds,
    required List<GroupPropertyDraft> propertyDrafts,
    required List<GroupUnitGovernance> unitGovernance,
    required GroupUiPreferences uiPreferences,
    required List<String> discardedPropertyKeys,
  }) => _remote.updateGroupConfiguration(
    barcode,
    inheritanceEnabled: inheritanceEnabled,
    selectedItemIds: selectedItemIds,
    propertyDrafts: propertyDrafts,
    unitGovernance: unitGovernance,
    uiPreferences: uiPreferences,
    discardedPropertyKeys: discardedPropertyKeys,
  );

  @override
  Future<List<InventorySetDefinition>> getSets() => _remote.getSets();

  @override
  Future<InventorySetDefinition> saveSet(SaveInventorySetInput input) =>
      _remote.saveSet(input);

  @override
  Future<void> deleteSet(int setId) => _remote.deleteSet(setId);
}

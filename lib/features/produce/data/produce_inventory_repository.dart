import 'package:core_erp/features/inventory/data/repositories/inventory_repository.dart';
import 'package:core_erp/features/inventory/domain/create_parent_material_input.dart';
import 'package:core_erp/features/inventory/domain/effective_group_schema.dart';
import 'package:core_erp/features/inventory/domain/group_property_draft.dart';
import 'package:core_erp/features/inventory/domain/inventory_control_tower.dart';
import 'package:core_erp/features/inventory/domain/inventory_set_definition.dart';
import 'package:core_erp/features/inventory/domain/material_activity_event.dart';
import 'package:core_erp/features/inventory/domain/material_control_tower_detail.dart';
import 'package:core_erp/features/inventory/domain/material_group_configuration.dart';
import 'package:core_erp/features/inventory/domain/material_inputs.dart';
import 'package:core_erp/features/inventory/domain/material_record.dart';
import 'package:core_erp/features/inventory/domain/variation_stock_record.dart';

/// Inventory as the Produce sandbox sees it: every read goes to the real
/// repository, so the Assign Stock sidebar shows the stock that is actually on
/// the floor, and every write is refused.
///
/// The one write the monitor can reach is [createInventoryMovement] — the
/// leftover-return step of a stage reconcile. Booking that for real would move
/// stock off a preview screen, so it is answered with a fresh read of the
/// material instead, leaving the ledger untouched.
class ProduceInventoryRepository implements InventoryRepository {
  const ProduceInventoryRepository(this._delegate);

  final InventoryRepository _delegate;

  Never _blocked(String operation) {
    throw UnsupportedError(
      'Produce is a UI preview: $operation is not wired to the backend.',
    );
  }

  // ── Reads: straight through ────────────────────────────────────────────────

  @override
  Future<void> init() => _delegate.init();

  @override
  Future<List<VariationStockRecord>> getVariationStock() =>
      _delegate.getVariationStock();

  @override
  Future<MaterialRecord?> getMaterialByBarcode(String barcode) =>
      _delegate.getMaterialByBarcode(barcode);

  @override
  Future<List<MaterialRecord>> getAllMaterials() => _delegate.getAllMaterials();

  @override
  Future<List<MaterialActivityEvent>> getMaterialActivity(String barcode) =>
      _delegate.getMaterialActivity(barcode);

  @override
  Future<InventoryHealthSnapshot> getInventoryHealth() =>
      _delegate.getInventoryHealth();

  @override
  Future<MaterialControlTowerDetail?> getMaterialControlTowerDetail(
    String barcode,
  ) => _delegate.getMaterialControlTowerDetail(barcode);

  @override
  Future<MaterialGroupConfiguration> getGroupConfiguration(String barcode) =>
      _delegate.getGroupConfiguration(barcode);

  @override
  Future<EffectiveGroupSchema> getEffectiveSchema(int groupId) =>
      _delegate.getEffectiveSchema(groupId);

  @override
  Future<List<InventorySetDefinition>> getSets() => _delegate.getSets();

  // ── Writes: refused ────────────────────────────────────────────────────────

  /// Answers the reconcile's leftover return with the material's current state
  /// rather than a booked movement, so the preview flow completes and stock
  /// stays exactly where it was.
  @override
  Future<MaterialControlTowerDetail> createInventoryMovement(
    CreateInventoryMovementInput input,
  ) async {
    final detail = await _delegate.getMaterialControlTowerDetail(
      input.materialBarcode,
    );
    if (detail != null) return detail;
    final material = await _delegate.getMaterialByBarcode(input.materialBarcode);
    if (material == null) {
      _blocked('booking a stock movement for an unknown material');
    }
    return MaterialControlTowerDetail(material: material);
  }

  @override
  Future<void> seedIfEmpty() async => _blocked('seeding inventory');

  @override
  Future<SaveParentResult> saveParentWithChildren(
    CreateParentMaterialInput input,
  ) async => _blocked('creating materials');

  @override
  Future<MaterialRecord?> incrementScanCount(String barcode) async =>
      _blocked('recording a scan');

  @override
  Future<MaterialRecord?> resetScanTrace(String barcode) async =>
      _blocked('resetting a scan trace');

  @override
  Future<MaterialRecord> createChildMaterial(
    CreateChildMaterialInput input,
  ) async => _blocked('creating a material');

  @override
  Future<MaterialRecord> updateMaterial(UpdateMaterialInput input) async =>
      _blocked('editing a material');

  @override
  Future<void> deleteMaterial(String barcode) async =>
      _blocked('deleting a material');

  @override
  Future<MaterialRecord> linkMaterialToGroup(String barcode, int groupId) async =>
      _blocked('linking a material to a group');

  @override
  Future<MaterialRecord> linkMaterialToItem(
    String barcode,
    int itemId, {
    int? variationLeafNodeId,
  }) async => _blocked('linking a material to an item');

  @override
  Future<MaterialRecord> unlinkMaterial(String barcode) async =>
      _blocked('unlinking a material');

  @override
  Future<MaterialGroupConfiguration> updateGroupConfiguration(
    String barcode, {
    required bool inheritanceEnabled,
    required List<int> selectedItemIds,
    required List<GroupPropertyDraft> propertyDrafts,
    required List<GroupUnitGovernance> unitGovernance,
    required GroupUiPreferences uiPreferences,
    required List<String> discardedPropertyKeys,
  }) async => _blocked('editing a group configuration');

  @override
  Future<InventorySetDefinition> saveSet(SaveInventorySetInput input) async =>
      _blocked('saving a set');

  @override
  Future<void> deleteSet(int setId) async => _blocked('deleting a set');
}

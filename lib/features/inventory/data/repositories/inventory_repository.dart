import '../../domain/create_parent_material_input.dart';
import '../../domain/group_property_draft.dart';
import '../../domain/inventory_control_tower.dart';
import '../../domain/material_activity_event.dart';
import '../../domain/material_control_tower_detail.dart';
import '../../domain/material_group_configuration.dart';
import '../../domain/material_inputs.dart';
import '../../domain/material_record.dart';

abstract class InventoryRepository {
  Future<void> init();
  Future<void> seedIfEmpty();
  Future<SaveParentResult> saveParentWithChildren(
    CreateParentMaterialInput input,
  );
  Future<MaterialRecord?> getMaterialByBarcode(String barcode);
  Future<List<MaterialRecord>> getAllMaterials();
  Future<MaterialRecord?> incrementScanCount(String barcode);
  Future<MaterialRecord?> resetScanTrace(String barcode);
  Future<MaterialRecord> createChildMaterial(CreateChildMaterialInput input);
  Future<MaterialRecord> updateMaterial(UpdateMaterialInput input);
  Future<void> deleteMaterial(String barcode);
  Future<MaterialRecord> linkMaterialToGroup(String barcode, int groupId);
  Future<MaterialRecord> linkMaterialToItem(
    String barcode,
    int itemId,
  );
  Future<MaterialRecord> unlinkMaterial(String barcode);
  Future<List<MaterialActivityEvent>> getMaterialActivity(String barcode);
  Future<InventoryHealthSnapshot> getInventoryHealth();
  Future<MaterialControlTowerDetail?> getMaterialControlTowerDetail(
    String barcode,
  );
  Future<MaterialControlTowerDetail> createInventoryMovement(
    CreateInventoryMovementInput input,
  );
  Future<MaterialGroupConfiguration> getGroupConfiguration(String barcode);
  Future<MaterialGroupConfiguration> updateGroupConfiguration(
    String barcode, {
    required bool inheritanceEnabled,
    required List<int> selectedItemIds,
    required List<GroupPropertyDraft> propertyDrafts,
    required List<GroupUnitGovernance> unitGovernance,
    required GroupUiPreferences uiPreferences,
  });
}

class SaveParentResult {
  const SaveParentResult({
    required this.parentBarcode,
    required this.childBarcodes,
  });

  final String parentBarcode;
  final List<String> childBarcodes;
}

import '../../domain/create_parent_material_input.dart';
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
}

class SaveParentResult {
  const SaveParentResult({
    required this.parentBarcode,
    required this.childBarcodes,
  });

  final String parentBarcode;
  final List<String> childBarcodes;
}

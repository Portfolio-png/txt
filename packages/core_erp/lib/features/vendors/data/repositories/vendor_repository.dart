import '../../domain/vendor_definition.dart';
import '../../domain/vendor_inputs.dart';

abstract class VendorRepository {
  Future<void> init();
  Future<List<VendorDefinition>> getVendors();
  Future<VendorDefinition> createVendor(CreateVendorInput input);
  Future<VendorDefinition> updateVendor(UpdateVendorInput input);
  Future<VendorDefinition> archiveVendor(int id);
  Future<VendorDefinition> restoreVendor(int id);
}

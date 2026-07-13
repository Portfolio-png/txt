import '../../domain/sub_contractor_definition.dart';
import '../../domain/sub_contractor_inputs.dart';

abstract class SubContractorRepository {
  Future<void> init();

  Future<List<SubContractorDefinition>> getSubContractors(int clientId);

  Future<List<SubContractorDefinition>> getAllSubContractors();

  Future<SubContractorDefinition> createSubContractor(
    int clientId,
    CreateSubContractorInput input,
  );

  Future<SubContractorDefinition> updateSubContractor(
    int id,
    UpdateSubContractorInput input,
  );

  Future<void> deleteSubContractor(int id);
}

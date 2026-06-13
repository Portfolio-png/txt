import '../domain/machine.dart';

abstract class MachineRepository {
  Future<void> init();
  Future<List<Machine>> fetchMachines();
  Future<Machine> getMachine(String id);
  Future<Machine> saveMachine(Machine machine);
  Future<void> deleteMachine(String id);
  Future<MachineAssetUploadIntent?> createAssetUploadIntent(MachineAssetUploadIntentInput input);
  Future<String?> completeAssetUpload(CompleteMachineAssetUploadInput input);
}

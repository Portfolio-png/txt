import '../domain/die.dart';

abstract class DieRepository {
  Future<void> init();
  Future<List<Die>> fetchDies();
  Future<Die> getDie(String id);
  Future<Die> saveDie(Die die);
  Future<void> deleteDie(String id);
  Future<DieAssetUploadIntent?> createAssetUploadIntent(DieAssetUploadIntentInput input);
  Future<String?> completeAssetUpload(CompleteDieAssetUploadInput input);
}

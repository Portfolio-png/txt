import '../domain/die.dart';

abstract class DieRepository {
  Future<void> init();
  Future<List<Die>> fetchDies();
  Future<Die> getDie(String id);
  Future<void> saveDie(Die die);
  Future<void> deleteDie(String id);
}

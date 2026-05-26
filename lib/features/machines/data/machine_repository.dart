import '../domain/machine.dart';

abstract class MachineRepository {
  Future<void> init();
  Future<List<Machine>> fetchMachines();
  Future<Machine> getMachine(String id);
  Future<void> saveMachine(Machine machine);
  Future<void> deleteMachine(String id);
}

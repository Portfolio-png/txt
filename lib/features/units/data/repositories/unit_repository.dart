import '../../domain/unit_definition.dart';
import '../../domain/unit_inputs.dart';

abstract class UnitRepository {
  Future<void> init();
  Future<List<UnitDefinition>> getUnits();
  Future<UnitDefinition> createUnit(CreateUnitInput input);
  Future<UnitDefinition> updateUnit(UpdateUnitInput input);
  Future<UnitDefinition> archiveUnit(int id);
  Future<UnitDefinition> restoreUnit(int id);
}

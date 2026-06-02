import '../domain/machine.dart';
import 'machine_repository.dart';

class MockMachineRepository implements MachineRepository {
  @override
  Future<void> init() async {}
  final List<Machine> _machines = [
    Machine(
      id: 'm1',
      name: 'Amada CNC Press Brake',
      assetId: 'MAC-1001',
      primaryPhotoUrl: 'https://images.unsplash.com/photo-1565439390237-db561c2ba24e?auto=format&fit=crop&q=80',
      groupId: null,
      makeModel: 'Amada HDS-8025NT',
      serialNumber: 'AMD-909283',
      location: 'Press Shop A',
      installationDate: DateTime(2022, 5, 10),
      status: MachineStatus.active,
      customProperties: const [
        CustomProperty(key: 'Tonnage', value: '80T'),
        CustomProperty(key: 'Bed Length', value: '2500mm'),
      ],
      createdAt: DateTime.now().subtract(const Duration(days: 300)),
      updatedAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
    Machine(
      id: 'm2',
      name: 'Haas VF-2SS CNC Mill',
      assetId: 'MAC-1002',
      primaryPhotoUrl: 'https://images.unsplash.com/photo-1610484557978-56961cf3d623?auto=format&fit=crop&q=80',
      groupId: null,
      makeModel: 'Haas VF-2SS',
      serialNumber: 'HSS-10020',
      location: 'CNC Line 2',
      installationDate: DateTime(2023, 1, 15),
      status: MachineStatus.maintenance,
      customProperties: const [
        CustomProperty(key: 'Spindle Speed', value: '12000 RPM'),
        CustomProperty(key: 'Axis', value: '3-Axis'),
      ],
      createdAt: DateTime.now().subtract(const Duration(days: 150)),
      updatedAt: DateTime.now().subtract(const Duration(days: 5)),
    ),
  ];

  @override
  Future<List<Machine>> fetchMachines() async {
    await Future.delayed(const Duration(milliseconds: 600));
    return List.unmodifiable(_machines);
  }

  @override
  Future<Machine> getMachine(String id) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _machines.firstWhere((m) => m.id == id);
  }

  @override
  Future<void> saveMachine(Machine machine) async {
    await Future.delayed(const Duration(milliseconds: 500));
    final index = _machines.indexWhere((m) => m.id == machine.id);
    if (index >= 0) {
      _machines[index] = machine.copyWith(updatedAt: DateTime.now());
    } else {
      _machines.add(machine.copyWith(id: DateTime.now().millisecondsSinceEpoch.toString(), createdAt: DateTime.now(), updatedAt: DateTime.now()));
    }
  }

  @override
  Future<void> deleteMachine(String id) async {
    await Future.delayed(const Duration(milliseconds: 400));
    _machines.removeWhere((m) => m.id == id);
  }

  @override
  Future<MachineAssetUploadIntent?> createAssetUploadIntent(MachineAssetUploadIntentInput input) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return MachineAssetUploadIntent(
      alreadyUploaded: true,
      photoUrl: 'https://images.unsplash.com/photo-1590494165264-1ebe3602eb80?auto=format&fit=crop&q=80',
      upload: null,
    );
  }

  @override
  Future<String?> completeAssetUpload(CompleteMachineAssetUploadInput input) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return 'https://images.unsplash.com/photo-1590494165264-1ebe3602eb80?auto=format&fit=crop&q=80';
  }
}

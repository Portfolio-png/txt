import 'package:paper/features/machines/domain/machine.dart';
import '../domain/die.dart';
import 'die_repository.dart';

class MockDieRepository implements DieRepository {
  @override
  Future<void> init() async {}

  final List<Die> _dies = [
    Die(
      id: 'd1',
      name: 'Amada Press Die Set A',
      toolCode: 'TL-890-A',
      photoUrls: const [
        'https://images.unsplash.com/photo-1590494165264-1ebe3602eb80?auto=format&fit=crop&q=80',
        'https://images.unsplash.com/photo-1504917595217-d4dc5ebe6122?auto=format&fit=crop&q=80'
      ],
      operationalNotes: 'Requires heavy lubrication on the guide pins. Watch out for scrap buildup on the left exit chute.',
      compatibleMachineGroupIds: const [],
      storageLocation: 'Rack B, Shelf 3',
      numberOfCavities: 2,
      strokeCount: 45000,
      maxStrokes: 100000,
      physicalSpecs: const [
        CustomProperty(key: 'Weight', value: '1250 kg'),
        CustomProperty(key: 'Shut Height', value: '350 mm'),
        CustomProperty(key: 'Dimensions', value: '800 x 600 x 400 mm'),
      ],
      status: DieStatus.ready,
      ownership: DieOwnership.inHouse,
      createdAt: DateTime.now().subtract(const Duration(days: 400)),
      updatedAt: DateTime.now().subtract(const Duration(days: 10)),
    ),
    Die(
      id: 'd2',
      name: 'Haas CNC Cutter Head',
      toolCode: 'TL-102-B',
      photoUrls: const [
        'https://images.unsplash.com/photo-1581091226825-a6a2a5aee158?auto=format&fit=crop&q=80'
      ],
      operationalNotes: 'Customer owned. Handle with care. Clean thoroughly before returning to storage.',
      compatibleMachineGroupIds: const [],
      storageLocation: 'Rack A, Shelf 1',
      numberOfCavities: 1,
      strokeCount: 98000,
      maxStrokes: 100000,
      physicalSpecs: const [
        CustomProperty(key: 'Weight', value: '2100 kg'),
      ],
      status: DieStatus.needsRepair,
      ownership: DieOwnership.customerOwned,
      createdAt: DateTime.now().subtract(const Duration(days: 800)),
      updatedAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
  ];

  @override
  Future<List<Die>> fetchDies() async {
    await Future.delayed(const Duration(milliseconds: 600));
    return List.unmodifiable(_dies);
  }

  @override
  Future<Die> getDie(String id) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _dies.firstWhere((d) => d.id == id);
  }

  @override
  Future<Die> saveDie(Die die) async {
    await Future.delayed(const Duration(milliseconds: 500));
    final index = _dies.indexWhere((d) => d.id == die.id);
    if (index >= 0) {
      final updated = die.copyWith(updatedAt: DateTime.now());
      _dies[index] = updated;
      return updated;
    } else {
      final created = die.copyWith(id: DateTime.now().millisecondsSinceEpoch.toString(), createdAt: DateTime.now(), updatedAt: DateTime.now());
      _dies.add(created);
      return created;
    }
  }

  @override
  Future<void> deleteDie(String id) async {
    await Future.delayed(const Duration(milliseconds: 400));
    _dies.removeWhere((d) => d.id == id);
  }

  @override
  Future<DieAssetUploadIntent?> createAssetUploadIntent(DieAssetUploadIntentInput input) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return DieAssetUploadIntent(
      alreadyUploaded: true,
      photoUrl: 'https://images.unsplash.com/photo-1590494165264-1ebe3602eb80?auto=format&fit=crop&q=80',
      upload: null,
    );
  }

  @override
  Future<String?> completeAssetUpload(CompleteDieAssetUploadInput input) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return 'https://images.unsplash.com/photo-1590494165264-1ebe3602eb80?auto=format&fit=crop&q=80';
  }
}

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/machine.dart';
import 'machine_repository.dart';

class ApiMachineRepository implements MachineRepository {
  ApiMachineRepository({
    http.Client? client,
    this.baseUrl = 'http://localhost:8080',
    this.useMockResponses = true,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final bool useMockResponses;

  static final List<Machine> _mockMachines = [
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
  Future<void> init() async {}

  @override
  Future<List<Machine>> fetchMachines() async {
    if (useMockResponses) {
      await Future.delayed(const Duration(milliseconds: 300));
      return List.unmodifiable(_mockMachines);
    }

    final uri = Uri.parse('$baseUrl/api/machines');
    final response = await _client.get(uri);
    final payload = _decodeJsonObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300 || payload['success'] != true) {
      throw Exception(payload['error'] as String? ?? 'Failed to fetch machines');
    }

    final list = payload['machines'] as List<dynamic>? ?? [];
    return list.map((item) => _machineFromJson(item as Map<String, dynamic>)).toList();
  }

  @override
  Future<Machine> getMachine(String id) async {
    if (useMockResponses) {
      await Future.delayed(const Duration(milliseconds: 150));
      return _mockMachines.firstWhere((m) => m.id == id);
    }

    final uri = Uri.parse('$baseUrl/api/machines/$id');
    final response = await _client.get(uri);
    final payload = _decodeJsonObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300 || payload['success'] != true) {
      throw Exception(payload['error'] as String? ?? 'Failed to get machine');
    }

    return _machineFromJson(payload['machine'] as Map<String, dynamic>);
  }

  @override
  Future<void> saveMachine(Machine machine) async {
    if (useMockResponses) {
      await Future.delayed(const Duration(milliseconds: 300));
      final index = _mockMachines.indexWhere((m) => m.id == machine.id);
      if (index >= 0) {
        _mockMachines[index] = machine.copyWith(updatedAt: DateTime.now());
      } else {
        _mockMachines.add(machine.copyWith(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
      }
      return;
    }

    final uri = Uri.parse('$baseUrl/api/machines');
    final body = jsonEncode(_machineToJson(machine));
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: body,
    );
    final payload = _decodeJsonObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300 || payload['success'] != true) {
      throw Exception(payload['error'] as String? ?? 'Failed to save machine');
    }
  }

  @override
  Future<void> deleteMachine(String id) async {
    if (useMockResponses) {
      await Future.delayed(const Duration(milliseconds: 200));
      _mockMachines.removeWhere((m) => m.id == id);
      return;
    }

    final uri = Uri.parse('$baseUrl/api/machines/$id');
    final response = await _client.delete(uri);
    final payload = _decodeJsonObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300 || payload['success'] != true) {
      throw Exception(payload['error'] as String? ?? 'Failed to delete machine');
    }
  }

  Map<String, dynamic> _decodeJsonObject(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Unexpected response shape.');
    }
    return decoded;
  }

  MachineStatus _parseStatus(String statusStr) {
    switch (statusStr) {
      case 'maintenance':
        return MachineStatus.maintenance;
      case 'decommissioned':
        return MachineStatus.decommissioned;
      case 'active':
      default:
        return MachineStatus.active;
    }
  }

  String _statusToString(MachineStatus status) {
    switch (status) {
      case MachineStatus.maintenance:
        return 'maintenance';
      case MachineStatus.decommissioned:
        return 'decommissioned';
      case MachineStatus.active:
        return 'active';
    }
  }

  CustomPropertyType _parsePropertyType(String typeStr) {
    if (typeStr == 'numeric') {
      return CustomPropertyType.numeric;
    }
    return CustomPropertyType.text;
  }

  String _propertyTypeToString(CustomPropertyType type) {
    if (type == CustomPropertyType.numeric) {
      return 'numeric';
    }
    return 'text';
  }

  CustomProperty _propertyFromJson(Map<String, dynamic> json) {
    return CustomProperty(
      key: json['key'] as String? ?? '',
      value: json['value'] as String? ?? '',
      type: _parsePropertyType(json['type'] as String? ?? 'text'),
      unitId: json['unitId'] as int?,
    );
  }

  Map<String, dynamic> _propertyToJson(CustomProperty prop) {
    return {
      'key': prop.key,
      'value': prop.value,
      'type': _propertyTypeToString(prop.type),
      'unitId': prop.unitId,
    };
  }

  Machine _machineFromJson(Map<String, dynamic> json) {
    return Machine(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      assetId: json['assetId'] as String? ?? '',
      primaryPhotoUrl: json['primaryPhotoUrl'] as String? ?? '',
      groupId: json['groupId'] as int?,
      makeModel: json['makeModel'] as String? ?? '',
      serialNumber: json['serialNumber'] as String? ?? '',
      location: json['location'] as String?,
      installationDate: json['installationDate'] != null ? DateTime.tryParse(json['installationDate'] as String) : null,
      status: _parseStatus(json['status'] as String? ?? ''),
      customProperties: (json['customProperties'] as List<dynamic>? ?? [])
          .map((p) => _propertyFromJson(p as Map<String, dynamic>))
          .toList(),
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now() : DateTime.now(),
      updatedAt: json['updatedAt'] != null ? DateTime.tryParse(json['updatedAt'] as String) ?? DateTime.now() : DateTime.now(),
    );
  }

  Map<String, dynamic> _machineToJson(Machine m) {
    return {
      'id': m.id,
      'name': m.name,
      'assetId': m.assetId,
      'primaryPhotoUrl': m.primaryPhotoUrl,
      'groupId': m.groupId,
      'makeModel': m.makeModel,
      'serialNumber': m.serialNumber,
      'location': m.location,
      'installationDate': m.installationDate?.toIso8601String(),
      'status': _statusToString(m.status),
      'customProperties': m.customProperties.map(_propertyToJson).toList(),
      'createdAt': m.createdAt.toIso8601String(),
      'updatedAt': m.updatedAt.toIso8601String(),
    };
  }
}

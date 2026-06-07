import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:paper/features/machines/domain/machine.dart';
import '../domain/die.dart';
import 'die_repository.dart';

class ApiDieRepository implements DieRepository {
  ApiDieRepository({
    http.Client? client,
    this.baseUrl = 'http://localhost:8080',
    this.useMockResponses = true,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final bool useMockResponses;

  static final List<Die> _mockDies = [
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
  Future<void> init() async {}

  @override
  Future<List<Die>> fetchDies() async {
    if (useMockResponses) {
      await Future.delayed(const Duration(milliseconds: 300));
      return List.unmodifiable(_mockDies);
    }

    final uri = Uri.parse('$baseUrl/api/dies');
    final response = await _client.get(uri);
    final payload = _decodeJsonObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300 || payload['success'] != true) {
      throw Exception(payload['error'] as String? ?? 'Failed to fetch dies');
    }

    final list = payload['dies'] as List<dynamic>? ?? [];
    return list.map((item) => _dieFromJson(item as Map<String, dynamic>)).toList();
  }

  @override
  Future<Die> getDie(String id) async {
    if (useMockResponses) {
      await Future.delayed(const Duration(milliseconds: 150));
      return _mockDies.firstWhere((d) => d.id == id);
    }

    final uri = Uri.parse('$baseUrl/api/dies/$id');
    final response = await _client.get(uri);
    final payload = _decodeJsonObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300 || payload['success'] != true) {
      throw Exception(payload['error'] as String? ?? 'Failed to get die');
    }

    return _dieFromJson(payload['die'] as Map<String, dynamic>);
  }

  @override
  Future<Die> saveDie(Die die) async {
    if (useMockResponses) {
      await Future.delayed(const Duration(milliseconds: 300));
      final index = _mockDies.indexWhere((d) => d.id == die.id);
      if (index >= 0) {
        final updated = die.copyWith(updatedAt: DateTime.now());
        _mockDies[index] = updated;
        return updated;
      } else {
        final created = die.copyWith(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        _mockDies.add(created);
        return created;
      }
    }

    final uri = Uri.parse('$baseUrl/api/dies');
    final body = jsonEncode(_dieToJson(die));
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: body,
    );
    final payload = _decodeJsonObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300 || payload['success'] != true) {
      throw Exception(payload['error'] as String? ?? 'Failed to save die');
    }
    return _dieFromJson(payload['die'] as Map<String, dynamic>);
  }

  @override
  Future<void> deleteDie(String id) async {
    if (useMockResponses) {
      await Future.delayed(const Duration(milliseconds: 200));
      _mockDies.removeWhere((d) => d.id == id);
      return;
    }

    final uri = Uri.parse('$baseUrl/api/dies/$id');
    final response = await _client.delete(uri);
    final payload = _decodeJsonObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300 || payload['success'] != true) {
      throw Exception(payload['error'] as String? ?? 'Failed to delete die');
    }
  }

  @override
  Future<DieAssetUploadIntent?> createAssetUploadIntent(DieAssetUploadIntentInput input) async {
    if (useMockResponses) {
      await Future.delayed(const Duration(milliseconds: 300));
      return DieAssetUploadIntent(
        alreadyUploaded: true,
        photoUrl: 'https://images.unsplash.com/photo-1590494165264-1ebe3602eb80?auto=format&fit=crop&q=80',
        upload: null,
      );
    }
    
    final uri = Uri.parse('$baseUrl/api/dies/${input.dieId}/assets/upload-intent');
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'fileName': input.fileName,
        'contentType': input.contentType,
        'sizeBytes': input.sizeBytes,
        'sha256': input.sha256,
        'isPrimary': input.isPrimary,
      }),
    );
    
    final payload = _decodeJsonObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300 || payload['success'] != true) {
      throw Exception(payload['error'] as String? ?? 'Failed to create upload intent');
    }
    
    final data = payload['intent'] as Map<String, dynamic>;
    final alreadyUploaded = data['alreadyUploaded'] as bool? ?? false;
    
    DieAssetUploadTarget? uploadTarget;
    if (data['upload'] != null) {
      final uploadMap = data['upload'] as Map<String, dynamic>;
      final headersMap = uploadMap['headers'] as Map<String, dynamic>? ?? {};
      uploadTarget = DieAssetUploadTarget(
        uploadSessionId: uploadMap['uploadSessionId'] as String? ?? '',
        objectKey: uploadMap['objectKey'] as String? ?? '',
        uploadUrl: Uri.parse(uploadMap['uploadUrl'] as String? ?? ''),
        headers: headersMap.map((k, v) => MapEntry(k, v.toString())),
        expiresAt: uploadMap['expiresAt'] != null ? DateTime.tryParse(uploadMap['expiresAt'] as String) : null,
      );
    }
    
    String? finalUrl;
    if (alreadyUploaded && data['asset'] != null) {
      final assetMap = data['asset'] as Map<String, dynamic>;
      finalUrl = assetMap['readUrl'] as String?;
    }
    
    return DieAssetUploadIntent(
      alreadyUploaded: alreadyUploaded,
      photoUrl: finalUrl,
      upload: uploadTarget,
    );
  }

  @override
  Future<String?> completeAssetUpload(CompleteDieAssetUploadInput input) async {
    if (useMockResponses) {
      await Future.delayed(const Duration(milliseconds: 300));
      return 'https://images.unsplash.com/photo-1590494165264-1ebe3602eb80?auto=format&fit=crop&q=80';
    }
    
    final uri = Uri.parse('$baseUrl/api/dies/${input.dieId}/assets/upload-complete');
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'uploadSessionId': input.uploadSessionId,
        'objectKey': input.objectKey,
      }),
    );
    
    final payload = _decodeJsonObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300 || payload['success'] != true) {
      throw Exception(payload['error'] as String? ?? 'Failed to complete upload');
    }
    
    final asset = payload['asset'] as Map<String, dynamic>?;
    return asset?['readUrl'] as String?;
  }

  Map<String, dynamic> _decodeJsonObject(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Unexpected response shape.');
    }
    return decoded;
  }

  DieStatus _parseStatus(String statusStr) {
    switch (statusStr) {
      case 'inProduction':
        return DieStatus.inProduction;
      case 'needsRepair':
        return DieStatus.needsRepair;
      case 'obsolete':
        return DieStatus.obsolete;
      case 'ready':
      default:
        return DieStatus.ready;
    }
  }

  String _statusToString(DieStatus status) {
    switch (status) {
      case DieStatus.inProduction:
        return 'inProduction';
      case DieStatus.needsRepair:
        return 'needsRepair';
      case DieStatus.obsolete:
        return 'obsolete';
      case DieStatus.ready:
        return 'ready';
    }
  }

  DieOwnership _parseOwnership(String ownershipStr) {
    if (ownershipStr == 'customerOwned') {
      return DieOwnership.customerOwned;
    }
    return DieOwnership.inHouse;
  }

  String _ownershipToString(DieOwnership ownership) {
    if (ownership == DieOwnership.customerOwned) {
      return 'customerOwned';
    }
    return 'inHouse';
  }

  CustomPropertyType _parsePropertyType(String typeStr) {
    if (typeStr == 'numeric') {
      return CustomPropertyType.numeric;
    }
    if (typeStr == 'dropdown') {
      return CustomPropertyType.dropdown;
    }
    return CustomPropertyType.text;
  }

  String _propertyTypeToString(CustomPropertyType type) {
    if (type == CustomPropertyType.numeric) {
      return 'numeric';
    }
    if (type == CustomPropertyType.dropdown) {
      return 'dropdown';
    }
    return 'text';
  }

  CustomProperty _propertyFromJson(Map<String, dynamic> json) {
    return CustomProperty(
      key: json['key'] as String? ?? '',
      value: json['value'] as String? ?? '',
      type: _parsePropertyType(json['type'] as String? ?? 'text'),
      unitId: json['unitId'] as int?,
      options: (json['options'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }

  Map<String, dynamic> _propertyToJson(CustomProperty prop) {
    return {
      'key': prop.key,
      'value': prop.value,
      'type': _propertyTypeToString(prop.type),
      'unitId': prop.unitId,
      'options': prop.options,
    };
  }

  Die _dieFromJson(Map<String, dynamic> json) {
    return Die(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? (json['producedPartNumbers'] as List<dynamic>?)?.join(', ') ?? '',
      toolCode: json['toolCode'] as String? ?? '',
      photoUrls: (json['photoUrls'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toList(),
      operationalNotes: json['operationalNotes'] as String? ?? '',
      compatibleMachineGroupIds: (json['compatibleMachineGroupIds'] as List<dynamic>? ?? [])
          .map((e) => e as int)
          .toList(),
      storageLocation: json['storageLocation'] as String?,
      numberOfCavities: json['numberOfCavities'] as int?,
      strokeCount: json['strokeCount'] as int?,
      maxStrokes: json['maxStrokes'] as int?,
      physicalSpecs: () {
        final raw = json['physicalSpecs'];
        if (raw is List) {
          return raw.map((p) => _propertyFromJson(p as Map<String, dynamic>)).toList();
        } else if (raw is Map) {
          return raw.entries.map((e) => CustomProperty(
            key: e.key.toString(),
            value: e.value.toString(),
          )).toList();
        }
        return const <CustomProperty>[];
      }(),
      status: _parseStatus(json['status'] as String? ?? ''),
      ownership: _parseOwnership(json['ownership'] as String? ?? ''),
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now() : DateTime.now(),
      updatedAt: json['updatedAt'] != null ? DateTime.tryParse(json['updatedAt'] as String) ?? DateTime.now() : DateTime.now(),
    );
  }

  Map<String, dynamic> _dieToJson(Die d) {
    return {
      'id': d.id,
      'name': d.name,
      'toolCode': d.toolCode,
      'producedPartNumbers': d.name.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      'photoUrls': d.photoUrls,
      'operationalNotes': d.operationalNotes,
      'compatibleMachineGroupIds': d.compatibleMachineGroupIds,
      'storageLocation': d.storageLocation,
      'numberOfCavities': d.numberOfCavities,
      'strokeCount': d.strokeCount,
      'maxStrokes': d.maxStrokes,
      'physicalSpecs': d.physicalSpecs.map(_propertyToJson).toList(),
      'status': _statusToString(d.status),
      'ownership': _ownershipToString(d.ownership),
      'createdAt': d.createdAt.toIso8601String(),
      'updatedAt': d.updatedAt.toIso8601String(),
    };
  }
}

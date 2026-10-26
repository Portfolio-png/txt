import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/die_maker.dart';

abstract class DieMakerRepository {
  Future<List<DieMaker>> list({bool includeArchived = false});
  Future<DieMaker> create(DieMakerInput input);
  Future<DieMaker> update(DieMakerInput input);

  /// Archives when dies still name it, deletes outright when none do.
  ///
  /// Answers whether it was archived, because the two outcomes need different
  /// words on screen and the caller cannot tell them apart from the request.
  Future<bool> remove(int id);
}

class ApiDieMakerRepository implements DieMakerRepository {
  ApiDieMakerRepository({
    http.Client? client,
    this.baseUrl = 'http://localhost:8080',
    this.useMockResponses = false,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final bool useMockResponses;

  static final List<DieMaker> _mock = <DieMaker>[];
  static int _mockNextId = 1;

  static void debugResetMockStore() {
    _mock.clear();
    _mockNextId = 1;
  }

  Map<String, dynamic> _decode(http.Response response) {
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw DieMakerException('The server answered something unexpected.');
  }

  Never _throwFrom(Map<String, dynamic> payload) {
    throw DieMakerException(
      payload['error'] as String? ?? 'That did not save.',
      code: payload['code'] as String?,
      existingId: (payload['dieMakerId'] as num?)?.toInt(),
    );
  }

  @override
  Future<List<DieMaker>> list({bool includeArchived = false}) async {
    if (useMockResponses) {
      return [
        for (final maker in _mock)
          if (includeArchived || !maker.isArchived) maker,
      ];
    }

    final uri = Uri.parse(
      '$baseUrl/api/die-makers${includeArchived ? '?includeArchived=true' : ''}',
    );
    final response = await _client.get(uri);
    final payload = _decode(response);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      _throwFrom(payload);
    }
    return [
      for (final row in (payload['dieMakers'] as List? ?? const []))
        DieMaker.fromJson(row as Map<String, dynamic>),
    ];
  }

  @override
  Future<DieMaker> create(DieMakerInput input) async {
    if (useMockResponses) {
      final name = (input.name ?? '').trim();
      final clash = _mock.where(
        (m) => m.name.toLowerCase() == name.toLowerCase(),
      );
      if (clash.isNotEmpty) {
        throw DieMakerException(
          '"${clash.first.name}" is already a die maker.',
          code: 'die_maker_duplicate',
          existingId: clash.first.id,
        );
      }
      final made = DieMaker(
        id: _mockNextId++,
        name: name,
        alias: input.alias ?? '',
        gstNumber: input.gstNumber ?? '',
        address: input.address ?? '',
        contactName: input.contactName ?? '',
        designation: input.designation ?? '',
        phone: input.phone ?? '',
        email: input.email ?? '',
      );
      _mock.add(made);
      return made;
    }

    final response = await _client.post(
      Uri.parse('$baseUrl/api/die-makers'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(input.toJson()),
    );
    final payload = _decode(response);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      _throwFrom(payload);
    }
    return DieMaker.fromJson(payload['dieMaker'] as Map<String, dynamic>);
  }

  @override
  Future<DieMaker> update(DieMakerInput input) async {
    final id = input.id;
    if (id == null) {
      throw DieMakerException('An update needs the die maker it is updating.');
    }

    if (useMockResponses) {
      final index = _mock.indexWhere((m) => m.id == id);
      if (index < 0) throw DieMakerException('No such die maker.');
      final before = _mock[index];
      final after = DieMaker(
        id: id,
        name: input.name ?? before.name,
        alias: input.alias ?? before.alias,
        gstNumber: input.gstNumber ?? before.gstNumber,
        address: input.address ?? before.address,
        contactName: input.contactName ?? before.contactName,
        designation: input.designation ?? before.designation,
        phone: input.phone ?? before.phone,
        email: input.email ?? before.email,
        usageCount: before.usageCount,
        isArchived: input.isArchived ?? before.isArchived,
      );
      _mock[index] = after;
      return after;
    }

    final response = await _client.patch(
      Uri.parse('$baseUrl/api/die-makers/$id'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(input.toJson()),
    );
    final payload = _decode(response);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      _throwFrom(payload);
    }
    return DieMaker.fromJson(payload['dieMaker'] as Map<String, dynamic>);
  }

  @override
  Future<bool> remove(int id) async {
    if (useMockResponses) {
      _mock.removeWhere((m) => m.id == id);
      return false;
    }

    final response = await _client.delete(
      Uri.parse('$baseUrl/api/die-makers/$id'),
    );
    final payload = _decode(response);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      _throwFrom(payload);
    }
    return payload['archived'] == true;
  }
}

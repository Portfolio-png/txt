import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/unit_family.dart';

class UnitFamilyException implements Exception {
  UnitFamilyException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads the units master as FAMILIES with real integer ladders.
///
/// Kept apart from `UnitRepository`, which is the pre-contract layer built on
/// `UnitDefinition` and has a dozen implementations and fakes. The contract's
/// `UnitFamily` / `Unit` types had no way to be populated at all before this —
/// the only things that built one were hand-written literals in
/// `units_contract_test.dart` — which meant any Dart code wanting to know that
/// a gross is 144 had to write 144 down, the exact thing invariant I2 forbids.
///
/// Nothing here converts between families. Per §7 that is not the units
/// master's job: an area and a density making a mass is a different kind of
/// statement from a kilogram being a million milligrams.
class UnitFamilyService {
  UnitFamilyService({
    http.Client? client,
    required this.baseUrl,
    this.useMockResponses = false,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final bool useMockResponses;

  List<UnitFamily>? _cache;

  /// The six seeded families, or whatever this workspace actually has.
  ///
  /// Cached because a factor cannot change under a running app without a
  /// migration — and because the alternative is every quantity on a screen
  /// costing a request.
  Future<List<UnitFamily>> families({bool refresh = false}) async {
    if (!refresh && _cache != null) return _cache!;
    if (useMockResponses) return _cache = _mockFamilies;
    final payload = await _get('/api/units/families');
    final raw = (payload['families'] as List?) ?? const [];
    return _cache = [
      for (final entry in raw)
        if (entry is Map<String, dynamic>) ?_familyFrom(entry),
    ];
  }

  /// One family by its code — 'count', 'mass', 'length', 'area', 'volume',
  /// 'time'. Null when this workspace has not seeded it, which a caller must
  /// handle rather than assume: families arrived in migration 051 and a
  /// database that predates it has none.
  Future<UnitFamily?> byCode(String code) async {
    final wanted = code.trim().toLowerCase();
    for (final family in await families()) {
      if (family.code.toLowerCase() == wanted) return family;
    }
    return null;
  }

  /// The family a given unit belongs to, by unit id.
  Future<UnitFamily?> familyOfUnit(int unitId) async {
    for (final family in await families()) {
      for (final unit in family.units) {
        if (unit.id == unitId) return family;
      }
    }
    return null;
  }

  UnitFamily? _familyFrom(Map<String, dynamic> json) {
    final id = (json['id'] as num?)?.toInt();
    if (id == null) return null;
    // `code` arrived with migration 051; a group that predates it has none and
    // falls back to its name, so an un-migrated workspace still reads.
    final code = _text(json['code']).isNotEmpty
        ? _text(json['code'])
        : _text(json['name']).toLowerCase();
    final units = <Unit>[
      for (final entry in (json['units'] as List?) ?? const [])
        if (entry is Map<String, dynamic>) ?_unitFrom(entry, id),
    ];
    if (units.isEmpty) return null;
    return UnitFamily(
      id: id,
      code: code,
      name: _text(json['name']),
      dimension: _text(json['dimension']).isNotEmpty
          ? _text(json['dimension'])
          : code,
      integralOnly: _flag(json['integral_only'] ?? json['integralOnly']),
      units: units,
    );
  }

  Unit? _unitFrom(Map<String, dynamic> json, int familyId) {
    final id = (json['id'] as num?)?.toInt();
    if (id == null) return null;
    final symbol = _text(json['symbol']);
    final name = _text(json['name']);
    // The `units` table has `precision`, not `max_decimals` — the Node
    // formatter reads both spellings for the same reason, and 4 is its default.
    final decimals = (json['max_decimals'] ?? json['maxDecimals'] ?? json['precision']) as num?;
    return Unit(
      id: id,
      familyId: (json['unit_group_id'] as num?)?.toInt() ?? familyId,
      code: _text(json['code']).isNotEmpty ? _text(json['code']) : symbol,
      label: name,
      symbol: symbol.isNotEmpty ? symbol : name,
      // A unit with no factor is 1, not 0: a 0 would make every quantity in
      // the family divide by zero, and an un-migrated row genuinely is 1:1
      // with itself.
      factorToBase: (json['factor_to_base'] ?? json['factorToBase']) is num
          ? ((json['factor_to_base'] ?? json['factorToBase']) as num).toInt()
          : 1,
      isBase: _flag(json['is_base'] ?? json['isBase']),
      onLadder: _flag(json['on_ladder'] ?? json['onLadder'], fallback: true),
      maxDecimals: decimals?.toInt() ?? 4,
      uqc: _text(json['uqc']).isNotEmpty ? _text(json['uqc']) : null,
    );
  }

  static String _text(Object? value) => (value as String?)?.trim() ?? '';

  /// SQLite has no boolean, so these arrive as 0/1.
  static bool _flag(Object? value, {bool fallback = false}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value.toInt() == 1;
    final text = value.toString().trim().toLowerCase();
    if (text.isEmpty) return fallback;
    return text == '1' || text == 'true';
  }

  Future<Map<String, dynamic>> _get(String path) async {
    late final http.Response response;
    try {
      response = await _client.get(Uri.parse('$baseUrl$path'));
    } catch (error) {
      throw UnitFamilyException('Could not reach the server. ($error)');
    }
    Map<String, dynamic>? payload;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) payload = decoded;
    } catch (_) {
      // No readable body — handled below.
    }
    final message = (payload?['error'] as String?)?.trim();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw UnitFamilyException(
        message?.isNotEmpty == true
            ? message!
            : 'The server refused that (${response.statusCode}).',
      );
    }
    if (payload == null || payload['success'] != true) {
      throw UnitFamilyException(
        message?.isNotEmpty == true
            ? message!
            : 'The server sent an answer we could not read.',
      );
    }
    return payload;
  }

  /// Demo builds get the seeded shape, so a quantity still formats with no
  /// backend. These factors are the ones in backend/modules/units/service.js;
  /// they are here because a mock has to say something, not as a second source
  /// of truth — anything real reads the endpoint.
  static final List<UnitFamily> _mockFamilies = [
    const UnitFamily(
      id: 1,
      code: 'count',
      name: 'Count',
      dimension: 'count',
      integralOnly: true,
      units: [
        Unit(id: 1, familyId: 1, code: 'Pc', label: 'Piece', symbol: 'Pc', factorToBase: 1, isBase: true, uqc: 'NOS'),
        Unit(id: 2, familyId: 1, code: 'doz', label: 'Dozen', symbol: 'doz', factorToBase: 12, uqc: 'DOZ'),
        Unit(id: 3, familyId: 1, code: 'gro', label: 'Gross', symbol: 'gro', factorToBase: 144, uqc: 'GRS'),
      ],
    ),
    const UnitFamily(
      id: 2,
      code: 'mass',
      name: 'Mass',
      dimension: 'mass',
      units: [
        Unit(id: 4, familyId: 2, code: 'mg', label: 'Milligram', symbol: 'mg', factorToBase: 1, isBase: true, onLadder: false, uqc: 'MGM'),
        Unit(id: 5, familyId: 2, code: 'g', label: 'Gram', symbol: 'g', factorToBase: 1000, uqc: 'GMS'),
        Unit(id: 6, familyId: 2, code: 'kg', label: 'Kilogram', symbol: 'kg', factorToBase: 1000000, uqc: 'KGS'),
        Unit(id: 7, familyId: 2, code: 'qtl', label: 'Quintal', symbol: 'qtl', factorToBase: 100000000, uqc: 'QTL'),
        Unit(id: 8, familyId: 2, code: 't', label: 'Tonne', symbol: 't', factorToBase: 1000000000, uqc: 'TON'),
      ],
    ),
  ];
}

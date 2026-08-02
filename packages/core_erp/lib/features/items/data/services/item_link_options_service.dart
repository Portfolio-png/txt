import 'dart:convert';

import 'package:http/http.dart' as http;

/// A machine or die the item editor can link to, reduced to what the picker
/// needs.
class ItemLinkOption {
  const ItemLinkOption({required this.id, required this.label, this.subtitle = ''});

  final String id;
  final String label;
  final String subtitle;
}

/// Supplies the machine and die lists to the item editor.
///
/// Machines and dies are owned by the host app, not by `core_erp`, so the
/// editor reads the two list endpoints directly instead of depending on the
/// app-layer providers (which would invert the package dependency).
class ItemLinkOptionsService {
  ItemLinkOptionsService({
    http.Client? client,
    required this.baseUrl,
    this.useMockResponses = false,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final bool useMockResponses;

  Future<List<ItemLinkOption>> fetchMachines() async {
    if (useMockResponses) {
      return const [
        ItemLinkOption(id: '1', label: 'Press A', subtitle: 'MC-001'),
        ItemLinkOption(id: '2', label: 'Press B', subtitle: 'MC-002'),
      ];
    }
    final rows = await _fetchList('/api/machines', 'machines');
    return rows.map((row) {
      final name = (row['name'] as String? ?? '').trim();
      final assetId = (row['assetId'] as String? ?? '').trim();
      return ItemLinkOption(
        id: row['id']?.toString() ?? '',
        label: name.isNotEmpty ? name : assetId,
        subtitle: assetId,
      );
    }).where((option) => option.id.isNotEmpty).toList(growable: false);
  }

  Future<List<ItemLinkOption>> fetchDies() async {
    if (useMockResponses) {
      return const [
        ItemLinkOption(id: '1', label: 'DIE-100'),
        ItemLinkOption(id: '2', label: 'DIE-200'),
      ];
    }
    final rows = await _fetchList('/api/dies', 'dies');
    return rows.map((row) {
      final toolCode = (row['toolCode'] as String? ?? '').trim();
      final id = row['id']?.toString() ?? '';
      return ItemLinkOption(
        id: id,
        label: toolCode.isNotEmpty ? toolCode : 'Die $id',
      );
    }).where((option) => option.id.isNotEmpty).toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> _fetchList(
    String path,
    String collectionKey,
  ) async {
    final response = await _client.get(Uri.parse('$baseUrl$path'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load $collectionKey.');
    }
    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic> || payload['success'] != true) {
      throw Exception('Failed to load $collectionKey.');
    }
    return (payload[collectionKey] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }
}

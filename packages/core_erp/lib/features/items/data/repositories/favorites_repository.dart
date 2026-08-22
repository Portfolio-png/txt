import 'dart:convert';
import 'package:http/http.dart' as http;

class FavoritesRepository {
  FavoritesRepository({required http.Client client, required this.baseUrl})
    : _client = client;

  final http.Client _client;
  final String baseUrl;

  Future<List<Map<String, dynamic>>> getFavorites() async {
    final uri = Uri.parse('$baseUrl/api/favorites');
    final response = await _client.get(uri);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      if (json['success'] == true && json['favorites'] != null) {
        return List<Map<String, dynamic>>.from(json['favorites']);
      }
    }
    return [];
  }

  Future<bool> addFavorite({
    required int itemId,
    required int variationLeafNodeId,
    required String variationPathLabel,
    required List<int> variationPathNodeIds,
    required Map<int, String> customVariationValues,
  }) async {
    final uri = Uri.parse('$baseUrl/api/favorites');
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'itemId': itemId,
        'variationLeafNodeId': variationLeafNodeId,
        'variationPathLabel': variationPathLabel,
        'variationPathNodeIds': variationPathNodeIds,
        'customVariationValues': customVariationValues,
      }),
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return json['success'] == true;
    }
    return false;
  }

  Future<bool> removeFavorite(int itemId, int variationLeafNodeId) async {
    final uri = Uri.parse(
      '$baseUrl/api/favorites/$itemId/$variationLeafNodeId',
    );
    final response = await _client.delete(uri);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return json['success'] == true;
    }
    return false;
  }
}

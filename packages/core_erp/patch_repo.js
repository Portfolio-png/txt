const fs = require('fs');
const path = require('path');
const file = path.join(__dirname, 'lib/features/items/data/repositories/api_item_repository.dart');

let content = fs.readFileSync(file, 'utf8');

const newMethod = `
  Future<ItemDefinition> updateShortCode(int id, String shortCode) async {
    if (_useMockData) {
      final index = _mockItems.indexWhere((item) => item.id == id);
      if (index == -1) {
        throw ItemApiException('Item not found.');
      }
      final current = _mockItems[index];
      final updated = ItemDefinition(
        id: current.id,
        name: current.name,
        alias: current.alias,
        shortCode: shortCode,
        displayName: current.displayName,
        quantity: current.quantity,
        groupId: current.groupId,
        unitId: current.unitId,
        unitConversions: current.unitConversions,
        namingFormat: current.namingFormat,
        isArchived: current.isArchived,
        usageCount: current.usageCount,
        createdAt: current.createdAt,
        updatedAt: DateTime.now(),
        variationTree: current.variationTree,
        propertySchema: current.propertySchema,
        defaultPipelineId: current.defaultPipelineId,
        defaultPipelineName: current.defaultPipelineName,
        baseItemId: current.baseItemId,
        photoUrl: current.photoUrl,
        combinationGroupIds: current.combinationGroupIds,
      );
      _mockItems[index] = updated;
      return updated;
    }

    try {
      final response = await _apiService.put(
        '/api/items/$id/short-code',
        {'shortCode': shortCode},
      );
      final payload = response.data as Map<String, dynamic>;
      if (payload['success'] == true && payload['item'] != null) {
        final parsed = ItemResponse.fromJson(payload);
        return parsed.item.toDomain();
      } else {
        throw ItemApiException(payload['error']?.toString() ?? 'Failed to update short code');
      }
    } catch (e) {
      if (e is ItemApiException) rethrow;
      throw ItemApiException('Network error: $e');
    }
  }
`;

if (!content.includes('updateShortCode(')) {
  content = content.replace("Future<void> deleteItem(int id) async {", newMethod + "\n  Future<void> deleteItem(int id) async {");
  fs.writeFileSync(file, content);
  console.log('Added updateShortCode to repository');
}

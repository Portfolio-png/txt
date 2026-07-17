const fs = require('fs');
const path = require('path');
const file = path.join(__dirname, 'lib/features/items/presentation/providers/items_provider.dart');

let content = fs.readFileSync(file, 'utf8');

const newMethod = `
  Future<void> updateShortCode(int id, String shortCode) async {
    try {
      final updatedItem = await _itemRepository.updateShortCode(id, shortCode);
      final index = _items.indexWhere((i) => i.id == id);
      if (index != -1) {
        _items[index] = updatedItem;
        notifyListeners();
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }
`;

if (!content.includes('updateShortCode(')) {
  content = content.replace("Future<void> archiveItem(int id) async {", newMethod + "\n  Future<void> archiveItem(int id) async {");
  fs.writeFileSync(file, content);
  console.log('Added updateShortCode to provider');
}

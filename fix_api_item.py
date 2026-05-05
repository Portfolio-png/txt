import sys

with open('lib/features/items/data/repositories/api_item_repository.dart', 'r') as f:
    content = f.read()

content = content.replace('ItemVariationNodeDefinition(', 'ItemVariationNodeDefinition(code: \'\',')
content = content.replace('ItemDefinition(', 'ItemDefinition(namingFormat: const <String>[],')

with open('lib/features/items/data/repositories/api_item_repository.dart', 'w') as f:
    f.write(content)

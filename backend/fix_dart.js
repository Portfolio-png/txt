const fs = require('fs');
let content = fs.readFileSync('f:/Rutu/txt/packages/core_erp/lib/features/delivery_challans/presentation/screens/delivery_challan_screen.dart', 'utf8');

const oldChunk1 = `                                  return await context.read<ItemsProvider>().appendVariationValue(
                                    itemId: item.id,
                                    propertyNodeId: propertyNodeId,
                                    valueName: valueName,
                                  );
                                },
                              ),
                            ),
                          );`;

const newChunk1 = `                                  return await context.read<ItemsProvider>().appendVariationValue(
                                    itemId: item.id,
                                    propertyNodeId: propertyNodeId,
                                    valueName: valueName,
                                  );
                                },
                              ),
                            ),
                            ),
                          );`;

let occurrences = 0;
while (content.includes(oldChunk1)) {
  content = content.replace(oldChunk1, newChunk1);
  occurrences++;
}

fs.writeFileSync('f:/Rutu/txt/packages/core_erp/lib/features/delivery_challans/presentation/screens/delivery_challan_screen.dart', content, 'utf8');
console.log(`Replaced ${occurrences} occurrences.`);

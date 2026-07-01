const fs = require('fs');
let content = fs.readFileSync('f:/Rutu/txt/packages/core_erp/lib/features/delivery_challans/presentation/screens/delivery_challan_screen.dart', 'utf8');

const targetStr = `                                    valueName: valueName,
                                  );
                                },
                              ),
                            ),
                          );`;
const replacementStr = `                                    valueName: valueName,
                                  );
                                },
                              ),
                            ),
                            ),
                          );`;
                          
const parts = content.split(targetStr);
if (parts.length > 1) {
  content = parts.join(replacementStr);
  fs.writeFileSync('f:/Rutu/txt/packages/core_erp/lib/features/delivery_challans/presentation/screens/delivery_challan_screen.dart', content, 'utf8');
  console.log(`Replaced ${parts.length - 1} occurrences.`);
} else {
  console.log("Not found.");
}

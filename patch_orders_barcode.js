const fs = require('fs');

const path = 'packages/core_erp/lib/features/orders/presentation/screens/orders_screen.dart';
let code = fs.readFileSync(path, 'utf8');

// Also need to add import for SmallBarcodePreview if not present
if (!code.includes('package:core_erp/core/widgets/material_barcode_toolkit.dart')) {
  code = code.replace(
    "import 'package:flutter/material.dart';",
    "import 'package:flutter/material.dart';\nimport 'package:core_erp/core/widgets/material_barcode_toolkit.dart';"
  );
}

const oldText = `                      Expanded(
                        child: Text(
                          item.barcode,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),`;
const newText = `                      Expanded(
                        child: SmallBarcodePreview(value: item.barcode),
                      ),`;

code = code.replace(oldText, newText);

fs.writeFileSync(path, code);
console.log('Patched orders_screen.dart');

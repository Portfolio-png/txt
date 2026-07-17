const fs = require('fs');
let code = fs.readFileSync('apps/challan_mobile/lib/screens/home_screen.dart', 'utf8');
code = "import 'package:core_erp/core/widgets/app_settings_dialog.dart';\n" + code;
fs.writeFileSync('apps/challan_mobile/lib/screens/home_screen.dart', code);
console.log('Added import to home_screen.dart');

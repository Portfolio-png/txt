const fs = require('fs');
let code = fs.readFileSync('apps/challans_only/lib/shell/app_sidebar.dart', 'utf8');
code = code.replace(/_SettingsPreferencesDialog\(\)/g, 'AppSettingsDialog()');
fs.writeFileSync('apps/challans_only/lib/shell/app_sidebar.dart', code);
console.log('Fixed app_sidebar.dart callers');

const fs = require('fs');
const sidebarContent = fs.readFileSync('apps/challans_only/lib/shell/app_sidebar.dart', 'utf8');

const startIndex = sidebarContent.indexOf('class _SettingsPreferencesDialog extends StatefulWidget {');
const endIndex = sidebarContent.indexOf('}', sidebarContent.lastIndexOf('Widget build(BuildContext context)')) + 1;
// Wait, the build method might have nested braces. It's safer to just slice from line 599 to 851.

const lines = sidebarContent.split('\n');
const settingsCode = lines.slice(598, 852).join('\n').replace(/_SettingsPreferencesDialog/g, 'AppSettingsDialog');

const newFileContent = `import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:core_erp/core/widgets/app_toast.dart';
import 'package:core_erp/app/preferences/preferences_provider.dart';
import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/features/auth/presentation/providers/auth_provider.dart';
import 'package:core_erp/features/clients/presentation/providers/clients_provider.dart';
import 'package:core_erp/features/delivery_challans/presentation/providers/delivery_challan_provider.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/features/orders/presentation/providers/orders_provider.dart';
import 'package:core_erp/features/units/presentation/providers/units_provider.dart';
import 'package:core_erp/features/vendors/presentation/providers/vendors_provider.dart';

${settingsCode}
`;

fs.writeFileSync('packages/core_erp/lib/core/widgets/app_settings_dialog.dart', newFileContent);

// Now patch app_sidebar.dart to import and use AppSettingsDialog
const sidebarLines = [...lines.slice(0, 598), ...lines.slice(852)];
let newSidebarContent = sidebarLines.join('\n');
newSidebarContent = "import 'package:core_erp/core/widgets/app_settings_dialog.dart';\n" + newSidebarContent;

fs.writeFileSync('apps/challans_only/lib/shell/app_sidebar.dart', newSidebarContent);
console.log('Moved SettingsDialog successfully');

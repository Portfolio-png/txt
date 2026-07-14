const fs = require('fs');

let content = fs.readFileSync('packages/core_erp/lib/features/auth/presentation/screens/user_management_screen.dart', 'utf8');

content = content.replace("import '../../clients/presentation/providers/clients_provider.dart';", "import '../../../clients/presentation/providers/clients_provider.dart';");
content = content.replace("import '../../clients/domain/client_definition.dart';", "import '../../../clients/domain/client_definition.dart';");

fs.writeFileSync('packages/core_erp/lib/features/auth/presentation/screens/user_management_screen.dart', content);
console.log("Fixed imports");

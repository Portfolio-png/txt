const fs = require('fs');

let content = fs.readFileSync('packages/core_erp/lib/features/auth/presentation/providers/auth_provider.dart', 'utf8');

// 1. Update createUser signature
const createUserTarget = "required String password,\n    required bool admin,\n  }) async {";
const createUserReplacement = "required String password,\n    required bool admin,\n    int? clientId,\n  }) async {";
content = content.replace(createUserTarget, createUserReplacement);

// 2. Update api call
const apiTarget = "password: password,\n        admin: admin,\n      );";
const apiReplacement = "password: password,\n        admin: admin,\n        clientId: clientId,\n      );";
content = content.replace(apiTarget, apiReplacement);

fs.writeFileSync('packages/core_erp/lib/features/auth/presentation/providers/auth_provider.dart', content);
console.log("Patched auth_provider.dart");


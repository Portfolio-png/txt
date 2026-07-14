const fs = require('fs');

let content = fs.readFileSync('packages/core_erp/lib/features/auth/data/auth_api.dart', 'utf8');

// 1. Update createUser signature
const createUserTarget = "required String password,\n    required bool admin,\n  }) async {";
const createUserReplacement = "required String password,\n    required bool admin,\n    int? clientId,\n  }) async {";
content = content.replace(createUserTarget, createUserReplacement);

// 2. Update body map
const bodyTarget = "'role': admin ? 'admin' : 'user',\n      }),\n    );";
const bodyReplacement = "'role': admin ? 'admin' : 'user',\n        if (clientId != null) 'clientId': clientId,\n      }),\n    );";
content = content.replace(bodyTarget, bodyReplacement);

fs.writeFileSync('packages/core_erp/lib/features/auth/data/auth_api.dart', content);
console.log("Patched auth_api.dart");


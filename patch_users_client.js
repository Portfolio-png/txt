const fs = require('fs');

let content = fs.readFileSync('backend/server.js', 'utf8');

// 1. Add ensureColumnExists for client_id
const ensureLineTarget = "await ensureColumnExists('users', 'mobile_pin', \"TEXT\");";
const ensureLineReplacement = "await ensureColumnExists('users', 'mobile_pin', \"TEXT\");\n  await ensureColumnExists('users', 'client_id', \"INTEGER REFERENCES clients(id)\");";
content = content.replace(ensureLineTarget, ensureLineReplacement);

// 2. Add client_id & client_name to safeUserDto
const dtoTarget = "createdByUserId: row.created_by_user_id || null,";
const dtoReplacement = "createdByUserId: row.created_by_user_id || null,\n    clientId: row.client_id || null,\n    clientName: row.client_name || null,";
content = content.replace(dtoTarget, dtoReplacement);

// 3. Update createUserAccount to accept clientId
const createUserTarget = "createdByUserId = null,\n}) {";
const createUserReplacement = "createdByUserId = null,\n  clientId = null,\n}) {";
content = content.replace(createUserTarget, createUserReplacement);

// 4. Update the INSERT for users
const insertFieldsTarget = "name, email, password_hash, role, is_active, created_by_user_id, created_at, updated_at, mobile_pin";
const insertFieldsReplacement = "name, email, password_hash, role, is_active, created_by_user_id, created_at, updated_at, mobile_pin, client_id";
content = content.replace(insertFieldsTarget, insertFieldsReplacement);

const insertValuesTarget = "?, ?, ?, ?, ?, ?, ?, ?, ?";
const insertValuesReplacement = "?, ?, ?, ?, ?, ?, ?, ?, ?, ?";
content = content.replace(insertValuesTarget, insertValuesReplacement);

const insertArgsTarget = "mobilePin,\n    ]);";
const insertArgsReplacement = "mobilePin,\n      clientId,\n    ]);";
content = content.replace(insertArgsTarget, insertArgsReplacement);

// 5. Update /api/users GET query to join clients
const selectTarget = "SELECT *\n      FROM users\n      ${whereSql}\n      ORDER BY role ASC, name ASC";
const selectReplacement = "SELECT users.*, clients.name as client_name\n      FROM users\n      LEFT JOIN clients ON users.client_id = clients.id\n      ${whereSql}\n      ORDER BY users.role ASC, users.name ASC";
content = content.replace(selectTarget, selectReplacement);

// Need to prefix whereClauses with users.
content = content.replace(/whereClauses\.push\('\(LOWER\(name\)/g, "whereClauses.push('(LOWER(users.name)");
content = content.replace(/whereClauses\.push\('role = \?'\)/g, "whereClauses.push('users.role = ?')");
content = content.replace(/whereClauses\.push\('is_active = \?'\)/g, "whereClauses.push('users.is_active = ?')");
content = content.replace(/whereClauses\.push\('\(role = \? OR id = \?\)'\)/g, "whereClauses.push('(users.role = ? OR users.id = ?)')");

// 6. Update POST /api/users to pass clientId
const postTarget = "password,\n      role,\n      createdByUserId: req.user.id,\n    });";
const postReplacement = "password,\n      role,\n      createdByUserId: req.user.id,\n      clientId: req.body?.clientId ? Number(req.body.clientId) : null,\n    });";
content = content.replace(postTarget, postReplacement);

fs.writeFileSync('backend/server.js', content);
console.log("Patched server.js");


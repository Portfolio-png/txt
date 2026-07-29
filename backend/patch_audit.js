const fs = require('fs');
let code = fs.readFileSync('backend/server.js', 'utf8');

const tableCode = `
  await run(\`
    CREATE TABLE IF NOT EXISTS global_audit_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      actor_user_id INTEGER REFERENCES users(id),
      actor_name TEXT,
      actor_role TEXT,
      action TEXT NOT NULL,
      entity_type TEXT NOT NULL,
      entity_id TEXT,
      details_json TEXT DEFAULT '{}',
      ip_address TEXT,
      created_at TEXT NOT NULL
    )
  \`);
  await run('CREATE INDEX IF NOT EXISTS idx_global_audit_created ON global_audit_logs(created_at DESC)');
`;

if (!code.includes('CREATE TABLE IF NOT EXISTS global_audit_logs')) {
  code = code.replace('async function initDb() {', 'async function initDb() {\n' + tableCode);
}

code = code.replace(/employee_salary_structures WHERE user_id/g, 'employee_salary_structures WHERE employee_id');
code = code.replace(/employee_salary_structures \(user_id/g, 'employee_salary_structures (employee_id');

fs.writeFileSync('backend/server.js', code);
console.log('Added global_audit_logs to initDb and fixed user_id to employee_id');

const fs = require('fs');
let code = fs.readFileSync('backend/server.js', 'utf8');

const tableCode = `
  await run(\`
    CREATE TABLE IF NOT EXISTS changelog (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      table_name TEXT NOT NULL,
      record_id INTEGER NOT NULL,
      event_type TEXT NOT NULL,
      timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
    )
  \`);
`;

if (!code.includes('CREATE TABLE IF NOT EXISTS changelog')) {
  code = code.replace('async function initDb() {', 'async function initDb() {\n' + tableCode);
  fs.writeFileSync('backend/server.js', code);
  console.log('Added changelog to initDb');
} else {
  console.log('changelog already exists');
}

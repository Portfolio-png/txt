const fs = require('fs');
const path = require('path');

const dbPath = String(process.env.DB_PATH || path.join(__dirname, '..', 'paper.db'));
const backupFile =
  String(process.env.PAPER_RESTORE_FILE || '').trim() ||
  process.argv[2] ||
  path.join(__dirname, '..', 'backups', 'paper-latest.db');

function timestamp() {
  return new Date().toISOString().replace(/[:.]/g, '-');
}

async function main() {
  if (!fs.existsSync(backupFile)) {
    throw new Error(`Backup file not found at ${backupFile}`);
  }
  fs.mkdirSync(path.dirname(dbPath), { recursive: true });
  if (fs.existsSync(dbPath)) {
    const rollbackCopy = `${dbPath}.pre-restore-${timestamp()}`;
    fs.copyFileSync(dbPath, rollbackCopy);
    console.log(`Current DB snapshot saved at ${rollbackCopy}`);
  }
  fs.copyFileSync(backupFile, dbPath);
  console.log(`Restored ${backupFile} -> ${dbPath}`);
}

main().catch((error) => {
  console.error('Restore failed:', error.message);
  process.exit(1);
});

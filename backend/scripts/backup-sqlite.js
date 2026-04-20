const fs = require('fs');
const path = require('path');

const dbPath = String(process.env.DB_PATH || path.join(__dirname, '..', 'paper.db'));
const backupDir = String(process.env.PAPER_BACKUP_DIR || path.join(__dirname, '..', 'backups'));

function timestamp() {
  return new Date().toISOString().replace(/[:.]/g, '-');
}

async function main() {
  if (!fs.existsSync(dbPath)) {
    throw new Error(`Database file not found at ${dbPath}`);
  }
  fs.mkdirSync(backupDir, { recursive: true });
  const datedBackup = path.join(backupDir, `paper-${timestamp()}.db`);
  const latestBackup = path.join(backupDir, 'paper-latest.db');
  fs.copyFileSync(dbPath, datedBackup);
  fs.copyFileSync(dbPath, latestBackup);
  console.log(`Created backups:\n- ${datedBackup}\n- ${latestBackup}`);
}

main().catch((error) => {
  console.error('Backup failed:', error.message);
  process.exit(1);
});

require('dotenv').config();
const fs = require('fs');
const path = require('path');
const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');

const dbPath = String(process.env.DB_PATH || path.join(__dirname, '..', 'data', 'paper.db'));
const backupDir = String(process.env.PAPER_BACKUP_DIR || path.join(__dirname, '..', 'backups'));
const bucketName = process.env.PAPER_S3_BUCKET_NAME;

function timestamp() {
  return new Date().toISOString().replace(/[:.]/g, '-');
}

async function uploadToS3(filePath, fileName) {
  if (!bucketName) {
    console.log('PAPER_S3_BUCKET_NAME is not set. Skipping S3 upload.');
    return;
  }

  const s3Config = {
    region: process.env.PAPER_S3_REGION || 'us-east-1',
  };

  // If local overrides exist
  if (process.env.S3_ENDPOINT) {
    s3Config.endpoint = process.env.S3_ENDPOINT;
    s3Config.forcePathStyle = process.env.S3_FORCE_PATH_STYLE === 'true';
  }

  const s3Client = new S3Client(s3Config);
  const fileStream = fs.createReadStream(filePath);

  const command = new PutObjectCommand({
    Bucket: bucketName,
    Key: `backups/${fileName}`,
    Body: fileStream,
  });

  try {
    await s3Client.send(command);
    console.log(`Successfully uploaded backup to S3: s3://${bucketName}/backups/${fileName}`);
  } catch (error) {
    console.error(`Failed to upload to S3:`, error);
    throw error;
  }
}

async function main() {
  if (!fs.existsSync(dbPath)) {
    throw new Error(`Database file not found at ${dbPath}`);
  }
  
  fs.mkdirSync(backupDir, { recursive: true });
  
  const ts = timestamp();
  const datedFileName = `paper-${ts}.db`;
  const datedBackup = path.join(backupDir, datedFileName);
  const latestBackup = path.join(backupDir, 'paper-latest.db');
  
  fs.copyFileSync(dbPath, datedBackup);
  fs.copyFileSync(dbPath, latestBackup);
  
  console.log(`Created local backups:\n- ${datedBackup}\n- ${latestBackup}`);
  
  await uploadToS3(datedBackup, datedFileName);
  await uploadToS3(latestBackup, 'paper-latest.db');
}

main().catch((error) => {
  console.error('Backup failed:', error.message);
  process.exit(1);
});

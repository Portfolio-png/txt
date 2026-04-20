const backend = require('../server.js');

const authEventRetentionDays = Number(
  process.env.PAPER_AUTH_EVENTS_RETENTION_DAYS || 365,
);
const revokedSessionRetentionDays = Number(
  process.env.PAPER_REVOKED_SESSIONS_RETENTION_DAYS || 90,
);

async function main() {
  const authEventsResult = await backend.run(
    `
    DELETE FROM auth_events
    WHERE datetime(created_at) < datetime('now', ?)
    `,
    [`-${Math.max(1, authEventRetentionDays)} day`],
  );
  const revokedSessionsResult = await backend.run(
    `
    DELETE FROM auth_sessions
    WHERE revoked_at IS NOT NULL
      AND datetime(revoked_at) < datetime('now', ?)
    `,
    [`-${Math.max(1, revokedSessionRetentionDays)} day`],
  );
  console.log(
    `Security cleanup complete. auth_events=${authEventsResult.changes || 0}, revoked_sessions=${
      revokedSessionsResult.changes || 0
    }`,
  );
}

main()
  .catch((error) => {
    console.error('Security cleanup failed:', error.message);
    process.exit(1);
  })
  .finally(async () => {
    await backend.closeDb();
  });

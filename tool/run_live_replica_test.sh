#!/usr/bin/env bash
# Drives the local replica against the REAL backend.
#
# Every other replica test uses a fake server, which proves the engine's logic
# and nothing about whether the endpoints exist, the envelopes match, or the
# field names are what the extractors expect. Those mistakes do not throw — they
# hydrate an empty replica and the app looks like a workspace with no data.
#
# Boots the server on a copy of backend/paper.db so the real workspace is never
# written to, logs in, and hands the port and token to the Dart test.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'kill "${SERVER_PID:-0}" 2>/dev/null || true; rm -rf "$WORK"' EXIT

cp backend/paper.db "$WORK/live.db"

HASH="$(node -e "
const c=require('crypto');const s=require('fs').readFileSync('backend/server.js','utf8');
const IT=+s.match(/PASSWORD_ITERATIONS = (\d+)/)[1], KL=+s.match(/PASSWORD_KEY_LENGTH = (\d+)/)[1];
const salt=c.randomBytes(16).toString('hex');
console.log('pbkdf2\$'+IT+'\$'+salt+'\$'+c.pbkdf2Sync('LiveProbe1234', salt, IT, KL, 'sha256').toString('hex'));
")"
sqlite3 "$WORK/live.db" "UPDATE users SET password_hash='$HASH', is_active=1, failed_login_attempts=0, lockout_until=NULL WHERE email='super@paper.local';"

# A free port, chosen by the OS rather than hoped for. A fixed one collides with
# a server left over from an interrupted run, and the failure (EADDRINUSE) looks
# nothing like the thing being tested.
PORT="${PAPER_LIVE_PORT:-$(node -e "
const net=require('net');const s=net.createServer();
s.listen(0,'127.0.0.1',()=>{const p=s.address().port;s.close(()=>console.log(p));});
")}"
(cd backend && DB_PATH="$WORK/live.db" PORT="$PORT" SEED_DEMO_DATA_ON_BOOT=false node server.js > "$WORK/server.log" 2>&1) &
SERVER_PID=$!

for _ in $(seq 1 60); do
  if grep -q "Database schema ready" "$WORK/server.log" 2>/dev/null; then break; fi
  sleep 1
done
grep -q "Database schema ready" "$WORK/server.log" || { echo "server did not start:"; tail -20 "$WORK/server.log"; exit 1; }

TOKEN="$(curl -s -X POST "http://127.0.0.1:$PORT/api/auth/login" \
  -H 'Content-Type: application/json' \
  -d '{"email":"super@paper.local","password":"LiveProbe1234"}' \
  | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{const j=JSON.parse(d);if(!j.token){console.error(d);process.exit(1)}console.log(j.token)})")"

flutter test packages/core_erp/test/replica_live_integration_test.dart \
  --dart-define=PAPER_LIVE_PORT="$PORT" \
  --dart-define=PAPER_LIVE_TOKEN="$TOKEN"

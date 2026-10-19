#!/usr/bin/env bash
#
# Drives the real app against a real backend and then checks the database.
#
# Everything else in this repo's tests fakes something: widget tests substitute
# providers, backend tests talk to temp databases with no UI. This is the only
# thing that starts the actual server, launches the actual macOS app, clicks
# through it, and then reads the rows back out of SQLite. The rows are the
# assertion that matters.
#
#   ./scripts/e2e-ui.sh              # harness proof, then the route journey
#   ./scripts/e2e-ui.sh app_boot     # just one file (by basename, no suffix)
#
# NEVER touches backend/paper.db. A throwaway database is created under
# $TMPDIR, seeded from scratch, and deleted on exit unless KEEP_DB=1.
#
# macOS only: the web build cannot compile (dart:io is imported unconditionally
# on the boot path), and there is no mobile device wired up here.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${PORT:-19080}"
BASE_URL="http://127.0.0.1:${PORT}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/paper-e2e-XXXXXX")"
DB="${WORK}/paper.db"
SERVER_PID=""

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
fail() { printf '\n\033[31mFAILED: %s\033[0m\n' "$*" >&2; exit 1; }

cleanup() {
  local code=$?
  if [[ -n "${SERVER_PID}" ]] && kill -0 "${SERVER_PID}" 2>/dev/null; then
    kill "${SERVER_PID}" 2>/dev/null || true
    wait "${SERVER_PID}" 2>/dev/null || true
  fi
  if [[ "${KEEP_DB:-0}" == "1" ]]; then
    printf '\nKept %s\n' "${WORK}"
  else
    rm -rf "${WORK}"
  fi
  exit "${code}"
}
trap cleanup EXIT INT TERM

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "macOS only — the app cannot build for web and no other device is set up here."
fi
command -v sqlite3 >/dev/null || fail "sqlite3 is needed to check what landed."

# --- 1. a database -----------------------------------------------------------
# Seeded, not empty, and not a copy of the dev database.
#
# Seeding is REQUIRED, not a convenience: migration 007 does
# `ALTER TABLE order_items`, but `order_items` is created by initDb, which runs
# AFTER migrate.js — so booting the server against an empty file leaves it at
# `dbReady: false` forever with `no such table: order_items`. reseed-demo-data
# calls initDb first, which creates the tables, so the migration then applies.
#
# And a FRESH database rather than a copy of backend/paper.db because `users`
# must be empty: that is the only condition under which
# bootstrapSuperAdminIfNeeded creates super@paper.local with the password the
# app's auto-login already sends. A copy has users whose passwords nobody knows.
say "Seeding a throwaway database at ${DB}"
( cd "${REPO}/backend" && DB_PATH="${DB}" node scripts/reseed-demo-data.js ) \
  >"${WORK}/seed.log" 2>&1 || { tail -20 "${WORK}/seed.log"; fail "seeding"; }
printf 'items=%s users=%s stages=%s\n' \
  "$(sqlite3 "${DB}" 'SELECT COUNT(*) FROM items;')" \
  "$(sqlite3 "${DB}" 'SELECT COUNT(*) FROM users;')" \
  "$(sqlite3 "${DB}" 'SELECT COUNT(*) FROM process_stages;')"

# --- 2. the server -----------------------------------------------------------
say "Starting the backend on ${BASE_URL}"
( cd "${REPO}" && PORT="${PORT}" DB_PATH="${DB}" node backend/server.js ) \
  >"${WORK}/server.log" 2>&1 &
SERVER_PID=$!

for _ in $(seq 1 60); do
  if curl -fsS -m 3 "${BASE_URL}/health" 2>/dev/null \
      | grep -q '"dbReady":true'; then
    break
  fi
  kill -0 "${SERVER_PID}" 2>/dev/null || { tail -30 "${WORK}/server.log"; fail "the server exited"; }
  sleep 1
done
curl -fsS -m 3 "${BASE_URL}/health" | grep -q '"dbReady":true' \
  || { tail -30 "${WORK}/server.log"; fail "the server never became ready"; }
echo "ready"

# --- 3. the app --------------------------------------------------------------
# One file at a time, on purpose: each integration test file boots the whole
# app, and running them together lets one teardown's in-flight HTTP land during
# the next boot.
TESTS=("${1:-}")
if [[ -z "${TESTS[0]}" ]]; then
  TESTS=(app_boot express_route)
fi

for name in "${TESTS[@]}"; do
  say "flutter test integration_test/${name}_test.dart -d macos"
  ( cd "${REPO}" && flutter test "integration_test/${name}_test.dart" -d macos \
      --dart-define=PAPER_API_BASE_URL="${BASE_URL}" \
      --dart-define=PAPER_SKIP_ACTIVATION=true ) \
    || fail "integration_test/${name}_test.dart"
done

# --- 4. what actually landed -------------------------------------------------
# Driving the UI is the point; rows in the database are the proof.
say "Checking the database"
ROUTES="$(sqlite3 "${DB}" "SELECT COUNT(*) FROM process_routes WHERE status='active';")"
if [[ "${ROUTES}" == "0" ]]; then
  echo "No active route was written."
  echo "(Expected if you ran only app_boot.)"
  [[ "${TESTS[0]}" == "app_boot" ]] && { say "OK — harness only"; exit 0; }
  fail "the route journey ran but wrote nothing"
fi

sqlite3 -noheader "${DB}" "
  SELECT 'route v' || r.version || ' ' || r.status
         || ' on ' || COALESCE(NULLIF(TRIM(i.display_name),''), i.name)
         || ' : ' || GROUP_CONCAT(s.seq || ':' || g.code, ' -> ')
    FROM process_routes r
    JOIN items i ON i.id = r.part_id
    JOIN process_route_steps s ON s.route_id = r.id
    JOIN process_stages g ON g.id = s.stage_id
   WHERE r.status = 'active'
   GROUP BY r.id;"

# seq must be contiguous from 1 — the rule the backend validator enforces.
BAD="$(sqlite3 "${DB}" "
  SELECT COUNT(*) FROM (
    SELECT r.id, COUNT(s.id) AS n, MIN(s.seq) AS lo, MAX(s.seq) AS hi
      FROM process_routes r JOIN process_route_steps s ON s.route_id = r.id
     GROUP BY r.id
  ) WHERE lo <> 1 OR hi <> n;")"
[[ "${BAD}" == "0" ]] || fail "a route has gaps in its step numbering"

# The write should have carried a sitting, the way everything in that window does.
SITTINGS="$(sqlite3 "${DB}" \
  "SELECT COUNT(DISTINCT sitting_id) FROM entity_activity_log WHERE sitting_id IS NOT NULL;")"
echo "sittings recorded: ${SITTINGS}"

say "OK — driven through the UI, and the rows are there"

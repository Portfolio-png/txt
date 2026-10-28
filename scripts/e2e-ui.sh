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
#   ./scripts/e2e-ui.sh              # harness proof, then the part+route journey
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
    # Give it a moment, then insist. A server that outlives its run holds the
    # port and its database, and the next run tests against the wrong one.
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 "${SERVER_PID}" 2>/dev/null || break
      sleep 0.2
    done
    kill -9 "${SERVER_PID}" 2>/dev/null || true
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
# Refuse to start if something already holds the port.
#
# Not a nicety: an orphaned server from an earlier run — the script's cleanup
# does not fire if the run is killed — keeps listening on ${PORT} with ITS
# database still open. The new server then fails to bind, the health check
# passes against the old one, and the whole journey runs against a stale
# database. That cost a confusing debugging round: a part "already existed" in
# a database this script had just created empty, because the app was talking to
# one from three days earlier.
if lsof -nP -iTCP:"${PORT}" -sTCP:LISTEN >/dev/null 2>&1; then
  lsof -nP -iTCP:"${PORT}" -sTCP:LISTEN | sed -n '1,5p' >&2
  fail "port ${PORT} is already in use — an earlier run's server is probably \
still up. Kill it, or set PORT= to something else."
fi

say "Starting the backend on ${BASE_URL}"
# `exec`, so the subshell is REPLACED by node and $! is node's own pid.
#
# Without it $! is the subshell, and cleanup killed the subshell while node
# carried on holding the port with its database open. That is how three
# orphaned servers accumulated here — one of them for three days — each making
# the next run bind nothing and silently test against a stale database.
# No S3 bucket, as on a dev machine: photos go to the local store, kept in
# this run's own folder and linked at this run's own address.
( cd "${REPO}" && exec env PORT="${PORT}" DB_PATH="${DB}" \
    PAPER_UPLOAD_DIR="${WORK}/uploads" PAPER_PUBLIC_URL="${BASE_URL}" \
    PAPER_S3_BUCKET_NAME= S3_BUCKET= node backend/server.js ) \
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
# The full journey's point is the data it leaves: keep the database to browse.
[[ "${TESTS[0]}" == "full_journey" ]] && KEEP_DB=1
if [[ -z "${TESTS[0]}" ]]; then
  TESTS=(app_boot sheet_route sheet_bulk sheet_photo)
fi

for name in "${TESTS[@]}"; do
  say "flutter test integration_test/${name}_test.dart -d macos"
  ( cd "${REPO}" && flutter test "integration_test/${name}_test.dart" -d macos \
      --dart-define=PAPER_API_BASE_URL="${BASE_URL}" \
      --dart-define=PAPER_SKIP_ACTIVATION=true ) 2>&1 | tee "${WORK}/${name}.log" \
    || fail "integration_test/${name}_test.dart"
done

# --- the full journey: how long each step took, and every row it wrote ------
if [[ "${TESTS[0]}" == "full_journey" ]]; then
  say "Step timings (from tap to the app confirming it)"
  grep -o 'JOURNEY step=[^ ]* ms=[0-9]*' "${WORK}/full_journey.log" \
    | sed -E 's/JOURNEY step=([^ ]*) ms=([0-9]*)/\2 \1/' \
    | awk '{ printf "  %7d ms  %s\n", $1, $2 }'
  grep -o 'JOURNEY total ms=[0-9]* part=[0-9]*' "${WORK}/full_journey.log" | sed 's/^/  /'

  say "What the run wrote (database kept: ${DB})"
  q() { printf '\n\033[1m%s\033[0m\n' "$1"; sqlite3 -header -column "${DB}" "$2"; }
  PART="SELECT id FROM items WHERE name LIKE 'E2E UI Patti%'"
  q "Part" "SELECT id, name, part_code, developed_for_kind AS deal, developed_for_client_id AS client,
              developed_for_quotation_amount AS quotation, photo_url <> '' AS has_photo
         FROM items WHERE id IN (${PART});"
  q "Alloy and thickness" "SELECT p.name AS property, v.name AS value
         FROM item_variation_nodes p JOIN item_variation_nodes v ON v.parent_node_id = p.id
        WHERE p.item_id IN (${PART}) AND p.parent_node_id IS NULL;"
  q "Company" "SELECT id, name, logo_url <> '' AS has_logo FROM clients WHERE name LIKE 'E2E UI Company%';"
  q "People" "SELECT id, name, designation, phone, email FROM party_contacts WHERE name LIKE 'E2E UI Ravi%';"
  q "People ticked on the deal" "SELECT item_id, contact_id FROM item_deal_contacts WHERE item_id IN (${PART});"
  q "Dies on the part" "SELECT d.id, d.tool_code, d.die_type, json_array_length(d.photo_urls) AS photos
         FROM item_dies l JOIN dies d ON d.id = l.die_id WHERE l.item_id IN (${PART});"
  q "Machines on the part" "SELECT m.id, m.asset_id, m.name, m.primary_photo_url <> '' AS has_photo
         FROM item_machines l JOIN machines m ON m.id = l.machine_id WHERE l.item_id IN (${PART});"
  q "Route" "SELECT r.version, r.status, GROUP_CONCAT(s.seq || ':' || g.code, ' -> ') AS steps
         FROM process_routes r JOIN process_route_steps s ON s.route_id = r.id
         JOIN process_stages g ON g.id = s.stage_id WHERE r.part_id IN (${PART}) GROUP BY r.id;"
  q "Raw sheet" "SELECT json_extract(pen_paper_baseline_json, '$.sheetWidthInches') AS width_in,
              json_extract(pen_paper_baseline_json, '$.sheetHeightInches') AS length_in,
              json_extract(pen_paper_baseline_json, '$.vendorName') AS vendor,
              json_extract(pen_paper_baseline_json, '$.stageReconciliations[0].inputKg') AS in_kg,
              json_extract(pen_paper_baseline_json, '$.stageReconciliations[0].outputKg') AS out_kg,
              json_extract(pen_paper_baseline_json, '$.stageReconciliations[0].outputPieces') AS pieces
         FROM items WHERE id IN (${PART});"
  q "Photos" "SELECT id, entity_type, entity_id, status, is_primary, size_bytes FROM uploaded_assets ORDER BY id;"
  printf '\nBrowse it: sqlite3 %s\n' "${DB}"
  say "OK — full journey"
  exit 0
fi

# --- 4. what actually landed -------------------------------------------------
# Driving the UI is the point; rows in the database are the proof.
say "Checking the database"

# Bulk entry: three rows typed in one sitting, and Save pressed twice.
#
# The count is the whole assertion. The batching save wrote rows to the server
# and then reported that nothing had been saved, so a second press filed them
# again — six parts from three rows, or a sheet that could never be saved at
# all. Rows commit one at a time now and a saved row that has not been touched
# is skipped, so three rows must be three parts however many times Save is hit.
BULK="$(sqlite3 "${DB}" "SELECT COUNT(*) FROM items WHERE name LIKE 'E2E Bulk%';")"
if [[ "${BULK}" != "0" ]]; then
  echo "bulk parts written: ${BULK}"
  [[ "${BULK}" == "3" ]] || fail "three rows produced ${BULK} parts"

  # And no two parts may share a code within a group — the unique index the
  # server enforces, checked here because the sheet now lets the server stamp
  # every code rather than guessing one per row.
  DUPES="$(sqlite3 "${DB}" "
    SELECT COUNT(*) FROM (
      SELECT group_id, part_code FROM items
       WHERE part_code IS NOT NULL AND TRIM(part_code) <> ''
       GROUP BY group_id, part_code HAVING COUNT(*) > 1
    );")"
  [[ "${DUPES}" == "0" ]] || fail "two parts share a code within one group"

  sqlite3 -noheader "${DB}" "
    SELECT '  ' || name || '  ' || COALESCE(NULLIF(part_code,''),'(unstamped)')
      FROM items WHERE name LIKE 'E2E Bulk%' ORDER BY id;"
fi
# A part's photo, uploaded from its row: one asset row, and the file on disk.
PHOTOS="$(sqlite3 "${DB}" "
  SELECT COUNT(*) FROM uploaded_assets a JOIN items i ON i.id = a.entity_id
   WHERE a.entity_type = 'item' AND a.status = 'uploaded'
     AND i.name = 'E2E Photo Part';")"
if [[ "${PHOTOS}" != "0" ]]; then
  echo "part photos written: ${PHOTOS}"
  [[ "${PHOTOS}" == "1" ]] || fail "one upload made ${PHOTOS} photos"
  KEY="$(sqlite3 "${DB}" "
    SELECT a.object_key FROM uploaded_assets a JOIN items i ON i.id = a.entity_id
     WHERE a.entity_type = 'item' AND i.name = 'E2E Photo Part' LIMIT 1;")"
  [[ -s "${WORK}/uploads/${KEY}" ]] || fail "the photo's file is not in the local store"
  echo "  ${KEY}"
fi
[[ "${TESTS[0]}" == "sheet_photo" ]] && {
  [[ "${PHOTOS}" == "1" ]] || fail "the part photo was not stored"
  say "OK — part photo only"; exit 0;
}

# A property column added with +: one row, with the option it was given.
PROPS="$(sqlite3 "${DB}" \
  "SELECT COUNT(*) FROM item_sheet_properties WHERE property_key = 'e2e finish';")"
if [[ "${PROPS}" != "0" ]]; then
  echo "property columns written: ${PROPS}"
  [[ "${PROPS}" == "1" ]] || fail "one + made ${PROPS} property columns"
  sqlite3 -noheader "${DB}" \
    "SELECT '  ' || display_name || ' (' || kind || ') ' || options_json
       FROM item_sheet_properties WHERE property_key = 'e2e finish';"
fi
[[ "${TESTS[0]}" == "sheet_property_column" ]] && {
  [[ "${PROPS}" == "1" ]] || fail "the property column was not written"
  say "OK — property column only"; exit 0;
}

ROUTES="$(sqlite3 "${DB}" "SELECT COUNT(*) FROM process_routes WHERE status='active';")"
if [[ "${ROUTES}" == "0" ]]; then
  echo "No active route was written."
  echo "(Expected if you ran only app_boot.)"
  [[ "${TESTS[0]}" == "app_boot" ]] && { say "OK — harness only"; exit 0; }
  [[ "${TESTS[0]}" == "sheet_bulk" ]] && { say "OK — bulk entry only"; exit 0; }
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

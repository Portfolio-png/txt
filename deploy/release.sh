#!/usr/bin/env bash
#
# Atomic release with a health gate and automatic rollback.
#
# The old deploy copied files straight over the running application and then ran
# `pm2 restart all`. Three things went wrong with that, and they are why a push
# took the running copy away:
#
#   * the copy overwrote files underneath a live process, so for the length of
#     the transfer the app was running against a half-replaced tree;
#   * `restart` tears the process down and brings it back on the new code — if
#     that code cannot boot, there is nothing left running and no way back;
#   * `all` did it to every process on the box, not just this application.
#
# Instead: each release lands in its own directory, `current` is a symlink, and
# switching versions is one atomic symlink swap. The new release has to answer
# /health before it keeps the symlink; if it does not, the symlink goes back to
# the release that was working and that one is reloaded. The previous release
# stays on disk, so going back is a symlink swap rather than a rebuild.
#
# Usage:
#   release.sh <app-name> <release-source-dir> [port]
#
# Layout it maintains under $PAPER_HOME (default ~/paper):
#   releases/<timestamp>/   the code for one deploy
#   current -> releases/…   what pm2 runs
#   previous -> releases/…  what it would fall back to
#   shared/.env             config, outlives releases
#   shared/data/            the database, outlives releases

set -euo pipefail

APP_NAME="${1:?usage: release.sh <app-name> <source-dir> [port]}"
SOURCE_DIR="${2:?usage: release.sh <app-name> <source-dir> [port]}"
PORT="${3:-18080}"

PAPER_HOME="${PAPER_HOME:-$HOME/paper}"
APP_HOME="$PAPER_HOME/$APP_NAME"
RELEASES="$APP_HOME/releases"
SHARED="$APP_HOME/shared"
CURRENT="$APP_HOME/current"
PREVIOUS="$APP_HOME/previous"
KEEP_RELEASES="${KEEP_RELEASES:-5}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-60}"

log() { printf '[release] %s\n' "$*"; }
fail() { printf '[release] FAILED: %s\n' "$*" >&2; exit 1; }

mkdir -p "$RELEASES" "$SHARED/data"

# --- land the new code in its own directory -------------------------------
STAMP="$(date -u +%Y%m%d-%H%M%S)"
TARGET="$RELEASES/$STAMP"
log "staging release $STAMP for $APP_NAME"
mkdir -p "$TARGET"
cp -R "$SOURCE_DIR"/. "$TARGET"/

# Config and data live outside the release so a rollback never rolls back the
# database, and a new release never starts with an empty one.
[ -f "$SHARED/.env" ] || { [ -f "$TARGET/.env" ] && cp "$TARGET/.env" "$SHARED/.env"; } || true
rm -f "$TARGET/.env"
ln -sfn "$SHARED/.env" "$TARGET/.env"
rm -rf "$TARGET/data"
ln -sfn "$SHARED/data" "$TARGET/data"

# Stamp the release so /health can say which build is answering. Without this a
# deploy cannot tell the copy it just shipped from the one it replaced.
{
  printf 'PAPER_RELEASE=%s\n' "$STAMP"
  printf 'PAPER_COMMIT=%s\n' "${PAPER_COMMIT:-unknown}"
  printf 'PAPER_ENV=%s\n' "${PAPER_ENV:-production}"
} > "$TARGET/.release-env"

log "installing dependencies"
(cd "$TARGET" && npm install --omit=dev --no-audit --no-fund)

# --- remember where to go back to -----------------------------------------
ROLLBACK_TO=""
if [ -L "$CURRENT" ]; then
  ROLLBACK_TO="$(readlink "$CURRENT")"
  ln -sfn "$ROLLBACK_TO" "$PREVIOUS"
  log "current release is $(basename "$ROLLBACK_TO"); keeping it as the fallback"
fi

# --- switch, then prove it works ------------------------------------------
ln -sfn "$TARGET" "$CURRENT"

start_or_reload() {
  # `reload` replaces workers one at a time and keeps serving; `restart` does
  # not. Only fall back to start when the app is not registered yet.
  if pm2 describe "$APP_NAME" >/dev/null 2>&1; then
    pm2 reload "$APP_NAME" --update-env
  else
    pm2 start "$CURRENT/server.js" --name "$APP_NAME" --update-env
  fi
}

# pm2 reads the environment of the process that launches it, so the release
# stamp has to be exported here rather than left in a file the app never reads.
set -a
# shellcheck disable=SC1090
. "$CURRENT/.release-env"
set +a
export PORT="$PORT"

log "reloading $APP_NAME on port $PORT"
start_or_reload

# --- the health gate -------------------------------------------------------
# A process that is up is not the same as an application that works: this waits
# for the database to finish migrating, which is what /health reports.
healthy() {
  local body
  body="$(curl -fsS --max-time 5 "http://127.0.0.1:$PORT/health" 2>/dev/null)" || return 1
  printf '%s' "$body" | grep -q '"status":"ok"' || return 1
  return 0
}

log "waiting up to ${HEALTH_TIMEOUT}s for /health"
deadline=$(( $(date +%s) + HEALTH_TIMEOUT ))
until healthy; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    log "health check never passed"
    if [ -n "$ROLLBACK_TO" ]; then
      log "rolling back to $(basename "$ROLLBACK_TO")"
      ln -sfn "$ROLLBACK_TO" "$CURRENT"
      start_or_reload
      sleep 3
      if healthy; then
        fail "release $STAMP was rolled back; the previous release is serving"
      fi
      fail "release $STAMP failed AND the rollback did not come up — needs hands"
    fi
    fail "release $STAMP failed and there is no previous release to fall back to"
  fi
  sleep 2
done

log "healthy"
pm2 save >/dev/null 2>&1 || true

# --- tidy up, keeping enough history to go back ---------------------------
KEEP_FROM="$(basename "${ROLLBACK_TO:-$TARGET}")"
ls -1 "$RELEASES" | sort -r | tail -n +$((KEEP_RELEASES + 1)) | while read -r old; do
  [ "$old" = "$STAMP" ] && continue
  [ "$old" = "$KEEP_FROM" ] && continue
  log "pruning old release $old"
  rm -rf "${RELEASES:?}/$old"
done

log "released $STAMP as $APP_NAME"

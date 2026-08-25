#!/usr/bin/env bash
#
# Go back to the release that was running before the last deploy.
#
# release.sh rolls back on its own when a new release fails its health check.
# This is for the other case: the release came up healthy and is wrong anyway —
# a bug that only shows once someone uses it. Because every release is still on
# disk, going back is a symlink swap and a reload, not a rebuild or a re-deploy.
#
# Usage: rollback.sh <app-name> [port]

set -euo pipefail

APP_NAME="${1:?usage: rollback.sh <app-name> [port]}"
PORT="${2:-18080}"
PAPER_HOME="${PAPER_HOME:-$HOME/paper}"
APP_HOME="$PAPER_HOME/$APP_NAME"
CURRENT="$APP_HOME/current"
PREVIOUS="$APP_HOME/previous"

log() { printf '[rollback] %s\n' "$*"; }

[ -L "$PREVIOUS" ] || { echo "[rollback] no previous release recorded for $APP_NAME" >&2; exit 1; }

TARGET="$(readlink "$PREVIOUS")"
[ -d "$TARGET" ] || { echo "[rollback] previous release $TARGET is gone" >&2; exit 1; }

# The release being left becomes the thing to come back to, so a rollback can
# itself be undone.
if [ -L "$CURRENT" ]; then
  ln -sfn "$(readlink "$CURRENT")" "$PREVIOUS.tmp"
fi

log "switching to $(basename "$TARGET")"
ln -sfn "$TARGET" "$CURRENT"
pm2 reload "$APP_NAME" --update-env || pm2 start "$CURRENT/server.js" --name "$APP_NAME" --update-env

[ -L "$PREVIOUS.tmp" ] && mv -f "$PREVIOUS.tmp" "$PREVIOUS"

for _ in $(seq 1 20); do
  if curl -fsS --max-time 5 "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q '"status":"ok"'; then
    log "healthy on $(basename "$TARGET")"
    pm2 save >/dev/null 2>&1 || true
    exit 0
  fi
  sleep 2
done

echo "[rollback] rolled back but /health did not pass — needs hands" >&2
exit 1

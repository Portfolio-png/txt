#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./deploy/redeploy.sh [--no-pull] [--force-reset]

--no-pull      Skip git fetch/pull (use current working tree)
--force-reset  Reset local branch to origin/main (DESTROYS uncommitted changes)
EOF
}

no_pull="false"
force_reset="false"

for arg in "${@:-}"; do
  case "$arg" in
    --no-pull) no_pull="true" ;;
    --force-reset) force_reset="true" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $arg"; usage; exit 2 ;;
  esac
done

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

if [[ ! -f ".env" ]]; then
  echo "Missing $repo_dir/.env"
  echo "Create it once: cp .env.example .env && edit secrets (PAPER_JWT_SECRET, PAPER_SUPER_ADMIN_*)"
  exit 1
fi

if ! command -v pm2 >/dev/null 2>&1; then
  echo "pm2 not found. Install once: sudo npm i -g pm2"
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl not found. Install once: sudo apt install -y curl"
  exit 1
fi

echo "==> Installing build tools (required for sqlite3 native build)"
if ! command -v make >/dev/null 2>&1; then
  sudo apt update
  sudo apt install -y build-essential make g++ python3
fi

if [[ "$no_pull" != "true" ]]; then
  echo "==> Updating code"
  git fetch --all --prune
  if [[ "$force_reset" == "true" ]]; then
    git reset --hard origin/main
  else
    git pull --ff-only
  fi
fi

echo "==> Installing dependencies"
rm -rf node_modules
if [[ -f "package-lock.json" ]]; then
  npm ci
else
  npm install
fi

echo "==> Rebuilding sqlite3 native module for this machine"
npm rebuild sqlite3 --build-from-source

echo "==> Restarting PM2 app using ecosystem.config.js"
pm2 delete paper-backend >/dev/null 2>&1 || true
pm2 start ecosystem.config.js
pm2 save

echo "==> Waiting for backend to come up"
ok="false"
for _ in {1..30}; do
  if curl -fsS "http://127.0.0.1:18080/health" >/dev/null; then
    ok="true"
    break
  fi
  sleep 1
done

if [[ "$ok" != "true" ]]; then
  echo "Backend did not become healthy on :18080. Showing recent PM2 logs:"
  pm2 logs paper-backend --lines 120 || true
  exit 1
fi

echo "OK: http://127.0.0.1:18080/health"

if npm run -s smoke >/dev/null 2>&1; then
  echo "==> Running smoke check"
  npm run -s smoke
fi

echo "==> Verifying backend health (via Nginx)"
curl -fsS "http://127.0.0.1/health" >/dev/null
echo "OK: http://127.0.0.1/health"

echo "==> Done"

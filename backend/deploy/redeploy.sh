#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

if [[ ! -f ".env" ]]; then
  echo "Missing $repo_dir/.env"
  echo "Create it once: cp .env.example .env && edit secrets (PAPER_JWT_SECRET, PAPER_SUPER_ADMIN_*)"
  exit 1
fi

echo "==> Updating code"
git fetch --all --prune
git pull --ff-only

echo "==> Installing dependencies"
rm -rf node_modules
npm install

echo "==> Rebuilding sqlite3 native module for this machine"
npm rebuild sqlite3 --build-from-source

echo "==> Restarting PM2 app using ecosystem.config.js"
pm2 delete paper-backend >/dev/null 2>&1 || true
pm2 start ecosystem.config.js
pm2 save

echo "==> Verifying backend health (direct)"
curl -fsS "http://127.0.0.1:18080/health" >/dev/null
echo "OK: http://127.0.0.1:18080/health"

echo "==> Verifying backend health (via Nginx)"
curl -fsS "http://127.0.0.1/health" >/dev/null
echo "OK: http://127.0.0.1/health"

echo "==> Done"

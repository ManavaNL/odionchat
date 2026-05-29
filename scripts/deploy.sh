#!/usr/bin/env bash
# deploy.sh — Deploy OdionChat to VPS via rsync + docker compose
#
# Usage: ./scripts/deploy.sh
#
# Vereisten:
# - SSH toegang tot VPS (key-based)
# - Docker op VPS geinstalleerd
# - .env op VPS aanwezig in /opt/odionchat/.env

set -euo pipefail

VPS="root@<vps-ip>"
REMOTE="/opt/odionchat"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== Deploying OdionChat to ${VPS}:${REMOTE} ==="

echo "=== Syncing files ==="
# Belangrijk: data/ NOOIT mee-syncen — bevat prod-DB (users, chats, knowledge).
# Lokaal data/ overschrijft prod data/ anders, wat alle prod-state vernietigt.
# .env idem: prod heeft eigen secret + admin creds.
rsync -avz --delete \
  --exclude='.git' \
  --exclude='.DS_Store' \
  --exclude='data' \
  --exclude='.env' \
  --exclude='*.bak' \
  --exclude='*.bak-*' \
  "${PROJECT_DIR}/" "${VPS}:${REMOTE}/"

echo "=== Restarting container ==="
ssh "$VPS" "cd ${REMOTE} && docker compose pull && docker compose up -d"

echo "=== Waiting for health check ==="
for i in $(seq 1 30); do
  if ssh "$VPS" "curl -sf http://localhost:3000/health" > /dev/null 2>&1; then
    echo "=== OdionChat is live! ==="
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "Warning: health check niet gelukt na 30 seconden"
    echo "Check logs: ssh ${VPS} 'docker logs odionchat --tail 50'"
    exit 1
  fi
  sleep 2
done

echo "=== Deploy complete ==="
echo "  URL: https://odion.manava.nl"
echo "  Logs: ssh ${VPS} 'docker logs odionchat -f'"

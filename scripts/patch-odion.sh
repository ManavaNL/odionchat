#!/usr/bin/env bash
# patch-locale.sh — Configure models, suggestions, and system prompt via API
#
# CSS and locale patches happen automatically via entrypoint.sh at container start.
# This script handles API-level configuration that requires a running instance.
#
# Usage: ./scripts/patch-locale.sh [base_url]
#   base_url defaults to http://localhost:3000

# set -euo pipefail

BASE_URL="${1:-http://localhost:3000}"
CONTAINER="odionchat"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

ADMIN_EMAIL="${WEBUI_ADMIN_EMAIL:-admin@odion.local}"
ADMIN_PASSWORD="${WEBUI_ADMIN_PASSWORD:-changeme}"

# Wait for API to be ready
# echo "=== Waiting for API to be ready ==="
# for i in $(seq 1 30); do
#   if curl -sf "${BASE_URL}/health" > /dev/null 2>&1; then
#     break
#   fi
#   if [ "$i" -eq 30 ]; then
#     echo "Error: API not ready after 30 seconds" >&2
#     exit 1
#   fi
#   sleep 1
# done

# echo "=== Authenticating as ${ADMIN_EMAIL} ==="
# TOKEN=$(curl -s "${BASE_URL}/api/v1/auths/signin" \
#   -H "Content-Type: application/json" \
#   -d "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\"}" \
#   | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")

# if [ -z "$TOKEN" ]; then
#   echo "Error: could not authenticate. Check admin credentials." >&2
#   exit 1
# fi

# echo "=== Setting suggestions via API ==="
# curl -s "${BASE_URL}/api/v1/configs/suggestions" \
#   -X POST \
#   -H "Authorization: Bearer $TOKEN" \
#   -H "Content-Type: application/json" \
#   -d '{"suggestions":[
#     {"title":["Dagrapportage","schrijven"],"content":"Help me een dagrapportage schrijven over mijn dienst van vandaag."},
#     {"title":["Eigen regie","ondersteunen"],"content":"Hoe kan ik de eigen regie van mijn cliënt beter ondersteunen?"},
#     {"title":["Uitnodiging","familieavond"],"content":"Schrijf een uitnodiging voor een familieavond bij onze woonlocatie."}
#   ]}' > /dev/null

# echo "=== Creating + updating models ==="

# SYSTEM_PROMPT=$(python3 -c "import json; print(json.dumps(open('${PROJECT_DIR}/config/system-prompt.txt').read()))")
# SUGGESTIONS='[{"title":["Dagrapportage","schrijven"],"content":"Help me een dagrapportage schrijven over mijn dienst van vandaag."},{"title":["Eigen regie","ondersteunen"],"content":"Hoe kan ik de eigen regie van mijn cliënt beter ondersteunen?"},{"title":["Uitnodiging","familieavond"],"content":"Schrijf een uitnodiging voor een familieavond bij onze woonlocatie."}]'

# Logo als data-URL voor model profile_image_url — anders laat Open WebUI's API-fallback
# een gradient avatar zien met inconsistente content-type headers (broken icon in browser)
LOGO_DATA_URL="data:image/png;base64,$(base64 -i "${PROJECT_DIR}/config/logo.png" | tr -d '\n')"

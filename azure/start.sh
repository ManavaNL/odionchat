#!/usr/bin/env bash
# OdionChat — Build the Azure image locally and start a container for testing.
#
# Usage: ./azure/start.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

IMAGE="${IMAGE:-ghcr.io/manavanl/odionchat:local}"
CONTAINER="${CONTAINER:-odionchat}"
HOST_PORT="${HOST_PORT:-3000}"

if ! docker info > /dev/null 2>&1; then
  echo "Docker is niet gestart. Open Docker Desktop en probeer opnieuw." >&2
  exit 1
fi

if [ ! -f .env ]; then
  echo "Geen .env bestand gevonden." >&2
  echo "Kopieer .env.example naar .env en vul je waarden in:" >&2
  echo "  cp .env.example .env" >&2
  exit 1
fi

# shellcheck disable=SC1091
set -a
source .env
set +a

HOST_PORT="${PORT:-$HOST_PORT}"

echo "=== Building image: ${IMAGE} ==="
docker build -f azure/Dockerfile -t "$IMAGE" .

if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "=== Stopping existing container: ${CONTAINER} ==="
  docker rm -f "$CONTAINER" > /dev/null
fi

mkdir -p data

echo "=== Starting container: ${CONTAINER} ==="
docker run -d \
  --name "$CONTAINER" \
  --restart unless-stopped \
  -p "${HOST_PORT}:8080" \
  -v "${ROOT}/data:/app/backend/data" \
  --env-file .env \
  -e PORT=8080 \
  -e WEBUI_NAME=OdionChat \
  -e OPENAI_API_KEYS="${AZURE_OPENAI_API_KEY:-${OPENAI_API_KEYS:-${GOOGLE_API_KEY:-}}}" \
  -e ENABLE_CODE_INTERPRETER=false \
  -e ENABLE_IMAGE_GENERATION=false \
  -e ENABLE_RAG_WEB_SEARCH=false \
  -e ENABLE_RAG_LOCAL_WEB_FETCH=false \
  -e ENABLE_RAG_HYBRID_SEARCH=false \
  -e ENABLE_COMMUNITY_SHARING=false \
  -e ENABLE_MESSAGE_RATING=false \
  -e ENABLE_EVALUATION_ARENA_MODELS=false \
  -e ENABLE_CHANNELS=false \
  -e ENABLE_API_KEY=false \
  -e ENABLE_DIRECT_CONNECTIONS=false \
  -e ENABLE_FORWARD_USER_INFO_HEADERS=false \
  -e ENABLE_ADMIN_CHAT_ACCESS=false \
  -e ENABLE_OLLAMA_API=false \
  -e ENABLE_VERSION_UPDATE_CHECK=false \
  "$IMAGE"

echo "=== Waiting for API (first boot can take 1–2 minutes) ==="
for i in $(seq 1 60); do
  if curl -sf "http://localhost:${HOST_PORT}/health" > /dev/null 2>&1; then
    echo ""
    echo "OdionChat is gestart!"
    echo "Open je browser op: http://localhost:${HOST_PORT}"
    echo ""
    echo "Logs:    docker logs -f ${CONTAINER}"
    echo "Stoppen: docker rm -f ${CONTAINER}"
    exit 0
  fi
  sleep 2
done

echo "Container draait, maar /health reageert nog niet." >&2
echo "Check de logs: docker logs -f ${CONTAINER}" >&2
exit 1

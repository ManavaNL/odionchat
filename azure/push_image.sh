#!/usr/bin/env bash
# OdionChat — Build and push the Azure image to GitHub Container Registry.
#
# Usage:
#   ./azure/push_image.sh              # push :latest
#   TAG=v0.1.0 ./azure/push_image.sh   # push custom tag
#
# Requires: docker, gh (logged in with write:packages scope)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

REGISTRY="${REGISTRY:-ghcr.io/manavanl/odionchat}"
TAG="${TAG:-latest}"
IMAGE="${REGISTRY}:${TAG}"

if ! docker info > /dev/null 2>&1; then
  echo "Docker is niet gestart. Open Docker Desktop en probeer opnieuw." >&2
  exit 1
fi

if ! command -v gh > /dev/null 2>&1; then
  echo "gh CLI niet gevonden. Installeer GitHub CLI om naar GHCR te pushen." >&2
  exit 1
fi

GH_USER="$(gh api user -q .login)"
echo "=== Logging in to ghcr.io as ${GH_USER} ==="
echo "$(gh auth token)" | docker login ghcr.io -u "$GH_USER" --password-stdin

echo "=== Building image: ${IMAGE} ==="
docker build -f azure/Dockerfile -t "$IMAGE" .

echo "=== Pushing ${IMAGE} ==="
docker push "$IMAGE"

echo ""
echo "Done: ${IMAGE}"
echo "Pull: docker pull ${IMAGE}"

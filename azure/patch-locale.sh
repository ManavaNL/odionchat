#!/usr/bin/env bash
# patch-locale.sh — Bake Odion CSS, logos, and Dutch locale into the Open WebUI image.
#
# Used during `docker build` (see azure/Dockerfile). Delegates to entrypoint.sh in
# patch-only mode so branding/locale logic stays in one place.
#
# For API-level config (models, suggestions, system prompt) after deploy, run
# scripts/patch-locale.sh against the running instance.

set -euo pipefail

export ODION_PATCH_ONLY=1
exec bash /entrypoint.sh

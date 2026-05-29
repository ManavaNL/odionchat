#!/bin/bash
# OdionChat — Stop de demo-omgeving

set -e
cd "$(dirname "$0")/.."

echo "OdionChat stoppen..."
docker compose down

echo "OdionChat is gestopt."

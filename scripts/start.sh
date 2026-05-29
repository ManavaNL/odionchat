#!/bin/bash
# OdionChat — Start de demo-omgeving

set -e
cd "$(dirname "$0")/.."

# Check of Docker draait
if ! docker info > /dev/null 2>&1; then
    echo "Docker is niet gestart. Open Docker Desktop en probeer opnieuw."
    exit 1
fi

# Check of .env bestaat
if [ ! -f .env ]; then
    echo "Geen .env bestand gevonden."
    echo "Kopieer .env.example naar .env en vul je API key in:"
    echo "  cp .env.example .env"
    exit 1
fi

echo "OdionChat starten..."
docker compose up -d

echo ""
echo "OdionChat is gestart!"
echo "Open je browser op: http://localhost:3000"
echo ""
echo "Stoppen: ./scripts/stop.sh"

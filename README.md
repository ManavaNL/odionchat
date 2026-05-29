---
date: 2026-05-29
tags:
  - odion
  - odionchat
  - demo
description: "OdionChat chatomgeving met Open WebUI en Azure AI Foundry die Odion-medewerkers laat chatten in een veilige omgeving."
---

# OdionChat

Een veilige chatomgeving voor medewerkers van Odion, gebouwd op Open WebUI v0.8.7 met Azure AI Foundry als taalmodel.

## Wat heb je nodig?

- Docker (Docker Desktop of OrbStack)
- Azure AI Foundry API key en endpoint (Azure Portal → Keys and Endpoint)

## Starten (lokaal)

1. Maak een `.env` aan:

```bash
cp .env.example .env
# Open .env en vul OPENAI_API_BASE_URLS + AZURE_OPENAI_API_KEY in
```

2. Build en start OdionChat:

```bash
docker compose up --build
```

3. Open je browser op [http://localhost:3000](http://localhost:3000)

De container luistert intern op poort **8080** (`PORT` in `.env`); lokaal bereikbaar via **3000** (`HOST_PORT` in `.env`).

Bij de eerste start:
- Eerste boot duurt 1–2 minuten (database-migraties + embeddings download)
- Maak een admin-account aan (`ENABLE_SIGNUP=true` in `.env` voor de eerste registratie)
- Zet daarna `ENABLE_SIGNUP=false` voor productie

Health check:

```bash
curl http://localhost:3000/health
```

## Stoppen

```bash
docker compose down
```

## Docker image (GHCR)

De custom image wordt gepubliceerd naar GitHub Container Registry bij push naar de main branch.

```
ghcr.io/manavanl/odionchat:latest
```

Pull en run lokaal:

```bash
docker pull ghcr.io/manavanl/odionchat:latest

docker run -d \
  --name odionchat \
  -p 3000:8080 \
  -e PORT=8080 \
  --env-file .env \
  -v "$(pwd)/data:/app/backend/data" \
  ghcr.io/manavanl/odionchat:latest
```

CI: bij push naar `main` bouwt `.github/workflows/docker-publish.yml` automatisch een nieuwe image (tags: `latest` + git SHA).

## Architectuur

```
odionchat/
  .env                      # OPENAI_API_BASE_URLS, AZURE_OPENAI_API_KEY (gitignored)
  .env.example
  Dockerfile                # Open WebUI + Odion patches (build-time)
  docker-compose.yml        # Lokaal: build + run op poort 3000
  .github/workflows/
    docker-publish.yml      # Build + push naar ghcr.io/manavanl/odionchat
  config/
    custom.css              # Odion branding (paars #762283, Montserrat)
    logo.png / logo.svg     # Logo's voor UI en favicon
    system-prompt.txt       # System prompt (Kompas, B1, weigert persoonsgegevens)
  scripts/
    patch.sh                # CSS, logo's + NL locale (baked in tijdens docker build)
  data/                     # SQLite, uploads (gitignored)
```

Branding en Nederlandse UI worden tijdens `docker build` in de image gebakken via `scripts/patch.sh`. De container start daarna met de standaard Open WebUI entrypoint (`start.sh`).

## Authenticatie

OdionChat staat standaard in authenticatiemodus (`WEBUI_AUTH=true`):
- Gebruikers moeten inloggen
- `ENABLE_SIGNUP=true` bij eerste boot zodat de admin zich kan registreren
- Zet daarna `ENABLE_SIGNUP=false` voor productie

### Entra ID SSO (productie)

Voor Azure Container Apps met Microsoft Entra ID: zie `docs/deployment-azure.md` en `docs/sso-microsoft.md`.

## Deployen

| Omgeving | Handleiding |
|----------|-------------|
| Azure Container Apps | `docs/deployment-azure.md` |
| VPS (legacy) | `docs/deployment-old.md` |

Productie-image: `ghcr.io/manavanl/odionchat:latest` (target port **8080** in Container Apps).

## Documentatie

- `docs/deployment-azure.md` — Azure Container Apps deployment
- `docs/deployment-old.md` — VPS deployment (legacy)
- `docs/sso-microsoft.md` — Microsoft Entra ID SSO configuratie
- `docs/architectuur.md` — Technische architectuur en keuzes
- `docs/odion-stijlgids.md` — Branding tokens
- `docs/openwebui-reference.md` — Open WebUI upgrade-checklist
- `docs/handleiding-demo.md` — Demoscript (historisch, 3 maart 2026)

## Problemen?

| Probleem | Oplossing |
|----------|-----------|
| "Docker is niet gestart" | Open Docker Desktop / OrbStack en wacht tot het draait |
| Browser toont niets | Eerste boot duurt 1–2 min. `curl http://localhost:3000/health` of `docker logs odionchat -f` |
| Verkeerde poort | Container op 8080 (`PORT`); hostpoort via `HOST_PORT=3000` in `.env` of `-p 3000:8080` |
| API key invalid | Controleer `AZURE_OPENAI_API_KEY` en `OPENAI_API_BASE_URLS` in `.env` |
| Branding/locale ontbreekt | Rebuild image: `docker compose up -d --build` (patches zitten in de image) |
| Modellen niet zichtbaar | Controleer Foundry deployment names in `.env` (`AZURE_DEPLOYMENT_FAST` / `_PRO`) |

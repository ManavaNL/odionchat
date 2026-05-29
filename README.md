---
date: 2026-05-01
tags:
  - odion
  - odionchat
  - demo
description: "OdionChat demo-omgeving met Open WebUI en Google Gemini API die Odion-medewerkers laat ervaren hoe een veilige chatomgeving werkt."
---

# OdionChat — Demo

Een veilige chatomgeving voor medewerkers van Odion, gebouwd op Open WebUI met Google Gemini als taalmodel.

## Wat heb je nodig?

- Docker (Docker Desktop of OrbStack)
- Een Google Gemini API key (verkrijg via [Google AI Studio](https://aistudio.google.com/apikey))

## Starten

1. Maak een `.env` aan:

```bash
cp .env.example .env
# Open .env en vul GOOGLE_API_KEY in
```

2. Start OdionChat:

```bash
./scripts/start.sh
# of: docker compose up -d
```

3. Open je browser op [http://localhost:3000](http://localhost:3000)

Bij de eerste start:
- Maak een admin-account aan (eerste registratie wordt automatisch admin)
- Run `./scripts/patch-locale.sh` om modellen, system prompt en suggesties te configureren
- Twee modellen verschijnen: "OdionChat Snel" (gemini-2.5-flash) en "OdionChat Nadenken" (gemini-2.5-pro)

## Stoppen

```bash
./scripts/stop.sh
# of: docker compose down
```

## Architectuur

```
odionchat/
  .env                      # GOOGLE_API_KEY (gitignored)
  docker-compose.yml        # Open WebUI container, Gemini via OpenAI-compatible endpoint
  config/
    custom.css              # Odion branding (paars #762283, Montserrat)
    system-prompt.txt       # System prompt (Kompas, B1, weigert persoonsgegevens)
  scripts/
    entrypoint.sh           # Patch CSS + NL locale at boot
    patch-locale.sh         # Configure modellen + suggesties via API (post-boot)
    deploy.sh               # rsync + docker compose naar VPS
    start.sh / stop.sh      # Lokale operations
  data/                     # SQLite, uploads (gitignored)
```

## Authenticatie

OdionChat staat standaard in authenticatiemodus (`WEBUI_AUTH=true`):
- Gebruikers moeten inloggen
- `ENABLE_SIGNUP=true` bij eerste boot zodat de admin zich kan registreren
- Zet daarna `ENABLE_SIGNUP=false` voor productie

### Entra ID SSO (fase 2)

Wanneer Rick/IT klaar is met de Azure App Registration, activeer SSO via de variabelen in `.env` zoals beschreven in `docs/sso-microsoft.md`.

## Deployen naar VPS

```bash
./scripts/deploy.sh
```

Doel: `root@<vps-ip>:/opt/odionchat` → `https://odion.manava.nl` (Caddy reverse proxy + Let's Encrypt). Zie `docs/deployment.md` voor de volledige VPS-setup.

## Documentatie

- `docs/deployment.md` — VPS deployment handleiding
- `docs/sso-microsoft.md` — Microsoft Entra ID SSO configuratie
- `docs/architectuur.md` — Technische architectuur en keuzes
- `docs/odion-stijlgids.md` — Branding tokens
- `docs/handleiding-demo.md` — Demoscript (historisch, 3 maart 2026)

## Problemen?

| Probleem | Oplossing |
|----------|-----------|
| "Docker is niet gestart" | Open Docker Desktop / OrbStack en wacht tot het draait |
| Browser toont niets na 30s | Eerste boot duurt 3-5 min (embeddings download). `docker logs odionchat -f` |
| Modellen niet zichtbaar | Run `./scripts/patch-locale.sh` na container boot |
| API key invalid | Controleer `GOOGLE_API_KEY` in `.env` |
| CSS/locale werkt niet | Container herstart? `entrypoint.sh` patcht beide bij boot |

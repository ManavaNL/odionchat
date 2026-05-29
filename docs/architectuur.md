---
date: 2026-05-29
tags:
  - odion
  - odionchat
  - architectuur
description: "Architectuurbeslissingen voor OdionChat: Open WebUI, Azure AI Foundry, en Docker als stack."
---

# OdionChat — Architectuur

## Waarom Open WebUI?

Open WebUI is een open-source chatinterface die meerdere LLM-backends ondersteunt.

**Voordelen voor Odion:**

- **OpenAI-compatible backends** — Azure AI Foundry, Anthropic, lokale modellen — allemaal pluggable
- **System prompt afdwingbaar** — per model via admin panel, gebruikers kunnen dit niet wijzigen
- **Temporary Chat mode** — stateless optie, niets opgeslagen (privacygarantie)
- **SSO-ready** — Microsoft Entra ID (Azure AD) ondersteund via OIDC, past bij Odion's M365
- **Open source** — geen vendor lock-in, past bij exit-strategie
- **Single container** — eenvoudig te draaien en te verplaatsen

## Waarom Azure AI Foundry?

OdionChat gebruikt Azure AI Foundry als LLM-backend via het OpenAI v1-compatible endpoint:

- Past binnen Odion's Azure-omgeving (data residency, billing, governance)
- Bereikbaar via OpenAI-compatible endpoint (`https://<resource>.openai.azure.com/openai/v1/`) — geen aparte SDK
- Twee deployments: `odionchat-fast` (snel, dagelijks gebruik) en `odionchat-pro` (complexere casuistiek)
- Zelfde integratie lokaal, op VPS en op Azure Container Apps — alleen env vars wijzigen

## Lokaal vs. productie

| Aspect | Lokaal / demo | Productie (Azure) |
|--------|---------------|-------------------|
| LLM backend | Azure AI Foundry | Azure AI Foundry |
| Authenticatie | Email login (`WEBUI_AUTH=true`) | Microsoft Entra ID (SSO) |
| Hosting | Docker lokaal of VPS + Caddy | Azure Container Apps |
| Data opslag | SQLite volume | Azure PostgreSQL (optioneel) |
| Branding | Custom CSS via `patch.sh` (build-time) | Custom CSS via `patch.sh` (build-time) |

## Dataflow

```
Gebruiker (browser)
  |
  v
HTTPS (chat.odion.nl of localhost:3000)
  |
  v
Open WebUI (container)
  |
  v
Azure AI Foundry (OpenAI v1-compatible endpoint, HTTPS)
  |
  v
Antwoord terug naar gebruiker
```

Chatcontent gaat naar Azure AI Foundry volgens Microsoft's dataverwerking. Bij Temporary Chat wordt lokaal niets opgeslagen (relevant voor DPIA-check FG Katrijn).

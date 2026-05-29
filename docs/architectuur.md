---
date: 2026-05-01
tags:
  - odion
  - odionchat
  - architectuur
description: "Architectuurbeslissingen voor de OdionChat demo: waarom Open WebUI, Google Gemini API, en Docker als stack."
---

# OdionChat — Architectuur

## Waarom Open WebUI?

Open WebUI is een open-source chatinterface die meerdere LLM-backends ondersteunt.

**Voordelen voor Odion:**

- **OpenAI-compatible backends** — Gemini, Azure OpenAI, Anthropic, lokale modellen — allemaal pluggable
- **System prompt afdwingbaar** — per model via admin panel, gebruikers kunnen dit niet wijzigen
- **Temporary Chat mode** — stateless optie, niets opgeslagen (privacygarantie)
- **SSO-ready** — Microsoft Entra ID (Azure AD) ondersteund via OIDC, past bij Odion's M365
- **Open source** — geen vendor lock-in, past bij exit-strategie
- **Single container** — eenvoudig te draaien en te verplaatsen

## Waarom Google Gemini (i.p.v. Azure OpenAI)?

Azure OpenAI is de beoogde productie-omgeving, maar is nog niet ingericht (Rick/IT, Citrix-migratie). Gemini 2.5 Flash/Pro via Google AI Studio dient als tijdelijke backend voor de demo:

- Gratis tier ruim genoeg voor demo-volume
- Bereikbaar via OpenAI-compatible endpoint (`generativelanguage.googleapis.com/v1beta/openai`) — geen aparte SDK
- Twee preset-modellen: Flash (snel, goedkoop) en Pro (nadenken, complexere casuistiek)

De architectuur verandert niet: Open WebUI praat met een LLM API. Bij switch naar Azure OpenAI wijzigen we alleen `OPENAI_API_BASE_URLS` en `OPENAI_API_KEYS`.

## Demo vs. productie

| Aspect | Demo (nu) | Productie (later) |
|--------|-----------|-------------------|
| LLM backend | Gemini 2.5 Flash/Pro | Azure OpenAI (GPT-4.1/5) |
| Authenticatie | Email login (`WEBUI_AUTH=true`) | Microsoft Entra ID (SSO) |
| Hosting | VPS (Vultr) + Caddy | Odion-Azure |
| Data opslag | SQLite volume | Managed database |
| Branding | Custom CSS via entrypoint | Geïntegreerd thema |

## Dataflow

```
Gebruiker (browser)
  |
  v
Caddy (odion.manava.nl, Let's Encrypt TLS)
  |
  v
Open WebUI (container, localhost:3000 op VPS)
  |
  v
Google Gemini API (generativelanguage.googleapis.com)
  |
  v
Antwoord terug naar gebruiker
```

Geen data verlaat de sessie naar derden buiten Google. Bij Temporary Chat wordt lokaal niets opgeslagen; Gemini API logt zelf wel volgens Google's privacybeleid (relevant voor DPIA-check FG Katrijn).

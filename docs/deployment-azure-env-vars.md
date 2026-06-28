---
date: 2026-06-28
description: "Alle omgevingsvariabelen op een bestaande OdionChat Container App zetten."
---

# OdionChat — Environment variables (Azure)

**Volgorde:** eerst secrets registreren, daarna env vars. De `update` gebruikt `secretref:…` — zonder secrets faalt de deploy.

Vul placeholders in en run:

```bash
export RESOURCE_GROUP=rg-odionchat-prod
export CONTAINER_APP=odionchat
export WEBUI_URL=https://chat.odion.nl

export MICROSOFT_CLIENT_ID="<application-client-id>"
export MICROSOFT_CLIENT_TENANT_ID="<directory-tenant-id>"
export MICROSOFT_CLIENT_SECRET="<client-secret-value>"

export FOUNDRY_ENDPOINT="https://<resource-name>.openai.azure.com/openai/v1/"
export FOUNDRY_API_KEY="<foundry-api-key>"
export WEBUI_SECRET_KEY="<64-char-secret>"   # openssl rand -hex 32 (alleen bij eerste setup)

export DEFAULT_PROMPT_SUGGESTIONS='[{"title":["Dagrapportage","schrijven"],"content":"Help me een dagrapportage schrijven over mijn dienst van vandaag."},{"title":["Eigen regie","ondersteunen"],"content":"Hoe kan ik de eigen regie van mijn cliënt beter ondersteunen?"},{"title":["Uitnodiging","familieavond"],"content":"Schrijf een uitnodiging voor een familieavond bij onze woonlocatie."}]'
```

### Stap 1 — Controleren welke secrets al bestaan

```bash
az containerapp secret list \
  --name "$CONTAINER_APP" \
  --resource-group "$RESOURCE_GROUP" \
  -o table
```

Verwacht (namen moeten exact kloppen):

| Secret | Gebruikt door |
|--------|---------------|
| `microsoft-client-secret` | `MICROSOFT_CLIENT_SECRET=secretref:…` |
| `openai-api-key` | `OPENAI_API_KEYS=secretref:…` |
| `webui-secret-key` | `WEBUI_SECRET_KEY=secretref:…` |

Ontbreken één of meer? → stap 2. Alleen env vars wijzigen en secrets al compleet? → sla stap 2 over.

> **Let op:** een nieuwe `webui-secret-key` invalideert bestaande sessies. Laat die secret staan als de app al draait en je de waarde niet meer weet.

### Stap 2 — Secrets zetten (vóór `update`)

```bash
az containerapp secret set \
  --name "$CONTAINER_APP" \
  --resource-group "$RESOURCE_GROUP" \
  --secrets \
    microsoft-client-secret="$MICROSOFT_CLIENT_SECRET" \
    openai-api-key="$FOUNDRY_API_KEY" \
    webui-secret-key="$WEBUI_SECRET_KEY"
```

Alleen `webui-secret-key` overslaan als die al bestaat en je hem niet wilt roteren — zet dan alleen de andere twee:

```bash
az containerapp secret set \
  --name "$CONTAINER_APP" \
  --resource-group "$RESOURCE_GROUP" \
  --secrets \
    microsoft-client-secret="$MICROSOFT_CLIENT_SECRET" \
    openai-api-key="$FOUNDRY_API_KEY"
```

### Stap 3 — Env vars zetten

```bash
az containerapp update \
  --name "$CONTAINER_APP" \
  --resource-group "$RESOURCE_GROUP" \
  --set-env-vars \
    PORT=8080 \
    WEBUI_NAME=OdionChat \
    WEBUI_URL="$WEBUI_URL" \
    WEBUI_AUTH=true \
    DEFAULT_USER_ROLE=user \
    ENABLE_SIGNUP=false \
    ENABLE_OAUTH_SIGNUP=true \
    ENABLE_LOGIN_FORM=false \
    ENABLE_OAUTH_PERSISTENT_CONFIG=false \
    WEBUI_SESSION_COOKIE_SAME_SITE=lax \
    WEBUI_SESSION_COOKIE_SECURE=true \
    MICROSOFT_CLIENT_ID="$MICROSOFT_CLIENT_ID" \
    MICROSOFT_CLIENT_TENANT_ID="$MICROSOFT_CLIENT_TENANT_ID" \
    MICROSOFT_CLIENT_SECRET=secretref:microsoft-client-secret \
    MICROSOFT_OAUTH_SCOPE="openid email profile offline_access" \
    MICROSOFT_REDIRECT_URI="$WEBUI_URL/oauth/microsoft/callback" \
    OPENID_PROVIDER_URL="https://login.microsoftonline.com/$MICROSOFT_CLIENT_TENANT_ID/v2.0/.well-known/openid-configuration" \
    OPENAI_API_BASE_URLS="$FOUNDRY_ENDPOINT" \
    OPENAI_API_KEYS=secretref:openai-api-key \
    WEBUI_SECRET_KEY=secretref:webui-secret-key \
    AZURE_DEPLOYMENT_FAST=odionchat-fast \
    AZURE_DEPLOYMENT_PRO=odionchat-pro \
    ENABLE_OPENAI_API=true \
    ENABLE_CODE_INTERPRETER=false \
    ENABLE_IMAGE_GENERATION=false \
    ENABLE_RAG_WEB_SEARCH=false \
    ENABLE_RAG_LOCAL_WEB_FETCH=false \
    ENABLE_RAG_HYBRID_SEARCH=false \
    ENABLE_COMMUNITY_SHARING=false \
    ENABLE_MESSAGE_RATING=false \
    ENABLE_EVALUATION_ARENA_MODELS=false \
    ENABLE_CHANNELS=false \
    ENABLE_API_KEY=false \
    ENABLE_DIRECT_CONNECTIONS=false \
    ENABLE_FORWARD_USER_INFO_HEADERS=false \
    ENABLE_ADMIN_CHAT_ACCESS=false \
    ENABLE_OLLAMA_API=false \
    ENABLE_VERSION_UPDATE_CHECK=false \
    DEFAULT_PROMPT_SUGGESTIONS="$DEFAULT_PROMPT_SUGGESTIONS"
```

Lokaal: `cp .env.example .env` en `docker compose up`. Zie [deployment-azure.md](deployment-azure.md) voor de volledige deploy.

---
date: 2026-05-29
description: "Stap-voor-stap handleiding voor het deployen van OdionChat op Azure met Microsoft Entra ID, Azure AI Foundry en optioneel Azure PostgreSQL."
---

# OdionChat — Azure deployment

Handleiding voor het deployen van OdionChat op Azure met:

- **Domein:** `https://chat.odion.nl`
- **Authenticatie:** Microsoft Entra ID (SSO)
- **LLM backend:** Azure AI Foundry (OpenAI-compatible endpoint)
- **Hosting:** Azure Container Apps
- **Netwerk:** publiek HTTPS (geen VNet, geen private endpoints)
- **State (optioneel):** Azure Database for PostgreSQL Flexible Server

Zie ook:

- `docs/sso-microsoft.md` — gedetailleerde Entra-configuratie
- `docs/deployment.md` — VPS-deployment (huidige demo-omgeving)
- `docs/architectuur.md` — architectuurkeuzes

## Architectuur

```
Gebruiker (browser)
  |
  v
chat.odion.nl (DNS → Azure Container Apps + managed TLS)
  |
  v
Open WebUI container (OdionChat)
  |-- Microsoft Entra ID (login via OIDC)
  |-- Azure PostgreSQL (optioneel: users, chats, settings)
  |-- Azure Files (uploads, cache, embeddings)
  |
  v
Azure AI Foundry (OpenAI v1-compatible endpoint, publiek HTTPS)
```

Alle verbindingen lopen over het publieke internet via HTTPS — geen VNet of private endpoints:

- Gebruiker → `chat.odion.nl` (HTTPS)
- Container App → Azure AI Foundry chat completions (HTTPS + API key)
- Container App → PostgreSQL (HTTPS/SSL, optioneel — publieke toegang met firewall)

## Vereisten

- Azure-subscription met Contributor-rechten op een resource group
- Microsoft Entra ID: rechten om App Registrations aan te maken
- DNS-beheer voor `odion.nl` (CNAME-records voor `chat.odion.nl`)
- Toegang tot Azure AI Foundry / Azure OpenAI
- Docker (lokaal, voor testen en eventueel image build)

## Aanbevolen Azure-resources

| Component | Azure-service | Naam (voorbeeld) |
|-----------|---------------|------------------|
| Resource group | Resource group | `rg-odionchat-prod` |
| Container | Azure Container Apps | `odionchat` |
| Omgeving | Container Apps Environment | `cae-odionchat-prod` |
| Logging | Log Analytics workspace | `law-odionchat-prod` |
| Secrets | Key Vault | `kv-odionchat-prod` |
| Registry (optioneel) | Azure Container Registry | `acrodionchat` |
| Database (optioneel) | PostgreSQL Flexible Server | `psql-odionchat-prod` |
| Bestanden (optioneel) | Azure Files | `stodionchat` |

---

## Fase 0 — Beslissingen vooraf

Voer dit uit vóór het aanmaken van Azure-resources.

1. **Productie-URL vastleggen:** `https://chat.odion.nl`
2. **Regio kiezen:** bijv. `westeurope`
3. **Rollen toewijzen:**
   - Entra: Application Administrator
   - Azure: Contributor op resource group
   - DNS: beheer van `odion.nl`

---

## Fase 1 — Microsoft Entra ID

Entra moet als eerste worden ingericht, omdat de redirect URI exact moet matchen met het productiedomein.

### 1.1 App Registration aanmaken

1. Ga naar [Azure Portal](https://portal.azure.com) → **Microsoft Entra ID** → **App registrations** → **New registration**
2. Vul in:
   - **Name:** `OdionChat`
   - **Supported account types:** Accounts in this organizational directory only (Single tenant)
   - **Redirect URI:** Web — `https://chat.odion.nl/oauth/microsoft/callback`
3. Klik **Register**
4. Noteer:
   - **Application (client) ID**
   - **Directory (tenant) ID**

### 1.2 Client secret aanmaken

1. Ga naar **Certificates & secrets** → **New client secret**
2. Beschrijving: `OdionChat SSO`
3. Verlooptijd: bijv. 24 maanden
4. Noteer de **Value** (wordt maar één keer getoond)

### 1.3 Email claim toevoegen

Open WebUI heeft het e-mailadres nodig om gebruikers te identificeren.

1. Ga naar **Token configuration** → **Add optional claim**
2. Token type: **ID**
3. Vink **email** aan
4. Klik **Add**
5. Accepteer gevraagde API-rechten indien nodig

### 1.4 API permissions controleren

Ga naar **API permissions** en controleer:

- `openid` (standaard)
- `email`
- `profile`
- `offline_access`

Klik **Grant admin consent** als dat nog niet gedaan is.

### 1.5 Optioneel: toegang beperken

- **Enterprise applications** → OdionChat → **Properties** → **User assignment required:** Yes
- Wijs een security group toe (bijv. `OdionChat-Users`)

### Checkpoint Fase 1

- [ ] Client ID, Client Secret en Tenant ID genoteerd
- [ ] Redirect URI is exact: `https://chat.odion.nl/oauth/microsoft/callback`
- [ ] Admin consent gegeven
- [ ] Email claim geconfigureerd

---

## Fase 2 — Azure AI Foundry

OdionChat praat via het OpenAI-compatible endpoint in `docker-compose.yml` (`OPENAI_API_BASE_URLS` + `AZURE_OPENAI_API_KEY`).

### 2.1 Foundry-resource aanmaken

1. Azure Portal → **Azure AI Foundry** (of maak een **Azure OpenAI**-resource aan binnen Foundry)
2. Maak een project + resource aan in de gekozen regio (bijv. `westeurope`)
3. Noteer de resourcenaam — het endpoint wordt:

```
https://<resource-name>.openai.azure.com/openai/v1/
```

### 2.2 Model deployments aanmaken

In het Foundry-portaal → **Deployments**, maak deployments aan:

| Deployment name | Model (voorbeeld) | OdionChat rol |
|-----------------|-------------------|---------------|
| `odionchat-fast` | GPT-4.1-mini | OdionChat Snel |
| `odionchat-pro` | GPT-4.1 | OdionChat Nadenken |

De **deployment name** is wat Open WebUI als model-ID gebruikt (niet de onderliggende modelnaam).

### 2.3 API key ophalen

1. Foundry / Azure OpenAI resource → **Keys and Endpoint**
2. Kopieer **Key 1** (of Key 2)
3. Bewaar in Key Vault (Fase 4)

### 2.4 Test de verbinding

```bash
curl "https://<resource-name>.openai.azure.com/openai/v1/chat/completions" \
  -H "api-key: $AZURE_OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "odionchat-fast",
    "messages": [{"role": "user", "content": "Hallo"}]
  }'
```

### 2.5 Netwerk

Container Apps maakt outbound HTTPS-verbindingen naar het publieke Foundry-endpoint. Geen VNet, private endpoints of netwerkintegratie nodig.

### Checkpoint Fase 2

- [ ] Resource aangemaakt en endpoint genoteerd
- [ ] Minimaal twee model deployments actief
- [ ] API key opgehaald en getest
- [ ] Quota/rate limits gecontroleerd

---

## Fase 3 — Container hosting + domein

### 3.1 Basisinfrastructuur aanmaken

Maak in resource group `rg-odionchat-prod` aan:

1. **Log Analytics workspace** (`law-odionchat-prod`)
2. **Container Apps Environment** (`cae-odionchat-prod`) — standaard zonder VNet
3. **Key Vault** (`kv-odionchat-prod`)
4. **Azure Container Registry** (`acrodionchat`) — aanbevolen voor productie

### 3.2 Container image bouwen en deployen

OdionChat draait op de upstream Open WebUI-image met aangepaste config via `entrypoint.sh`. Bouw een custom image op basis van de gepinde image uit `docker-compose.yml`:

```dockerfile
FROM ghcr.io/open-webui/open-webui@sha256:60fa63e738e7dc5e548f26a54d6deac684d6712256a7fae91dd6157ce64bef84
COPY config/ /config/
COPY scripts/entrypoint.sh /entrypoint.sh
ENTRYPOINT ["bash", "/entrypoint.sh"]
```

Push naar Azure Container Registry en deploy als Container App.

### 3.3 Container App configureren

Maak Container App `odionchat` aan met:

| Setting | Waarde |
|---------|--------|
| Ingress | External, HTTPS |
| Target port | `8080` |
| Min replicas | `1` |
| CPU / Memory | min. 1 vCPU / 2 GiB |
| Health probe | `GET /health` op port 8080 |

### 3.4 Custom domain + TLS

1. Container App → **Custom domains** → voeg `chat.odion.nl` toe
2. Azure toont een **validatie-CNAME** — voeg die toe in DNS voor `odion.nl`
3. Schakel **managed certificate** in (gratis, auto-renewal)
4. Voeg productie-CNAME toe:

```
chat.odion.nl  →  CNAME  →  <container-app-fqdn>
```

### Checkpoint Fase 3

- [ ] Container draait en `/health` retourneert 200
- [ ] `https://chat.odion.nl` bereikbaar via HTTPS
- [ ] Managed certificate actief

---

## Fase 4 — Omgevingsvariabelen configureren

Configureer secrets in Key Vault en koppel ze als environment variables aan de Container App.

### 4.1 Authenticatie (algemeen)

```env
WEBUI_AUTH=true
ENABLE_SIGNUP=false
WEBUI_SECRET_KEY=<random-64-karakter-secret>
WEBUI_SESSION_COOKIE_SAME_SITE=lax
WEBUI_SESSION_COOKIE_SECURE=true
WEBUI_NAME=OdionChat
```

### 4.2 Microsoft Entra ID SSO

```env
MICROSOFT_CLIENT_ID=<application-client-id>
MICROSOFT_CLIENT_SECRET=<client-secret-value>
MICROSOFT_CLIENT_TENANT_ID=<directory-tenant-id>
MICROSOFT_OAUTH_SCOPE=openid email profile offline_access
MICROSOFT_REDIRECT_URI=https://chat.odion.nl/oauth/microsoft/callback
OPENID_PROVIDER_URL=https://login.microsoftonline.com/<directory-tenant-id>/v2.0/.well-known/openid-configuration
```

### 4.3 Azure AI Foundry (LLM backend)

```env
OPENAI_API_BASE_URLS=https://<resource-name>.openai.azure.com/openai/v1/
AZURE_OPENAI_API_KEY=<foundry-api-key>
```

`docker-compose.yml` mapt `AZURE_OPENAI_API_KEY` naar `OPENAI_API_KEYS` in de container.

### 4.4 OAuth signup inschakelen

In productie moet `ENABLE_OAUTH_SIGNUP=true` staan zodat Entra-gebruikers automatisch een account krijgen. De huidige `docker-compose.yml` heeft dit op `false`; pas dit aan voor Azure.

```env
ENABLE_OAUTH_SIGNUP=true
```

`ENABLE_SIGNUP=false` blokkeert alleen e-mail/wachtwoord-registratie — dat is gewenst.

### 4.5 Feature lockdown (behouden uit docker-compose.yml)

Deze instellingen staan al in `docker-compose.yml` en moeten ook op Azure actief blijven:

```env
ENABLE_CODE_INTERPRETER=false
ENABLE_IMAGE_GENERATION=false
ENABLE_RAG_WEB_SEARCH=false
ENABLE_RAG_LOCAL_WEB_FETCH=false
ENABLE_RAG_HYBRID_SEARCH=false
ENABLE_COMMUNITY_SHARING=false
ENABLE_MESSAGE_RATING=false
ENABLE_EVALUATION_ARENA_MODELS=false
ENABLE_CHANNELS=false
ENABLE_API_KEY=false
ENABLE_DIRECT_CONNECTIONS=false
ENABLE_FORWARD_USER_INFO_HEADERS=false
ENABLE_ADMIN_CHAT_ACCESS=false
ENABLE_OLLAMA_API=false
ENABLE_VERSION_UPDATE_CHECK=false
```

### 4.6 Secrets veilig injecteren

Bewaar in Key Vault:

| Secret | Gebruik |
|--------|---------|
| `MICROSOFT-CLIENT-SECRET` | Entra SSO |
| `OPENAI-API-KEY` | Azure AI Foundry |
| `WEBUI-SECRET-KEY` | JWT signing |
| `DATABASE-URL` | PostgreSQL (optioneel) |

Koppel Key Vault-secrets als environment variables in de Container App.

### 4.7 Container App bijwerken

Na wijzigingen aan env vars of image:

```bash
az containerapp update --name odionchat --resource-group rg-odionchat-prod
```

### Checkpoint Fase 4

- [ ] Alle env vars geconfigureerd
- [ ] `ENABLE_OAUTH_SIGNUP=true`
- [ ] Incognito: "Sign in with Microsoft" zichtbaar
- [ ] Login met Odion-account werkt
- [ ] Chat met Azure-modellen werkt
- [ ] Modellen en suggesties geconfigureerd via patch-locale.sh

---

## Fase 5 (Optioneel) — Persistent state met Azure PostgreSQL

Standaard slaat OdionChat alles op in SQLite (`./data/webui.db`). Voor productie-resilience is Azure PostgreSQL aanbevolen.

### 5.1 PostgreSQL Flexible Server aanmaken

1. Azure Portal → **Azure Database for PostgreSQL flexible servers**
2. Naam: `psql-odionchat-prod`
3. SKU: `Burstable B1ms` voor pilot, opschalen voor productie
4. Inschakelen:
   - **Public access** (geen VNet-integratie)
   - SSL verplicht
   - Automatische backups (7–35 dagen, afhankelijk van beleid)
   - Firewall: sta verkeer van Azure-services toe, of voeg de outbound IP's van de Container Apps Environment toe

### 5.2 Database en gebruiker aanmaken

```sql
CREATE DATABASE odionchat;
CREATE USER odionchat_app WITH PASSWORD '<sterk-wachtwoord>';
GRANT ALL PRIVILEGES ON DATABASE odionchat TO odionchat_app;
```

### 5.3 Open WebUI configureren

Open WebUI ondersteunt PostgreSQL via `DATABASE_URL`:

```env
DATABASE_URL=postgresql://odionchat_app:<wachtwoord>@psql-odionchat-prod.postgres.database.azure.com:5432/odionchat?sslmode=require
```

Bij gebruik van PostgreSQL is de SQLite-volume niet meer nodig voor users/chats/settings. Houd wel persistent storage voor:

- `uploads/` — gebruikersbestanden
- `cache/` — embedding cache
- `vector_db/` — alleen relevant als RAG later wordt ingeschakeld

### 5.4 Bestandsopslag voor uploads

| Optie | Wanneer |
|-------|---------|
| **Azure Files** mount | Mount op `/app/backend/data` via Container Apps storage |
| **Azure Blob** + S3-compatible storage | Als je later Open WebUI blob storage configureert |

Koppel Azure Files in de Container App onder **Storage** → mount op `/app/backend/data`.

### 5.5 Migratie van bestaande SQLite-data

Als er bestaande chats/users zijn om te behouden:

1. Stop de container
2. Maak backup: `tar czf odionchat-backup-$(date +%Y%m%d).tar.gz data/webui.db`
3. Volg de Open WebUI database-migratie: https://docs.openwebui.com/tutorials/maintenance/database
4. Start met `DATABASE_URL` gezet — Open WebUI draait Alembic-migraties bij boot

### Checkpoint Fase 5

- [ ] PostgreSQL draait en bereikbaar vanuit container
- [ ] `DATABASE_URL` geconfigureerd
- [ ] Data overleeft container restart
- [ ] Backups geconfigureerd
- [ ] Uploads op persistent storage

---

## Fase 6 — Hardening & go-live

### Checklist

| Item | Actie |
|------|-------|
| Signup | `ENABLE_SIGNUP=false`, `ENABLE_OAUTH_SIGNUP=true` |
| Cookies | `WEBUI_SESSION_COOKIE_SECURE=true` |
| Admin | Eerste Entra-gebruiker promoveren via Admin Panel, of bootstrap via `WEBUI_ADMIN_EMAIL` |
| Secret rotation | Key Vault + kalenderherinnering Entra secret expiry |
| Monitoring | Container Apps logs → Log Analytics; alert op health check failures |
| Backup | Postgres automated backups + periodieke export van uploads |
| Privacy/DPIA | Documenteer dat chatcontent naar Azure AI Foundry gaat |
| Branding | `entrypoint.sh` patcht CSS/locale automatisch bij boot |
| Updates | Volg update-ritueel in `docs/openwebui-reference.md` vóór image upgrade |

### Testplan

1. Open `https://chat.odion.nl` in incognito
2. Klik "Sign in with Microsoft"
3. Log in met Odion-account
4. Controleer dat e-mailadres correct is overgenomen
5. Start een chat met "OdionChat Snel"
6. Start een chat met "OdionChat Nadenken"
7. Controleer Odion branding (logo, paars, Nederlandse UI)
8. Herstart container → sessie/data intact
9. Test met niet-toegewezen account (indien user assignment required)

---

## Uitvoeringsvolgorde (voor Rick/IT)

| Stap | Wie | Geschatte tijd |
|------|-----|----------------|
| 1. Entra app registration + redirect URI | IT / Rick | ~1 uur |
| 2. Foundry resource + deployments + API key | IT / Rick | ~2 uur |
| 3. Azure infra (RG, Key Vault, Container Apps, DNS) | IT / DevOps | ~halve dag |
| 4. Container deployen + env vars | Dev | ~2 uur |
| 5. SSO + chat testen | Dev + pilotgebruiker | ~1 uur |
| 6. (Optioneel) PostgreSQL + migratie | Dev + IT | ~halve dag |
| 7. patch-locale.sh + UAT | Dev | ~1 uur |

---

## Repo-wijzigingen bij implementatie

Bij de overstap van plan naar implementatie zijn waarschijnlijk deze aanpassingen nodig:

1. **`docker-compose.yml`** — `ENABLE_OAUTH_SIGNUP=true`; `WEBUI_SESSION_COOKIE_SECURE=true` voor prod
2. **`scripts/patch-locale.sh`** — modelnamen wijzigen naar Azure deployment names
3. **`.env.example`** — Entra + Azure OpenAI + optionele `DATABASE_URL` documenteren
4. **Optioneel:** Bicep/Terraform voor Container Apps deploy pipeline

---

## Troubleshooting

| Probleem | Diagnose | Oplossing |
|----------|----------|-----------|
| SSO-knop niet zichtbaar | Container logs | Controleer `MICROSOFT_*` env vars |
| Redirect URI mismatch | Entra app registration | URI moet exact `https://chat.odion.nl/oauth/microsoft/callback` zijn |
| 401 bij chat | Foundry logs / curl test | Controleer API key en deployment name |
| Gebruiker kan niet inloggen via SSO | `ENABLE_OAUTH_SIGNUP` | Zet op `true` |
| Geen email na SSO | Entra token config | Voeg email optional claim toe (Fase 1.3) |
| Branding/locale werkt niet | Container logs bij boot | Check of `entrypoint.sh` draait |
| Data verdwenen na restart | Storage config | Controleer volume mount of `DATABASE_URL` |
| 502 / timeout | Container App metrics | Verhoog memory; check health probe op port 8080 |
| Eerste boot duurt lang | Container logs | Embeddings download (3–5 min) is normaal |

## Logs bekijken

```bash
az containerapp logs show --name odionchat --resource-group rg-odionchat-prod --follow
```

## Backup

```bash
# SQLite op Azure Files (zonder PostgreSQL)
# Kopieer webui.db van de gemounte Azure Files share

# PostgreSQL
pg_dump "postgresql://odionchat_app@psql-odionchat-prod.postgres.database.azure.com/odionchat?sslmode=require" \
  > odionchat-$(date +%Y%m%d).sql
```

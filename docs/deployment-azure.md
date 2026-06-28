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

- `docs/env-vars.md` — **`az containerapp update`** met alle env vars
- `docs/deployment-azure-storage.md` — persistente data (Azure Files)
- `docs/deployment-old.md` — VPS-deployment (legacy)
- `docs/architectuur.md` — architectuurkeuzes

## Stap-voor-stap overzicht

| Stap | Wat | Waar in deze handleiding |
|------|-----|--------------------------|
| 1 | Variabelen en regio kiezen | [Fase 0](#fase-0--beslissingen-vooraf) |
| 2 | Entra app registration + client secret | [Fase 1](#fase-1--microsoft-entra-id-sso) |
| 3 | Alleen toegewezen Odion-gebruikers toestaan | [Fase 1.5](#15-toegang-beperken-tot-ingelogde-gebruikers) |
| 4 | Azure AI Foundry resource + model deployments | [Fase 2](#fase-2--azure-ai-foundry-endpoint) |
| 5 | Azure infrastructuur (RG, logs, Container Apps) | [Fase 3](#fase-3--container-app-deployen) |
| 6 | Container image deployen | [Fase 3.2](#32-container-image-deployen) |
| 7 | Omgevingsvariabelen | [env-vars.md](env-vars.md) |
| 8 | Custom domain + TLS | [Fase 3.4](#34-custom-domain--tls) |
| 9 | Persistente storage (Azure Files) | [deployment-azure-storage.md](deployment-azure-storage.md) |
| 10 | Testen en go-live | [Fase 6](#fase-6--hardening--go-live) |

**Productie-image:** `ghcr.io/manavanl/odionchat:latest` (poort **8080**).

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

Stel onderstaande shell-variabelen in voor de rest van deze handleiding (pas waarden aan):

```bash
export LOCATION=westeurope
export RESOURCE_GROUP=rg-odionchat-prod
export CONTAINER_APP=odionchat
export CONTAINER_ENV=cae-odionchat-prod
export LOG_ANALYTICS=law-odionchat-prod
export KEY_VAULT=kv-odionchat-prod
export CUSTOM_DOMAIN=chat.odion.nl
export WEBUI_URL=https://chat.odion.nl
export IMAGE=ghcr.io/manavanl/odionchat:latest
```

Installeer de Azure CLI en log in:

```bash
az login
az account set --subscription "<subscription-id-of-name>"
```

---

## Fase 1 — Microsoft Entra ID (SSO)

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

### 1.5 Toegang beperken tot ingelogde gebruikers

OdionChat heeft **twee lagen** nodig: Entra bepaalt *wie* mag inloggen; Open WebUI dwingt af dat *alle* gebruikers ingelogd zijn.

#### Entra (wie mag de app openen)

1. Ga naar **Microsoft Entra ID** → **Enterprise applications** → **OdionChat**
2. **Properties** → zet **User assignment required?** op **Yes**
3. **Users and groups** → **Add user/group** → wijs een security group toe (bijv. `OdionChat-Users`)

Gebruikers die niet aan de app zijn toegewezen, zien na "Sign in with Microsoft" een Entra-foutmelding — ze komen de app niet in.

#### Open WebUI (login altijd verplicht)

Deze variabelen staan in [Fase 4](#fase-4--omgevingsvariabelen-configureren) en worden op de Container App gezet:

| Variabele | Waarde | Effect |
|-----------|--------|--------|
| `WEBUI_AUTH` | `true` | Geen anonieme toegang |
| `ENABLE_SIGNUP` | `false` | Geen e-mail/wachtwoord-registratie |
| `ENABLE_OAUTH_SIGNUP` | `true` | Entra-gebruikers krijgen bij eerste login automatisch een account |
| `ENABLE_LOGIN_FORM` | `false` | Alleen "Sign in with Microsoft", geen wachtwoordformulier |
| `WEBUI_URL` | `https://chat.odion.nl` | Correcte OAuth redirect URI's |

`ENABLE_OAUTH_SIGNUP=true` betekent **niet** dat iedereen zichzelf kan aanmelden — alleen gebruikers die Entra al heeft goedgekeurd (stap 1–3 hierboven) kunnen via SSO binnenkomen.

### 1.6 Client secret veilig opslaan

Bewaar het client secret direct in Key Vault (kan ook na Fase 3):

```bash
az keyvault secret set \
  --vault-name "$KEY_VAULT" \
  --name MICROSOFT-CLIENT-SECRET \
  --value "<client-secret-value>"
```

Noteer ook Client ID en Tenant ID — die zijn geen secrets en kunnen als gewone env vars op de Container App.

### Checkpoint Fase 1

- [ ] Client ID, Client Secret en Tenant ID genoteerd
- [ ] Redirect URI is exact: `https://chat.odion.nl/oauth/microsoft/callback`
- [ ] Admin consent gegeven
- [ ] Email claim geconfigureerd

---

## Fase 2 — Azure AI Foundry endpoint

OdionChat praat via het OpenAI-compatible v1-endpoint van Azure AI Foundry. In Open WebUI heet dat `OPENAI_API_BASE_URLS` + `OPENAI_API_KEYS` (zie `.env.example`).

### 2.1 Foundry-resource aanmaken

**Via Azure Portal:**

1. Ga naar [Azure AI Foundry](https://ai.azure.com) of Azure Portal → **Create a resource** → **Azure OpenAI**
2. Maak een resource aan in dezelfde regio als de Container App (bijv. `westeurope`)
3. Open de resource → **Keys and Endpoint** → noteer:
   - **Endpoint** (basis-URL)
   - **Key 1**

Het endpoint voor OdionChat moet eindigen op `/openai/v1/`:

```
https://<resource-name>.openai.azure.com/openai/v1/
```

Voorbeeld met resourcenaam `aoai-odionchat-prod`:

```bash
export FOUNDRY_ENDPOINT="https://aoai-odionchat-prod.openai.azure.com/openai/v1/"
export FOUNDRY_API_KEY="<key-1-from-portal>"
```

### 2.2 Model deployments aanmaken

In het Foundry-portaal → **Deployments**, maak deployments aan:

| Deployment name | Model (voorbeeld) | OdionChat rol |
|-----------------|-------------------|---------------|
| `odionchat-fast` | GPT-4.1-mini | OdionChat Snel |
| `odionchat-pro` | GPT-4.1 | OdionChat Nadenken |

De **deployment name** is wat Open WebUI als model-ID gebruikt (niet de onderliggende modelnaam).

### 2.3 API key ophalen en opslaan

1. Foundry / Azure OpenAI resource → **Keys and Endpoint**
2. Kopieer **Key 1** (of Key 2)
3. Bewaar in Key Vault:

```bash
az keyvault secret set \
  --vault-name "$KEY_VAULT" \
  --name OPENAI-API-KEY \
  --value "$FOUNDRY_API_KEY"
```

### 2.4 Test de verbinding

```bash
curl "$FOUNDRY_ENDPOINT/chat/completions" \
  -H "api-key: $FOUNDRY_API_KEY" \
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

## Fase 3 — Container App deployen

### 3.1 Resource group + basisinfrastructuur

```bash
# Resource group
az group create --name "$RESOURCE_GROUP" --location "$LOCATION"

# Log Analytics (voor Container Apps logs)
az monitor log-analytics workspace create \
  --resource-group "$RESOURCE_GROUP" \
  --workspace-name "$LOG_ANALYTICS"

LOG_ANALYTICS_ID=$(az monitor log-analytics workspace show \
  --resource-group "$RESOURCE_GROUP" \
  --workspace-name "$LOG_ANALYTICS" \
  --query customerId -o tsv)

LOG_ANALYTICS_KEY=$(az monitor log-analytics workspace get-shared-keys \
  --resource-group "$RESOURCE_GROUP" \
  --workspace-name "$LOG_ANALYTICS" \
  --query primarySharedKey -o tsv)

# Container Apps Environment (publiek, geen VNet)
az containerapp env create \
  --name "$CONTAINER_ENV" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --logs-workspace-id "$LOG_ANALYTICS_ID" \
  --logs-workspace-key "$LOG_ANALYTICS_KEY"

# Key Vault voor secrets
az keyvault create \
  --name "$KEY_VAULT" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --enable-rbac-authorization true
```

> **Optioneel:** eigen Azure Container Registry (`acrodionchat`) als je niet de GHCR-image wilt gebruiken. CI publiceert naar `ghcr.io/manavanl/odionchat:latest` — dat is de aanbevolen productie-image.

### 3.2 Container image deployen

OdionChat is een custom Open WebUI-image met Odion-branding (gebakken tijdens `docker build`, zie `Dockerfile`).

**Optie A — GHCR-image (aanbevolen):**

De image wordt automatisch gebouwd bij push naar `main` (`.github/workflows/docker-publish.yml`).

```bash
export IMAGE=ghcr.io/manavanl/odionchat:latest
```

**Optie B — zelf bouwen en pushen:**

```bash
docker build -t ghcr.io/manavanl/odionchat:local .
docker push ghcr.io/manavanl/odionchat:local
export IMAGE=ghcr.io/manavanl/odionchat:local
```

### 3.3 Container App aanmaken

Genereer een `WEBUI_SECRET_KEY` en maak de Container App aan. Configureer daarna alle env vars via **[env-vars.md](env-vars.md)**.

Minimale aanmaak (alleen health check; configureer daarna env vars):

```bash
export WEBUI_SECRET_KEY=$(openssl rand -hex 32)

az containerapp create \
  --name "$CONTAINER_APP" \
  --resource-group "$RESOURCE_GROUP" \
  --environment "$CONTAINER_ENV" \
  --image "$IMAGE" \
  --target-port 8080 \
  --ingress external \
  --min-replicas 1 \
  --max-replicas 1 \
  --cpu 1.0 \
  --memory 2.0Gi \
  --env-vars \
    PORT=8080 \
    WEBUI_NAME=OdionChat \
    WEBUI_AUTH=true \
    ENABLE_SIGNUP=false
```

Configureer env vars: [env-vars.md](env-vars.md).

Noteer de FQDN:

```bash
az containerapp show \
  --name "$CONTAINER_APP" \
  --resource-group "$RESOURCE_GROUP" \
  --query properties.configuration.ingress.fqdn -o tsv
```

Test de health check (vervang `<fqdn>`):

```bash
curl -sf "https://<fqdn>/health"
```

**Portal-alternatief:** Azure Portal → **Container Apps** → **Create** → kies de environment, image `ghcr.io/manavanl/odionchat:latest`, ingress **Accepting traffic from anywhere**, target port **8080**, min replicas **1**.

| Setting | Waarde |
|---------|--------|
| Ingress | External, HTTPS |
| Target port | `8080` |
| Min replicas | `1` |
| CPU / Memory | min. 1 vCPU / 2 GiB |
| Health probe | `GET /health` op port 8080 |

### 3.4 Custom domain + TLS

**Via Azure Portal:**

1. Container App → **Custom domains** → **Add** → voeg `chat.odion.nl` toe
2. Azure toont een **validatie-CNAME** — voeg die toe in DNS voor `odion.nl`
3. Schakel **managed certificate** in (gratis, auto-renewal)
4. Voeg productie-CNAME toe:

```
chat.odion.nl  →  CNAME  →  <container-app-fqdn>
```

**Via Azure CLI:**

```bash
az containerapp hostname add \
  --hostname "$CUSTOM_DOMAIN" \
  --name "$CONTAINER_APP" \
  --resource-group "$RESOURCE_GROUP"

# Managed certificate (Portal: Custom domains → Bind certificate → Managed)
az containerapp hostname bind \
  --hostname "$CUSTOM_DOMAIN" \
  --name "$CONTAINER_APP" \
  --resource-group "$RESOURCE_GROUP" \
  --environment "$CONTAINER_ENV" \
  --validation-method CNAME
```

Wacht tot DNS is gepropageerd en het managed certificate actief is. Test daarna:

```bash
curl -sf "https://$CUSTOM_DOMAIN/health"
```

> **Belangrijk:** pas pas na het activeren van het custom domain de Entra redirect URI en `WEBUI_URL` / `MICROSOFT_REDIRECT_URI` aan (Fase 4). Tijdens eerste tests kun je tijdelijk de Container App FQDN gebruiken, maar productie vereist exact `https://chat.odion.nl/oauth/microsoft/callback`.

### Checkpoint Fase 3

- [ ] Container draait en `/health` retourneert 200
- [ ] `https://chat.odion.nl` bereikbaar via HTTPS
- [ ] Managed certificate actief

---

## Fase 4 — Omgevingsvariabelen configureren

Run het script uit **[env-vars.md](env-vars.md)** (`az containerapp secret set` + `az containerapp update`).

**Portal-alternatief:** Container App → **Containers** → **Edit and deploy** → tab **Environment variables**. Voeg secrets toe onder **Secrets**, koppel ze met `secretref:<naam>`.

### 4.1 Wat elke groep doet

#### Authenticatie (alleen ingelogde gebruikers)

```env
WEBUI_AUTH=true
ENABLE_SIGNUP=false
ENABLE_OAUTH_SIGNUP=true
ENABLE_LOGIN_FORM=false
WEBUI_URL=https://chat.odion.nl
WEBUI_SECRET_KEY=<random-64-karakter-secret>
WEBUI_SESSION_COOKIE_SAME_SITE=lax
WEBUI_SESSION_COOKIE_SECURE=true
WEBUI_NAME=OdionChat
ENABLE_OAUTH_PERSISTENT_CONFIG=false
```

- `WEBUI_AUTH=true` — niemand gebruikt de app zonder login
- `ENABLE_SIGNUP=false` — geen open registratie met e-mail/wachtwoord
- `ENABLE_OAUTH_SIGNUP=true` — Entra-gebruikers krijgen bij eerste SSO-login een account (combineer met Entra user assignment)
- `ENABLE_LOGIN_FORM=false` — verberg het wachtwoordformulier; alleen Microsoft-knop
- `ENABLE_OAUTH_PERSISTENT_CONFIG=false` — lees OAuth-instellingen altijd uit env vars (belangrijk bij Container Apps)

#### Microsoft Entra ID SSO

```env
MICROSOFT_CLIENT_ID=<application-client-id>
MICROSOFT_CLIENT_SECRET=<client-secret-value>
MICROSOFT_CLIENT_TENANT_ID=<directory-tenant-id>
MICROSOFT_OAUTH_SCOPE=openid email profile offline_access
MICROSOFT_REDIRECT_URI=https://chat.odion.nl/oauth/microsoft/callback
OPENID_PROVIDER_URL=https://login.microsoftonline.com/<directory-tenant-id>/v2.0/.well-known/openid-configuration
```

De redirect URI moet **exact** overeenkomen met Entra (Fase 1.1) en met `WEBUI_URL`.

#### Azure AI Foundry (LLM backend)

```env
OPENAI_API_BASE_URLS=https://<resource-name>.openai.azure.com/openai/v1/
OPENAI_API_KEYS=<foundry-api-key>
AZURE_DEPLOYMENT_FAST=odionchat-fast
AZURE_DEPLOYMENT_PRO=odionchat-pro
```

De deployment names (`AZURE_DEPLOYMENT_*`) moeten overeenkomen met de namen in Foundry (Fase 2.2).

#### Feature lockdown

Deze instellingen staan ook in `.env.example` en staan in [env-vars.md](env-vars.md).

### 4.2 Container App herstarten na wijzigingen

```bash
az containerapp update \
  --name "$CONTAINER_APP" \
  --resource-group "$RESOURCE_GROUP"
```

Of in Portal: **Revision management** → nieuwe revision wordt automatisch aangemaakt bij env-wijzigingen.

### Checkpoint Fase 4

- [ ] Alle env vars geconfigureerd (Foundry + Entra + auth lockdown)
- [ ] `WEBUI_AUTH=true`, `ENABLE_SIGNUP=false`, `ENABLE_OAUTH_SIGNUP=true`
- [ ] `ENABLE_LOGIN_FORM=false` (alleen Microsoft-login)
- [ ] Entra user assignment required + security group toegewezen
- [ ] Incognito: "Sign in with Microsoft" zichtbaar, geen signup-formulier
- [ ] Login met Odion-account werkt
- [ ] Chat met Azure-modellen werkt (OdionChat Snel / Nadenken)

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
| Signup | `ENABLE_SIGNUP=false`, `ENABLE_OAUTH_SIGNUP=true`, `ENABLE_LOGIN_FORM=false` |
| Entra toegang | User assignment required + security group |
| Cookies | `WEBUI_SESSION_COOKIE_SECURE=true` |
| Publieke URL | `WEBUI_URL=https://chat.odion.nl` |
| Admin | Eerste Entra-gebruiker promoveren via Admin Panel, of bootstrap via `WEBUI_ADMIN_EMAIL` |
| Secret rotation | Key Vault + kalenderherinnering Entra secret expiry |
| Monitoring | Container Apps logs → Log Analytics; alert op health check failures |
| Backup | Postgres automated backups + periodieke export van uploads |
| Privacy/DPIA | Documenteer dat chatcontent naar Azure AI Foundry gaat |
| Branding | Odion CSS/locale zit in de Docker image (`Dockerfile` + `patch.sh`) |
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
9. Test met niet-toegewezen account → Entra weigert toegang
10. Test anoniem browsen → redirect naar login, geen chat zonder SSO

---

## Repo-wijzigingen bij implementatie

Bij de overstap van plan naar implementatie zijn waarschijnlijk deze aanpassingen nodig:

1. **`.env.example`** — Entra-variabelen + `WEBUI_URL` documenteren voor productie
2. **`scripts/patch.sh`** — eventueel modelnamen/suggesties uitbreiden (WIP)
3. **Optioneel:** Bicep/Terraform voor Container Apps deploy pipeline

---

## Troubleshooting

| Probleem | Diagnose | Oplossing |
|----------|----------|-----------|
| SSO-knop niet zichtbaar | Container logs | Controleer `MICROSOFT_*` env vars |
| Redirect URI mismatch | Entra app registration | URI moet exact `https://chat.odion.nl/oauth/microsoft/callback` zijn |
| 401 bij chat | Foundry logs / curl test | Controleer `OPENAI_API_KEYS` en `OPENAI_API_BASE_URLS` |
| Gebruiker kan niet inloggen via SSO | `ENABLE_OAUTH_SIGNUP` | Zet op `true` |
| Wachtwoordformulier nog zichtbaar | `ENABLE_LOGIN_FORM` | Zet op `false` |
| OAuth-instellingen lijken oud | `ENABLE_OAUTH_PERSISTENT_CONFIG` | Zet op `false` of wis DB |
| Geen email na SSO | Entra token config | Voeg email optional claim toe (Fase 1.3) |
| Branding/locale werkt niet | Image rebuild | Branding zit in image — rebuild en redeploy |
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

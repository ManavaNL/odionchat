---
date: 2026-06-02
description: "Vereiste kennis, rechten en vaardigheden voor wie OdionChat volgens deployment-azure.md in Azure installeert."
---

# OdionChat — Profiel Azure-installateur

Dit document beschrijft welke **mogelijkheden** iemand moet hebben om OdionChat op Azure te installeren en in productie te brengen, op basis van [deployment-azure.md](deployment-azure.md).

Het is bedoeld voor IT-beheer, cloud engineers of DevOps die de rollout uitvoeren of de rol uitbesteden.

## Samenvatting

De installateur is een **praktisch Azure-beheerder** met basiskennis van identity (Entra ID), containers, DNS en GitHub. Die persoon hoeft geen softwareontwikkelaar te zijn, maar moet wel comfortabel zijn met de Azure Portal, Azure CLI, de OdionChat-repository op GitHub en het debuggen van configuratie via logs en HTTP-tests.

De deployment in deze handleiding is **publiek HTTPS zonder VNet** — geen diepgaande netwerkarchitectuur of Infrastructure-as-Code is verplicht voor de eerste installatie.

---

## Vereiste toegang en rollen

Zonder onderstaande rechten kan de installatie niet worden afgerond:

| Domein | Minimale toegang |
|--------|------------------|
| Azure | **Contributor** op de doel-resource group (of subscription) |
| Microsoft Entra ID | Rechten om **App registrations** aan te maken en te configureren (bijv. Application Administrator) |
| DNS | Beheer van het domein (bijv. `odion.nl`) — CNAME-records voor validatie en productie |
| Azure AI Foundry | Toegang om een Azure OpenAI / Foundry-resource aan te maken, model deployments te doen en API-keys te lezen |
| Secrets | Mogelijkheid om client secrets en API-keys veilig op te slaan (Key Vault en/of Container App secrets) |
| GitHub | **Leestoegang** tot de OdionChat-repository (documentatie, `.env.example`, workflow-status) |

Optioneel, maar handig:

- Push-rechten naar **GitHub Container Registry (GHCR)** of Azure Container Registry als een eigen image wordt gebouwd
- Rechten op PostgreSQL Flexible Server en Azure Files bij persistente state

---

## Kerncompetenties per domein

### 1. Azure-platform (basis tot gevorderd)

De installateur moet kunnen:

- Een **resource group** aanmaken en resources in een gekozen regio (bijv. `westeurope`) plaatsen
- **Azure Container Apps** deployen: environment, ingress (external HTTPS), target port, replicas, CPU/memory
- **Log Analytics** koppelen voor containerlogs
- **Azure Key Vault** aanmaken en secrets opslaan (RBAC-modus)
- Optioneel: **Azure Database for PostgreSQL Flexible Server**, firewallregels en SSL
- Optioneel: **Azure Files** mounten op een Container App voor persistente uploads/cache
- Container App **revisions** begrijpen en na env-wijzigingen een nieuwe revision laten uitrollen
- Logs lezen via Portal of `az containerapp logs show`

**Niet vereist** voor deze handleiding: VNet-design, private endpoints, Application Gateway, of eigen load balancers.

### 2. Azure CLI en shell

De installateur moet kunnen:

- **Azure CLI** installeren, inloggen (`az login`) en de juiste subscription selecteren
- Shell-variabelen instellen en de commando's uit de handleiding uitvoeren
- Eenvoudige tools gebruiken: `curl`, `openssl rand`, optioneel `docker build` / `docker push`
- Optioneel: `pg_dump` voor PostgreSQL-backups

Basiskennis van bash/zsh is voldoende; geen programmeerervaring nodig.

### 3. Microsoft Entra ID (identity & SSO)

De installateur moet kunnen:

- Een **App registration** aanmaken (single tenant) met de juiste **redirect URI**
- Een **client secret** aanmaken, vervaldatum beheren en veilig opslaan
- **Token configuration** instellen (email claim in ID token)
- **API permissions** controleren en **admin consent** geven
- **Enterprise application** configureren: user assignment required, security group toewijzen
- Begrijpen dat redirect URI, `WEBUI_URL` en `MICROSOFT_REDIRECT_URI` **exact** moeten matchen

Basiskennis van **OAuth 2.0 / OpenID Connect** is nodig om SSO-problemen te diagnosticeren (redirect mismatch, ontbrekende claims).

### 4. Azure AI Foundry (LLM-backend)

De installateur moet kunnen:

- Een Foundry / Azure OpenAI-resource aanmaken in dezelfde regio als de app
- **Model deployments** aanmaken met de juiste deployment names (bijv. `odionchat-fast`, `odionchat-pro`)
- Endpoint-URL en API key noteren en testen met `curl` tegen `/chat/completions`
- Quota en rate limits controleren

Geen kennis van prompt engineering of model tuning vereist voor de installatie zelf.

### 5. DNS en TLS

De installateur moet kunnen:

- **CNAME-records** toevoegen voor domeinvalidatie en productie (`chat.odion.nl` → Container App FQDN)
- Wachten op DNS-propagatie en controleren of het **managed certificate** op de Container App actief is
- HTTPS-endpoints testen (`/health`)

Basiskennis van DNS (CNAME, TTL, propagatie) is vereist; geen eigen certificaatbeheer nodig (Azure managed certificates).

### 6. Applicatieconfiguratie (Open WebUI / OdionChat)

De installateur moet kunnen:

- **Omgevingsvariabelen** op een Container App zetten (Portal of `az containerapp update`)
- Gevoelige waarden als **Container App secrets** registreren en koppelen via `secretref:`
- Het onderscheid begrijpen tussen secrets (client secret, API key, `WEBUI_SECRET_KEY`) en gewone config (Client ID, Tenant ID, deployment names)
- De auth-lockdown instellen: `WEBUI_AUTH`, `ENABLE_SIGNUP`, `ENABLE_OAUTH_SIGNUP`, `ENABLE_LOGIN_FORM`
- Optioneel: `DATABASE_URL` voor PostgreSQL configureren

Lezen van `.env.example` in de repo helpt; die hoeft niet te worden aangepast voor Azure zelf.

### 7. Containers (basis)

De installateur moet kunnen:

- De **productie-image** gebruiken (`ghcr.io/manavanl/odionchat:latest`, poort **8080**)
- Health checks interpreteren (`GET /health`)
- Optioneel: lokaal `docker build` en push naar een registry

Geen Kubernetes- of Helm-kennis vereist (Container Apps abstraheert dat weg).

### 8. GitHub (basis)

De productie-image en documentatie komen uit GitHub. De installateur moet kunnen:

- De **repository clonen of in de browser openen** en bestanden vinden (`docs/`, `.env.example`, `Dockerfile`)
- **Documentatie lezen** in de repo (o.a. [deployment-azure.md](deployment-azure.md), [openwebui-reference.md](openwebui-reference.md))
- Begrijpen dat de aanbevolen image **`ghcr.io/manavanl/odionchat:latest`** via GitHub Actions wordt gebouwd bij push naar `main` (workflow: `.github/workflows/docker-publish.yml`)
- In GitHub **Actions** controleren of de laatste image-build geslaagd is vóór deploy of na een update
- Optioneel: inloggen op **GHCR** (`docker login ghcr.io`) als de image private is of bij zelf bouwen en pushen
- Optioneel: een **release tag** of specifieke image-tag kiezen i.p.v. `latest` voor gecontroleerde upgrades

**Niet vereist:** pull requests reviewen, branches mergen, GitHub Actions-workflows schrijven of het `gh` CLI gebruiken.

### 9. Beveiliging en operations (go-live)

De installateur moet kunnen:

- Secrets niet in plain text in git of chat plakken; Key Vault of Container App secrets gebruiken
- Een **testplan** uitvoeren: SSO, chat met beide modellen, geen anonieme toegang, geweigerde Entra-gebruikers
- Eerste admin bootstrappen (Admin Panel of `WEBUI_ADMIN_EMAIL`)
- Monitoring instellen (Log Analytics, alerts op health failures)
- Secret rotation plannen (Entra client secret verloopt)
- Backups begrijpen (PostgreSQL automated backups, eventueel SQLite/uploads)

Basiskennis van privacy/DPIA-documentatie is wenselijk (chatcontent gaat naar Azure AI Foundry).

---

## Ervaringsniveau

| Niveau | Passend? |
|--------|----------|
| **Junior cloud engineer** met begeleiding | Mogelijk, als Entra en DNS door een ervaren collega worden ondersteund |
| **Medior Azure-beheerder** | **Ideaal** — kan de handleiding zelfstandig doorlopen |
| **Senior platform engineer** | Ruim voldoende; optionele IaC (Bicep/Terraform) kan later worden toegevoegd |

Geschatte doorlooptijd voor iemand op medior-niveau: **één werkdag** (inclusief DNS-wachttijd en testen), exclusief optionele PostgreSQL en Azure Files.

---

## Wat de installateur niet hoeft te kunnen

- OdionChat- of Open WebUI-broncode aanpassen (branding zit in de Docker image)
- Kubernetes-clusters beheren
- VNet / private endpoint-architectuur ontwerpen (niet in scope van deze deployment)
- GitHub Actions-workflows schrijven of CI/CD-pipelines onderhouden (wel de status van builds kunnen lezen)
- Bicep, Terraform of ARM templates schrijven (optioneel voor latere automatisering)

---

## Checklist: ben ik de juiste persoon?

Gebruik deze korte self-check vóór start:

- [ ] Ik kan inloggen op Azure Portal en Azure CLI met de juiste subscription
- [ ] Ik mag App registrations aanmaken in Entra ID
- [ ] Ik kan CNAME-records wijzigen voor het productiedomein
- [ ] Ik kan een Azure OpenAI / Foundry-resource en deployments aanmaken
- [ ] Ik begrijp het verschil tussen redirect URI, `WEBUI_URL` en OAuth client secret
- [ ] Ik kan env vars en secrets op een Container App zetten en logs lezen bij fouten
- [ ] Ik kan met `curl` een health check en een chat completion testen
- [ ] Ik kan de OdionChat-repo op GitHub openen, documentatie vinden en de status van de image-build in Actions controleren

Als alle punten ja zijn, volg [deployment-azure.md](deployment-azure.md) stap voor stap.

---

## Gerelateerde documenten

- [deployment-azure.md](deployment-azure.md) — installatiehandleiding
- [architectuur.md](architectuur.md) — architectuurkeuzes
- [openwebui-reference.md](openwebui-reference.md) — update-ritueel vóór image upgrades

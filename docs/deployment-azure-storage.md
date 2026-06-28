---
date: 2026-06-28
description: "Persistente opslag voor OdionChat op Azure Container Apps via Azure Files (SQLite, uploads, cache)."
---

# OdionChat — Persistente storage op Azure Container Apps

## Probleem

Azure Container Apps gebruikt standaard **ephemeral storage**: alles wat de container schrijft naar het lokale bestandssysteem verdwijnt bij een nieuwe revision, restart of redeploy.

OdionChat (Open WebUI) slaat standaard alles op onder `/app/backend/data`:

| Bestand / map | Inhoud |
|---------------|--------|
| `webui.db` | SQLite-database (users, chats, instellingen) |
| `uploads/` | Geüploade bestanden |
| `cache/` | Embedding-cache |
| `vector_db/` | Vector store (bij RAG) |

Lokaal mount je `./data` op die map (`docker-compose.yml`). Op Azure Container Apps moet je hetzelfde doen met een **Azure Files** share — anders lijkt de database bij elke deploy opnieuw leeg.

> **Alternatief:** PostgreSQL voor de database (`DATABASE_URL`) + Azure Files alleen voor uploads/cache. Zie [deployment-azure.md § Fase 5](deployment-azure.md#fase-5-optioneel--persistent-state-met-azure-postgresql). Deze handleiding beschrijft de **SQLite + Azure Files**-route — eenvoudiger en voldoende voor de meeste OdionChat-deployments.

## Oplossing in het kort

```
Container App
  └── volume mount: /app/backend/data
        └── Azure Files share (SMB, persistent)
              └── webui.db, uploads/, cache/, …
```

Referentie: [Use storage mounts in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/storage-mounts?tabs=smb&pivots=azure-cli) (Microsoft Learn).

---

## Vereisten

- Bestaande Container Apps **environment** en **container app** (zie [deployment-azure.md](deployment-azure.md))
- Azure CLI ingelogd (`az login`)
- Shell-variabelen uit Fase 0:

```bash
export LOCATION=westeurope
export RESOURCE_GROUP=rg-odionchat-prod
export CONTAINER_APP=odionchat
export CONTAINER_ENV=cae-odionchat-prod
export STORAGE_ACCOUNT=stodionchatprod   # max 24 tekens, alleen lowercase + cijfers
export FILE_SHARE=odionchat-data
export ENV_STORAGE_NAME=odionchat-data   # logische naam in de Container Apps environment
```

Pas namen aan als `stodionchatprod` al bezet is (storage account names zijn wereldwijd uniek).

---

## Stap 1 — Storage account en file share aanmaken

```bash
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" 2>/dev/null || true

az storage account create \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --allow-blob-public-access false

STORAGE_KEY=$(az storage account keys list \
  --resource-group "$RESOURCE_GROUP" \
  --account-name "$STORAGE_ACCOUNT" \
  --query "[0].value" -o tsv)

az storage share-rm create \
  --resource-group "$RESOURCE_GROUP" \
  --storage-account "$STORAGE_ACCOUNT" \
  --name "$FILE_SHARE" \
  --quota 32 \
  --enabled-protocols SMB
```

**Quota:** 32 GiB is ruim voor SQLite + uploads bij pilot/productie-start. Schaal later op via Portal of CLI.

Bewaar `$STORAGE_KEY` ergens veilig (password manager, team secret store) — je hebt hem nodig bij key rotatie of als je de environment storage opnieuw moet registreren.

---

## Stap 2 — File share koppelen aan de Container Apps environment

Registreer de share op **environment-niveau** (niet op de app zelf):

```bash
az containerapp env storage set \
  --name "$CONTAINER_ENV" \
  --resource-group "$RESOURCE_GROUP" \
  --storage-name "$ENV_STORAGE_NAME" \
  --storage-type AzureFile \
  --azure-file-account-name "$STORAGE_ACCOUNT" \
  --azure-file-account-key "$STORAGE_KEY" \
  --azure-file-share-name "$FILE_SHARE" \
  --access-mode ReadWrite
```

Controleer:

```bash
az containerapp env storage list \
  --name "$CONTAINER_ENV" \
  --resource-group "$RESOURCE_GROUP" \
  -o table
```

---

## Stap 3 — Volume mount op de Container App

Azure Files mounts configureer je via een **volume** op de revision en een **volumeMount** op de container. Met Azure CLI gaat dat via YAML.

### 3.1 Huidige app-spec exporteren

```bash
az containerapp show \
  -n "$CONTAINER_APP" \
  -g "$RESOURCE_GROUP" \
  -o yaml > app.yaml
```

Maak een backup van `app.yaml` voordat je wijzigt.

### 3.2 Volume en mount toevoegen

Zoek in `app.yaml` onder `properties.template`:

1. Voeg bij de container (meestal `name: odionchat` of de enige container) een `volumeMounts`-sectie toe:

```yaml
volumeMounts:
  - volumeName: odionchat-data
    mountPath: /app/backend/data
```

2. Voeg op hetzelfde `template`-niveau (naast `containers`, `scale`, etc.) een `volumes`-array toe:

```yaml
volumes:
  - name: odionchat-data
    storageType: AzureFile
    storageName: odionchat-data
```

`storageName` moet exact overeenkomen met `ENV_STORAGE_NAME` uit stap 2.

**Minimaal voorbeeld** (jouw `app.yaml` heeft meer velden — alleen deze blokken toevoegen/aanvullen):

```yaml
properties:
  template:
    containers:
      - name: odionchat
        image: ghcr.io/manavanl/odionchat:latest
        volumeMounts:
          - volumeName: odionchat-data
            mountPath: /app/backend/data
        # … bestaande env, resources, probes …
    volumes:
      - name: odionchat-data
        storageType: AzureFile
        storageName: odionchat-data
    scale:
      minReplicas: 1
      maxReplicas: 2
```

> **Volume names:** gebruik geen punten of speciale tekens in volumenamen (bijv. geen `data.json`).

### 3.3 App updaten

```bash
az containerapp update \
  --name "$CONTAINER_APP" \
  --resource-group "$RESOURCE_GROUP" \
  --yaml app.yaml
```

Azure maakt automatisch een **nieuwe revision** aan. Wacht tot die actief is:

```bash
az containerapp revision list \
  --name "$CONTAINER_APP" \
  --resource-group "$RESOURCE_GROUP" \
  -o table
```

---

## Stap 4 — Verificatie

1. **Health check**

```bash
curl -sf "https://chat.odion.nl/health"
```

2. **Data overleeft redeploy** — log in, start een chat, deploy opnieuw (of forceer nieuwe revision):

```bash
az containerapp update \
  --name "$CONTAINER_APP" \
  --resource-group "$RESOURCE_GROUP" \
  --image ghcr.io/manavanl/odionchat:latest
```

De chat en gebruikers moeten behouden blijven.

3. **Logs** — geen SQLite- of permission-fouten:

```bash
az containerapp logs show \
  --name "$CONTAINER_APP" \
  --resource-group "$RESOURCE_GROUP" \
  --follow
```

4. **Optioneel: bestanden op de share controleren** — mount de share lokaal of bekijk via Azure Portal → Storage account → File shares → `odionchat-data`. Na eerste boot verschijnen o.a. `webui.db` en `cache/`.

---

## Portal-alternatief

Als je liever de Azure Portal gebruikt:

### Environment: file share registreren

1. Ga naar **Container Apps Environments** → `cae-odionchat-prod`
2. **Settings** → **Azure Files** (of **Storage** / **Volume mounts**, afhankelijk van Portal-versie)
3. **Add** → protocol **SMB**
4. Vul in: naam `odionchat-data`, storage account, access key, share `odionchat-data`, access mode **Read/Write**
5. **Save**

### Container App: volume + mount

1. Ga naar **Container Apps** → `odionchat`
2. **Application** → **Revisions and replicas** → **Create new revision**
3. Tab **Volumes** → **Add** → type **Azure file volume**, koppel de share uit de environment
4. Tab **Container** → container selecteren → **Volume mounts**
5. Volume: `odionchat-data`, mount path: `/app/backend/data`
6. **Create** om de revision te deployen

Zie ook: [Create an Azure Files storage mount in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/storage-mounts-azure-files?tabs=bash).

---

## Backup

Periodieke backup van de hele share (SQLite + uploads):

```bash
# Download share naar lokale map
az storage file download-batch \
  --destination "./backup-$(date +%Y%m%d)" \
  --source "$FILE_SHARE" \
  --account-name "$STORAGE_ACCOUNT" \
  --account-key "$STORAGE_KEY"

# Of alleen de database
az storage file download \
  --share-name "$FILE_SHARE" \
  --path webui.db \
  --dest "./webui-$(date +%Y%m%d).db" \
  --account-name "$STORAGE_ACCOUNT" \
  --account-key "$STORAGE_KEY"
```

Automatiseer via een scheduled job (Azure Automation, GitHub Actions, etc.).

---

## Aandachtspunten

| Onderwerp | Advies |
|-----------|--------|
| **Replicas** | Houd `minReplicas: 1` en `maxReplicas: 1` zolang je SQLite gebruikt. Meerdere replicas + SQLite op gedeelde storage kan locking-problemen geven. |
| **Mount path** | Moet exact `/app/backend/data` zijn (Open WebUI `DATA_DIR` default). |
| **Eerste boot** | Duurt 1–5 min (migraties + embeddings). Normaal gedrag. |
| **Secrets in DB** | OAuth/API-instellingen met `ENABLE_OAUTH_PERSISTENT_CONFIG=false` komen uit env vars — database bevat vooral users/chats. |
| **PostgreSQL later** | Bij overstap: migreer `webui.db` naar Postgres (zie [Open WebUI database tutorial](https://docs.openwebui.com/tutorials/maintenance/database)); Azure Files blijft nuttig voor uploads. |
| **Storage account key** | Rotatie vereist update van environment storage config. Overweeg later managed identity ([share-level RBAC](https://learn.microsoft.com/en-us/azure/storage/files/storage-files-identity-assign-share-level-permissions)). |

---

## Troubleshooting

| Symptom | Oorzaak | Oplossing |
|---------|---------|-----------|
| Database leeg na deploy | Geen volume mount | Voer stap 2–3 opnieuw uit; controleer revision YAML |
| Container start niet | Verkeerde `storageName` | Moet matchen met environment storage |
| Container start niet | Volume name met `.` of `/` in subPath | Hernoem volume; subPath niet laten beginnen met `/` |
| Permission denied op DB | Share read-only | `--access-mode ReadWrite` |
| Data van vóór mount kwijt | Stond op ephemeral disk | Herstel uit backup; oude data is niet automatisch gemigreerd |
| Chats verdwijnen sporadisch | Meerdere replicas + SQLite | Zet `maxReplicas: 1` |

---

## Checkpoint

- [ ] Storage account + file share aangemaakt
- [ ] Share geregistreerd op Container Apps environment
- [ ] Volume mount op `/app/backend/data` in actieve revision
- [ ] Login + chat overleeft container restart / nieuwe deploy
- [ ] Backup-procedure vastgelegd

---

## Gerelateerde documentatie

- [deployment-azure.md](deployment-azure.md) — volledige Azure-deploy
- [openwebui-reference.md](openwebui-reference.md) — database en backup
- [Microsoft Learn: storage mounts (SMB)](https://learn.microsoft.com/en-us/azure/container-apps/storage-mounts?tabs=smb&pivots=azure-cli)

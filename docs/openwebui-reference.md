---
description: Referentie naar canonical bronnen voor Open WebUI configuratie, instellingen en update-procedure — zodat we breaking changes kunnen volgen wanneer we naar een nieuwere versie willen
---

# Open WebUI — referentie

OdionChat draait op **Open WebUI v0.8.7** (image `ghcr.io/open-webui/open-webui:main`, gepind in `docker-compose.yml`). Dit document bevat de canonical links naar documentatie en source code, zodat we bij elke update kunnen verifiëren wat er is veranderd en welke configuratie-knoppen er bij zijn gekomen.

**Update-ritueel** wanneer we naar een nieuwere versie willen:
1. Lees de [release notes](https://github.com/open-webui/open-webui/releases) sinds v0.8.7
2. Diff `config.py` tussen v0.8.7 en de nieuwe tag (zie sectie 3) — nieuwe env vars
3. Diff de `migrations/versions/` map — schema-wijzigingen die backups breken
4. Maak backup van `data/webui.db` (zie sectie 8) vóór upgrade
5. Update de versie-tag in deze referentie als `v0.8.7` → `v0.X.Y` in alle URLs hieronder

## 1. Officiële documentatie

Canonical docs site, niet versie-gepind (volgt altijd `main`). Bevat alle gebruikers- en admin-documentatie, structureel ingedeeld in Getting Started / Features / Reference / Tutorials / Troubleshooting / Enterprise.

→ https://docs.openwebui.com/

## 2. GitHub repository

Officiële source repo. Backend is Python (FastAPI) onder `backend/open_webui/`, frontend is SvelteKit onder `src/`.

- Repo: https://github.com/open-webui/open-webui
- Versie-gepind v0.8.7: https://github.com/open-webui/open-webui/tree/v0.8.7

## 3. Environment variables

Open WebUI heeft 200+ env vars (auth, database, storage, RAG, model routing, logging). Veel daarvan zijn `PersistentConfig`: ze zijn na eerste boot via de admin-UI te wijzigen en worden in de DB opgeslagen — de env var wordt dan alleen voor de *eerste* startup gelezen.

- Reference docs: https://docs.openwebui.com/reference/env-configuration/
- Source of truth (v0.8.7): https://github.com/open-webui/open-webui/blob/v0.8.7/backend/open_webui/config.py

Belangrijke env vars in onze setup (zie `docker-compose.yml`):

| Var | Doel |
|-----|------|
| `WEBUI_SECRET_KEY` | JWT signing key — gepind in `.env` om sessies stabiel te houden over restarts |
| `WEBUI_ADMIN_EMAIL` / `WEBUI_ADMIN_PASSWORD` | Bootstrap admin op lege users-tabel |
| `WEBUI_AUTH` | `true` — login vereist |
| `ENABLE_SIGNUP` | `false` — gebruikers worden door admin aangemaakt |
| `OPENAI_API_BASE_URLS` | Azure AI Foundry via OpenAI-compatible endpoint |
| `WEBUI_SESSION_COOKIE_SAME_SITE` | `lax` — voor `http://localhost` |
| `WEBUI_SESSION_COOKIE_SECURE` | `false` lokaal, `true` op prod |

## 4. Authenticatie en admin

Auth (signup, login, OAuth, LDAP, SCIM, API keys) en admin-settings (user management, RBAC, banners). RBAC roles + groups beheren toegang tot models, tools, knowledge.

Docs:
- Auth & access: https://docs.openwebui.com/features/authentication-access/
- Admin: https://docs.openwebui.com/features/administration/
- Banners: https://docs.openwebui.com/features/administration/banners/
- RBAC roles: https://docs.openwebui.com/features/authentication-access/rbac/roles/

Source (v0.8.7):
- Auths router: https://github.com/open-webui/open-webui/blob/v0.8.7/backend/open_webui/routers/auths.py
- Users router: https://github.com/open-webui/open-webui/blob/v0.8.7/backend/open_webui/routers/users.py
- Groups router: https://github.com/open-webui/open-webui/blob/v0.8.7/backend/open_webui/routers/groups.py
- SCIM router: https://github.com/open-webui/open-webui/blob/v0.8.7/backend/open_webui/routers/scim.py

## 5. Model management API

REST API voor CRUD op models (custom model definitions met system prompts, params, knowledge, tools), Ollama proxy en OpenAI-compatible proxy.

- API endpoints docs: https://docs.openwebui.com/getting-started/api-endpoints
- Live Swagger UI: `http://localhost:3000/docs` (op een draaiende instance)

Source (v0.8.7):
- Models router: https://github.com/open-webui/open-webui/blob/v0.8.7/backend/open_webui/routers/models.py
- Ollama proxy: https://github.com/open-webui/open-webui/blob/v0.8.7/backend/open_webui/routers/ollama.py
- OpenAI proxy: https://github.com/open-webui/open-webui/blob/v0.8.7/backend/open_webui/routers/openai.py
- Chats router: https://github.com/open-webui/open-webui/blob/v0.8.7/backend/open_webui/routers/chats.py
- Volledige routers tree (28 files): https://github.com/open-webui/open-webui/tree/v0.8.7/backend/open_webui/routers

Onze API-calls voor model creation staan (WIP) in `scripts/patch.sh`. Bij upgrade: check of `POST /api/v1/models/create` en `POST /api/v1/models/model/update?id=...` nog bestaan in de nieuwe `models.py` router.

## 6. Database en storage

SQLite by default in `${DATA_DIR}/webui.db` (Postgres optioneel via `DATABASE_URL`). `DATA_DIR` defaultet naar `/app/backend/data` in Docker — bij ons gemount op `./data/`.

Submappen in `data/`:
- `uploads/` — user files
- `cache/` — whisper-cache, embedding cache
- `vector_db/` — Chroma default; ook Qdrant/Milvus/Pgvector mogelijk

Schema-migraties via Alembic.

Docs:
- Database tutorial: https://docs.openwebui.com/tutorials/maintenance/database

Source (v0.8.7):
- Models package (SQLAlchemy schemas): https://github.com/open-webui/open-webui/tree/v0.8.7/backend/open_webui/models
- Alembic migraties: https://github.com/open-webui/open-webui/tree/v0.8.7/backend/open_webui/migrations
- DB init: https://github.com/open-webui/open-webui/blob/v0.8.7/backend/open_webui/internal/db.py

## 7. Customization (CSS, JS, static files)

Native customization is beperkt: er is een `backend/open_webui/static/custom.css` die je kunt overschrijven (mount via volume), plus favicon/logo/splash images in dezelfde folder. `WEBUI_STATIC_DIR` env var verzet de hele static folder.

Voor diepgaandere theming biedt Enterprise officiële customization. In OSS is de gebruikelijke workflow: bind-mount eigen `static/` folder + `custom.css` over de defaults heen, of patch via `scripts/patch.sh` tijdens `docker build` (onze aanpak).

Docs:
- Customization (Enterprise): https://docs.openwebui.com/enterprise/customization/
- Banners (admin UI feature, geen code-injectie): https://docs.openwebui.com/features/administration/banners/

Source (v0.8.7):
- Static folder (custom.css, loader.js, favicons, logo's): https://github.com/open-webui/open-webui/tree/v0.8.7/backend/open_webui/static
- `custom.css` (overschrijfbaar): https://github.com/open-webui/open-webui/blob/v0.8.7/backend/open_webui/static/custom.css

## 8. Backup en restore

Stop container, snapshot `DATA_DIR` (bevat sqlite DB + uploads + vector store), restore door folder terug te zetten en container te herstarten. Bij Postgres: standaard `pg_dump` / `pg_restore`. Geen ingebouwde "export alle data"-knop.

→ https://docs.openwebui.com/tutorials/maintenance/backups

Voor OdionChat lokaal:
```bash
cd ~/Manava/'2. Klanten en partners'/Odion/odionchat
docker compose down
cp -a data/ "data.bak-$(date +%Y%m%d-%H%M%S)"
docker compose up -d
```

Voor prod (VPS):
```bash
ssh root@<vps-ip> "cd /opt/odionchat && docker compose down && cp -a data/ data.bak-\$(date +%Y%m%d-%H%M%S) && docker compose up -d"
```

## 9. Upgrade procedure

Standaard upgrade: `docker pull` → `docker stop` → `docker rm` → `docker run` met behoud van de `data/` volume. Migraties draaien automatisch bij startup. Pre-upgrade altijd backup vóór major bumps want vector DB schema kan wijzigen.

Docs:
- Update guide: https://docs.openwebui.com/getting-started/updating
- Quick start (Docker): https://docs.openwebui.com/getting-started/quick-start/

Onze workflow:
```bash
# Lokaal
cd ~/Manava/'2. Klanten en partners'/Odion/odionchat
cp -a data/ "data.bak-$(date +%Y%m%d)"
docker compose pull
docker compose up -d

# Prod (vereist update van image-tag in docker-compose.yml + deploy.sh)
./scripts/deploy.sh
```

## 10. Release notes en changelog

Twee canonical bronnen, beide bijgehouden door maintainers.

- Releases overview: https://github.com/open-webui/open-webui/releases
- Specifiek 0.8.7: https://github.com/open-webui/open-webui/releases/tag/v0.8.7
- CHANGELOG (volgt main): https://github.com/open-webui/open-webui/blob/main/CHANGELOG.md
- CHANGELOG @ v0.8.7: https://github.com/open-webui/open-webui/blob/v0.8.7/CHANGELOG.md

## 11. Community

- Discord (officieel): https://discord.gg/5rJgQTnV4s
- GitHub Discussions: https://github.com/open-webui/open-webui/discussions
- Reddit: https://www.reddit.com/r/OpenWebUI/
- X / Twitter: https://x.com/OpenWebUI

## 12. Watch-list voor breaking changes

Bij elke versie-upgrade: diff deze paden tussen huidige en nieuwe tag.

| Bestand | Waarom | Diff URL pattern |
|---------|--------|------------------|
| `backend/open_webui/config.py` | Single source of truth voor env vars en defaults | `https://github.com/open-webui/open-webui/compare/v0.8.7...v0.X.Y` |
| `backend/open_webui/main.py` | App entrypoint, mount-volgorde van routers, lifespan hooks | (idem) |
| `backend/open_webui/routers/*` | 28 routers — elke API-wijziging loopt hier doorheen | (idem) |
| `backend/open_webui/migrations/versions/*` | Alembic migraties — schema-wijzigingen die backups breken | (idem) |
| `CHANGELOG.md` | Snelste overzicht van breaking changes per release | (idem) |
| `pyproject.toml` | Python deps + version pin | (idem) |

Raw URL pattern voor scripted drift-checks:
`https://raw.githubusercontent.com/open-webui/open-webui/v0.8.7/<path>`

## 13. Project-specifieke leerlessen

Niet alle Open WebUI gedrag is gedocumenteerd. Onze sessie-bevindingen staan in:
- `~/.claude/skills/odionchat/SKILL.md` — sectie "Learned Lessons"
- `.claude/SESSION.md` — actuele sessie-status

Korte recap van niet-obvious gedrag:
- API endpoints zonder trailing slash (`/api/v1/models`, niet `/api/v1/models/`) — anders krijg je HTML terug van de SvelteKit catch-all
- POST voor delete-operaties (niet DELETE)
- `WEBUI_SECRET_KEY` MOET gepind in `.env`, anders ongeldige JWTs bij elke restart
- `WEBUI_ADMIN_EMAIL`/`WEBUI_ADMIN_PASSWORD` werken alleen op een lege users-tabel — bestaande admins worden niet overschreven
- Custom CSS hoort in `/app/build/static/custom.css` *en* `/app/backend/open_webui/static/custom.css`
- Sidebar logo wordt opgehaald van `/logo.png` (root-path), niet `/static/logo.png` — moet in `/app/build/logo.png` staan

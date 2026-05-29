---
date: 2026-03-02
tags:
  - odion
  - odionchat
  - deployment
  - vps
description: "Deployment handleiding voor OdionChat op een VPS met Docker en Caddy als reverse proxy."
---

# OdionChat — VPS deployment

Handleiding voor het deployen van OdionChat op een Linux VPS met Docker en Caddy.

## Vereisten

- Linux VPS (Debian/Ubuntu) met root-toegang
- Minimaal 2 GB RAM, 10 GB opslag
- Domeinnaam met DNS A-record naar het VPS IP-adres
- Azure AI Foundry API key en endpoint

## Stap 1: Docker installeren

```bash
apt-get update && apt-get install -y docker.io docker-compose-plugin
systemctl enable docker && systemctl start docker
```

Controleer:
```bash
docker --version
docker compose version
```

## Stap 2: Project deployen

Vanaf je lokale machine:

```bash
./scripts/deploy.sh
```

Of handmatig:

```bash
rsync -avz --exclude='.git' --exclude='.DS_Store' --exclude='data/cache' \
  odionchat/ root@<vps-ip>:/opt/odionchat/
```

## Stap 3: .env aanmaken op VPS

```bash
ssh root@<vps-ip>
cat > /opt/odionchat/.env << 'EOF'
OPENAI_API_BASE_URLS=https://<resource-name>.openai.azure.com/openai/v1/
AZURE_OPENAI_API_KEY=<jouw-foundry-key>
WEBUI_AUTH=true
PORT=3000
EOF
```

## Stap 4: Caddy installeren en configureren

```bash
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt-get update && apt-get install caddy
```

Voeg toe aan `/etc/caddy/Caddyfile`:

```caddy
odion.manava.nl {
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        Referrer-Policy "strict-origin-when-cross-origin"
        -Server
    }
    reverse_proxy 127.0.0.1:3000
}
```

Herstart Caddy:
```bash
systemctl reload caddy
```

Caddy regelt automatisch Let's Encrypt HTTPS-certificaten.

## Stap 5: Container starten

```bash
cd /opt/odionchat && docker compose up -d
```

Controleer:
```bash
docker logs odionchat --tail 20
curl -sI https://odion.manava.nl
```

## Stap 6: Admin-account aanmaken

Bij de eerste keer bezoeken met `WEBUI_AUTH=true`:
1. Open https://odion.manava.nl
2. Maak een admin-account aan (eerste registratie wordt automatisch admin)
3. Log in en configureer modellen via `./scripts/patch-locale.sh https://odion.manava.nl`

## Updates deployen

Gebruik het deploy-script:
```bash
./scripts/deploy.sh
```

Dit synct bestanden en herstart de container. De `.env` op de VPS wordt niet overschreven.

## Troubleshooting

| Probleem | Diagnose | Oplossing |
|----------|----------|-----------|
| Container start niet | `docker logs odionchat` | Check .env en docker-compose.yml |
| HTTPS werkt niet | `systemctl status caddy` | Check DNS A-record en Caddyfile |
| 502 Bad Gateway | `docker ps` | Container draait niet, `docker compose up -d` |
| Locale/CSS niet geladen | `docker logs odionchat \| head -20` | Check of entrypoint.sh correct is gemount |
| API key werkt niet | Chat testen in browser | Controleer `AZURE_OPENAI_API_KEY` en `OPENAI_API_BASE_URLS` in .env |

## Logs bekijken

```bash
# Container logs
docker logs odionchat -f

# Caddy logs
journalctl -u caddy -f
```

## Backup

De database en instellingen staan in `/opt/odionchat/data/`:
```bash
# Backup
tar czf odionchat-backup-$(date +%Y%m%d).tar.gz /opt/odionchat/data/webui.db

# Restore
tar xzf odionchat-backup-*.tar.gz -C /
docker compose restart
```

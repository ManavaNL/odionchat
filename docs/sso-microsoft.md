---
date: 2026-03-02
tags:
  - odion
  - odionchat
  - sso
  - microsoft
description: "Configuratiehandleiding voor Microsoft Entra ID (Azure AD) SSO-koppeling met OdionChat via OIDC."
---

# Microsoft Entra ID SSO — configuratiehandleiding

Deze handleiding beschrijft hoe Odion ICT Microsoft Entra ID (voorheen Azure AD) koppelt aan OdionChat, zodat medewerkers kunnen inloggen met hun Odion Microsoft-account.

## Wat is nodig

- Toegang tot het Azure-portaal met rechten om App Registrations aan te maken
- De URL waarop OdionChat draait (bijv. `https://odionchat.odion.nl`)
- Toegang tot de `.env` van de OdionChat-server

## Stap 1: Azure App Registration aanmaken

1. Ga naar [Azure Portal](https://portal.azure.com) > **Microsoft Entra ID** > **App registrations** > **New registration**
2. Vul in:
   - **Name:** OdionChat
   - **Supported account types:** Accounts in this organizational directory only (Single tenant)
   - **Redirect URI:** Web — `https://odionchat.odion.nl/oauth/microsoft/callback`
3. Klik **Register**
4. Noteer de **Application (client) ID** en **Directory (tenant) ID**

## Stap 2: Client secret aanmaken

1. Ga naar **Certificates & secrets** > **New client secret**
2. Beschrijving: `OdionChat SSO`
3. Verlooptijd: kies een passende periode (bijv. 24 maanden)
4. Noteer de **Value** (dit is het client secret — wordt maar een keer getoond)

## Stap 3: Email claim toevoegen

Open WebUI heeft het emailadres nodig om gebruikers te identificeren.

1. Ga naar **Token configuration** > **Add optional claim**
2. Token type: **ID**
3. Vink **email** aan
4. Klik **Add**
5. Accepteer de gevraagde API-rechten als daar om gevraagd wordt

## Stap 4: API permissions controleren

Ga naar **API permissions** en controleer dat deze aanwezig zijn:
- `openid` (standaard)
- `email`
- `profile`
- `offline_access` (voor token refresh)

Klik op **Grant admin consent** als dat nog niet gedaan is.

## Stap 5: OdionChat configureren

Voeg de volgende variabelen toe aan `.env` op de server:

```env
# Microsoft Entra ID SSO
MICROSOFT_CLIENT_ID=<application-client-id>
MICROSOFT_CLIENT_SECRET=<client-secret-value>
MICROSOFT_CLIENT_TENANT_ID=<directory-tenant-id>
MICROSOFT_OAUTH_SCOPE=openid email profile offline_access
MICROSOFT_REDIRECT_URI=https://odionchat.odion.nl/oauth/microsoft/callback

# OpenID Connect provider URL (verplicht voor OIDC discovery)
OPENID_PROVIDER_URL=https://login.microsoftonline.com/<directory-tenant-id>/v2.0/.well-known/openid-configuration
```

Herstart daarna de container:

```bash
docker compose down && docker compose up -d
```

## Stap 6: Testen

1. Open OdionChat in een incognito-venster
2. Je zou nu een "Sign in with Microsoft" knop moeten zien op de loginpagina
3. Log in met een Odion Microsoft-account
4. Controleer dat het emailadres correct wordt overgenomen

## Aandachtspunten

- **Redirect URI moet exact matchen.** Als de URL van OdionChat verandert, moet de Redirect URI in Azure ook aangepast worden.
- **Email claim is verplicht.** Zonder de email optional claim kan Open WebUI de gebruiker niet identificeren.
- **offline_access scope** zorgt voor token refresh. Zonder deze scope moeten gebruikers vaker opnieuw inloggen.
- **Single tenant** is aanbevolen. Hiermee kunnen alleen Odion-accounts inloggen.
- **Admin consent** moet eenmalig gegeven worden door een Azure AD admin.
- **WEBUI_AUTH moet true zijn** (standaard). SSO werkt niet als authenticatie uitstaat.

## Gebruikersbeheer

Na SSO-koppeling:
- Nieuwe gebruikers die inloggen via Microsoft krijgen automatisch de rol "user"
- Admins kunnen in Open WebUI rollen aanpassen via **Admin Panel** > **Users**
- `ENABLE_SIGNUP=false` heeft geen effect op SSO-logins — SSO-gebruikers worden altijd aangemaakt

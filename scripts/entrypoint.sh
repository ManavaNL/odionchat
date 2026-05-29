#!/usr/bin/env bash
# entrypoint.sh — Auto-patch CSS + Dutch locale at container start, then launch Open WebUI
set -euo pipefail

echo "[entrypoint] Copying Odion CSS..."
if [ -f /config/custom.css ]; then
  cp /config/custom.css /app/backend/open_webui/static/custom.css 2>/dev/null || true
  cp /config/custom.css /app/build/static/custom.css 2>/dev/null || true
  echo "[entrypoint] CSS copied to static dirs"
else
  echo "[entrypoint] Warning: /config/custom.css not found, skipping CSS"
fi

# Cache-buster: bump custom.css link in index.html met md5 van het bestand
# Browsers zien hierdoor bij elke restart een nieuwe URL = forced refresh,
# ongeacht ETag/HTTP-cache. Voorkomt "ik zie de oude versie"-problemen.
if [ -f /app/build/index.html ] && [ -f /app/build/static/custom.css ]; then
  CSS_HASH=$(md5sum /app/build/static/custom.css | cut -d' ' -f1 | head -c 8)
  # Zet versie achter custom.css (vervang bestaande ?v=... als die er al is)
  sed -i -E "s|href=\"/static/custom.css(\\?v=[a-z0-9]+)?\"|href=\"/static/custom.css?v=${CSS_HASH}\"|g" /app/build/index.html
  echo "[entrypoint] Cache-buster set: custom.css?v=${CSS_HASH}"
fi

echo "[entrypoint] Copying Odion logos..."
if [ -f /config/logo.svg ]; then
  for DIR in /app/backend/open_webui/static /app/build/static; do
    cp /config/logo.svg "$DIR/logo.svg" 2>/dev/null || true
    cp /config/logo.svg "$DIR/logo2.svg" 2>/dev/null || true   # 0.8.7 verwijst naar logo2.svg in sommige UI-componenten
    cp /config/logo.svg "$DIR/favicon.svg" 2>/dev/null || true
  done
  # Echte PNG voor login page (splash.png) en favicon.png — browser kan SVG-bytes
  # in .png extension niet als raster renderen, daarom een echte PNG-render
  if [ -f /config/logo.png ]; then
    for DIR in /app/backend/open_webui/static /app/build/static; do
      cp /config/logo.png "$DIR/logo.png" 2>/dev/null || true
      cp /config/logo.png "$DIR/splash.png" 2>/dev/null || true
      cp /config/logo.png "$DIR/splash-dark.png" 2>/dev/null || true
      cp /config/logo.png "$DIR/favicon.png" 2>/dev/null || true
      cp /config/logo.png "$DIR/favicon-dark.png" 2>/dev/null || true
      cp /config/logo.png "$DIR/favicon-96x96.png" 2>/dev/null || true
      cp /config/logo.png "$DIR/apple-touch-icon.png" 2>/dev/null || true
    done
    # Sidebar logo: 0.8.7 vraagt /logo.png op root-path (niet /static/), valt
    # anders door naar SvelteKit SPA-catchall die HTML serveert → broken icon.
    cp /config/logo.png /app/build/logo.png 2>/dev/null || true
  fi

  # Strip "(Open WebUI)" branding suffix uit backend env.py (line: WEBUI_NAME += " (Open WebUI)")
  echo "[entrypoint] Patching '(Open WebUI)' suffix in backend..."
  sed -i 's|WEBUI_NAME += " (Open WebUI)"|pass  # patched: Odion branding|' /app/backend/open_webui/env.py 2>/dev/null || true
  # Invalidate bytecode cache zodat Python opnieuw inleest
  rm -f /app/backend/open_webui/__pycache__/env.cpython-*.pyc 2>/dev/null || true

  # Force Dutch locale + cross-browser logo replacement via MutationObserver.
  # Vervangt gradient-avatars met Odion logo én verwijdert crossorigin attribuut
  # (anders blokkeert Chrome de fetch op same-origin static asset).
  echo "[entrypoint] Injecting locale + logo-MutationObserver in index.html..."
  if [ -f /app/build/index.html ] && ! grep -q 'odionLogoObserver\|fixImg' /app/build/index.html; then
    cat > /tmp/inject.html <<'INJECT'
<script>
(function(){
  try {
    localStorage.setItem("i18nextLng","nl-NL");
    document.cookie="i18next=nl-NL;path=/;max-age=31536000;SameSite=Lax";
    document.documentElement.lang="nl-NL";
    Object.defineProperty(navigator,"language",{get:function(){return "nl-NL"}});
    Object.defineProperty(navigator,"languages",{get:function(){return ["nl-NL","nl","en"]}});
  } catch(e) {}
  var ODION_LOGO = "/static/logo.png";
  function fixImg(img) {
    if (!img) return;
    var s = img.src || "";
    if (s.indexOf("/api/v1/models/model/profile/image") !== -1 ||
        s.indexOf("/profile/image") !== -1) {
      if (img.dataset.odionFixed !== "1") {
        if (img.hasAttribute("crossorigin")) img.removeAttribute("crossorigin");
        img.src = ODION_LOGO + "?_t=" + Date.now();
        img.dataset.odionFixed = "1";
        return;
      }
    }
    if (img.id === "logo" ||
        s.indexOf("favicon-dark.png") !== -1 ||
        s.indexOf("splash-dark.png") !== -1 ||
        s.indexOf("splash.png") !== -1) {
      if (img.dataset.odionFixed !== "1") {
        if (img.hasAttribute("crossorigin")) img.removeAttribute("crossorigin");
        img.src = ODION_LOGO + "?_t=" + Date.now();
        img.style.objectFit = "contain";
        img.dataset.odionFixed = "1";
      }
    }
    if (s.indexOf("/static/logo.png") !== -1 && img.hasAttribute("crossorigin")) {
      img.removeAttribute("crossorigin");
    }
  }
  function scan(root) { (root || document).querySelectorAll("img").forEach(fixImg); }
  document.addEventListener("DOMContentLoaded", function(){
    scan();
    new MutationObserver(function(muts){
      muts.forEach(function(m){
        m.addedNodes && m.addedNodes.forEach(function(n){
          if (n.nodeType === 1) { if (n.tagName === "IMG") fixImg(n); else scan(n); }
        });
        if (m.type === "attributes" && m.target && m.target.tagName === "IMG") {
          // Marker NIET wissen: anders triggert onze eigen src-mutatie weer fixImg → infinite loop
          if (m.target.dataset.odionFixed !== "1") fixImg(m.target);
        }
      });
    }).observe(document.body, {childList:true, subtree:true, attributes:true, attributeFilter:["src","crossorigin"]});
  });
})();
</script>
INJECT
    python3 -c "
html = open('/app/build/index.html').read()
inject = open('/tmp/inject.html').read()
html = html.replace('</head>', inject + '</head>', 1)
open('/app/build/index.html','w').write(html)
print('inject done')
"
  fi
  if [ -f /config/logo-tekst.svg ]; then
    cp /config/logo-tekst.svg /app/backend/open_webui/static/logo-tekst.svg 2>/dev/null || true
    cp /config/logo-tekst.svg /app/build/static/logo-tekst.svg 2>/dev/null || true
  fi
  echo "[entrypoint] Logos copied"
fi

echo "[entrypoint] Searching for Dutch locale file..."
LOCALE_FILE=$(find /app/build/_app/immutable/chunks -name '*.js' -exec grep -l '"nl-NL"' {} \; 2>/dev/null | head -1)

if [ -z "$LOCALE_FILE" ]; then
  echo "[entrypoint] Warning: Dutch locale file not found, skipping locale patch"
else
  echo "[entrypoint] Patching locale file: $LOCALE_FILE"

  # Batch 1: Folders, Chat History, Sidebar, Users, Archive, Files, Notes
  sed -i \
    -e 's/"Folders":""/"Folders":"Mappen"/g' \
    -e 's/"Folder":""/"Folder":"Map"/g' \
    -e 's/"Create Folder":""/"Create Folder":"Map maken"/g' \
    -e 's/"Edit Folder":""/"Edit Folder":"Map bewerken"/g' \
    -e 's/"Folder Background Image":""/"Folder Background Image":"Map-achtergrondafbeelding"/g' \
    -e 's/"Folder Name":""/"Folder Name":"Mapnaam"/g' \
    -e 's/"Folder name":""/"Folder name":"Mapnaam"/g' \
    -e 's/"Folder options":""/"Folder options":"Mapopties"/g' \
    -e 's/"Enter folder name":""/"Enter folder name":"Voer mapnaam in"/g' \
    -e 's/"Change folder icon":""/"Change folder icon":"Mappictogram wijzigen"/g' \
    -e 's/"Delete all contents inside this folder":""/"Delete all contents inside this folder":"Alle inhoud in deze map verwijderen"/g' \
    -e 's/"Folder updated successfully":""/"Folder updated successfully":"Map succesvol bijgewerkt"/g' \
    -e 's/"Chat History":""/"Chat History":"Chatarchief"/g' \
    -e 's/"New Temporary Chat":""/"New Temporary Chat":"Nieuw tijdelijk gesprek"/g' \
    -e 's/"Start a new conversation":""/"Start a new conversation":"Begin een nieuw gesprek"/g' \
    -e 's/"Close Sidebar":""/"Close Sidebar":"Zijbalk sluiten"/g' \
    -e 's/"Open Sidebar":""/"Open Sidebar":"Zijbalk openen"/g' \
    -e 's/"All Users":""/"All Users":"Alle gebruikers"/g' \
    -e 's/"User Groups":""/"User Groups":"Gebruikersgroepen"/g' \
    -e 's/"User Status":""/"User Status":"Gebruikersstatus"/g' \
    -e 's/"User menu":""/"User menu":"Gebruikersmenu"/g' \
    -e 's/"Change User Role":""/"Change User Role":"Gebruikersrol wijzigen"/g' \
    -e 's/"Archive All":""/"Archive All":"Alles archiveren"/g' \
    -e 's/"Delete All":""/"Delete All":"Alles verwijderen"/g' \
    -e 's/"Show All":""/"Show All":"Alles tonen"/g' \
    -e 's/"Show Files":""/"Show Files":"Bestanden tonen"/g' \
    -e 's/"Search Files":""/"Search Files":"Bestanden zoeken"/g' \
    -e 's/"New Note":""/"New Note":"Nieuwe notitie"/g' \
    -e 's/"No Notes":""/"No Notes":"Geen notities"/g' \
    -e 's/"search for folders":""/"search for folders":"zoeken in mappen"/g' \
    -e 's/"search for archived chats":""/"search for archived chats":"zoeken in gearchiveerde chats"/g' \
    -e 's/"search for pinned chats":""/"search for pinned chats":"zoeken in vastgezette chats"/g' \
    -e 's/"search for shared chats":""/"search for shared chats":"zoeken in gedeelde chats"/g' \
    -e 's/"No chats found":""/"No chats found":"Geen chats gevonden"/g' \
    -e 's/"No chats found.":""/"No chats found.":"Geen chats gevonden."/g' \
    -e 's/"No content":""/"No content":"Geen inhoud"/g' \
    -e 's/"Send now":""/"Send now":"Nu versturen"/g' \
    -e 's/"Stop Generating":""/"Stop Generating":"Stop genereren"/g' \
    -e 's/"Copy Last Response":""/"Copy Last Response":"Laatste antwoord kopiëren"/g' \
    -e 's/"Regenerate Response":""/"Regenerate Response":"Antwoord opnieuw genereren"/g' \
    "$LOCALE_FILE"

  # Batch 2: Modals, Upload, Files, Account, Messages
  sed -i \
    -e "s/\"What's on your mind?\":\"\"/\"What's on your mind?\":\"Waar denk je aan?\"/g" \
    -e 's/"Close Modal":""/"Close Modal":"Venster sluiten"/g' \
    -e 's/"Submit question":""/"Submit question":"Vraag indienen"/g' \
    -e 's/"Try Again":""/"Try Again":"Opnieuw proberen"/g' \
    -e 's/"Toggle Sidebar":""/"Toggle Sidebar":"Zijbalk aan\/uit"/g' \
    -e 's/"Upload Audio":""/"Upload Audio":"Audio uploaden"/g' \
    -e 's/"Uploading...":""/"Uploading...":"Uploaden..."/g' \
    -e 's/"Uploading file...":""/"Uploading file...":"Bestand uploaden..."/g' \
    -e 's/"Upload profile image":""/"Upload profile image":"Profielafbeelding uploaden"/g' \
    -e 's/"File uploaded!":""/"File uploaded!":"Bestand geüpload!"/g' \
    -e 's/"Remove File":""/"Remove File":"Bestand verwijderen"/g' \
    -e 's/"Remove file":""/"Remove file":"Bestand verwijderen"/g' \
    -e 's/"Remove image":""/"Remove image":"Afbeelding verwijderen"/g' \
    -e 's/"Add Image":""/"Add Image":"Afbeelding toevoegen"/g' \
    -e 's/"No files found":""/"No files found":"Geen bestanden gevonden"/g' \
    -e 's/"File name":""/"File name":"Bestandsnaam"/g' \
    -e 's/"Your Account":""/"Your Account":"Jouw account"/g' \
    -e 's/"Enter Your Name":""/"Enter Your Name":"Voer je naam in"/g' \
    -e 's/"Enter your name":""/"Enter your name":"Voer je naam in"/g' \
    -e 's/"Pinned Messages":""/"Pinned Messages":"Vastgezette berichten"/g' \
    "$LOCALE_FILE"

  # Batch 3: Folders, Suggestions, Favorites, Sharing, Models
  sed -i \
    -e 's/"This folder is empty":""/"This folder is empty":"Deze map is leeg"/g' \
    -e 's/"Prompt Suggestions":""/"Prompt Suggestions":"Voorgestelde vragen"/g' \
    -e 's/"Add to favorites":""/"Add to favorites":"Aan favorieten toevoegen"/g' \
    -e 's/"Remove from favorites":""/"Remove from favorites":"Uit favorieten verwijderen"/g' \
    -e 's/"Keep in Sidebar":""/"Keep in Sidebar":"In zijbalk houden"/g' \
    -e 's/"Hide from Sidebar":""/"Hide from Sidebar":"Verbergen in zijbalk"/g' \
    -e 's/"Share link copied to clipboard.":""/"Share link copied to clipboard.":"Deellink gekopieerd."/g' \
    -e 's/"Copy content":""/"Copy content":"Inhoud kopiëren"/g' \
    -e 's/"Learn More":""/"Learn More":"Meer informatie"/g' \
    -e 's/"Learn more":""/"Learn more":"Meer informatie"/g' \
    -e 's/"More Options":""/"More Options":"Meer opties"/g' \
    -e 's/"More options":""/"More options":"Meer opties"/g' \
    -e 's/"Available models":""/"Available models":"Beschikbare modellen"/g' \
    -e 's/"Select a language":""/"Select a language":"Kies een taal"/g' \
    -e 's/"Shared Chats":""/"Shared Chats":"Gedeelde chats"/g' \
    -e 's/"No history available":""/"No history available":"Geen geschiedenis beschikbaar"/g' \
    "$LOCALE_FILE"

  # Time-related translations
  sed -i \
    -e 's/"\[Today at\] h:mm A":""/"\[Today at\] h:mm A":"Vandaag om h:mm"/g' \
    -e 's/"\[Yesterday at\] h:mm A":""/"\[Yesterday at\] h:mm A":"Gisteren om h:mm"/g' \
    "$LOCALE_FILE"

  # Placeholder text
  sed -i \
    -e 's/"How can I help you today\?":"[^"]*"/"How can I help you today?":"Wat is je vraag?"/g' \
    "$LOCALE_FILE"

  # Variable-reference translations (key:VarName -> key:"Dutch")
  sed -i \
    -e 's/Folders:St/Folders:"Mappen"/g' \
    -e 's/General:Tt/General:"Algemeen"/g' \
    -e 's/Settings:Ea/Settings:"Instellingen"/g' \
    -e 's/Theme:Za/Theme:"Thema"/g' \
    -e 's/Profile:Go/Profile:"Profiel"/g' \
    -e 's/Account:.[a-z]/Account:"Account"/g' \
    -e 's/Personalization:Mo/Personalization:"Personalisatie"/g' \
    -e 's/Language:.[a-z]/Language:"Taal"/g' \
    -e 's/Notifications:.[a-z]/Notifications:"Meldingen"/g' \
    -e 's/Controls:Ae/Controls:"Bediening"/g' \
    -e 's/Dark:Ee/Dark:"Donker"/g' \
    -e 's/Light:Sn/Light:"Licht"/g' \
    -e 's/System:Ka/System:"Systeem"/g' \
    -e 's/Password:To/Password:"Wachtwoord"/g' \
    -e 's/Gender:Et/Gender:"Geslacht"/g' \
    -e 's/Delete:Re/Delete:"Verwijderen"/g' \
    -e 's/Copy:Ie/Copy:"Kopiëren"/g' \
    -e 's/Copied:Se/Copied:"Gekopieerd"/g' \
    -e 's/Create:Ce/Create:"Aanmaken"/g' \
    -e 's/Share:Ta/Share:"Delen"/g' \
    -e 's/Send:Sa/Send:"Versturen"/g' \
    -e 's/Done:He/Done:"Klaar"/g' \
    -e 's/Help:Bt/Help:"Help"/g' \
    -e 's/Hide:Kt/Hide:"Verbergen"/g' \
    -e 's/Hidden:Wt/Hidden:"Verborgen"/g' \
    -e 's/Visible:Mr/Visible:"Zichtbaar"/g' \
    -e 's/Models:Zn/Models:"Modellen"/g' \
    -e 's/Manage:Rn/Manage:"Beheren"/g' \
    -e 's/Message:Kn/Message:"Bericht"/g' \
    -e 's/Memories:Bn/Memories:"Herinneringen"/g' \
    -e 's/Memory:Wn/Memory:"Herinnering"/g' \
    -e 's/Members:Gn/Members:"Leden"/g' \
    -e 's/Default:Ue/Default:"Standaard"/g' \
    -e 's/Defaults:Me/Defaults:"Standaardwaarden"/g' \
    -e 's/Status:Oa/Status:"Status"/g' \
    -e 's/Session:Ca/Session:"Sessie"/g' \
    -e 's/Voice:Lr/Voice:"Stem"/g' \
    -e 's/Image:Qt/Image:"Afbeelding"/g' \
    -e 's/Images:Xt/Images:"Afbeeldingen"/g' \
    -e 's/Documents:Ke/Documents:"Documenten"/g' \
    -e 's/Document:Be/Document:"Document"/g' \
    -e 's/Overview:So/Overview:"Overzicht"/g' \
    -e 's/Workspace:Gr/Workspace:"Werkruimte"/g' \
    -e 's/Permissions:Uo/Permissions:"Rechten"/g' \
    -e 's/Pending:Do/Pending:"In afwachting"/g' \
    -e 's/Pinned:Lo/Pinned:"Vastgezet"/g' \
    -e 's/Pin:Ro/Pin:"Vastzetten"/g' \
    -e 's/Preview:Vo/Preview:"Voorbeeld"/g' \
    -e 's/Prompt:Bo/Prompt:"Prompt"/g' \
    -e 's/Prompts:Wo/Prompts:"Prompts"/g' \
    -e 's/Refresh:Zo/Refresh:"Vernieuwen"/g' \
    -e 's/Regenerate:Qo/Regenerate:"Opnieuw genereren"/g' \
    -e 's/Source:La/Source:"Bron"/g' \
    -e 's/Stop:Na/Stop:"Stoppen"/g' \
    -e 's/Support:Ba/Support:"Ondersteuning"/g' \
    -e 's/Sync:Wa/Sync:"Synchroniseren"/g' \
    -e 's/Tag:Ha/Tag:"Label"/g' \
    -e 's/User:Ir/User:"Gebruiker"/g' \
    -e 's/Username:Cr/Username:"Gebruikersnaam"/g' \
    -e 's/Users:Er/Users:"Gebruikers"/g' \
    -e 's/Version:Dr/Version:"Versie"/g' \
    -e 's/Warning:Or/Warning:"Waarschuwing"/g' \
    -e 's/Yesterday:Hr/Yesterday:"Gisteren"/g' \
    -e 's/Home:Jt/Home:"Startpagina"/g' \
    -e 's/Read:Jo/Read:"Lezen"/g' \
    -e 's/Write:Br/Write:"Schrijven"/g' \
    -e 's/Sort:Ra/Sort:"Sorteren"/g' \
    -e 's/Skills:Ua/Skills:"Vaardigheden"/g' \
    -e 's/Edited:Qe/Edited:"Bewerkt"/g' \
    -e 's/Editing:Xe/Editing:"Bewerken"/g' \
    -e 's/Disabled:Ve/Disabled:"Uitgeschakeld"/g' \
    "$LOCALE_FILE"

  # Settings and UI strings with empty values
  sed -i \
    -e 's/"High Contrast Mode":""/"High Contrast Mode":"Hoog contrast"/g' \
    -e 's/"Scroll On Branch Change":""/"Scroll On Branch Change":"Scroll bij vertakking"/g' \
    -e 's/"Birth Date":""/"Birth Date":"Geboortedatum"/g' \
    -e 's/"Speech-to-Text":""/"Speech-to-Text":"Spraak-naar-tekst"/g' \
    -e 's/"Display Multi-model Responses in Tabs":""/"Display Multi-model Responses in Tabs":"Meerdere modellen in tabbladen"/g' \
    -e 's/"Display chat title in tab":""/"Display chat title in tab":"Chattitel in tabblad tonen"/g' \
    -e 's/"Confirm Your Password":""/"Confirm Your Password":"Bevestig je wachtwoord"/g' \
    -e 's/"Enter New Password":""/"Enter New Password":"Voer nieuw wachtwoord in"/g' \
    -e 's/"Passwords do not match.":""/"Passwords do not match.":"Wachtwoorden komen niet overeen."/g' \
    -e 's/"Always Play Notification Sound":""/"Always Play Notification Sound":"Altijd meldingsgeluid afspelen"/g' \
    -e 's/"Are you sure you want to archive all chats? This action cannot be undone.":""/"Are you sure you want to archive all chats? This action cannot be undone.":"Weet je zeker dat je alle chats wilt archiveren? Dit kan niet ongedaan worden."/g' \
    -e 's/"Are you sure you want to delete all chats? This action cannot be undone.":""/"Are you sure you want to delete all chats? This action cannot be undone.":"Weet je zeker dat je alle chats wilt verwijderen? Dit kan niet ongedaan worden."/g' \
    -e 's/"Close settings modal":""/"Close settings modal":"Instellingen sluiten"/g' \
    -e 's/"Close chat controls":""/"Close chat controls":"Chatbediening sluiten"/g' \
    -e 's/"Chat exported successfully":""/"Chat exported successfully":"Chat succesvol geëxporteerd"/g' \
    -e 's/"Manage your account information.":""/"Manage your account information.":"Beheer je accountgegevens."/g' \
    -e 's/"Allow Speech to Text":""/"Allow Speech to Text":"Spraak-naar-tekst toestaan"/g' \
    -e 's/"Allow Text to Speech":""/"Allow Text to Speech":"Tekst-naar-spraak toestaan"/g' \
    -e 's/"Allow Chat Export":""/"Allow Chat Export":"Chat exporteren toestaan"/g' \
    -e 's/"Allow Chat Share":""/"Allow Chat Share":"Chat delen toestaan"/g' \
    -e 's/"Allow Continue Response":""/"Allow Continue Response":"Antwoord voortzetten toestaan"/g' \
    -e 's/"Allow Delete Messages":""/"Allow Delete Messages":"Berichten verwijderen toestaan"/g' \
    -e 's/"Allow Rate Response":""/"Allow Rate Response":"Antwoord beoordelen toestaan"/g' \
    -e 's/"Allow Regenerate Response":""/"Allow Regenerate Response":"Antwoord opnieuw genereren toestaan"/g' \
    -e 's/"Interface Settings Access":""/"Interface Settings Access":"Toegang interface-instellingen"/g' \
    -e 's/"Settings Permissions":""/"Settings Permissions":"Instellingenrechten"/g' \
    -e 's/"Save Chat":""/"Save Chat":"Chat opslaan"/g' \
    -e 's/"Custom Gender":""/"Custom Gender":"Anders"/g' \
    -e 's/"Language Locales":""/"Language Locales":"Taalinstellingen"/g' \
    "$LOCALE_FILE"

  echo "[entrypoint] Locale patched successfully"
fi

echo "[entrypoint] Starting Open WebUI..."
exec bash /app/backend/start.sh

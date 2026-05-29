---
date: 2026-03-02
tags:
  - odion
  - odionchat
  - demo
description: "Stap-voor-stap demoscript voor de OdionChat-presentatie aan Odion op 3 maart 2026."
---

# OdionChat — Demoscript (3 maart 2026)

## Voorbereiding (voor de demo)

1. Start Docker Desktop
2. Run `./scripts/start.sh`
3. Open [http://localhost:3000](http://localhost:3000) en controleer dat alles werkt
4. Zet een testgesprek op om te checken dat Claude reageert
5. Wis het testgesprek

## Demo-flow

### 1. Introductie (2 min)

"Dit is OdionChat — jullie eigen veilige AI-assistent. Wat jullie hier zien is hoe het er straks uitziet voor medewerkers."

Laat zien:
- De interface (Odion-paars, herkenbaar)
- Het invoerveld onderaan
- De naam "OdionChat" bovenaan

### 2. Eerste vraag — eenvoudig (2 min)

Typ: **"Wat is het Odion Kompas?"**

Laat zien dat OdionChat:
- Het Kompas kent (ingebakken in de system prompt)
- In helder Nederlands antwoordt
- De vijf pijlers benoemt

### 3. Praktijkvoorbeeld — dagrapportage (3 min)

Typ: **"Help me een dagrapportage schrijven. De client heeft vandaag meegedaan aan de kookactiviteit, was eerst terughoudend maar ging uiteindelijk zelf groenten snijden."**

Laat zien:
- Professionele, bondige output
- Juiste terminologie (client, begeleider)
- Bruikbaar in het ECD

### 4. Casuistiek — meedenken (3 min)

Typ: **"Een client wil graag zelfstandig boodschappen doen maar de ouders maken zich zorgen over de veiligheid. Hoe kan ik dit bespreken in de triade?"**

Laat zien:
- Genuanceerd advies
- Verwijst naar eigen regie
- Benoemt dat de medewerker beslist

### 5. Privacy en veiligheid (2 min)

Typ: **"Wat zijn de gegevens van Jan de Vries?"**

Laat zien:
- OdionChat weigert — vraagt niet om persoonsgegevens
- Verwijst naar privacy-by-design

Toon ook:
- **Temporary Chat** toggle (linksonder of in instellingen)
- "Als je dit aanzet wordt er niets opgeslagen — elk gesprek begint blanco"

### 6. Beperkingen — transparantie (2 min)

Typ: **"Welke medicatie moet ik geven bij epilepsie?"**

Laat zien:
- OdionChat geeft geen medisch advies
- Verwijst naar de arts of het protocol
- Is eerlijk over zijn beperkingen

### 7. Samenvatting en vragen (5 min)

Kernpunten:
- "Dit is dezelfde technologie die straks op jullie eigen Azure-omgeving draait"
- "De system prompt — de regels die OdionChat volgt — zijn gebaseerd op jullie Kompas"
- "Medewerkers loggen straks in met hun Odion-account (SSO)"
- "Alles draait binnen jullie eigen omgeving, data verlaat Odion niet"

## Veelgestelde vragen (voorbereid)

**"Kan het ook [X]?"**
"Ja, we kunnen de system prompt uitbreiden. Dit is versie 1 — we bouwen verder op basis van jullie feedback."

**"Is dit veilig?"**
"De data gaat niet naar derden. In productie draait alles op jullie eigen Azure-omgeving. Voor deze demo gebruiken we een beveiligde API-verbinding."

**"Wanneer kunnen we dit gebruiken?"**
"Zodra de Azure-omgeving is ingericht door Michiel en Boyd. De chatinterface en de regels staan klaar."

**"Wat kost dit?"**
"De kosten zitten in het API-gebruik (per vraag/antwoord) en de hosting. We werken het kostenplaatje uit in de volgende fase."

"""Da dove prendiamo lo stato delle colonnine, adesso che TomTom non basta.

`Ocpi.leggiLocations` nel nucleo legge già lo stato in tempo reale di ogni
presa nel formato OCPI 2.2.1 — è scritto e non è mai stato collegato a
niente, perché manca l'indirizzo di un feed. In Italia quel feed dovrebbe
essere la PUN, la piattaforma nazionale che il regolamento AFIR obbliga a
pubblicare lo stato dei punti di ricarica.

Questa sonda va a cercarlo. Dalla macchina di chi scrive il codice non si
esce (il proxy blocca tutto tranne GitHub), dal runner della CI sì: apre il
portale, si legge i suoi script, tira fuori gli indirizzi che sembrano
un'API, e li prova uno per uno dicendo cosa risponde.

Non manda credenziali e non ne ha: cerca solo quello che è pubblico.
"""

import json
import re
import sys
import urllib.error
import urllib.request

TESTA = {"User-Agent": "gdanav-sonda/1 (+https://github.com/danigio15/gdanav)"}
PORTALE = "https://www.piattaformaunicanazionale.it/"

# Indirizzi da provare comunque, oltre a quelli che si trovano nel portale.
NOTI = [
    "https://services9.arcgis.com/Iko2iF79CuZQnhht/ArcGIS/rest/services?f=pjson",
    "https://www.piattaformaunicanazionale.it/ocpi/versions",
    "https://www.piattaformaunicanazionale.it/api/ocpi/versions",
]


def avviso(titolo: str, testo: str) -> None:
    print(f"::notice title={titolo}::{testo}"[:3900])


def prendi(url: str, secondi: int = 25) -> tuple[int, bytes]:
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=TESTA), timeout=secondi) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, b""
    except Exception as e:  # noqa: BLE001
        print(f"::warning title=Colonnine::{url[:120]} — {e}")
        return 0, b""


# 1. Il portale, e i suoi script: dentro ci sono gli indirizzi che chiama.
stato, corpo = prendi(PORTALE)
avviso("Colonnine portale", f"{PORTALE} → HTTP {stato}, {len(corpo)} byte")
testo = corpo.decode("utf-8", "replace")
script = re.findall(r'src="([^"]+\.js[^"]*)"', testo)[:8]
for s in script:
    pieno = s if s.startswith("http") else PORTALE.rstrip("/") + "/" + s.lstrip("/")
    st, b = prendi(pieno, 20)
    testo += b.decode("utf-8", "replace")
avviso("Colonnine script", f"{len(script)} script letti, {len(testo)} caratteri in tutto")

# 2. Gli indirizzi che sembrano un'API.
trovati = sorted(
    {
        u.rstrip("',\")")
        for u in re.findall(r'https?://[A-Za-z0-9._~:/?#\[\]@!$&()*+,;=%-]{12,160}', testo)
        if any(k in u.lower() for k in ("api", "arcgis", "rest", "ocpi", "service", "feature", "geoserver"))
    }
)
avviso("Colonnine indirizzi", " · ".join(trovati[:20]) if trovati else "nessun indirizzo che sembri un'API")

# 3. Si provano: i trovati e i noti.
for url in (trovati[:10] + NOTI):
    st, b = prendi(url, 20)
    if st != 200 or not b:
        avviso("Colonnine prova", f"{url[:110]} → HTTP {st}")
        continue
    try:
        j = json.loads(b)
    except Exception:  # noqa: BLE001
        avviso("Colonnine prova", f"{url[:110]} → HTTP 200, {len(b)} byte, non JSON")
        continue
    # Com'è fatto: le chiavi di primo livello bastano a riconoscere OCPI
    # (`data`/`status_code`) da ArcGIS (`services`/`layers`/`features`).
    forma = sorted(j)[:12] if isinstance(j, dict) else f"lista di {len(j)}"
    ocpi = isinstance(j, dict) and ("status_code" in j or "versions" in j)
    avviso("Colonnine prova", f"{url[:110]} → HTTP 200, {len(b)} byte, chiavi {forma}{' ← sembra OCPI' if ocpi else ''}")

if not trovati:
    sys.exit(0)

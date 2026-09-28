"""Le tessere di mappa di TomTom si possono usare con la chiave che abbiamo?

Oggi la mappa la disegnano le tessere di OpenFreeMap (dati OpenStreetMap). Per
cambiarle con quelle di TomTom serve che la chiave abbia acceso il prodotto
«Maps», che è diverso da «Traffic» e da «Routing»: se non ce l'ha, il server
risponde 403 e non c'è niente da discutere.

Questa sonda lo chiede e stampa la risposta. Stampa solo esiti e nomi di
strato, mai la chiave.
"""

import collections
import os
import sys
import urllib.error
import urllib.request

import mapbox_vector_tile

CHIAVE = os.environ.get("TOMTOM", "")
if not CHIAVE:
    print("::warning title=Mappa::manca il segreto GDANAV_TOMTOM_CHIAVE")
    sys.exit(0)

# Napoli, zoom 14: la stessa zona delle foto dal campo.
Z, X, Y = 14, 8840, 6151

PROVE = [
    ("tessere classiche", f"https://api.tomtom.com/map/1/tile/basic/main/{Z}/{X}/{Y}.pbf"),
    (
        "tessere Orbis",
        f"https://api.tomtom.com/maps/orbis/map-display/tile/{Z}/{X}/{Y}.pbf?apiVersion=1&view=Unified",
    ),
]

for nome, url in PROVE:
    unione = "&" if "?" in url else "?"
    try:
        with urllib.request.urlopen(f"{url}{unione}key={CHIAVE}", timeout=30) as r:
            dati = r.read()
    except urllib.error.HTTPError as e:
        quale = {403: "il prodotto non è acceso su questa chiave", 404: "indirizzo sbagliato"}.get(e.code, "")
        print(f"::notice title=Mappa {nome}::HTTP {e.code}{f' — {quale}' if quale else ''}")
        continue
    except Exception as e:  # noqa: BLE001
        print(f"::warning title=Mappa {nome}::{str(e).replace(CHIAVE, '***')}")
        continue

    try:
        t = mapbox_vector_tile.decode(dati)
    except Exception as e:  # noqa: BLE001
        print(f"::warning title=Mappa {nome}::{len(dati)} byte, ma non è un tassello: {e}")
        continue

    strati = {k: len(v["features"]) for k, v in t.items()}
    strade = collections.Counter()
    for k, v in t.items():
        if "road" in k.lower() or "strada" in k.lower():
            for f in v["features"]:
                for campo in ("class", "subclass", "road_type", "category"):
                    if campo in f["properties"]:
                        strade[f"{campo}={f['properties'][campo]}"] += 1
    print(
        f"::notice title=Mappa {nome}::SI — {len(dati)} byte, strati {strati}"
        f"{f'; strade {dict(strade.most_common(8))}' if strade else ''}"[:3900]
    )

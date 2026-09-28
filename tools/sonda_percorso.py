"""Cosa ci dà TomTom se gli chiediamo il percorso, non solo i tempi.

Oggi `TrafficoTomTom` chiama `calculateRoute` ma gli impone la nostra linea
con `supportingPoints`: lo usa come cronometro. Qui gliela si chiede davvero,
per sapere se le sue istruzioni bastano a far girare gdanav — le manovre, i
nomi delle uscite, i cartelli, le corsie — prima di riscrivere il client.

Stampa nomi di campo e qualche esempio; mai la chiave.
"""

import collections
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

CHIAVE = os.environ.get("TOMTOM", "")
if not CHIAVE:
    print("::warning title=Percorso::manca il segreto GDANAV_TOMTOM_CHIAVE")
    sys.exit(0)

VIAGGI = [
    ("Napoli → Milano", (40.8518, 14.2681), (45.4642, 9.1900)),
    # Corso Malta: il sottopasso delle foto dal campo, dove serviva il cartello.
    ("Corso Malta", (40.8556, 14.2740), (40.8641, 14.2905)),
]

for nome, (a_lat, a_lon), (b_lat, b_lon) in VIAGGI:
    q = urllib.parse.urlencode(
        {
            "key": CHIAVE,
            "traffic": "true",
            "travelMode": "car",
            "routeType": "fastest",
            "instructionsType": "tagged",
            "routeRepresentation": "polyline",
            "computeTravelTimeFor": "all",
            "sectionType": "traffic",
            "language": "it-IT",
            "maxAlternatives": "2",
        }
    )
    url = f"https://api.tomtom.com/routing/1/calculateRoute/{a_lat},{a_lon}:{b_lat},{b_lon}/json?{q}"
    try:
        with urllib.request.urlopen(url, timeout=40) as r:
            j = json.load(r)
    except urllib.error.HTTPError as e:
        quale = {403: "il prodotto Routing non è acceso su questa chiave"}.get(e.code, "")
        print(f"::notice title=Percorso {nome}::HTTP {e.code}{f' — {quale}' if quale else ''}")
        continue
    except Exception as e:  # noqa: BLE001
        print(f"::warning title=Percorso {nome}::{str(e).replace(CHIAVE, '***')}")
        continue

    rotte = j.get("routes", [])
    if not rotte:
        print(f"::notice title=Percorso {nome}::risposta senza percorsi: {sorted(j)}")
        continue
    r0 = rotte[0]
    punti = sum(len(t.get("points", [])) for t in r0.get("legs", []))
    istruzioni = r0.get("guidance", {}).get("instructions", [])
    manovre = collections.Counter(i.get("maneuver") for i in istruzioni)
    campi = collections.Counter(k for i in istruzioni for k in i)
    sezioni = collections.Counter(s.get("sectionType") for s in r0.get("sections", []))
    s = r0.get("summary", {})
    print(
        f"::notice title=Percorso {nome}::{len(rotte)} alternative, "
        f"{s.get('lengthInMeters')} m, {s.get('travelTimeInSeconds')} s, "
        f"ritardo {s.get('trafficDelayInSeconds')} s, {punti} punti, "
        f"{len(istruzioni)} manovre; sezioni {dict(sezioni)}"
    )
    print(f"::notice title=Percorso {nome} campi::{dict(campi)}"[:3900])
    print(f"::notice title=Percorso {nome} manovre::{dict(manovre)}"[:3900])
    # Le prime istruzioni per intero: si vede com'è fatta una manovra vera.
    for i in istruzioni[:3]:
        print(f"::notice title=Percorso {nome} esempio::{json.dumps(i, ensure_ascii=False)}"[:3900])
    # E una manovra di uscita, se c'è: è quella che ci mancava a Corso Malta.
    uscita = next((i for i in istruzioni if "exitNumber" in i or "signpost" in json.dumps(i).lower()), None)
    if uscita:
        print(f"::notice title=Percorso {nome} uscita::{json.dumps(uscita, ensure_ascii=False)}"[:3900])

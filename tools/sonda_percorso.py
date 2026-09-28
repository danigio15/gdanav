"""Cosa ci dà TomTom se gli chiediamo il percorso, non solo i tempi.

Oggi `TrafficoTomTom` chiama `calculateRoute` ma gli impone la nostra linea
con `supportingPoints`: lo usa come cronometro. Qui gliela si chiede davvero,
per sapere se le sue istruzioni bastano a far girare gdanav — le manovre, i
nomi delle uscite, i cartelli, le corsie — prima di riscrivere il client.

Due motori: quello di sempre e Orbis, che è il nuovo. Le corsie servono alle
frecce del popup dello svincolo, e nel vecchio non ci sono: si guarda se il
nuovo le porta.

Le annotazioni di GitHub si troncano, quindi la guida per intero finisce in
un file, che la CI mette nella release. Stampa nomi di campo ed esempi, mai
la chiave.
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
    ("Napoli-Milano", (40.8518, 14.2681), (45.4642, 9.1900)),
    # Corso Malta: il sottopasso delle foto dal campo, dove serviva il cartello.
    ("Corso-Malta", (40.8556, 14.2740), (40.8641, 14.2905)),
]

MOTORI = [
    ("classico", "https://api.tomtom.com/routing/1/calculateRoute", {}),
    (
        "orbis",
        "https://api.tomtom.com/maps/orbis/routing/calculateRoute",
        {"apiVersion": "2", "extendedRouteRepresentation": "laneGuidance"},
    ),
]

COMUNI = {
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


def avviso(titolo: str, testo: str) -> None:
    print(f"::notice title={titolo}::{testo}"[:3900])


for nome, (a_lat, a_lon), (b_lat, b_lon) in VIAGGI:
    for motore, base, extra in MOTORI:
        eti = f"Percorso {nome} {motore}"
        q = urllib.parse.urlencode({**COMUNI, **extra, "key": CHIAVE})
        try:
            with urllib.request.urlopen(f"{base}/{a_lat},{a_lon}:{b_lat},{b_lon}/json?{q}", timeout=40) as r:
                j = json.load(r)
        except urllib.error.HTTPError as e:
            quale = {403: "il prodotto non e' acceso su questa chiave", 400: "richiesta non accettata"}.get(e.code, "")
            avviso(eti, f"HTTP {e.code}{f' — {quale}' if quale else ''}")
            continue
        except Exception as e:  # noqa: BLE001
            print(f"::warning title={eti}::{str(e).replace(CHIAVE, '***')}")
            continue

        rotte = j.get("routes", [])
        if not rotte:
            avviso(eti, f"risposta senza percorsi: {sorted(j)}")
            continue
        r0 = rotte[0]
        punti = sum(len(t.get("points", [])) for t in r0.get("legs", []))
        guida = r0.get("guidance", {})
        istruzioni = guida.get("instructions", [])
        s = r0.get("summary", {})
        avviso(
            eti,
            f"{len(rotte)} alternative, {s.get('lengthInMeters')} m, {s.get('travelTimeInSeconds')} s, "
            f"ritardo {s.get('trafficDelayInSeconds')} s, {punti} punti, {len(istruzioni)} manovre; "
            f"chiavi rotta {sorted(r0)}; chiavi guida {sorted(guida)}",
        )
        avviso(f"{eti} campi", str(dict(collections.Counter(k for i in istruzioni for k in i))))
        avviso(f"{eti} manovre", str(dict(collections.Counter(i.get("maneuver") for i in istruzioni))))
        # Le corsie: ci sono o no? È la domanda che decide se si perde il popup.
        corsie = [i for i in istruzioni if "lanes" in i or "laneSeparators" in i]
        avviso(f"{eti} corsie", f"{len(corsie)} manovre con le corsie" if corsie else "NESSUNA manovra con le corsie")
        if corsie:
            avviso(f"{eti} corsie esempio", json.dumps(corsie[0], ensure_ascii=False))

        with open(f"percorso-{nome}-{motore}.json", "w", encoding="utf-8") as f:
            json.dump(
                {"summary": s, "chiavi_rotta": sorted(r0), "sezioni": r0.get("sections", [])[:20], "guida": guida},
                f,
                ensure_ascii=False,
                indent=1,
            )

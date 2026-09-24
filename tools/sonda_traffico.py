"""Com'è fatto un tassello vettoriale del traffico TomTom (flow e incidenti):
i nomi degli strati e delle proprietà, per disegnarlo nell'app. Stampa solo
nomi e valori d'esempio, mai la chiave."""

import collections
import os
import sys
import urllib.request

import mapbox_vector_tile

CHIAVE = os.environ.get("TOMTOM", "")
if not CHIAVE:
    print("::warning title=Traffico::manca il segreto GDANAV_TOMTOM_CHIAVE")
    sys.exit(0)

# Milano, zoom 12 (x, y del tassello).
for nome, url in [
    ("flow relative", "https://api.tomtom.com/traffic/map/4/tile/flow/relative/12/2176/1467.pbf"),
    ("flow relative-delay", "https://api.tomtom.com/traffic/map/4/tile/flow/relative-delay/12/2176/1467.pbf"),
    ("incidents", "https://api.tomtom.com/traffic/map/4/tile/incidents/12/2176/1467.pbf"),
]:
    try:
        with urllib.request.urlopen(f"{url}?key={CHIAVE}", timeout=30) as r:
            dati = r.read()
        t = mapbox_vector_tile.decode(dati)
        for strato, contenuto in t.items():
            f = contenuto["features"]
            chiavi = collections.Counter(k for x in f for k in x["properties"])
            esempi = {k: sorted({str(x["properties"].get(k)) for x in f if k in x["properties"]})[:8] for k in chiavi}
            geometrie = collections.Counter(x["geometry"]["type"] for x in f)
            print(f"::notice title=Traffico {nome} / {strato}::{len(f)} elementi {dict(geometrie)}; {esempi}"[:3900])
    except Exception as e:  # noqa: BLE001
        print(f"::warning title=Traffico {nome}::{str(e).replace(CHIAVE, '***')}")

"""Come si vedrebbe Napoli con le tessere di TomTom.

Non è una prova: serve a guardare. Scarica un riquadro di mappa di TomTom
intorno a Napoli e lo cuce in un PNG solo, così si confronta con uno scatto
dell'app di oggi senza doverci installare niente sopra.

Gira in CI perché di qui `api.tomtom.com` non si raggiunge. Stampa solo esiti,
mai la chiave.
"""

import io
import math
import os
import sys
import urllib.error
import urllib.request

from PIL import Image

CHIAVE = os.environ.get("TOMTOM", "")
if not CHIAVE:
    print("::warning title=Anteprima mappa::manca il segreto GDANAV_TOMTOM_CHIAVE")
    sys.exit(0)


def tessera(lat: float, lon: float, z: int) -> tuple[int, int]:
    """La tessera che contiene quel punto, a quello zoom."""
    n = 2**z
    x = int((lon + 180.0) / 360.0 * n)
    r = math.radians(lat)
    y = int((1.0 - math.asinh(math.tan(r)) / math.pi) / 2.0 * n)
    return x, y


# Le stesse due inquadrature delle foto dal campo: la citta' larga e
# Poggioreale da vicino.
VISTE = [
    ("napoli-largo", 40.8700, 14.2750, 13, 3),
    ("poggioreale", 40.8620, 14.2850, 15, 3),
]

for nome, lat, lon, z, lato in VISTE:
    x0, y0 = tessera(lat, lon, z)
    mezzo = lato // 2
    foglio = Image.new("RGB", (256 * lato, 256 * lato), "#ffffff")
    mancanti = 0
    for dx in range(lato):
        for dy in range(lato):
            x, y = x0 - mezzo + dx, y0 - mezzo + dy
            url = f"https://api.tomtom.com/map/1/tile/basic/main/{z}/{x}/{y}.png?key={CHIAVE}"
            try:
                with urllib.request.urlopen(url, timeout=30) as r:
                    foglio.paste(Image.open(io.BytesIO(r.read())).convert("RGB"), (256 * dx, 256 * dy))
            except urllib.error.HTTPError as e:
                mancanti += 1
                if mancanti == 1:
                    print(f"::notice title=Anteprima {nome}::HTTP {e.code} sulle tessere PNG")
            except Exception as e:  # noqa: BLE001
                mancanti += 1
                if mancanti == 1:
                    print(f"::warning title=Anteprima {nome}::{str(e).replace(CHIAVE, '***')}")
    if mancanti == lato * lato:
        continue
    foglio.save(f"tomtom-{nome}.png")
    print(f"::notice title=Anteprima {nome}::{lato}×{lato} tessere a zoom {z}, {mancanti} mancanti → tomtom-{nome}.png")

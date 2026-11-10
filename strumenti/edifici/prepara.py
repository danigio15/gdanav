"""Gli edifici di Overture Maps in pacchetti PMTiles, uno per cella z8.

«Lungo il percorso voglio vedere le cose reali.» Le tessere di OpenFreeMap
hanno gli edifici di OpenStreetMap, e in molti paesi (Carinaro: 5 edifici entro
150 m da via Torretta, dove è tutto costruito) non li ha disegnati nessuno.
Overture unisce quelli di OpenStreetMap a quelli che Microsoft ha ricavato
dalle foto dal satellite, con l'altezza stimata: lì sono 43.

Ogni pacchetto è una cella z8 (circa 150 km di lato) con le tessere z14 della
scena 3D: un solo livello, `building`, con `render_height` come nelle tessere
di OpenFreeMap. L'app scarica il pacchetto della zona una volta e lo legge dal
telefono: nessun server da chiamare a ogni tessera.

    python prepara.py --cella 8/141/96 --uscita pacchetti/
    python prepara.py --italia --elenco          # le celle che toccano l'Italia

Licenza dei dati: ODbL (Overture Maps Foundation, OpenStreetMap, Microsoft).
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import math
import sys
import time
from collections import defaultdict
from pathlib import Path

import mapbox_vector_tile
import numpy as np
import pyarrow.compute as pc
import pyarrow.dataset as ds
import pyarrow.fs as pfs
import shapely
from pmtiles.tile import Compression, TileType, zxy_to_tileid
from pmtiles.writer import Writer

ZOOM = 14
ESTENSIONE = 4096
MARGINE = 64
ALTEZZA_PREDEFINITA = 8.0
RILASCIO = "2026-10-21.0"
ITALIA = (6.6, 35.4, 18.6, 47.1)
ATTRIBUZIONE = "© OpenStreetMap, Overture Maps Foundation, Microsoft (ODbL)"


def lon_x(lon: float, z: int) -> float:
    return (lon + 180.0) / 360.0 * 2**z


def lat_y(lat: float, z: int) -> float:
    r = math.radians(lat)
    return (1.0 - math.log(math.tan(r) + 1.0 / math.cos(r)) / math.pi) / 2.0 * 2**z


def x_lon(x: float, z: int) -> float:
    return x / 2**z * 360.0 - 180.0


def y_lat(y: float, z: int) -> float:
    return math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * y / 2**z))))


def confini(z: int, x: int, y: int) -> tuple[float, float, float, float]:
    """Ovest, sud, est, nord della tessera."""
    return x_lon(x, z), y_lat(y + 1, z), x_lon(x + 1, z), y_lat(y, z)


def celle_italia() -> list[tuple[int, int, int]]:
    w, s, e, n = ITALIA
    return [
        (8, x, y)
        for x in range(int(lon_x(w, 8)), int(lon_x(e, 8)) + 1)
        for y in range(int(lat_y(n, 8)), int(lat_y(s, 8)) + 1)
    ]


def leggi(cella: tuple[int, int, int], rilascio: str):
    """Gli edifici di Overture che toccano la cella: geometrie WKB e altezze."""
    w, s, e, n = confini(*cella)
    fs = pfs.S3FileSystem(anonymous=True, region="us-west-2")
    d = ds.dataset(
        f"overturemaps-us-west-2/release/{rilascio}/theme=buildings/type=building/",
        filesystem=fs,
        format="parquet",
    )
    filtro = (
        (pc.field("bbox", "xmax") > w)
        & (pc.field("bbox", "xmin") < e)
        & (pc.field("bbox", "ymax") > s)
        & (pc.field("bbox", "ymin") < n)
    )
    return d.to_table(columns=["id", "geometry", "height"], filter=filtro)


def in_metri_tessera(geom, tx: int, ty: int):
    """Da lon/lat alle coordinate della tessera z14 (0…4096, y in giù)."""
    scala = 2**ZOOM

    def trasforma(coords):
        px = (coords[:, 0] + 180.0) / 360.0 * scala
        r = np.radians(coords[:, 1])
        py = (1.0 - np.log(np.tan(r) + 1.0 / np.cos(r)) / np.pi) / 2.0 * scala
        return np.column_stack(((px - tx) * ESTENSIONE, (py - ty) * ESTENSIONE))

    return shapely.transform(geom, trasforma)


def tessere_di(cella, tabella):
    """Ogni edificio nelle tessere z14 che tocca, ritagliato col margine."""
    cz, cx, cy = cella
    k = 2 ** (ZOOM - cz)
    dentro = (cx * k, (cx + 1) * k, cy * k, (cy + 1) * k)
    geometrie = shapely.from_wkb(tabella.column("geometry").to_numpy(zero_copy_only=False))
    altezze = tabella.column("height").to_numpy(zero_copy_only=False)
    ids = tabella.column("id").to_pylist()
    limiti = shapely.bounds(geometrie)
    per_tessera: dict[tuple[int, int], list] = defaultdict(list)
    for i, g in enumerate(geometrie):
        if g is None or g.is_empty:
            continue
        w, s, e, n = limiti[i]
        x0, x1 = int(lon_x(w, ZOOM)), int(lon_x(e, ZOOM))
        y0, y1 = int(lat_y(n, ZOOM)), int(lat_y(s, ZOOM))
        h = altezze[i]
        h = float(h) if h is not None and not (isinstance(h, float) and math.isnan(h)) and h > 0 else ALTEZZA_PREDEFINITA
        fid = int(hashlib.blake2b(ids[i].encode(), digest_size=6).hexdigest(), 16)
        for tx in range(x0, x1 + 1):
            for ty in range(y0, y1 + 1):
                # Solo le tessere di questa cella: quelle di confine le fa la vicina.
                if not (dentro[0] <= tx < dentro[1] and dentro[2] <= ty < dentro[3]):
                    continue
                per_tessera[(tx, ty)].append((i, g, round(h, 1), fid))
    return per_tessera


def tessera_mvt(tx: int, ty: int, edifici) -> bytes | None:
    features = []
    for _, g, h, fid in edifici:
        locale = in_metri_tessera(g, tx, ty)
        locale = shapely.clip_by_rect(locale, -MARGINE, -MARGINE, ESTENSIONE + MARGINE, ESTENSIONE + MARGINE)
        if locale.is_empty or locale.area < 1:
            continue
        features.append({"geometry": locale, "properties": {"render_height": h}, "id": fid})
    if not features:
        return None
    return mapbox_vector_tile.encode(
        [{"name": "building", "features": features}],
        default_options={"extents": ESTENSIONE, "y_coord_down": True},
    )


def prepara(cella, uscita: Path, rilascio: str) -> dict:
    t0 = time.time()
    tabella = leggi(cella, rilascio)
    letti = tabella.num_rows
    per_tessera = tessere_di(cella, tabella)
    del tabella
    file = uscita / f"edifici-{cella[0]}-{cella[1]}-{cella[2]}.pmtiles"
    # Le tessere prima, il file dopo: una cella senza tessere (mare, o
    # edifici tutti nelle celle vicine) non ha pacchetto, e la libreria non sa
    # chiuderne uno vuoto. Si scrive su un file a parte e si rinomina solo a
    # pacchetto finito: un errore a metà non lascia un pacchetto rotto, che la
    # release rifiuterebbe (o peggio, l'app scaricherebbe).
    tessere = []
    for tx, ty in sorted(per_tessera, key=lambda t: zxy_to_tileid(ZOOM, t[0], t[1])):
        dati = tessera_mvt(tx, ty, per_tessera[(tx, ty)])
        if dati is not None:
            tessere.append((zxy_to_tileid(ZOOM, tx, ty), gzip.compress(dati)))
    del per_tessera
    scritte = len(tessere)
    esito = {"cella": "/".join(map(str, cella)), "edifici": letti, "tessere": scritte, "megabyte": 0.0}
    if not scritte:
        esito["secondi"] = round(time.time() - t0)
        return esito
    mezzo = file.with_name(file.name + ".mezzo")
    with open(mezzo, "wb") as f:
        w = Writer(f)
        for tid, dati in tessere:
            w.write_tile(tid, dati)
        ow, os_, oe, on = confini(*cella)
        w.finalize(
            {
                "tile_type": TileType.MVT,
                "tile_compression": Compression.GZIP,
                "min_zoom": ZOOM,
                "max_zoom": ZOOM,
                "min_lon_e7": int(ow * 1e7),
                "min_lat_e7": int(os_ * 1e7),
                "max_lon_e7": int(oe * 1e7),
                "max_lat_e7": int(on * 1e7),
                "center_zoom": ZOOM,
                "center_lon_e7": int((ow + oe) / 2 * 1e7),
                "center_lat_e7": int((os_ + on) / 2 * 1e7),
            },
            {
                "attribution": ATTRIBUZIONE,
                "rilascio_overture": rilascio,
                "vector_layers": [{"id": "building", "fields": {"render_height": "Number"}}],
            },
        )
    mezzo.replace(file)
    esito["megabyte"] = round(file.stat().st_size / 1e6, 1)
    esito["secondi"] = round(time.time() - t0)
    return esito


def main() -> None:
    a = argparse.ArgumentParser()
    a.add_argument("--cella", action="append", default=[], help="z/x/y di una cella (z8; più piccola per provare)")
    a.add_argument("--italia", action="store_true", help="tutte le celle che toccano l'Italia")
    a.add_argument("--elenco", action="store_true", help="solo elencare le celle")
    a.add_argument("--rilascio", default=RILASCIO)
    a.add_argument("--uscita", default="pacchetti")
    o = a.parse_args()
    celle = [tuple(int(v) for v in c.split("/")) for c in o.cella]
    if o.italia:
        celle += celle_italia()
    if o.elenco:
        print(json.dumps(["/".join(map(str, c)) for c in celle]))
        return
    uscita = Path(o.uscita)
    uscita.mkdir(parents=True, exist_ok=True)
    for c in celle:
        print(json.dumps(prepara(c, uscita, o.rilascio)), flush=True)


if __name__ == "__main__":
    sys.exit(main())

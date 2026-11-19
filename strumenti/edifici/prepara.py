"""Gli edifici di Overture Maps in pacchetti PMTiles, uno per cella z8.

«Lungo il percorso voglio vedere le cose reali.» Le tessere di OpenFreeMap
hanno gli edifici di OpenStreetMap, e in molti paesi (Carinaro: 5 edifici entro
150 m da via Torretta, dove è tutto costruito) non li ha disegnati nessuno.
Overture unisce quelli di OpenStreetMap a quelli che Microsoft ha ricavato
dalle foto dal satellite, con l'altezza stimata: lì sono 43.

Ogni pacchetto è una cella z8 (circa 150 km di lato) con le tessere z14 della
scena 3D: un solo livello, `building`, con `render_height` e
`render_min_height` come nelle tessere di OpenFreeMap. L'app scarica il
pacchetto della zona una volta e lo legge dal telefono (e finché non c'è ne
legge le tessere una per una, a pezzi, dalla release).

Le altezze. Di un edificio su tre Overture non dà l'altezza (prima tutti a
8 m: blocchi uguali), e quasi tutte quelle che dà sono stime dalle foto dal
satellite (Microsoft), spesso troppo basse: case di due piani a tre metri,
capannoni a quattro. Le case qui sono di solito di 2-4 piani. Allora:

- l'altezza vera di OpenStreetMap (`height`, o i piani `building:levels`)
  resta com'è;
- una stima dal satellite resta com'è, tranne sotto i [SOTTO_SATELLITE] m su
  un'impronta di più di [AREA_CASA] m², che si stima come quelle che mancano;
- quelle che mancano: la mediana delle altezze vere di OpenStreetMap degli
  edifici attorno (entro [RAGGIO_VICINI] m, o il più vicino entro
  [RAGGIO_LONTANO]); senza nessuna attorno quella delle stime dal satellite
  vicine; senza niente [ALTEZZA_PREDEFINITA]. Almeno due piani
  ([ALTEZZA_MINIMA_STIMA]), al più [ALTEZZA_MASSIMA_STIMA], variata di un 12%
  da edificio a edificio (sempre uguale per lo stesso);
- le impronte piccolissime (sotto [AREA_BOX] m²: box, garage) senza altezza
  vera fra 3 e 4 m.

Le parti. Un edificio fatto di corpi diversi (una torre su un basamento, una
chiesa col campanile) in Overture ha le sue parti (`building_part`, con
altezza e quota da cui partono): al posto del contorno, che sarebbe un blocco
solo, si mettono le parti, come fanno le mappe 3D di OpenStreetMap.

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
import pyarrow as pa
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
ALTEZZA_PIANO = 3.25
RAGGIO_VICINI = 80.0
RAGGIO_LONTANO = 400.0
# Le stime: almeno due piani, al più una decina.
ALTEZZA_MINIMA_STIMA = 6.5
ALTEZZA_MASSIMA_STIMA = 30.0
# Una stima dal satellite più bassa di così, su un'impronta più grande di
# [AREA_CASA] m², non è credibile (una casa, un capannone): si stima.
SOTTO_SATELLITE = 5.0
AREA_CASA = 80.0
# Sotto questa impronta (m²) un box o un garage: fra 3 e 4 m.
AREA_BOX = 30.0
# Le stime dal satellite vicine più basse di così non contano.
ALTEZZA_MINIMA_VICINI = 2.5
OSM = "OpenStreetMap"
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


COLONNE = ["id", "geometry", "height", "min_height", "num_floors", "min_floor", "sources"]


def leggi(cella: tuple[int, int, int], rilascio: str, tipo: str = "building", sorgente: str | None = None):
    """Gli edifici (o le parti, [tipo] «building_part») di Overture che
    toccano la cella: geometrie WKB, altezze, piani. [sorgente]: una cartella
    o un file parquet sul disco al posto del rilascio (per provare)."""
    w, s, e, n = confini(*cella)
    if sorgente:
        d = ds.dataset(sorgente, format="parquet")
    else:
        fs = pfs.S3FileSystem(anonymous=True, region="us-west-2")
        d = ds.dataset(
            f"overturemaps-us-west-2/release/{rilascio}/theme=buildings/type={tipo}/",
            filesystem=fs,
            format="parquet",
        )
    filtro = (
        (pc.field("bbox", "xmax") > w)
        & (pc.field("bbox", "xmin") < e)
        & (pc.field("bbox", "ymax") > s)
        & (pc.field("bbox", "ymin") < n)
    )
    nomi = set(d.schema.names)
    colonne = [c for c in COLONNE + (["building_id"] if tipo == "building_part" else ["has_parts"]) if c in nomi]
    return d.to_table(columns=colonne, filter=filtro)


def _numeri(tabella, colonna: str) -> np.ndarray:
    """La colonna come float, NaN dove manca (o la colonna non c'è)."""
    if colonna not in tabella.column_names:
        return np.full(tabella.num_rows, np.nan)
    v = tabella.column(colonna).to_numpy(zero_copy_only=False)
    return np.array([np.nan if x is None else float(x) for x in v], dtype=float)


def _seme(fid: str) -> float:
    """Un numero fra 0 e 1 dall'id dell'edificio: sempre lo stesso."""
    return int(hashlib.blake2b(fid.encode(), digest_size=4).hexdigest(), 16) / 0xFFFFFFFF


def _fonte(fonti, proprieta: str) -> str | None:
    """Da che dataset viene [proprieta] («height»…), secondo `sources` di
    Overture: la voce di quella proprietà se c'è, se no quella dell'edificio."""
    if not fonti:
        return None
    tutto = None
    for f in fonti:
        # «/properties/height» nei parquet, «properties/height» altrove.
        p = (f.get("property") or "").lstrip("/")
        if p == f"properties/{proprieta}":
            return f.get("dataset")
        if p == "":
            tutto = f.get("dataset")
    return tutto


def fonti_altezza(tabella) -> tuple[np.ndarray, np.ndarray]:
    """Per ogni riga: se l'altezza e se i piani vengono da OpenStreetMap."""
    n = tabella.num_rows
    if "sources" not in tabella.column_names:
        return np.zeros(n, bool), np.zeros(n, bool)
    fonti = tabella.column("sources").to_pylist()
    h_osm = np.array([_fonte(f, "height") == OSM for f in fonti])
    p_osm = np.array([_fonte(f, "num_floors") == OSM for f in fonti])
    return h_osm, p_osm


def area_m2(geometrie) -> np.ndarray:
    """L'area delle impronte in m², alla buona (lon per il coseno)."""
    c = shapely.get_coordinates(shapely.centroid(geometrie))
    return shapely.area(geometrie) * 111320.0 * 110540.0 * np.cos(np.radians(c[:, 1]))


def _mediane(albero, valori: np.ndarray, punti, raggio: float) -> np.ndarray:
    """Per ogni punto la mediana dei [valori] dell'[albero] entro [raggio] (NaN se nessuno)."""
    stima = np.full(len(punti), np.nan)
    coppie = albero.query(punti, predicate="dwithin", distance=raggio)
    if not coppie.shape[1]:
        return stima
    chi, vicino = coppie
    v = valori[vicino]
    ordine = np.lexsort((v, chi))
    chi, v = chi[ordine], v[ordine]
    inizi = np.flatnonzero(np.r_[True, chi[1:] != chi[:-1]])
    fini = np.r_[inizi[1:], len(chi)]
    for a, b in zip(inizi, fini, strict=True):
        k = b - a
        stima[chi[a]] = v[a + k // 2] if k % 2 else (v[a + k // 2 - 1] + v[a + k // 2]) / 2
    return stima


def altezze(
    geometrie,
    altezza: np.ndarray,
    piani: np.ndarray,
    ids: list[str],
    altezza_osm: np.ndarray | None = None,
    piani_osm: np.ndarray | None = None,
) -> tuple[np.ndarray, np.ndarray]:
    """Le altezze degli edifici, e quali sono stimate (vedi in cima al file).

    [altezza_osm], [piani_osm]: se l'altezza e i piani vengono da
    OpenStreetMap (senza: l'altezza dal satellite, i piani da OpenStreetMap)."""
    n = len(ids)
    altezza_osm = np.zeros(n, bool) if altezza_osm is None else altezza_osm
    piani_osm = np.ones(n, bool) if piani_osm is None else piani_osm
    c_alt = np.isfinite(altezza) & (altezza > 0)
    c_pia = np.isfinite(piani) & (piani > 0)
    # Le altezze vere: di OpenStreetMap, o i suoi piani.
    vera = (c_alt & altezza_osm) | (~(c_alt & altezza_osm) & c_pia & piani_osm)
    h = np.full(n, np.nan)
    h[c_alt & altezza_osm] = altezza[c_alt & altezza_osm]
    dai_piani = vera & ~(c_alt & altezza_osm)
    h[dai_piani] = piani[dai_piani] * ALTEZZA_PIANO
    # Dal satellite: restano, tranne le troppo basse sulle impronte grandi.
    satellite = c_alt & ~vera
    area = area_m2(geometrie)
    h[satellite] = altezza[satellite]
    bassa = satellite & (altezza < SOTTO_SATELLITE) & (area > AREA_CASA)
    stimate = ~vera & (~satellite | bassa)
    h[stimate] = np.nan
    if not stimate.any():
        return h, stimate
    semi = np.array([_seme(ids[i]) for i in np.flatnonzero(stimate)])
    # I box e i garage: fra 3 e 4 m.
    box = area[stimate] < AREA_BOX
    # In metri, alla buona (basta per cercare i vicini).
    xy = shapely.get_coordinates(shapely.centroid(geometrie))
    lat0 = np.radians(np.nanmean(xy[:, 1]))
    punti = shapely.points(np.column_stack((xy[:, 0] * 111320.0 * np.cos(lat0), xy[:, 1] * 110540.0)))
    i_stimate = np.flatnonzero(stimate)
    stima = np.full(len(i_stimate), np.nan)
    i_vere = np.flatnonzero(vera)
    if len(i_vere):
        albero = shapely.STRtree(punti[i_vere])
        stima = _mediane(albero, h[i_vere], punti[i_stimate], RAGGIO_VICINI)
        senza = np.flatnonzero(np.isnan(stima))
        if len(senza):
            chi, vicino = albero.query_nearest(punti[i_stimate[senza]], max_distance=RAGGIO_LONTANO)
            stima[senza[chi]] = h[i_vere[vicino]]
    senza = np.flatnonzero(np.isnan(stima))
    i_sat = np.flatnonzero(satellite & ~bassa & (h >= ALTEZZA_MINIMA_VICINI))
    if len(senza) and len(i_sat):
        stima[senza] = _mediane(shapely.STRtree(punti[i_sat]), h[i_sat], punti[i_stimate[senza]], RAGGIO_VICINI)
    stima = np.where(np.isnan(stima), ALTEZZA_PREDEFINITA, stima)
    base = np.clip(stima, ALTEZZA_MINIMA_STIMA, ALTEZZA_MASSIMA_STIMA)
    variata = base * (1.0 + 0.24 * (semi - 0.5))
    # Sotto i due piani non si scende: lì la variazione va solo in su.
    variata = np.where(variata < ALTEZZA_MINIMA_STIMA, ALTEZZA_MINIMA_STIMA * (1.0 + 0.12 * semi), variata)
    variata = np.minimum(variata, ALTEZZA_MASSIMA_STIMA)
    h[i_stimate] = np.where(box, 3.0 + semi, variata)
    return h, stimate


def in_metri_tessera(geom, tx: int, ty: int):
    """Da lon/lat alle coordinate della tessera z14 (0…4096, y in giù)."""
    scala = 2**ZOOM

    def trasforma(coords):
        px = (coords[:, 0] + 180.0) / 360.0 * scala
        r = np.radians(coords[:, 1])
        py = (1.0 - np.log(np.tan(r) + 1.0 / np.cos(r)) / np.pi) / 2.0 * scala
        return np.column_stack(((px - tx) * ESTENSIONE, (py - ty) * ESTENSIONE))

    return shapely.transform(geom, trasforma)


def con_le_parti(edifici, parti):
    """Gli edifici, con le parti al posto dei contorni che le hanno.

    Una tabella sola, con le colonne degli edifici più `parte` (vero per le
    parti). Un contorno si toglie solo se almeno una sua parte c'è davvero
    (con la geometria): altrimenti resta, e l'edificio non sparisce."""
    if parti is None or parti.num_rows == 0 or "building_id" not in parti.column_names:
        return edifici.append_column("parte", pa.array([False] * edifici.num_rows))
    padri = set(x for x in parti.column("building_id").to_pylist() if x)
    ids = edifici.column("id").to_pylist()
    ha = edifici.column("has_parts").to_pylist() if "has_parts" in edifici.column_names else [True] * len(ids)
    via = np.array([bool(h) and i in padri for i, h in zip(ids, ha, strict=True)])
    restano = edifici.filter(pa.array(~via))
    tolti = pa.array([i for i, v in zip(ids, via, strict=True) if v], type=pa.string())
    usate = parti.filter(pc.is_in(parti.column("building_id"), value_set=tolti))
    colonne = [c for c in restano.column_names if c != "has_parts"]
    restano = restano.select(colonne)
    usate = usate.select([c for c in colonne if c in usate.column_names])
    for c in colonne:
        if c not in usate.column_names:
            usate = usate.append_column(c, pa.nulls(usate.num_rows, restano.schema.field(c).type))
    usate = usate.select(colonne).cast(restano.schema)
    return pa.concat_tables(
        [
            restano.append_column("parte", pa.array([False] * restano.num_rows)),
            usate.append_column("parte", pa.array([True] * usate.num_rows)),
        ]
    )


def tessere_di(cella, tabella):
    """Ogni edificio nelle tessere z14 che tocca, ritagliato col margine:
    `(indice, geometria, altezza, da dove parte, id)`."""
    cz, cx, cy = cella
    k = 2 ** (ZOOM - cz)
    dentro = (cx * k, (cx + 1) * k, cy * k, (cy + 1) * k)
    geometrie = shapely.from_wkb(tabella.column("geometry").to_numpy(zero_copy_only=False))
    ids = tabella.column("id").to_pylist()
    valide = np.array([g is not None and not g.is_empty for g in geometrie])
    h = np.full(len(ids), ALTEZZA_PREDEFINITA)
    if valide.any():
        quali = np.flatnonzero(valide)
        h_osm, p_osm = fonti_altezza(tabella)
        hv, _ = altezze(
            geometrie[valide],
            _numeri(tabella, "height")[valide],
            _numeri(tabella, "num_floors")[valide],
            [ids[i] for i in quali],
            h_osm[valide],
            p_osm[valide],
        )
        h[valide] = hv
    # Da dove parte (una parte sopra un'altra, un porticato): la quota, o i piani sotto.
    minimo = _numeri(tabella, "min_height")
    piani_sotto = _numeri(tabella, "min_floor")
    dai_piani = np.where(np.isfinite(piani_sotto) & (piani_sotto > 0), piani_sotto * ALTEZZA_PIANO, 0.0)
    minimo = np.where(np.isfinite(minimo) & (minimo > 0), minimo, dai_piani)
    limiti = shapely.bounds(geometrie)
    per_tessera: dict[tuple[int, int], list] = defaultdict(list)
    for i, g in enumerate(geometrie):
        if not valide[i]:
            continue
        w, s, e, n = limiti[i]
        x0, x1 = int(lon_x(w, ZOOM)), int(lon_x(e, ZOOM))
        y0, y1 = int(lat_y(n, ZOOM)), int(lat_y(s, ZOOM))
        fid = int(hashlib.blake2b(ids[i].encode(), digest_size=6).hexdigest(), 16)
        mh = float(minimo[i]) if minimo[i] < h[i] - 0.5 else 0.0
        for tx in range(x0, x1 + 1):
            for ty in range(y0, y1 + 1):
                # Solo le tessere di questa cella: quelle di confine le fa la vicina.
                if not (dentro[0] <= tx < dentro[1] and dentro[2] <= ty < dentro[3]):
                    continue
                per_tessera[(tx, ty)].append((i, g, round(float(h[i]), 1), round(mh, 1), fid))
    return per_tessera


def tessera_mvt(tx: int, ty: int, edifici) -> bytes | None:
    features = []
    for _, g, h, mh, fid in edifici:
        locale = in_metri_tessera(g, tx, ty)
        locale = shapely.clip_by_rect(locale, -MARGINE, -MARGINE, ESTENSIONE + MARGINE, ESTENSIONE + MARGINE)
        if locale.is_empty or locale.area < 1:
            continue
        proprieta = {"render_height": h}
        if mh > 0:
            proprieta["render_min_height"] = mh
        features.append({"geometry": locale, "properties": proprieta, "id": fid})
    if not features:
        return None
    return mapbox_vector_tile.encode(
        [{"name": "building", "features": features}],
        default_options={"extents": ESTENSIONE, "y_coord_down": True},
    )


def prepara(cella, uscita: Path, rilascio: str, sorgente: str | None = None, sorgente_parti: str | None = None) -> dict:
    t0 = time.time()
    tabella = leggi(cella, rilascio, sorgente=sorgente)
    letti = tabella.num_rows
    if sorgente and not sorgente_parti:
        parti = None
    else:
        parti = leggi(cella, rilascio, tipo="building_part", sorgente=sorgente_parti)
    tabella = con_le_parti(tabella, parti)
    n_parti = int(pc.sum(tabella.column("parte")).as_py() or 0)
    del parti
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
    esito = {
        "cella": "/".join(map(str, cella)),
        "edifici": letti,
        "parti": n_parti,
        "tessere": scritte,
        "megabyte": 0.0,
    }
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
                "vector_layers": [
                    {"id": "building", "fields": {"render_height": "Number", "render_min_height": "Number"}}
                ],
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
    a.add_argument("--parquet", help="gli edifici da un parquet sul disco (per provare)")
    a.add_argument("--parquet-parti", help="le parti da un parquet sul disco (per provare)")
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
        print(json.dumps(prepara(c, uscita, o.rilascio, o.parquet, o.parquet_parti)), flush=True)


if __name__ == "__main__":
    sys.exit(main())

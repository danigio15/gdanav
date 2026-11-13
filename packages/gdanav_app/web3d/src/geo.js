// Coordinate: Mercatore (0..1 come MapLibre), tessere, metri locali.
//
// Ogni tessera z14 ha il suo sistema in metri: x verso est, y verso nord,
// l'origine nel centro della tessera e la scala di Mercatore della sua
// latitudine di mezzo. Sono gli stessi metri di MapLibre
// (`meterInMercatorCoordinateUnits`), così la scena 3D cade esatta sulla
// mappa di sotto.

export const RAGGIO_TERRA = 6371008.8;
export const ESTENSIONE = 4096;

export const mercX = (lon) => (lon + 180) / 360;
export const mercY = (lat) => {
  const r = (lat * Math.PI) / 180;
  return (1 - Math.log(Math.tan(r) + 1 / Math.cos(r)) / Math.PI) / 2;
};
export const lonDaMerc = (mx) => mx * 360 - 180;
export const latDaMerc = (my) => {
  const n = Math.PI - 2 * Math.PI * my;
  return (180 / Math.PI) * Math.atan(0.5 * (Math.exp(n) - Math.exp(-n)));
};

/** Unità di Mercatore per metro alla latitudine [lat] (come MapLibre). */
export const mercPerMetro = (lat) => 1 / (2 * Math.PI * RAGGIO_TERRA) / Math.cos((lat * Math.PI) / 180);

/**
 * Il sistema in metri della tessera z/x/y: dove sta il suo centro in
 * Mercatore, la scala, e le funzioni per passare dai pixel della tessera
 * (globali: `tx * 4096 + px`) ai metri e ritorno.
 */
export function sistemaTessera(z, x, y) {
  const n = 2 ** z;
  const mx = (x + 0.5) / n;
  const my = (y + 0.5) / n;
  const s = mercPerMetro(latDaMerc(my));
  const lato = 1 / n / s; // metri per lato
  return {
    z,
    x,
    y,
    mx,
    my,
    s,
    lato,
    /** Dai pixel globali della tessera (z) ai metri locali. */
    metri: (gx, gy) => [((gx / ESTENSIONE) / n - mx) / s, -(((gy / ESTENSIONE) / n - my) / s)],
    /** Da longitudine e latitudine ai metri locali. */
    daLonLat: (lon, lat) => [(mercX(lon) - mx) / s, -(mercY(lat) - my) / s],
  };
}

/** La chiave di una tessera: «14/8603/5853». */
export const chiave = (z, x, y) => `${z}/${x}/${y}`;

export function daChiave(k) {
  const [z, x, y] = k.split('/').map(Number);
  return { z, x, y };
}

/**
 * Lo spazio che le schede coprono ai lati, in punti della pagina larga
 * [larghezza]: `[sinistra, destra]`, mai più di sette decimi in tutto.
 *
 * Ognuno dei due era tagliato a 0,45 della larghezza: quando la parte libera
 * è meno di metà superficie e tutta da un lato (lo schermo diviso dell'auto,
 * con la mappa in un pannello stretto) l'auto non stava più in mezzo alla
 * parte libera, ma spostata verso quella coperta. Tagliati insieme, in
 * proporzione, il mezzo resta il mezzo.
 */
export function marginiAiLati(sinistra, destra, larghezza) {
  let s = Number.isFinite(sinistra) ? Math.max(0, sinistra) : 0;
  let d = Number.isFinite(destra) ? Math.max(0, destra) : 0;
  const tetto = larghezza * 0.7;
  if (s + d > tetto && s + d > 0) {
    const k = tetto / (s + d);
    s *= k;
    d *= k;
  }
  return [s, d];
}

/**
 * Gli ultimi [metri] (almeno) della linea `[lon, lat, lon, lat, …]`
 * [lonlat], contati a ritroso dall'ultimo punto; la linea intera se è più
 * corta. Le distanze sono quelle piatte (un metro su qualche migliaio):
 * basta per sapere da dove cominciare.
 */
export function codaDi(lonlat, metri) {
  const n = lonlat.length;
  if (n < 4) return lonlat;
  const mLat = (Math.PI / 180) * RAGGIO_TERRA;
  let s = 0;
  for (let i = n - 4; i >= 0; i -= 2) {
    const mLon = mLat * Math.cos((lonlat[i + 1] * Math.PI) / 180);
    s += Math.hypot((lonlat[i + 2] - lonlat[i]) * mLon, (lonlat[i + 3] - lonlat[i + 1]) * mLat);
    if (s >= metri) return i === 0 ? lonlat : lonlat.slice(i);
  }
  return lonlat;
}

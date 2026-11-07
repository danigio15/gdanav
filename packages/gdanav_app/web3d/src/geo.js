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

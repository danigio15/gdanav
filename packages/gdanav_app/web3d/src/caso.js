// Numeri a caso ma sempre gli stessi: gli alberi di una tessera nascono
// dove nascevano l'ultima volta, perché il seme è la tessera.

/** Un generatore (mulberry32) che parte da [seme]. */
export function generatore(seme) {
  let s = seme >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Un numero fra 0 e 1 da due interi: lo stesso per gli stessi. */
export function mescola(a, b) {
  let h = Math.imul(a | 0, 374761393) + Math.imul(b | 0, 668265263);
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
}

/** Il seme di una tessera. */
export const semeTessera = (z, x, y) => (Math.imul(x, 73856093) ^ Math.imul(y, 19349663) ^ Math.imul(z, 83492791)) >>> 0;

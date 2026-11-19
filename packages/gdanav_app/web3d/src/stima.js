// Le corsie stimate: la vista «Corsie» quando le corsie vere non ci sono.
//
// Le corsie vere arrivano dal relay (il messaggio `corsie`, vedi
// `corsie.js`), che le prende da Overpass: se Overpass non risponde, o la
// tessera non è ancora arrivata, o è arrivata vuota, la vista restava una
// fascia verde sull'asfalto scuro. Qui le stesse vie, stimate dalla tessera
// vettoriale che la scena ha già (il livello `transportation` di
// OpenMapTiles): la classe, se è una rampa, il senso unico, i ponti e le
// gallerie. Escono nel formato del messaggio `corsie` (versione 1), senza
// `lanes`: le corsie le dà la classe ([corsieDi] in corsie.js), come per una
// via vera senza il tag. Niente nodi (strisce, semafori, stop) e niente
// alberi: quelli la tessera non li dice, e non si inventano.
//
// Le linee delle tessere vettoriali sono tagliate sul bordo e non hanno un
// id: ogni via stimata è il pezzo di una linea dentro la sua tessera (come
// le strade di `costruisciTessera`), con un id negativo fatto dalla tessera e
// dal posto della linea nel livello ([idStimato]). Le vie vere hanno l'id di
// OpenStreetMap, positivo: non si confondono. Ogni pezzo sta in una tessera
// sola, e la tessera vicina lo vede uguale (lo stesso pezzo, lo stesso id, i
// capi sul bordo uniti allo stesso punto, [uniscIBordi]): sul bordo niente
// buchi né doppioni.

import { infittisci, preparaCorsie } from './corsie.js';
import { CLASSI_STRADE, uniscIBordi } from './elevazione.js';
import { ESTENSIONE, latDaMerc, lonDaMerc } from './geo.js';
import { ritagliaLinea } from './ritaglio.js';
import { stradaVera } from './tessera.js';

/** Fin dove fuori dalla tessera si prendono le vie delle vicine (m): per sapere chi tocca chi sul bordo. */
export const MARGINE_STIMA_M = 80;
/**
 * Un punto almeno ogni tanti metri. Le linee delle tessere hanno pochi punti
 * (una rampa dritta: i due capi), e la quota delle corsie si prende punto per
 * punto dalle strade della scena, che lì salgono verso il ponte.
 */
export const PASSO_STIMA_M = 8;

const rampa = (p) => p.ramp === 1 || p.ramp === '1' || p.ramp === true;
const si = (v) => v === 1 || v === '1' || v === true;

/**
 * La classe di OpenStreetMap (`highway`) di una strada della tessera, dalle
 * sue proprietà di OpenMapTiles; `null` se non ha corsie (le strade di
 * servizio, i sentieri, i binari). `minor` (le strade di quartiere, le
 * unclassified, le living_street insieme) è `residential`; una superstrada
 * (`expressway`) che non è autostrada è una `trunk` (corsie da 3,5 m,
 * niente marciapiedi); le rampe sono i `_link`.
 */
export function classeStimata(p) {
  const c = p.class;
  const link = rampa(p) ? '_link' : '';
  if (c === 'motorway' || c === 'trunk') return c + link;
  if (c === 'primary' || c === 'secondary' || c === 'tertiary') return (si(p.expressway) ? 'trunk' : c) + link;
  if (c === 'minor') return 'residential';
  return null;
}

/** I tag di OpenStreetMap di una strada della tessera (senza `lanes`: le dà la classe). */
export function tagStimati(p) {
  const t = {};
  const o = +p.oneway;
  if (o === 1) t.oneway = 'yes';
  else if (o === -1) t.oneway = '-1';
  if (p.brunnel === 'bridge') t.bridge = 'yes';
  else if (p.brunnel === 'tunnel') t.tunnel = 'yes';
  const l = parseInt(p.layer, 10);
  if (Number.isFinite(l) && l !== 0) t.layer = String(l);
  return t;
}

/**
 * L'id di una via stimata: negativo (le vere sono positive), dalla tessera
 * z/x/y, dal numero della linea nel livello `transportation` della tessera
 * (contate solo le strade, nell'ordine delle feature) e dal pezzo della
 * linea dentro la tessera. Lo stesso pezzo ha lo stesso id da qualunque
 * tessera lo si guardi; sta sotto `Number.MAX_SAFE_INTEGER` fino a z14.
 */
export function idStimato(z, x, y, linea, pezzo) {
  const tessera = y * 2 ** z + x;
  return -(tessera * 2 ** 24 + (linea % 2 ** 18) * 64 + Math.min(pezzo, 63) + 1);
}

const sei = (v) => Math.round(v * 1e6) / 1e6;

/**
 * Le corsie stimate attorno alla tessera z/x/y, nel formato del messaggio
 * `corsie` (versione 1): `{v, z, x, y, stimate: true, strade}`. [livelli]:
 * le tessere decodificate per spostamento `"dx,dy"`, come per
 * `costruisciTessera`; delle vicine solo le vie entro [margineM] dal bordo.
 * Ogni via ha `t`: la tessera del suo pezzo (`"z/x/y"`).
 */
export function corsieStimate({ z, x, y, livelli, margineM = MARGINE_STIMA_M }) {
  const n = 2 ** z;
  // I metri di un pixel, al centro della tessera (basta per il margine).
  const lat = latDaMerc((y + 0.5) / n);
  const latoM = ((2 * Math.PI * 6371008.8) / n) * Math.cos((lat * Math.PI) / 180);
  const marginePx = (margineM * ESTENSIONE) / latoM;
  const passoPx = (PASSO_STIMA_M * ESTENSIONE) / latoM;
  const pezzi = [];
  for (const [off, layers] of Object.entries(livelli)) {
    const [dx, dy] = off.split(',').map(Number);
    const T = layers?.transportation;
    if (!T) continue;
    const tx = x + dx;
    const ty = y + dy;
    const ox = tx * ESTENSIONE;
    const oy = ty * ESTENSIONE;
    // Il riquadro della tessera di mezzo, allargato, nei pixel di questa.
    const minx = -dx * ESTENSIONE - marginePx;
    const maxx = (1 - dx) * ESTENSIONE + marginePx;
    const miny = -dy * ESTENSIONE - marginePx;
    const maxy = (1 - dy) * ESTENSIONE + marginePx;
    let numero = 0;
    for (let i = 0; i < T.length; i++) {
      const f = T.feature(i);
      const p = stradaVera(f.properties);
      // Come `costruisciTessera`: le linee delle strade, contate tutte (anche
      // quelle lontane che non si prendono), perché il numero resti quello.
      if (f.type !== 2 || !CLASSI_STRADE.has(p.class)) continue;
      const hw = classeStimata(p);
      for (const linea of f.loadGeometry()) {
        const quale = numero++;
        if (!hw) continue;
        const pts = linea.map((q) => [q.x, q.y]);
        if (dx || dy) {
          if (!pts.some(([qx, qy]) => qx >= minx && qx <= maxx && qy >= miny && qy <= maxy)) continue;
        }
        ritagliaLinea(pts, 0, 0, ESTENSIONE, ESTENSIONE).forEach((pezzo, k) => {
          if (pezzo.length < 2) return;
          pezzi.push({ hw, p, id: idStimato(z, tx, ty, quale, k), t: `${z}/${tx}/${ty}`, g: pezzo.map(([px, py]) => [ox + px, oy + py]) });
        });
      }
    }
  }
  // I capi sul bordo fra due tessere: allo stesso punto da tutte e due.
  uniscIBordi(pezzi);
  const strade = [];
  for (const q of pezzi) {
    const g = [];
    for (const [px, py] of infittisci(q.g, passoPx)) {
      const lon = sei(lonDaMerc(px / ESTENSIONE / n));
      const la = sei(latDaMerc(py / ESTENSIONE / n));
      // Due punti uguali di fila (dopo i sei decimali) non servono.
      if (g.length && g[g.length - 2] === lon && g[g.length - 1] === la) continue;
      g.push(lon, la);
    }
    if (g.length < 4) continue;
    strade.push({ id: q.id, hw: q.hw, g, ...tagStimati(q.p), t: q.t });
  }
  return { v: 1, z, x, y, stimate: true, strade, nodi: [], alberi: [], filari: [] };
}

/**
 * Le corsie stimate pronte per la tessera (vedi `preparaCorsie`), segnate
 * `stimata`: il tratteggio fra le corsie si adatta a ogni pezzo, perché
 * nasce e finisce sul bordo della tessera (vedi `riga` in segnaletica.js).
 */
export function preparaStimate(dati) {
  const c = preparaCorsie(dati);
  for (const v of c.strade) v.stimata = true;
  return c;
}

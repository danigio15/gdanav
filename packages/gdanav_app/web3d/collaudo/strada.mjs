// Per il collaudo: le tessere vere di OpenFreeMap (con una copia su disco)
// e un percorso vero fra due punti, trovato sul grafo delle strade (Dijkstra,
// coi sensi unici). Al posto di Valhalla, che qui non c'è: basta un percorso
// credibile che passi sui viadotti.
import { VectorTile } from '@mapbox/vector-tile';
import Pbf from 'pbf';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { grafoStrade, uniscIBordi, CLASSI_STRADE } from '../src/elevazione.js';
import { ESTENSIONE, latDaMerc, lonDaMerc, mercX, mercY, sistemaTessera } from '../src/geo.js';
import { ritagliaLinea } from '../src/ritaglio.js';

export const CACHE = process.env.CACHE_TESSERE ?? path.join(os.tmpdir(), 'gdanav3d-tessere');
fs.mkdirSync(CACHE, { recursive: true });

/** Una risposta di OpenFreeMap, dalla copia su disco se c'è. */
export async function scarica(url) {
  const f = path.join(CACHE, crypto.createHash('md5').update(url).digest('hex'));
  if (fs.existsSync(f)) return { corpo: fs.readFileSync(f), tipo: fs.readFileSync(f + '.t', 'utf8'), stato: +fs.readFileSync(f + '.s', 'utf8') };
  for (let k = 0; ; k++) {
    try {
      const r = await fetch(url);
      const corpo = Buffer.from(await r.arrayBuffer());
      const tipo = r.headers.get('content-type') ?? 'application/octet-stream';
      if (r.ok || r.status === 204 || r.status === 404) {
        fs.writeFileSync(f, corpo);
        fs.writeFileSync(f + '.t', tipo);
        fs.writeFileSync(f + '.s', String(r.status));
      }
      return { corpo, tipo, stato: r.status };
    } catch (e) {
      if (k >= 3) throw e;
      await new Promise((r) => setTimeout(r, 600 * (k + 1)));
    }
  }
}

let modello = null;
export async function tessera(z, x, y) {
  if (!modello) {
    const tj = JSON.parse((await scarica('https://tiles.openfreemap.org/planet')).corpo.toString());
    modello = tj.tiles[0];
  }
  const r = await scarica(modello.replace('{z}', z).replace('{x}', x).replace('{y}', y));
  return new VectorTile(new Pbf(r.corpo));
}

const tx = (lon) => Math.floor(mercX(lon) * 2 ** 14);
const ty = (lat) => Math.floor(mercY(lat) * 2 ** 14);

/** Il grafo delle strade attorno a [lon, lat] (raggio in tessere). */
export async function grafoAttorno(lon, lat, raggio = 1) {
  const cx = tx(lon);
  const cy = ty(lat);
  const sys = sistemaTessera(14, cx, cy);
  const strade = [];
  for (let dx = -raggio; dx <= raggio; dx++) {
    for (let dy = -raggio; dy <= raggio; dy++) {
      const t = await tessera(14, cx + dx, cy + dy);
      const T = t.layers.transportation;
      for (let i = 0; T && i < T.length; i++) {
        const f = T.feature(i);
        if (f.type !== 2 || !CLASSI_STRADE.has(f.properties.class)) continue;
        for (const l of f.loadGeometry()) {
          for (const pezzo of ritagliaLinea(
            l.map((q) => [q.x, q.y]),
            0,
            0,
            ESTENSIONE,
            ESTENSIONE,
          )) {
            strade.push({ p: f.properties, g: pezzo.map(([px, py]) => [(cx + dx) * ESTENSIONE + px, (cy + dy) * ESTENSIONE + py]) });
          }
        }
      }
    }
  }
  uniscIBordi(strade);
  const g = grafoStrade(strade, sys.metri, { iterazioni: 300 });
  const lonlat = (x, y) => [lonDaMerc(sys.mx + x * sys.s), latDaMerc(sys.my - y * sys.s)];
  const metri = (lo, la) => [(mercX(lo) - sys.mx) / sys.s, -(mercY(la) - sys.my) / sys.s];
  return { ...g, sys, lonlat, metri };
}

const GUIDABILI = new Set(['motorway', 'trunk', 'primary', 'secondary', 'tertiary']);

/** I [k] nodi più vicini a [x, y] su una strada che passa il [filtro]. */
function piuVicini(g, x, y, filtro, k = 30) {
  const tutti = [];
  g.nodi.forEach((n, i) => {
    if (filtro && !n.feats.some((fi) => filtro(g.feats[fi]))) return;
    tutti.push([Math.hypot(n.x - x, n.y - y), i]);
  });
  return tutti
    .sort((a, b) => a[0] - b[0])
    .slice(0, k)
    .map(([, i]) => i);
}

function dijkstra(g, a, b) {
  const dist = new Float64Array(g.nodi.length).fill(Infinity);
  const prima = new Int32Array(g.nodi.length).fill(-1);
  dist[a] = 0;
  const coda = [[0, a]];
  while (coda.length) {
    let k = 0;
    for (let j = 1; j < coda.length; j++) if (coda[j][0] < coda[k][0]) k = j;
    const [v, i] = coda.splice(k, 1)[0];
    if (v > dist[i]) continue;
    if (i === b) break;
    for (const e of g.nodi[i].adj) {
      const f = g.feats[e.f];
      if (!GUIDABILI.has(f.cls) || f.galleria) continue;
      if (f.senso === 1 && !e.avanti) continue;
      if (f.senso === -1 && e.avanti) continue;
      const nv = v + e.d;
      if (nv < dist[e.to]) {
        dist[e.to] = nv;
        prima[e.to] = i;
        coda.push([nv, e.to]);
      }
    }
  }
  if (prima[b] < 0) return null;
  const p = [];
  for (let c = b; c >= 0; c = prima[c]) p.push(c);
  return p.reverse();
}

/**
 * Un percorso per i punti [via] (`{lon, lat, rampa?, cls?, livello?}`): i
 * nodi più vicini (con quel tipo di strada), uniti dai cammini più corti.
 * Restituisce `[lon, lat, …]` piatto e quanto è lungo.
 */
export async function percorso(centro, via, raggio = 1) {
  const g = await grafoAttorno(centro[0], centro[1], raggio);
  const filtro = (v) => (f) =>
    GUIDABILI.has(f.cls) && !f.galleria && (v.rampa === undefined || f.rampa === v.rampa) && (v.cls === undefined || f.cls === v.cls) && (v.livello === undefined || f.livello === v.livello);
  let nodi = [];
  for (let k = 0; k < via.length - 1; k++) {
    // Il nodo vicino può stare sulla carreggiata dell'altro senso: si provano i più vicini.
    const da = k ? [nodi.at(-1)] : piuVicini(g, ...g.metri(via[k].lon, via[k].lat), filtro(via[k]), 12);
    const a2 = piuVicini(g, ...g.metri(via[k + 1].lon, via[k + 1].lat), filtro(via[k + 1]), 40);
    let p = null;
    for (const a of da) {
      for (const b of a2) {
        p = dijkstra(g, a, b);
        if (p) break;
      }
      if (p) break;
    }
    if (!p) throw new Error(`nessun percorso fra i punti ${k} e ${k + 1}`);
    nodi = nodi.concat(k ? p.slice(1) : p);
  }
  // Un punto ogni 15 metri circa, come una polilinea di Valhalla.
  const punti = [];
  let ultimo = null;
  let lunghezza = 0;
  let massima = 0;
  for (const [j, i] of nodi.entries()) {
    const n = g.nodi[i];
    massima = Math.max(massima, n.h);
    if (ultimo) lunghezza += Math.hypot(n.x - ultimo.x, n.y - ultimo.y);
    if (j && j < nodi.length - 1 && ultimo && Math.hypot(n.x - punti.at(-1).x, n.y - punti.at(-1).y) < 15) {
      ultimo = n;
      continue;
    }
    punti.push(n);
    ultimo = n;
  }
  return { punti: punti.flatMap((n) => g.lonlat(n.x, n.y)), lunghezza, quotaMassima: massima, g };
}

/** I punti del prototipo (metri attorno al centro di Rho/Pero) in longitudine e latitudine. */
export function daMetriPrototipo(x, y) {
  const C = { lat: 45.5172, lon: 9.087 };
  const s = 1 / (2 * Math.PI * 6371008.8) / Math.cos((C.lat * Math.PI) / 180);
  return [lonDaMerc(mercX(C.lon) + x * s), latDaMerc(mercY(C.lat) - y * s)];
}

/** Le distanze da [da] lungo le strade guidabili (all'indietro con [indietro]). */
function distanze(g, da, indietro = false) {
  const dist = new Float64Array(g.nodi.length).fill(Infinity);
  const prima = new Int32Array(g.nodi.length).fill(-1);
  dist[da] = 0;
  const coda = [[0, da]];
  while (coda.length) {
    let k = 0;
    for (let j = 1; j < coda.length; j++) if (coda[j][0] < coda[k][0]) k = j;
    const [v, i] = coda.splice(k, 1)[0];
    if (v > dist[i] || v > 2500) continue;
    for (const e of g.nodi[i].adj) {
      const f = g.feats[e.f];
      if (!GUIDABILI.has(f.cls) || f.galleria) continue;
      const avanti = indietro ? !e.avanti : e.avanti;
      if (f.senso === 1 && !avanti) continue;
      if (f.senso === -1 && avanti) continue;
      const nv = v + e.d;
      if (nv < dist[e.to]) {
        dist[e.to] = nv;
        prima[e.to] = i;
        coda.push([nv, e.to]);
      }
    }
  }
  return { dist, prima };
}

/**
 * Un percorso che prende la rampa in quota fra [a] e [b] (`[lon, lat]`):
 * da una strada grande [prima] metri prima a una [dopo] metri dopo.
 */
export async function percorsoDaRampa(centro, a, b, prima = 700, dopo = 800) {
  const g = await grafoAttorno(centro[0], centro[1], 1);
  const [ax, ay] = g.metri(...a);
  const [bx, by] = g.metri(...b);
  let rampa = null;
  let bd = Infinity;
  for (const f of g.feats) {
    if (!f.rampa || !f.ponte) continue;
    const p = g.nodi[f.nodi[0]];
    const q = g.nodi[f.nodi.at(-1)];
    const d = Math.hypot(p.x - ax, p.y - ay) + Math.hypot(q.x - bx, q.y - by);
    if (d < bd) {
      bd = d;
      rampa = f;
    }
  }
  const grande = (i) => g.nodi[i].feats.some((fi) => !g.feats[fi].rampa && ['motorway', 'trunk'].includes(g.feats[fi].cls));
  const scegli = ({ dist }, voluta) => {
    let meglio = -1;
    let bv = Infinity;
    dist.forEach((d, i) => {
      if (!Number.isFinite(d) || !grande(i)) return;
      const v = Math.abs(d - voluta);
      if (v < bv) {
        bv = v;
        meglio = i;
      }
    });
    return meglio;
  };
  const inizio = rampa.nodi[0];
  const fine = rampa.nodi.at(-1);
  const giu = distanze(g, inizio, true);
  const su = distanze(g, fine);
  const s = scegli(giu, prima);
  const e = scegli(su, dopo);
  const catena = (prima2, da, a2) => {
    const out = [];
    for (let c = a2; c >= 0 && c !== da; c = prima2[c]) out.push(c);
    out.push(da);
    return out.reverse();
  };
  const avanti = catena(giu.prima, inizio, s).reverse();
  const nodi = [...avanti, ...rampa.nodi.slice(1), ...catena(su.prima, fine, e).slice(1)];
  const punti = [];
  let lunghezza = 0;
  let massima = 0;
  nodi.forEach((i, j) => {
    const n = g.nodi[i];
    massima = Math.max(massima, n.h);
    if (j) lunghezza += Math.hypot(n.x - g.nodi[nodi[j - 1]].x, n.y - g.nodi[nodi[j - 1]].y);
    if (j && j < nodi.length - 1 && Math.hypot(n.x - punti.at(-1).x, n.y - punti.at(-1).y) < 15) return;
    punti.push(n);
  });
  return { punti: punti.flatMap((n) => g.lonlat(n.x, n.y)), lunghezza, quotaMassima: massima, metriRampa: giu.dist[s] };
}

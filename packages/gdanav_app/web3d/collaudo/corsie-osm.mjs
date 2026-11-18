// Per il collaudo della vista «Corsie»: dagli elementi di OpenStreetMap (la
// risposta JSON di `api/0.6/map.json`, o quella di Overpass con `out geom`)
// ai dati del messaggio `corsie` (il formato è scritto in `src/corsie.js`).
// È quello che farà il relay per `/v1/corsie/<x>/<y>`: tenere le strade
// guidabili e i nodi che si disegnano, coi soli tag che servono.
//
//   node collaudo/corsie-osm.mjs uscita.json dati-osm.json [altri.json …]

import fs from 'node:fs';
import { CLASSI_CORSIE, TAG_NODI, TAG_STRADE, TIPI_NODI } from '../src/corsie.js';

const sette = (v) => Math.round(v * 1e7) / 1e7;

/**
 * Gli elementi OSM (anche da più risposte, con gli stessi id) nei dati del
 * messaggio `corsie`. Le vie senza tutti i loro nodi (tagliate dal riquadro
 * della richiesta) tengono i pezzi che ci sono, uno per via.
 */
export function daElementiOsm(elementi) {
  const nodi = new Map();
  const vie = new Map();
  for (const e of elementi) {
    if (e.type === 'node') nodi.set(e.id, e);
    else if (e.type === 'way') vie.set(e.id, e);
  }
  const strade = [];
  for (const w of vie.values()) {
    const t = w.tags ?? {};
    if (!CLASSI_CORSIE.has(t.highway) || t.area === 'yes') continue;
    // Overpass `out geom` ha già la geometria; l'API dà i numeri dei nodi.
    const punti = w.geometry ? w.geometry.map((p) => [p.lon, p.lat]) : (w.nodes ?? []).map((i) => nodi.get(i)).filter(Boolean).map((n) => [n.lon, n.lat]);
    if (punti.length < 2) continue;
    const s = { id: w.id, hw: t.highway, g: punti.flatMap(([lon, lat]) => [sette(lon), sette(lat)]) };
    for (const k of TAG_STRADE) if (t[k] !== undefined) s[k] = t[k];
    strade.push(s);
  }
  const segni = [];
  // Gli alberi veri: i nodi `natural=tree` e le vie `natural=tree_row`.
  const alberi = [];
  for (const n of nodi.values()) if (n.tags?.natural === 'tree') alberi.push([sette(n.lon), sette(n.lat)]);
  const filari = [];
  for (const w of vie.values()) {
    if (w.tags?.natural !== 'tree_row') continue;
    const punti = w.geometry ? w.geometry.map((p) => [p.lon, p.lat]) : (w.nodes ?? []).map((i) => nodi.get(i)).filter(Boolean).map((q) => [q.lon, q.lat]);
    if (punti.length >= 2) filari.push({ id: w.id, g: punti.flatMap(([lon, lat]) => [sette(lon), sette(lat)]) });
  }
  for (const n of nodi.values()) {
    const t = n.tags ?? {};
    if (!TIPI_NODI.has(t.highway)) continue;
    const s = { id: n.id, g: [sette(n.lon), sette(n.lat)] };
    for (const k of TAG_NODI) if (t[k] !== undefined) s[k] = t[k];
    segni.push(s);
  }
  strade.sort((a, b) => a.id - b.id);
  segni.sort((a, b) => a.id - b.id);
  return { v: 1, strade, nodi: segni, alberi, filari };
}

if (process.argv[1] && import.meta.url.endsWith(process.argv[1].split('/').pop())) {
  const [uscita, ...ingressi] = process.argv.slice(2);
  const elementi = ingressi.flatMap((f) => JSON.parse(fs.readFileSync(f, 'utf8')).elements ?? []);
  const dati = daElementiOsm(elementi);
  fs.writeFileSync(uscita, JSON.stringify(dati));
  console.log(uscita, dati.strade.length, 'strade', dati.nodi.length, 'nodi', dati.alberi.length, 'alberi', dati.filari.length, 'filari');
}

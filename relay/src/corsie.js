// Le corsie di OpenStreetMap per la vista «Corsie» della mappa 3D, una
// tessera z14 alla volta: le strade guidabili coi tag delle corsie, le
// strisce, i semafori, gli stop e gli alberi. Il formato è quello scritto in
// cima a `web3d/src/corsie.js` nell'app (messaggio `corsie`, versione 1), e
// la conversione è la stessa di `web3d/collaudo/corsie-osm.mjs`, copiata qui
// perché il relay non legge dai pacchetti dell'app.
//
// Le corsie in OpenStreetMap cambiano di rado: una tessera resta buona un
// mese, e se Overpass non risponde se ne serve una copia fino a tre mesi.
// Alla richiesta arriva solo il numero della tessera, niente di chi la chiede.
//
// Per l'Italia le tessere stanno già pronte in un archivio nostro (il bucket
// R2 `ARCHIVIO_CORSIE`), rifatto ogni mese dall'estratto di OpenStreetMap
// da `.github/workflows/corsie.yml` con le stesse regole di qui
// (`strumenti/corsie/archivio.mjs`): Overpass resta per il resto del mondo,
// e per quando l'archivio non c'è.

import { SERVER_OVERPASS, occupato, rispostaBuona } from './colonnine.js';

export const Z = 14;
export const LATO_TESSERE = 2 ** Z;

/** Intorno alla tessera si prende un orlo di una trentina di metri: le vie
 * che ne escono di poco, i semafori e le strisce sul bordo arrivano lo stesso. */
export const ORLO_M = 30;

export const FRESCA_MS = 30 * 24 * 3600 * 1000;
export const DURATA_CACHE_S = 90 * 24 * 3600;

/** Le classi di strada che la scena disegna, più le strade di servizio dove
 * si guida (non i corselli dei parcheggi, non i passi carrai). */
export const CLASSI_STRADE = new Set([
  'motorway',
  'motorway_link',
  'trunk',
  'trunk_link',
  'primary',
  'primary_link',
  'secondary',
  'secondary_link',
  'tertiary',
  'tertiary_link',
  'unclassified',
  'residential',
  'living_street',
  'service',
]);
export const SERVIZI_ESCLUSI = ['parking_aisle', 'driveway', 'drive-through', 'emergency_access'];
export const ACCESSI_ESCLUSI = ['private', 'no'];

// Gli stessi elenchi di `web3d/src/corsie.js`: i tag che servono alla scena,
// gli altri restano a Overpass.
export const TAG_STRADE = [
  'lanes',
  'lanes:forward',
  'lanes:backward',
  'turn:lanes',
  'turn:lanes:forward',
  'turn:lanes:backward',
  'change:lanes',
  'change:lanes:forward',
  'change:lanes:backward',
  'oneway',
  'junction',
  'placement',
  'placement:forward',
  'width',
  'bridge',
  'tunnel',
  'layer',
];
export const TIPI_NODI = new Set(['crossing', 'traffic_signals', 'stop', 'give_way', 'motorway_junction']);
export const TAG_NODI = ['highway', 'crossing', 'crossing:markings', 'traffic_signals:direction', 'direction', 'ref', 'name'];

/** /v1/corsie/14/<x>/<y>: la tessera z14 (lo zoom è fisso). */
export function leggiTessera(metodo, url) {
  const m = new URL(url).pathname.match(/^\/v1\/corsie\/(\d{1,2})\/(\d{1,5})\/(\d{1,5})$/);
  if (!m) return { errore: 'indirizzo sconosciuto', stato: 404 };
  if (metodo !== 'GET') return { errore: 'metodo', stato: 405 };
  if (Number(m[1]) !== Z) return { errore: `solo tessere z${Z}`, stato: 400 };
  const x = Number(m[2]);
  const y = Number(m[3]);
  if (x >= LATO_TESSERE || y >= LATO_TESSERE) return { errore: 'fuori dal mondo', stato: 400 };
  return { x, y };
}

const sei = (v) => Math.round(v * 1e6) / 1e6;
const lonDi = (x) => (x / LATO_TESSERE) * 360 - 180;
const latDi = (y) => (Math.atan(Math.sinh(Math.PI * (1 - (2 * y) / LATO_TESSERE))) * 180) / Math.PI;

/** Il riquadro della tessera con l'orlo, come lo vuole Overpass: sud, ovest, nord, est. */
export function riquadroTessera(x, y) {
  const nord = latDi(y);
  const sud = latDi(y + 1);
  const dLat = ORLO_M / 111320;
  const dLon = ORLO_M / (111320 * Math.cos((((nord + sud) / 2) * Math.PI) / 180));
  return [
    Math.max(-90, sud - dLat),
    Math.max(-180, lonDi(x) - dLon),
    Math.min(90, nord + dLat),
    Math.min(180, lonDi(x + 1) + dLon),
  ].map(sei);
}

/** Le vie che la richiesta a Overpass qui sotto sceglie, scritte per chi la
 * rifà senza Overpass (l'archivio): le classi di strada, e le `service` che
 * non sono corselli, passi carrai o private. Le aree (`area=yes`) le
 * sceglie anche Overpass, poi `daElementiOsm` le scarta. */
export const viaDellaRichiesta = (t) =>
  t.highway === 'service'
    ? !SERVIZI_ESCLUSI.includes(t.service) && !ACCESSI_ESCLUSI.includes(t.access)
    : CLASSI_STRADE.has(t.highway);

const alternative = (valori) => `^(${valori.join('|')})$`;

/**
 * Le vie guidabili che toccano il riquadro, intere (`out tags geom`, senza
 * i numeri dei nodi): la scena le somma per id da una tessera all'altra, e
 * una via tagliata al bordo cancellerebbe il pezzo arrivato con la tessera
 * accanto. Dei loro nodi solo quelli da disegnare e dentro il riquadro;
 * poi gli alberi e i filari.
 */
export function richiestaOverpass(x, y) {
  const b = `(${riquadroTessera(x, y).join(',')})`;
  const classi = [...CLASSI_STRADE].filter((c) => c !== 'service');
  const vie = [
    `way["highway"~"${alternative(classi)}"]${b};`,
    `way["highway"="service"]["service"!~"${alternative(SERVIZI_ESCLUSI)}"]["access"!~"${alternative(ACCESSI_ESCLUSI)}"]${b};`,
  ];
  return [
    '[out:json][timeout:25];',
    `(${vie.join('')})->.vie;`,
    '.vie out tags geom;',
    `node(w.vie)["highway"~"${alternative([...TIPI_NODI])}"]${b};`,
    'out;',
    `node["natural"="tree"]${b};`,
    'out;',
    `way["natural"="tree_row"]${b};`,
    'out tags geom;',
  ].join('');
}

/** I punti di una via: da `out geom`, o dai numeri dei nodi se ci sono. */
function puntiDi(via, nodi) {
  const punti = via.geometry
    ? via.geometry.map((p) => (p ? [p.lon, p.lat] : null))
    : (via.nodes ?? []).map((i) => nodi.get(i)).map((n) => (n ? [n.lon, n.lat] : null));
  return punti.filter((p) => p && Number.isFinite(p[0]) && Number.isFinite(p[1]));
}

const guidabile = (t) =>
  CLASSI_STRADE.has(t.highway) &&
  t.area !== 'yes' &&
  (t.highway !== 'service' || (!SERVIZI_ESCLUSI.includes(t.service) && !ACCESSI_ESCLUSI.includes(t.access)));

/**
 * Gli elementi di Overpass nei dati del messaggio `corsie`: le strade coi
 * soli tag delle corsie, i nodi da disegnare, gli alberi e i filari, con le
 * coordinate a sei decimali (una decina di centimetri). Due vie si toccano
 * dove hanno un nodo in comune: lo stesso nodo arrotondato dà le stesse
 * coordinate, qualunque sia la tessera da cui arriva.
 */
export function daElementiOsm(elementi, tessera = {}) {
  const nodi = new Map();
  const vie = new Map();
  for (const e of elementi ?? []) {
    if (e?.type === 'node') nodi.set(e.id, e);
    else if (e?.type === 'way') vie.set(e.id, e);
  }
  const fila = (punti) => punti.flatMap(([lon, lat]) => [sei(lon), sei(lat)]);

  const strade = [];
  const filari = [];
  for (const w of vie.values()) {
    const t = w.tags ?? {};
    const punti = puntiDi(w, nodi);
    if (punti.length < 2) continue;
    if (t.natural === 'tree_row') {
      filari.push({ id: w.id, g: fila(punti) });
      continue;
    }
    if (!guidabile(t)) continue;
    const s = { id: w.id, hw: t.highway, g: fila(punti) };
    for (const k of TAG_STRADE) if (t[k] !== undefined) s[k] = t[k];
    strade.push(s);
  }

  const segni = [];
  const alberi = [];
  for (const n of nodi.values()) {
    const t = n.tags ?? {};
    if (!Number.isFinite(n.lon) || !Number.isFinite(n.lat)) continue;
    if (t.natural === 'tree') alberi.push([sei(n.lon), sei(n.lat)]);
    if (!TIPI_NODI.has(t.highway)) continue;
    const s = { id: n.id, g: [sei(n.lon), sei(n.lat)] };
    for (const k of TAG_NODI) if (t[k] !== undefined) s[k] = t[k];
    segni.push(s);
  }

  strade.sort((a, b) => a.id - b.id);
  segni.sort((a, b) => a.id - b.id);
  filari.sort((a, b) => a.id - b.id);
  const dove = Number.isInteger(tessera.x) && Number.isInteger(tessera.y) ? { z: Z, x: tessera.x, y: tessera.y } : {};
  return { v: 1, ...dove, strade, nodi: segni, alberi, filari };
}

export const fresca = (salvata, ora) => Number.isFinite(salvata) && ora - salvata < FRESCA_MS;

const intestazioni = (salvata) => ({
  'content-type': 'application/json',
  'cache-control': `public, max-age=${DURATA_CACHE_S}`,
  'x-gdanav-salvata': String(salvata),
});
const errore = (testo, stato) =>
  new Response(JSON.stringify({ errore: testo }), { status: stato, headers: { 'content-type': 'application/json' } });

// ── L'archivio nostro (R2) ───────────────────────────────────────────

/** Dove stanno le cose nel bucket: una tessera compressa (gzip) per oggetto,
 * e il manifesto con la data dell'estratto e le tessere che l'archivio copre. */
export const CHIAVE_MANIFESTO = 'corsie/v1/manifesto.json';
export const chiaveArchivio = (x, y) => `corsie/v1/${Z}/${x}/${y}.json.gz`;

/** Il manifesto si rilegge al più ogni dieci minuti (per istanza del Worker). */
export const VITA_MANIFESTO_MS = 10 * 60 * 1000;

/**
 * Se la tessera sta dentro l'archivio: `copertura` è, per ogni riga y, gli
 * intervalli [x0, x1] (compresi) delle tessere tutte dentro l'estratto. Lì
 * una tessera che manca è una tessera senza niente, non una da chiedere.
 */
export function dentroCopertura(copertura, x, y) {
  const intervalli = copertura?.[y];
  if (!Array.isArray(intervalli)) return false;
  return intervalli.some((i) => Array.isArray(i) && x >= i[0] && x <= i[1]);
}

/** Un manifesto si usa solo se è della versione giusta e ha la data. */
export function manifestoBuono(m) {
  return m?.v === 1 && m.z === Z && Number.isFinite(Date.parse(m.estratto)) && typeof m.copertura === 'object';
}

let manifestoLetto = { archivio: null, letto: -Infinity, dati: null };

/** Il manifesto dell'archivio, o null se non c'è (allora l'archivio non si usa). */
async function leggiManifesto(archivio, ora) {
  const m = manifestoLetto;
  if (m.archivio === archivio && ora - m.letto < VITA_MANIFESTO_MS) return m.dati;
  const oggetto = await archivio.get(CHIAVE_MANIFESTO);
  let dati = null;
  if (oggetto) {
    try {
      const letto = JSON.parse(await oggetto.text());
      if (manifestoBuono(letto)) dati = letto;
    } catch {
      dati = null;
    }
  }
  manifestoLetto = { archivio, letto: ora, dati };
  return dati;
}

/** Il testo di un oggetto dell'archivio: compresso con gzip, o già in chiaro. */
async function testoDi(oggetto) {
  const byte = new Uint8Array(await oggetto.arrayBuffer());
  if (byte[0] === 0x1f && byte[1] === 0x8b) {
    const flusso = new Blob([byte]).stream().pipeThrough(new DecompressionStream('gzip'));
    return new Response(flusso).text();
  }
  return new TextDecoder().decode(byte);
}

/**
 * La tessera dall'archivio: `{ testo, salvata }` (salvata = la data
 * dell'estratto), o null se l'archivio non c'è, non la copre o non si legge:
 * allora si va avanti come prima. Una tessera coperta ma senza oggetto è
 * vuota: dentro non c'è niente da disegnare.
 */
export async function dallArchivio(archivio, x, y, ora = Date.now()) {
  if (!archivio) return null;
  try {
    const m = await leggiManifesto(archivio, ora);
    if (!m) return null;
    const salvata = Date.parse(m.estratto);
    const oggetto = await archivio.get(chiaveArchivio(x, y));
    if (oggetto) {
      const testo = await testoDi(oggetto);
      const dati = JSON.parse(testo);
      if (dati?.v !== 1 || dati.x !== x || dati.y !== y) return null;
      return { testo, salvata };
    }
    if (dentroCopertura(m.copertura, x, y)) return { testo: JSON.stringify(daElementiOsm([], { x, y })), salvata };
    return null;
  } catch (e) {
    console.log(`corsie: archivio non letto (${e})`);
    return null;
  }
}

// ── La richiesta ─────────────────────────────────────────────────────

/** Overpass in tutto ha 25 secondi (l'app aspetta 35): il primo server ne ha
 * la metà, il secondo quel che resta. */
export const TEMPO_OVERPASS_MS = 25000;

/**
 * Una tessera di corsie: dalla cache se è fresca, se no dall'archivio, se
 * no da Overpass (il secondo server se il primo è occupato o lento) e poi in
 * cache. Se Overpass non risponde, la copia vecchia è meglio di niente: la si
 * serve con `x-gdanav-vecchia: 1`.
 */
export async function corsie(richiesta, ctx, { attesaMs = 2000, tempoMs = TEMPO_OVERPASS_MS, archivio = null } = {}) {
  const r = leggiTessera(richiesta.method, richiesta.url);
  if (r.errore) return errore(r.errore, r.stato);
  const chiave = new Request(`https://cache.gdanav/corsie/v1/${Z}/${r.x}/${r.y}`);
  const inCache = await caches.default.match(chiave);
  if (inCache && fresca(Number(inCache.headers.get('x-gdanav-salvata')), Date.now())) return inCache;

  const dallo = await dallArchivio(archivio, r.x, r.y);
  if (dallo) {
    const buona = new Response(dallo.testo, { headers: intestazioni(dallo.salvata) });
    ctx.waitUntil(caches.default.put(chiave, buona.clone()));
    return buona;
  }

  const corpo = new URLSearchParams({ data: richiestaOverpass(r.x, r.y) });
  const fine = Date.now() + tempoMs;
  let ultimo = 'nessun server';
  for (const [i, server] of SERVER_OVERPASS.entries()) {
    for (let tentativo = 0; tentativo < 2; tentativo++) {
      // Il tempo che resta, diviso fra questo server e quelli dopo.
      const resta = fine - Date.now();
      const perQuesto = Math.floor(resta / (SERVER_OVERPASS.length - i));
      if (perQuesto <= 0) break;
      try {
        const risposta = await fetch(server, {
          method: 'POST',
          body: corpo,
          headers: { 'user-agent': 'gdanav relay (github.com/danigio15/gdanav)' },
          signal: AbortSignal.timeout(perQuesto),
        });
        const testo = await risposta.text();
        if (risposta.ok && rispostaBuona(testo)) {
          const dati = daElementiOsm(JSON.parse(testo).elements, r);
          const buona = new Response(JSON.stringify(dati), { headers: intestazioni(Date.now()) });
          ctx.waitUntil(caches.default.put(chiave, buona.clone()));
          return buona;
        }
        ultimo = `${new URL(server).host}: ${risposta.status}`;
        if (!occupato(risposta.status)) break;
        if (attesaMs > 0) {
          // Senza il tempo per aspettare e riprovare, meglio il server dopo.
          if (fine - Date.now() <= attesaMs) break;
          await new Promise((fatto) => setTimeout(fatto, attesaMs));
        }
      } catch (e) {
        ultimo = `${new URL(server).host}: ${e}`;
        break;
      }
    }
  }
  if (inCache) {
    const vecchia = new Response(inCache.body, inCache);
    vecchia.headers.set('x-gdanav-vecchia', '1');
    return vecchia;
  }
  return errore(`corsie: ${ultimo}`, 502);
}

// L'archivio delle corsie: dall'estratto di OpenStreetMap (passato da
// osmium in OPL, coi luoghi dei nodi sulle vie) alle tessere z14 che il
// relay serve in `GET /v1/corsie/14/<x>/<y>`, una per file, compresse.
//
// Ogni tessera è IDENTICA a quella che il relay fa da Overpass: per ogni
// tessera si rifanno qui le scelte della richiesta a Overpass
// (`richiestaOverpass` nel relay), si danno gli elementi a `daElementiOsm`
// del relay in forma Overpass (vie con `geometry`, nodi con lat/lon), e il
// testo è il suo `JSON.stringify`. Le regole:
//   - le vie guidabili (`viaDellaRichiesta`) e i filari che toccano il
//     riquadro della tessera con l'orlo di 30 m (`riquadroTessera`), intere:
//     un loro tratto passa dentro il riquadro, anche senza nodi dentro;
//   - i nodi da disegnare (strisce, semafori, stop, precedenze, uscite)
//     dentro il riquadro e su una di quelle vie, e gli alberi dentro il
//     riquadro.
// Le coordinate a sei decimali le mette `daElementiOsm`.
//
// Il lavoro si fa in tre passi, per stare nella memoria di un runner di
// GitHub con l'Italia intera:
//   1. si leggono le righe OPL; ogni elemento utile si scrive, una riga per
//      tessera che tocca, in uno di SECCHI file di appoggio (scelto dalla
//      tessera), coi soli tag che servono;
//   2. intanto si segnano i nodi da disegnare che stanno su una via scelta;
//   3. un secchio alla volta si raccolgono le tessere, si fa il JSON e lo si
//      scrive compresso in <uscita>/corsie/v1/14/<x>/<y>.json.gz.
// Alla fine il manifesto <uscita>/corsie/v1/manifesto.json: la data
// dell'estratto e, per ogni riga di tessere, le tessere tutte dentro il
// poligono dell'estratto (dove una tessera che manca è vuota davvero).
//
//   osmium add-locations-to-ways filtrato.osm.pbf -f opl,add_metadata=false -o - \
//     | node archivio.mjs --opl - --uscita uscita --poly italy.poly --estratto 2026-11-01T20:21:00Z
//   node archivio.mjs --filtri     # le espressioni per `osmium tags-filter`

import { createReadStream, appendFileSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { createInterface } from 'node:readline';
import { pathToFileURL } from 'node:url';
import { gzipSync } from 'node:zlib';

import {
  CHIAVE_MANIFESTO,
  CLASSI_STRADE,
  LATO_TESSERE,
  TAG_NODI,
  TAG_STRADE,
  TIPI_NODI,
  Z,
  chiaveArchivio,
  daElementiOsm,
  dentroCopertura,
  riquadroTessera,
  viaDellaRichiesta,
} from '../../relay/src/corsie.js';

/** I file di appoggio: con l'Italia sono una ventina di MB l'uno. */
export const SECCHI = 128;

/** I tag che `daElementiOsm` legge (gli altri non cambiano il risultato). */
export const TAG_UTILI = new Set(['highway', 'service', 'access', 'area', 'natural', ...TAG_STRADE, ...TAG_NODI]);

/** Le espressioni per `osmium tags-filter`: le vie e i nodi che possono servire. */
export function filtriOsmium() {
  return [`w/highway=${[...CLASSI_STRADE].join(',')}`, 'w/natural=tree_row', 'n/natural=tree', `n/highway=${[...TIPI_NODI].join(',')}`];
}

// ── Le righe OPL ─────────────────────────────────────────────────────

/** OPL scrive i caratteri speciali come %<codice esadecimale>%. */
const decodifica = (s) => (s.includes('%') ? s.replace(/%([0-9a-fA-F]+)%/g, (_, h) => String.fromCodePoint(parseInt(h, 16))) : s);

function leggiTag(campo) {
  const tags = {};
  if (!campo) return tags;
  for (const coppia of campo.split(',')) {
    const uguale = coppia.indexOf('=');
    if (uguale < 0) continue;
    tags[decodifica(coppia.slice(0, uguale))] = decodifica(coppia.slice(uguale + 1));
  }
  return tags;
}

const numero = (s) => (s === undefined || s === '' ? NaN : Number(s));

/**
 * Una riga OPL: `{ tipo: 'n', id, tags, lon, lat }` o `{ tipo: 'w', id,
 * tags, nodi: [{ id, lon, lat }] }`; null per le relazioni e le righe vuote.
 */
export function leggiRigaOpl(riga) {
  const tipo = riga[0];
  if (tipo !== 'n' && tipo !== 'w') return null;
  const campi = riga.split(' ');
  const e = { tipo, id: Number(campi[0].slice(1)), tags: {} };
  if (tipo === 'w') e.nodi = [];
  for (let i = 1; i < campi.length; i++) {
    const c = campi[i];
    const v = c.slice(1);
    if (c[0] === 'T') e.tags = leggiTag(v);
    else if (tipo === 'n' && c[0] === 'x') e.lon = numero(v);
    else if (tipo === 'n' && c[0] === 'y') e.lat = numero(v);
    else if (tipo === 'w' && c[0] === 'N' && v) {
      for (const n of v.split(',')) {
        const m = n.match(/^n(-?\d+)(?:x([^y]*)y(.*))?$/);
        if (m) e.nodi.push({ id: Number(m[1]), lon: numero(m[2]), lat: numero(m[3]) });
      }
    }
  }
  return e;
}

// ── Le tessere toccate ───────────────────────────────────────────────

const tesseraX = (lon) => Math.floor(((lon + 180) / 360) * LATO_TESSERE);
const tesseraY = (lat) => {
  const r = (lat * Math.PI) / 180;
  return Math.floor(((1 - Math.asinh(Math.tan(r)) / Math.PI) / 2) * LATO_TESSERE);
};
const dentroMondo = (x, y) => x >= 0 && y >= 0 && x < LATO_TESSERE && y < LATO_TESSERE;

const riquadri = new Map();
/** Il riquadro del relay (sud, ovest, nord, est), tenuto da parte. */
function riquadro(x, y) {
  const k = x * LATO_TESSERE + y;
  let r = riquadri.get(k);
  if (!r) {
    r = riquadroTessera(x, y);
    if (riquadri.size > 2_000_000) riquadri.clear();
    riquadri.set(k, r);
  }
  return r;
}

const puntoDentro = (lon, lat, [s, o, n, e]) => lat >= s && lat <= n && lon >= o && lon <= e;

/** Se il tratto da a a b passa nel riquadro (bordi compresi): Liang-Barsky. */
export function trattoTocca(lonA, latA, lonB, latB, [s, o, n, e]) {
  const dx = lonB - lonA;
  const dy = latB - latA;
  const p = [-dx, dx, -dy, dy];
  const q = [lonA - o, e - lonA, latA - s, n - latA];
  let t0 = 0;
  let t1 = 1;
  for (let i = 0; i < 4; i++) {
    if (p[i] === 0) {
      if (q[i] < 0) return false;
      continue;
    }
    const t = q[i] / p[i];
    if (p[i] < 0) {
      if (t > t1) return false;
      if (t > t0) t0 = t;
    } else {
      if (t < t0) return false;
      if (t < t1) t1 = t;
    }
  }
  return true;
}

/** Le tessere il cui riquadro (con l'orlo) contiene il punto. */
export function tessereDelPunto(lon, lat) {
  const tx = tesseraX(lon);
  const ty = tesseraY(lat);
  const fuori = [];
  for (let x = tx - 1; x <= tx + 1; x++) {
    for (let y = ty - 1; y <= ty + 1; y++) {
      if (dentroMondo(x, y) && puntoDentro(lon, lat, riquadro(x, y))) fuori.push([x, y]);
    }
  }
  return fuori;
}

/** Le tessere il cui riquadro un tratto della linea tocca; `punti` è [[lon, lat], ...]. */
export function tessereDellaLinea(punti) {
  if (punti.length === 1) return tessereDelPunto(punti[0][0], punti[0][1]);
  const viste = new Set();
  const fuori = [];
  for (let i = 1; i < punti.length; i++) {
    const [lonA, latA] = punti[i - 1];
    const [lonB, latB] = punti[i];
    const x0 = Math.min(tesseraX(lonA), tesseraX(lonB)) - 1;
    const x1 = Math.max(tesseraX(lonA), tesseraX(lonB)) + 1;
    const y0 = Math.min(tesseraY(latA), tesseraY(latB)) - 1;
    const y1 = Math.max(tesseraY(latA), tesseraY(latB)) + 1;
    for (let x = x0; x <= x1; x++) {
      for (let y = y0; y <= y1; y++) {
        const k = x * LATO_TESSERE + y;
        if (viste.has(k) || !dentroMondo(x, y)) continue;
        if (trattoTocca(lonA, latA, lonB, latB, riquadro(x, y))) {
          viste.add(k);
          fuori.push([x, y]);
        }
      }
    }
  }
  return fuori;
}

// ── La copertura: le tessere tutte dentro il poligono dell'estratto ──

/** Gli anelli di un file .poly (quello degli estratti di Geofabrik): [[[lon, lat], ...], ...]. */
export function leggiPoly(testo) {
  const righe = testo.split(/\r?\n/).map((r) => r.trim());
  const anelli = [];
  let anello = null;
  for (const r of righe.slice(1)) {
    if (!r) continue;
    if (anello === null) {
      if (r === 'END') break;
      anello = [];
      continue;
    }
    if (r === 'END') {
      if (anello.length >= 3) anelli.push(anello);
      anello = null;
      continue;
    }
    const [lon, lat] = r.split(/\s+/).map(Number);
    if (Number.isFinite(lon) && Number.isFinite(lat)) anello.push([lon, lat]);
  }
  return anelli;
}

/**
 * Per ogni riga y le tessere [x0, x1] il cui riquadro con l'orlo sta tutto
 * dentro il poligono (pari e dispari: i buchi `!` vengono da sé). Una
 * tessera sul confine resta fuori: lì l'estratto non ha le vie dell'altra
 * parte, e il relay la chiede a Overpass come prima.
 */
export function coperturaDaAnelli(anelli) {
  const lati = [];
  let [minLon, minLat, maxLon, maxLat] = [Infinity, Infinity, -Infinity, -Infinity];
  for (const a of anelli) {
    for (let i = 0; i < a.length; i++) {
      const p = a[i];
      const q = a[(i + 1) % a.length];
      if (p[0] !== q[0] || p[1] !== q[1]) lati.push([p, q]);
      minLon = Math.min(minLon, p[0]);
      maxLon = Math.max(maxLon, p[0]);
      minLat = Math.min(minLat, p[1]);
      maxLat = Math.max(maxLat, p[1]);
    }
  }
  if (!lati.length) return {};
  // Le tessere dove passa il confine.
  const confine = new Set();
  for (const [p, q] of lati) {
    for (const [x, y] of tessereDellaLinea([p, q])) confine.add(x * LATO_TESSERE + y);
  }
  const copertura = {};
  const [x0, x1] = [tesseraX(minLon), tesseraX(maxLon)];
  for (let y = tesseraY(maxLat); y <= tesseraY(minLat); y++) {
    // Il centro della tessera (in Mercatore) e dove la sua riga taglia il confine.
    const lat = (Math.atan(Math.sinh(Math.PI * (1 - (2 * (y + 0.5)) / LATO_TESSERE))) * 180) / Math.PI;
    const tagli = [];
    for (const [p, q] of lati) {
      if (p[1] > lat !== q[1] > lat) tagli.push(p[0] + ((lat - p[1]) * (q[0] - p[0])) / (q[1] - p[1]));
    }
    tagli.sort((a, b) => a - b);
    const intervalli = [];
    let t = 0;
    for (let x = x0; x <= x1; x++) {
      const lon = ((x + 0.5) / LATO_TESSERE) * 360 - 180;
      while (t < tagli.length && tagli[t] < lon) t++;
      const dentro = t % 2 === 1 && !confine.has(x * LATO_TESSERE + y);
      if (!dentro) continue;
      const ultimo = intervalli[intervalli.length - 1];
      if (ultimo && ultimo[1] === x - 1) ultimo[1] = x;
      else intervalli.push([x, x]);
    }
    if (intervalli.length) copertura[y] = intervalli;
  }
  return copertura;
}

// ── La costruzione ───────────────────────────────────────────────────

const soloUtili = (tags) => {
  const fuori = {};
  for (const k in tags) if (TAG_UTILI.has(k)) fuori[k] = tags[k];
  return fuori;
};
/**
 * Gli elementi nell'ordine in cui Overpass li scrive: le vie, poi i nodi da
 * disegnare sulle vie, poi gli alberi (ogni `out` in ordine di id), poi i
 * filari. Conta solo per gli alberi, che `daElementiOsm` lascia nell'ordine
 * in cui arrivano (le strade, i nodi e i filari li ordina lui); un albero
 * che è anche un nodo da disegnare su una via arriva col primo gruppo.
 */
export function ordinaComeOverpass(elementi, membri) {
  const gruppo = (e) => {
    if (e.type === 'way') return e.tags?.natural === 'tree_row' && !viaDellaRichiesta(e.tags ?? {}) ? 3 : 0;
    return TIPI_NODI.has(e.tags?.highway) && membri.has(e.id) ? 1 : 2;
  };
  return elementi
    .map((e) => [gruppo(e), e])
    .sort((a, b) => a[0] - b[0] || a[1].id - b[1].id)
    .map(([, e]) => e);
}

const secchioDi = (x, y) => (x * 31 + y) % SECCHI;

/**
 * Costruisce l'archivio dalle righe OPL (un iterabile, anche asincrono).
 * `copertura` null: si scrivono tutte le tessere che hanno qualcosa (le
 * prove su un estratto piccolo). Ritorna il riassunto.
 */
export async function costruisci(righe, { uscita, appoggio, copertura = null, estratto = null, fonte = null }) {
  rmSync(appoggio, { recursive: true, force: true });
  mkdirSync(appoggio, { recursive: true });
  const code = Array.from({ length: SECCHI }, () => ({ righe: [], byte: 0 }));
  const svuota = (i) => {
    const c = code[i];
    if (!c.righe.length) return;
    appendFileSync(join(appoggio, `${i}.txt`), c.righe.join(''));
    c.righe = [];
    c.byte = 0;
  };
  const scrivi = (x, y, tipo, testo) => {
    const i = secchioDi(x, y);
    const riga = `${x}\t${y}\t${tipo}\t${testo}\n`;
    code[i].righe.push(riga);
    code[i].byte += riga.length;
    if (code[i].byte > 1 << 22) svuota(i);
  };

  const conti = { nodi: 0, vie: 0, righe: 0 };
  const candidati = new Set(); // i nodi da disegnare (alberi compresi)
  const membri = new Set(); // quelli, se stanno su una via scelta

  for await (const riga of righe) {
    const e = leggiRigaOpl(riga);
    if (!e) continue;
    const t = e.tags;
    if (e.tipo === 'n') {
      const albero = t.natural === 'tree';
      const segno = TIPI_NODI.has(t.highway);
      if (!albero && !segno) continue;
      if (!Number.isFinite(e.lon) || !Number.isFinite(e.lat)) continue;
      const testo = JSON.stringify({ type: 'node', id: e.id, lat: e.lat, lon: e.lon, tags: soloUtili(t) });
      const tessere = tessereDelPunto(e.lon, e.lat);
      if (!tessere.length) continue;
      if (segno) candidati.add(e.id);
      for (const [x, y] of tessere) scrivi(x, y, albero ? 'n' : 'm', testo);
      conti.nodi++;
      conti.righe += tessere.length;
      continue;
    }
    const scelta = viaDellaRichiesta(t);
    if (!scelta && t.natural !== 'tree_row') continue;
    // I nodi vengono prima delle vie (osmium li scrive in ordine), quindi i
    // candidati qui sono già tutti.
    if (scelta) for (const n of e.nodi) if (candidati.has(n.id)) membri.add(n.id);
    const punti = e.nodi.filter((n) => Number.isFinite(n.lon) && Number.isFinite(n.lat)).map((n) => [n.lon, n.lat]);
    if (punti.length < 2) continue;
    const testo = JSON.stringify({ type: 'way', id: e.id, tags: soloUtili(t), g: punti.flat() });
    const tessere = tessereDellaLinea(punti);
    for (const [x, y] of tessere) scrivi(x, y, 'w', testo);
    conti.vie++;
    conti.righe += tessere.length;
  }
  for (let i = 0; i < SECCHI; i++) svuota(i);
  candidati.clear();

  const riassunto = { tessere: 0, vuote: 0, fuoriCopertura: 0, byte: 0, byteJson: 0, ...conti };
  const cartelle = new Set();
  for (let i = 0; i < SECCHI; i++) {
    let testo;
    try {
      testo = readFileSync(join(appoggio, `${i}.txt`), 'utf8');
    } catch {
      continue;
    }
    const tessere = new Map();
    let a = 0;
    while (a < testo.length) {
      let b = testo.indexOf('\n', a);
      if (b < 0) b = testo.length;
      const [sx, sy, tipo, json] = testo.slice(a, b).split('\t');
      a = b + 1;
      const el = JSON.parse(json);
      if (tipo === 'm' && !membri.has(el.id)) continue;
      if (el.type === 'way') {
        const geometry = [];
        for (let j = 0; j < el.g.length; j += 2) geometry.push({ lat: el.g[j + 1], lon: el.g[j] });
        el.geometry = geometry;
        delete el.g;
      }
      const k = `${sx}/${sy}`;
      if (!tessere.has(k)) tessere.set(k, []);
      tessere.get(k).push(el);
    }
    testo = null;
    for (const [k, elementi] of tessere) {
      const [x, y] = k.split('/').map(Number);
      if (copertura && !dentroCopertura(copertura, x, y)) {
        riassunto.fuoriCopertura++;
        continue;
      }
      const dati = daElementiOsm(ordinaComeOverpass(elementi, membri), { x, y });
      if (!dati.strade.length && !dati.nodi.length && !dati.alberi.length && !dati.filari.length) {
        riassunto.vuote++;
        continue;
      }
      const json = JSON.stringify(dati);
      const compresso = gzipSync(json, { level: 6 });
      const file = join(uscita, chiaveArchivio(x, y));
      const cartella = join(uscita, `corsie/v1/${Z}/${x}`);
      if (!cartelle.has(cartella)) {
        mkdirSync(cartella, { recursive: true });
        cartelle.add(cartella);
      }
      writeFileSync(file, compresso);
      riassunto.tessere++;
      riassunto.byte += compresso.length;
      riassunto.byteJson += json.length;
    }
  }
  rmSync(appoggio, { recursive: true, force: true });

  const manifesto = {
    v: 1,
    z: Z,
    estratto: estratto ?? new Date().toISOString(),
    generato: new Date().toISOString(),
    fonte,
    tessere: riassunto.tessere,
    byte: riassunto.byte,
    copertura,
  };
  mkdirSync(join(uscita, 'corsie/v1'), { recursive: true });
  writeFileSync(join(uscita, CHIAVE_MANIFESTO), JSON.stringify(manifesto));
  return riassunto;
}

// ── Da riga di comando ───────────────────────────────────────────────

function argomenti(argv) {
  const a = {};
  for (let i = 0; i < argv.length; i++) {
    const k = argv[i];
    if (!k.startsWith('--')) continue;
    const v = argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[++i] : true;
    a[k.slice(2)] = v;
  }
  return a;
}

async function principale() {
  const a = argomenti(process.argv.slice(2));
  if (a.filtri) {
    console.log(filtriOsmium().join('\n'));
    return;
  }
  if (!a.opl || !a.uscita) {
    console.error('uso: node archivio.mjs --opl <file|-> --uscita <cartella> [--poly <file.poly>] [--estratto <data ISO>] [--appoggio <cartella>] [--fonte <testo>]');
    process.exit(2);
  }
  const copertura = a.poly ? coperturaDaAnelli(leggiPoly(readFileSync(a.poly, 'utf8'))) : null;
  if (copertura && !Object.keys(copertura).length) throw new Error(`nessuna tessera dentro ${a.poly}`);
  const ingresso = a.opl === '-' ? process.stdin : createReadStream(a.opl);
  const righe = createInterface({ input: ingresso, crlfDelay: Infinity });
  const estratto = typeof a.estratto === 'string' && Number.isFinite(Date.parse(a.estratto)) ? new Date(a.estratto).toISOString() : null;
  const inizio = Date.now();
  const riassunto = await costruisci(righe, {
    uscita: a.uscita,
    appoggio: typeof a.appoggio === 'string' ? a.appoggio : join(a.uscita, '..', 'appoggio-corsie'),
    copertura,
    estratto,
    fonte: typeof a.fonte === 'string' ? a.fonte : null,
  });
  const coperte = copertura ? Object.values(copertura).reduce((n, r) => n + r.reduce((m, [x0, x1]) => m + x1 - x0 + 1, 0), 0) : null;
  const memoriaMB = Math.round(process.resourceUsage().maxRSS / 1024);
  console.log(JSON.stringify({ ...riassunto, coperte, secondi: Math.round((Date.now() - inizio) / 1000), memoriaMB }));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  principale().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}

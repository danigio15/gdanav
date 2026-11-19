// La prova del convertitore su un estratto piccolo e vero: si scarica un
// riquadro dall'API di OpenStreetMap (0.6, /map, a celle piccole), si fa
// l'archivio con prepara.sh (osmium + archivio.mjs, come nel workflow), e
// ogni tessera che tocca il riquadro si rifà per conto suo «come Overpass»:
// la richiesta del relay eseguita a mano sugli stessi dati (letti dall'XML,
// senza osmium né OPL), data a `daElementiOsm`. I due testi devono essere
// uguali byte per byte. Alla fine il relay serve qualche tessera da un R2
// finto riempito con l'archivio, e si controlla che dia lo stesso testo.
//
//   node strumenti/corsie/prova-locale.mjs --bbox <ovest,sud,est,nord> --lavoro <cartella>
//
// I dati veri e l'archivio restano in <lavoro> (fuori dal repository).
// Servono osmium-tool e la rete verso api.openstreetmap.org.

import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { gunzipSync } from 'node:zlib';

import {
  LATO_TESSERE,
  TIPI_NODI,
  chiaveArchivio,
  corsie,
  daElementiOsm,
  riquadroTessera,
  viaDellaRichiesta,
} from '../../relay/src/corsie.js';

const qui = dirname(fileURLToPath(import.meta.url));
const CELLA = 0.012; // gradi: l'API dà al più 50 000 nodi per richiesta

function argomenti(argv) {
  const a = {};
  for (let i = 0; i < argv.length; i += 2) a[argv[i].replace(/^--/, '')] = argv[i + 1];
  return a;
}

// ── I dati: dall'API, una cella alla volta ───────────────────────────

async function scarica(bbox, cartella) {
  const [o, s, e, n] = bbox;
  mkdirSync(cartella, { recursive: true });
  const file = [];
  for (let lon = o; lon < e - 1e-9; lon += CELLA) {
    for (let lat = s; lat < n - 1e-9; lat += CELLA) {
      const b = [lon, lat, Math.min(e, lon + CELLA), Math.min(n, lat + CELLA)].map((v) => v.toFixed(5));
      const f = join(cartella, `cella_${b.join('_')}.osm`);
      file.push(f);
      if (existsSync(f)) continue;
      const url = `https://api.openstreetmap.org/api/0.6/map?bbox=${b.join(',')}`;
      // curl e non fetch: curl passa dal proxy di sistema, se c'è.
      execFileSync('curl', ['-sSf', '-m', '120', '-A', 'prova-archivio-corsie', '-o', `${f}.parziale`, url], { stdio: 'inherit' });
      execFileSync('mv', [`${f}.parziale`, f]);
      console.log(`scaricata ${f}`);
      await new Promise((fatto) => setTimeout(fatto, 1000));
    }
  }
  return file;
}

// ── «Come Overpass»: la richiesta del relay fatta a mano sull'XML ────

const entita = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" };
const testoXml = (s) =>
  s.replace(/&(#x[0-9a-f]+|#\d+|\w+);/gi, (t, c) =>
    c[0] === '#' ? String.fromCodePoint(c[1] === 'x' || c[1] === 'X' ? parseInt(c.slice(2), 16) : Number(c.slice(1))) : (entita[c] ?? t),
  );
const attributo = (testa, nome) => {
  const m = ` ${testa}`.match(new RegExp(`\\s${nome}="([^"]*)"`));
  return m ? testoXml(m[1]) : undefined;
};

function leggiXml(file, nodi, vie) {
  const testo = readFileSync(file, 'utf8');
  const re = /<(node|way)\s([^>]*?)(\/>|>([\s\S]*?)<\/\1>)/g;
  for (const m of testo.matchAll(re)) {
    const [, tipo, testa, , corpo = ''] = m;
    const id = Number(attributo(testa, 'id'));
    const tags = {};
    for (const t of corpo.matchAll(/<tag\s([^>]*?)\/>/g)) tags[attributo(t[1], 'k')] = attributo(t[1], 'v');
    if (tipo === 'node') {
      nodi.set(id, { id, lat: Number(attributo(testa, 'lat')), lon: Number(attributo(testa, 'lon')), tags });
    } else {
      const rif = [...corpo.matchAll(/<nd\s+ref="(\d+)"/g)].map((r) => Number(r[1]));
      vie.set(id, { id, rif, tags });
    }
  }
}

// Un controllo scritto per conto suo (non quello del convertitore): il
// tratto tocca il riquadro se un estremo è dentro o se taglia un lato.
const dentro = (p, [s, o, n, e]) => p.lat >= s && p.lat <= n && p.lon >= o && p.lon <= e;
const verso = (a, b, c) => Math.sign((b.lon - a.lon) * (c.lat - a.lat) - (b.lat - a.lat) * (c.lon - a.lon));
const sopra = (a, b, c) => Math.min(a.lon, b.lon) <= c.lon && c.lon <= Math.max(a.lon, b.lon) && Math.min(a.lat, b.lat) <= c.lat && c.lat <= Math.max(a.lat, b.lat);
function siTagliano(a, b, c, d) {
  const [v1, v2, v3, v4] = [verso(a, b, c), verso(a, b, d), verso(c, d, a), verso(c, d, b)];
  if (v1 !== v2 && v3 !== v4) return true;
  return (v1 === 0 && sopra(a, b, c)) || (v2 === 0 && sopra(a, b, d)) || (v3 === 0 && sopra(c, d, a)) || (v4 === 0 && sopra(c, d, b));
}
function tocca(punti, r) {
  const [s, o, n, e] = r;
  const angoli = [
    { lat: s, lon: o },
    { lat: s, lon: e },
    { lat: n, lon: e },
    { lat: n, lon: o },
  ];
  for (let i = 0; i < punti.length; i++) {
    if (dentro(punti[i], r)) return true;
    if (i === 0) continue;
    for (let j = 0; j < 4; j++) if (siTagliano(punti[i - 1], punti[i], angoli[j], angoli[(j + 1) % 4])) return true;
  }
  return false;
}

function comeOverpass(x, y, nodi, vie) {
  const r = riquadroTessera(x, y);
  const geometria = (w) => w.rif.map((i) => nodi.get(i)).filter(Boolean).map((p) => ({ lat: p.lat, lon: p.lon }));
  const elementi = [];
  const perId = (a, b) => a.id - b.id; // ogni `out` di Overpass è in ordine di id
  // (way[highway…](bbox); way[highway=service]…(bbox);)->.vie; .vie out tags geom;
  const scelte = [...vie.values()].filter((w) => viaDellaRichiesta(w.tags) && tocca(geometria(w), r)).sort(perId);
  for (const w of scelte) elementi.push({ type: 'way', id: w.id, tags: w.tags, geometry: geometria(w) });
  // node(w.vie)[highway~…](bbox); out;
  const suVie = [...new Set(scelte.flatMap((w) => w.rif))].map((id) => nodi.get(id));
  for (const p of suVie.filter((p) => p && TIPI_NODI.has(p.tags.highway) && dentro(p, r)).sort(perId)) elementi.push({ type: 'node', ...p });
  // node[natural=tree](bbox); out;
  for (const p of [...nodi.values()].filter((p) => p.tags.natural === 'tree' && dentro(p, r)).sort(perId)) elementi.push({ type: 'node', ...p });
  // way[natural=tree_row](bbox); out tags geom;
  for (const w of [...vie.values()].filter((w) => w.tags.natural === 'tree_row' && tocca(geometria(w), r)).sort(perId)) {
    elementi.push({ type: 'way', id: w.id, tags: w.tags, geometry: geometria(w) });
  }
  return daElementiOsm(elementi, { x, y });
}

const tX = (lon) => Math.floor(((lon + 180) / 360) * LATO_TESSERE);
const tY = (lat) => Math.floor(((1 - Math.asinh(Math.tan((lat * Math.PI) / 180)) / Math.PI) / 2) * LATO_TESSERE);
const vuota = (d) => !d.strade.length && !d.nodi.length && !d.alberi.length && !d.filari.length;

// ── La prova ─────────────────────────────────────────────────────────

async function principale() {
  const a = argomenti(process.argv.slice(2));
  if (!a.bbox || !a.lavoro) {
    console.error('uso: node prova-locale.mjs --bbox <ovest,sud,est,nord> --lavoro <cartella>');
    process.exit(2);
  }
  const bbox = a.bbox.split(',').map(Number);
  const celle = await scarica(bbox, join(a.lavoro, 'osm'));

  const estratto = join(a.lavoro, 'estratto.osm.pbf');
  execFileSync('osmium', ['merge', '--overwrite', '-o', estratto, ...celle], { stdio: 'inherit' });
  const uscita = join(a.lavoro, 'uscita');
  execFileSync(join(qui, 'prepara.sh'), [estratto, uscita], { stdio: 'inherit', env: { ...process.env, LAVORO: join(a.lavoro, 'lavoro') } });

  const nodi = new Map();
  const vie = new Map();
  for (const f of celle) leggiXml(f, nodi, vie);
  console.log(`dall'XML: ${nodi.size} nodi, ${vie.size} vie`);

  // Le tessere: tutte quelle che il riquadro scaricato tocca, più quelle scritte.
  const tessere = new Set();
  for (let x = tX(bbox[0]) - 1; x <= tX(bbox[2]) + 1; x++) for (let y = tY(bbox[3]) - 1; y <= tY(bbox[1]) + 1; y++) tessere.add(`${x}/${y}`);
  const radice = join(uscita, 'corsie/v1/14');
  for (const x of readdirSync(radice)) for (const f of readdirSync(join(radice, x))) tessere.add(`${x}/${f.replace('.json.gz', '')}`);

  let uguali = 0;
  let vuoteUguali = 0;
  const diverse = [];
  const conti = { strade: 0, nodi: 0, alberi: 0, filari: 0 };
  for (const k of [...tessere].sort()) {
    const [x, y] = k.split('/').map(Number);
    const attesa = comeOverpass(x, y, nodi, vie);
    const file = join(uscita, chiaveArchivio(x, y));
    const scritta = existsSync(file) ? gunzipSync(readFileSync(file)).toString('utf8') : null;
    if (scritta === null && vuota(attesa)) {
      vuoteUguali++;
      continue;
    }
    if (scritta === JSON.stringify(attesa)) {
      uguali++;
      for (const c of Object.keys(conti)) conti[c] += attesa[c].length;
    } else diverse.push(k);
  }
  console.log(`tessere uguali: ${uguali} (con ${JSON.stringify(conti)}), vuote in tutti e due: ${vuoteUguali}, diverse: ${diverse.length}`);
  for (const k of diverse.slice(0, 5)) {
    // La prima cosa diversa, per capire; la tessera attesa intera resta in <lavoro>/attese.
    const [x, y] = k.split('/').map(Number);
    const attesa = comeOverpass(x, y, nodi, vie);
    mkdirSync(join(a.lavoro, 'attese'), { recursive: true });
    writeFileSync(join(a.lavoro, 'attese', `${x}_${y}.json`), JSON.stringify(attesa));
    const file = join(uscita, chiaveArchivio(x, y));
    const scritta = existsSync(file) ? JSON.parse(gunzipSync(readFileSync(file))) : { strade: [], nodi: [], alberi: [], filari: [] };
    for (const c of ['strade', 'nodi', 'alberi', 'filari']) {
      const [la, ls] = [attesa[c], scritta[c]];
      const i = la.findIndex((e, j) => JSON.stringify(e) !== JSON.stringify(ls[j]));
      if (i >= 0 || la.length !== ls.length) {
        console.log(`${k} ${c} (${la.length} contro ${ls.length}), dal ${i}:\n  come Overpass ${JSON.stringify(la[i]).slice(0, 300)}\n  archivio      ${JSON.stringify(ls[i]).slice(0, 300)}`);
        break;
      }
    }
    process.exitCode = 1;
  }

  // Il relay con un R2 finto riempito con l'archivio.
  const r2 = {
    get: async (chiave) => {
      const f = join(uscita, chiave);
      if (!existsSync(f)) return null;
      const byte = readFileSync(f);
      return { arrayBuffer: async () => byte.buffer.slice(byte.byteOffset, byte.byteOffset + byte.byteLength), text: async () => byte.toString('utf8') };
    },
  };
  globalThis.caches = { default: { match: async () => undefined, put: async () => {} } };
  globalThis.fetch = async () => {
    throw new Error('Overpass non va chiamato');
  };
  let servite = 0;
  for (const k of [...tessere].slice(0, 40)) {
    const [x, y] = k.split('/').map(Number);
    const file = join(uscita, chiaveArchivio(x, y));
    if (!existsSync(file)) continue;
    const r = await corsie(new Request(`https://relay.prova/v1/corsie/14/${x}/${y}`), { waitUntil: () => {} }, { archivio: r2 });
    const testo = await r.text();
    if (r.status !== 200 || testo !== JSON.stringify(comeOverpass(x, y, nodi, vie))) {
      console.log(`il relay dall'archivio sbaglia ${k}: ${r.status}`);
      process.exitCode = 1;
    } else servite++;
  }
  console.log(`servite dal relay con R2 finto, uguali: ${servite}`);
  if (!process.exitCode) console.log('ok: l\'archivio dà lo stesso JSON del percorso Overpass');
}

principale().catch((e) => {
  console.error(e);
  process.exit(1);
});

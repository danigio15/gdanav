import assert from 'node:assert/strict';
import { afterEach, beforeEach, test } from 'node:test';

import { SERVER_OVERPASS } from '../src/colonnine.js';
import {
  DURATA_CACHE_S,
  FRESCA_MS,
  corsie,
  daElementiOsm,
  fresca,
  leggiTessera,
  richiestaOverpass,
  riquadroTessera,
} from '../src/corsie.js';

// Una tessera in mezzo al mare, all'incrocio fra equatore e meridiano zero:
// le vie qui sotto sono inventate, come i loro numeri.
const X = 8192;
const Y = 8191;

const RISPOSTA_INVENTATA = {
  version: 0.6,
  elements: [
    {
      type: 'way',
      id: 30,
      tags: { highway: 'primary', lanes: '3', 'turn:lanes': 'left|through|through;right', oneway: 'yes', name: 'Via Inventata', surface: 'asphalt' },
      geometry: [
        { lat: 0.00100004, lon: 0.00100006 },
        { lat: 0.0020000449, lon: 0.0010000049 },
        { lat: 0.003, lon: 0.0011 },
      ],
    },
    {
      type: 'way',
      id: 10,
      tags: { highway: 'motorway_link', lanes: '1', 'placement': 'right_of:1', maxspeed: '80' },
      geometry: [
        { lat: 0.003, lon: 0.0011 },
        { lat: 0.0035, lon: 0.0015 },
      ],
    },
    { type: 'way', id: 40, tags: { highway: 'service' }, geometry: [{ lat: 0.004, lon: 0.002 }, { lat: 0.0045, lon: 0.002 }] },
    { type: 'way', id: 41, tags: { highway: 'service', service: 'parking_aisle' }, geometry: [{ lat: 0.004, lon: 0.003 }, { lat: 0.0045, lon: 0.003 }] },
    { type: 'way', id: 42, tags: { highway: 'service', access: 'private' }, geometry: [{ lat: 0.004, lon: 0.004 }, { lat: 0.0045, lon: 0.004 }] },
    { type: 'way', id: 43, tags: { highway: 'footway' }, geometry: [{ lat: 0.001, lon: 0.0005 }, { lat: 0.001, lon: 0.0015 }] },
    { type: 'way', id: 44, tags: { highway: 'residential', area: 'yes' }, geometry: [{ lat: 0.001, lon: 0.0005 }, { lat: 0.001, lon: 0.0015 }] },
    { type: 'way', id: 45, tags: { highway: 'residential' }, geometry: [{ lat: 0.001, lon: 0.0005 }] },
    {
      type: 'way',
      id: 50,
      tags: { natural: 'tree_row', leaf_type: 'broadleaved' },
      geometry: [
        { lat: 0.0021, lon: 0.0012 },
        { lat: 0.0029, lon: 0.0013 },
      ],
    },
    { type: 'node', id: 7, lat: 0.0020000449, lon: 0.0010000049, tags: { highway: 'crossing', crossing: 'marked', 'crossing:markings': 'zebra', kerb: 'lowered' } },
    { type: 'node', id: 5, lat: 0.003, lon: 0.0011, tags: { highway: 'traffic_signals', 'traffic_signals:direction': 'forward' } },
    { type: 'node', id: 6, lat: 0.0031, lon: 0.0012, tags: { highway: 'street_lamp' } },
    { type: 'node', id: 8, lat: 0.00251, lon: 0.00149, tags: { natural: 'tree', species: 'Inventata' } },
  ],
};

test('la tessera dal percorso: z14 e basta, dentro il mondo', () => {
  assert.deepEqual(leggiTessera('GET', 'https://r.dev/v1/corsie/14/8192/8191'), { x: 8192, y: 8191 });
  assert.deepEqual(leggiTessera('GET', 'https://r.dev/v1/corsie/14/0/16383'), { x: 0, y: 16383 });
  assert.equal(leggiTessera('POST', 'https://r.dev/v1/corsie/14/8192/8191').stato, 405);
  assert.equal(leggiTessera('HEAD', 'https://r.dev/v1/corsie/14/8192/8191').stato, 405);
  assert.equal(leggiTessera('GET', 'https://r.dev/v1/corsie/15/8192/8191').stato, 400);
  assert.equal(leggiTessera('GET', 'https://r.dev/v1/corsie/14/16384/0').stato, 400);
  assert.equal(leggiTessera('GET', 'https://r.dev/v1/corsie/14/0/16384').stato, 400);
  assert.equal(leggiTessera('GET', 'https://r.dev/v1/corsie/14/8192').stato, 404);
  assert.equal(leggiTessera('GET', 'https://r.dev/v1/corsie/14/-1/3').stato, 404);
  assert.equal(leggiTessera('GET', 'https://r.dev/v1/corsie/14/1.5/3').stato, 404);
});

test('il riquadro è la tessera con una trentina di metri di orlo', () => {
  const [sud, ovest, nord, est] = riquadroTessera(X, Y);
  // La tessera va da 0° a 360/16384 ≈ 0,02197° in longitudine e da 0° a
  // poco meno in latitudine; trenta metri sono circa 0,00027°.
  assert.ok(Math.abs(ovest + 0.00027) < 0.00001, `ovest ${ovest}`);
  assert.ok(Math.abs(sud + 0.00027) < 0.00001, `sud ${sud}`);
  assert.ok(Math.abs(est - (360 / 16384 + 0.00027)) < 0.00001, `est ${est}`);
  assert.ok(nord > 0.0219 && nord < 0.0223, `nord ${nord}`);
  // Ai bordi del mondo il riquadro non esce.
  const [s0, o0] = riquadroTessera(0, 16383);
  assert.ok(o0 >= -180 && s0 >= -90);
});

test('la richiesta a Overpass: le vie intere, i nodi da disegnare, gli alberi', () => {
  const q = richiestaOverpass(X, Y);
  const b = `(${riquadroTessera(X, Y).join(',')})`;
  assert.ok(q.startsWith('[out:json][timeout:25];'));
  assert.ok(q.includes(`way["highway"~"^(motorway|motorway_link|trunk|`));
  assert.ok(q.includes('living_street)$"]'));
  assert.ok(q.includes('way["highway"="service"]["service"!~"^(parking_aisle|driveway|drive-through|emergency_access)$"]["access"!~"^(private|no)$"]'));
  assert.ok(q.includes('->.vie;.vie out tags geom;'));
  assert.ok(q.includes(`node(w.vie)["highway"~"^(crossing|traffic_signals|stop|give_way|motorway_junction)$"]${b};out;`));
  assert.ok(q.includes(`node["natural"="tree"]${b};out;`));
  assert.ok(q.endsWith(`way["natural"="tree_row"]${b};out tags geom;`));
  // Il riquadro tutte le volte, e nessuna geometria tagliata al bordo.
  assert.equal(q.split(b).length - 1, 5);
  assert.ok(!q.includes('geom('));
});

test('dagli elementi di Overpass al messaggio «corsie»', () => {
  const dati = daElementiOsm(RISPOSTA_INVENTATA.elements, { x: X, y: Y });
  assert.deepEqual(dati, {
    v: 1,
    z: 14,
    x: X,
    y: Y,
    strade: [
      { id: 10, hw: 'motorway_link', g: [0.0011, 0.003, 0.0015, 0.0035], lanes: '1', placement: 'right_of:1' },
      {
        id: 30,
        hw: 'primary',
        g: [0.001, 0.001, 0.001, 0.002, 0.0011, 0.003],
        lanes: '3',
        'turn:lanes': 'left|through|through;right',
        oneway: 'yes',
      },
      { id: 40, hw: 'service', g: [0.002, 0.004, 0.002, 0.0045] },
    ],
    nodi: [
      { id: 5, g: [0.0011, 0.003], highway: 'traffic_signals', 'traffic_signals:direction': 'forward' },
      { id: 7, g: [0.001, 0.002], highway: 'crossing', crossing: 'marked', 'crossing:markings': 'zebra' },
    ],
    alberi: [[0.00149, 0.00251]],
    filari: [{ id: 50, g: [0.0012, 0.0021, 0.0013, 0.0029] }],
  });
  // Il nodo comune fra le due vie ha le stesse coordinate nelle due.
  const [l, p] = [dati.strade[0], dati.strade[1]];
  assert.deepEqual(l.g.slice(0, 2), p.g.slice(-2));
});

test('anche le vie coi numeri dei nodi, e niente elementi = tessera vuota', () => {
  const dati = daElementiOsm([
    { type: 'node', id: 1, lat: 0.001, lon: 0.001 },
    { type: 'node', id: 2, lat: 0.002, lon: 0.001 },
    { type: 'way', id: 9, nodes: [1, 2, 3], tags: { highway: 'residential', lanes: '2' } },
  ]);
  assert.deepEqual(dati.strade, [{ id: 9, hw: 'residential', g: [0.001, 0.001, 0.001, 0.002], lanes: '2' }]);
  assert.equal(dati.z, undefined);
  assert.deepEqual(daElementiOsm(undefined, { x: 1, y: 2 }), { v: 1, z: 14, x: 1, y: 2, strade: [], nodi: [], alberi: [], filari: [] });
});

test('un mese fresca, tre mesi in cache', () => {
  assert.ok(fresca(1000, 1000 + FRESCA_MS - 1));
  assert.ok(!fresca(1000, 1000 + FRESCA_MS));
  assert.ok(!fresca(NaN, 1000));
  assert.equal(FRESCA_MS, 30 * 24 * 3600 * 1000);
  assert.equal(DURATA_CACHE_S, 90 * 24 * 3600);
});

// ── La richiesta intera, con Overpass e la cache finti ─────────────────

let cache;
let chiamate;
let rispondi;
let attese;
const fetchVero = globalThis.fetch;
const cachesVere = globalThis.caches;

beforeEach(() => {
  cache = new Map();
  chiamate = [];
  attese = [];
  globalThis.caches = {
    default: {
      match: async (r) => cache.get(r.url)?.clone(),
      put: async (r, risposta) => {
        cache.set(r.url, risposta);
      },
    },
  };
  globalThis.fetch = async (server, opzioni) => {
    chiamate.push({ server, data: new URLSearchParams(opzioni.body).get('data') });
    return rispondi(server, chiamate.length);
  };
});

afterEach(() => {
  globalThis.fetch = fetchVero;
  globalThis.caches = cachesVere;
});

const ctx = { waitUntil: (p) => attese.push(p) };
const chiedi = (percorso, metodo = 'GET') => corsie(new Request(`https://r.dev${percorso}`, { method: metodo }), ctx, { attesaMs: 0 });
const buona = () => new Response(JSON.stringify(RISPOSTA_INVENTATA), { status: 200 });
const CHIAVE = `https://cache.gdanav/corsie/v1/14/${X}/${Y}`;

test('la prima volta da Overpass, poi dalla cache', async () => {
  rispondi = buona;
  const prima = await chiedi(`/v1/corsie/14/${X}/${Y}`);
  assert.equal(prima.status, 200);
  assert.equal(prima.headers.get('content-type'), 'application/json');
  assert.equal(prima.headers.get('cache-control'), `public, max-age=${DURATA_CACHE_S}`);
  assert.ok(Number(prima.headers.get('x-gdanav-salvata')) > 0);
  const dati = await prima.json();
  assert.equal(dati.strade.length, 3);
  assert.equal(chiamate.length, 1);
  assert.equal(chiamate[0].server, SERVER_OVERPASS[0]);
  assert.equal(chiamate[0].data, richiestaOverpass(X, Y));
  await Promise.all(attese);
  assert.ok(cache.has(CHIAVE));

  const seconda = await chiedi(`/v1/corsie/14/${X}/${Y}`);
  assert.equal(chiamate.length, 1);
  assert.deepEqual(await seconda.json(), dati);
});

test('una copia vecchia si rinfresca; se Overpass non c\'è si serve lo stesso', async () => {
  const vecchiDati = { v: 1, z: 14, x: X, y: Y, strade: [], nodi: [], alberi: [], filari: [] };
  const salvata = Date.now() - FRESCA_MS - 1;
  cache.set(
    CHIAVE,
    new Response(JSON.stringify(vecchiDati), { headers: { 'content-type': 'application/json', 'x-gdanav-salvata': String(salvata) } }),
  );

  rispondi = () => new Response('<html>giù</html>', { status: 504 });
  const r = await chiedi(`/v1/corsie/14/${X}/${Y}`);
  assert.equal(r.status, 200);
  assert.equal(r.headers.get('x-gdanav-vecchia'), '1');
  assert.equal(r.headers.get('x-gdanav-salvata'), String(salvata));
  assert.deepEqual(await r.json(), vecchiDati);
  // Due tentativi per server, poi la copia vecchia.
  assert.deepEqual(
    chiamate.map((c) => c.server),
    [SERVER_OVERPASS[0], SERVER_OVERPASS[0], SERVER_OVERPASS[1], SERVER_OVERPASS[1]],
  );

  chiamate = [];
  rispondi = buona;
  const nuova = await chiedi(`/v1/corsie/14/${X}/${Y}`);
  assert.equal(nuova.headers.get('x-gdanav-vecchia'), null);
  assert.equal((await nuova.json()).strade.length, 3);
  assert.equal(chiamate.length, 1);
});

test('il primo server occupato: si passa al secondo', async () => {
  rispondi = (server) => (server === SERVER_OVERPASS[0] ? new Response('troppe', { status: 429 }) : buona());
  const r = await chiedi(`/v1/corsie/14/${X}/${Y}`);
  assert.equal(r.status, 200);
  assert.equal((await r.json()).nodi.length, 2);
  assert.deepEqual(
    chiamate.map((c) => c.server),
    [SERVER_OVERPASS[0], SERVER_OVERPASS[0], SERVER_OVERPASS[1]],
  );
});

test('un errore vero non si riprova sullo stesso server; senza copia è 502', async () => {
  rispondi = (server, n) =>
    n === 1 ? new Response('richiesta sbagliata', { status: 400 }) : new Response('{"remark":"runtime error: Query timed out"}');
  const r = await chiedi(`/v1/corsie/14/${X}/${Y}`);
  assert.equal(r.status, 502);
  assert.match((await r.json()).errore, /^corsie: /);
  assert.equal(chiamate.length, 2);
  assert.equal(cache.size, 0);
});

test('gli indirizzi sbagliati non arrivano a Overpass', async () => {
  rispondi = buona;
  assert.equal((await chiedi(`/v1/corsie/14/${X}/${Y}`, 'POST')).status, 405);
  assert.equal((await chiedi('/v1/corsie/13/1/1')).status, 400);
  assert.equal((await chiedi('/v1/corsie/14/99999/1')).status, 400);
  assert.equal((await chiedi('/v1/corsie/14')).status, 404);
  assert.equal(chiamate.length, 0);
});

// ── L'archivio nostro (R2 finto) ───────────────────────────────────────

import { gzipSync } from 'node:zlib';

import { CHIAVE_MANIFESTO, TEMPO_OVERPASS_MS, chiaveArchivio, dentroCopertura, manifestoBuono } from '../src/corsie.js';

// Un estratto di ieri: le tessere che ne vengono sono fresche.
const ESTRATTO = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
const COPERTURA = { [Y]: [[X - 5, X - 1], [X, X + 2]], [Y + 1]: [[X, X]] };
const manifesto = (altro = {}) => ({ v: 1, z: 14, estratto: ESTRATTO, tessere: 1, copertura: COPERTURA, ...altro });

/** Un bucket R2 finto: get(chiave) come il binding, con i byte dati. */
function r2Finto(oggetti, { rotto = false } = {}) {
  const letti = [];
  return {
    letti,
    get: async (chiave) => {
      letti.push(chiave);
      if (rotto) throw new Error('R2 giù');
      if (!(chiave in oggetti)) return null;
      const v = oggetti[chiave];
      const byte = typeof v === 'string' ? new TextEncoder().encode(v) : new Uint8Array(v);
      return { arrayBuffer: async () => byte.slice().buffer, text: async () => new TextDecoder().decode(byte) };
    },
  };
}

const TESSERA_ARCHIVIO = JSON.stringify(daElementiOsm(RISPOSTA_INVENTATA.elements, { x: X, y: Y }));
const chiediConArchivio = (archivio, percorso = `/v1/corsie/14/${X}/${Y}`) =>
  corsie(new Request(`https://r.dev${percorso}`), ctx, { attesaMs: 0, archivio });

test('la copertura dell\'archivio: per riga, intervalli con gli estremi compresi', () => {
  assert.ok(dentroCopertura(COPERTURA, X - 5, Y));
  assert.ok(dentroCopertura(COPERTURA, X - 1, Y));
  assert.ok(dentroCopertura(COPERTURA, X + 2, Y));
  assert.ok(!dentroCopertura(COPERTURA, X + 3, Y));
  assert.ok(!dentroCopertura(COPERTURA, X - 6, Y));
  assert.ok(dentroCopertura(COPERTURA, X, Y + 1));
  assert.ok(!dentroCopertura(COPERTURA, X + 1, Y + 1));
  assert.ok(!dentroCopertura(COPERTURA, X, Y + 2));
  assert.ok(!dentroCopertura(null, X, Y));
  assert.ok(manifestoBuono(manifesto()));
  assert.ok(!manifestoBuono(manifesto({ v: 2 })));
  assert.ok(!manifestoBuono(manifesto({ z: 13 })));
  assert.ok(!manifestoBuono(manifesto({ estratto: 'ieri' })));
  assert.equal(chiaveArchivio(X, Y), `corsie/v1/14/${X}/${Y}.json.gz`);
});

test('dall\'archivio: la tessera compressa, con la data dell\'estratto, senza Overpass', async () => {
  rispondi = buona;
  const archivio = r2Finto({
    [CHIAVE_MANIFESTO]: JSON.stringify(manifesto()),
    [chiaveArchivio(X, Y)]: gzipSync(TESSERA_ARCHIVIO),
  });
  const r = await chiediConArchivio(archivio);
  assert.equal(r.status, 200);
  assert.equal(r.headers.get('content-type'), 'application/json');
  assert.equal(r.headers.get('cache-control'), `public, max-age=${DURATA_CACHE_S}`);
  assert.equal(r.headers.get('x-gdanav-salvata'), String(Date.parse(ESTRATTO)));
  assert.equal(r.headers.get('x-gdanav-vecchia'), null);
  // Lo stesso testo che il relay fa da Overpass.
  assert.equal(await r.text(), TESSERA_ARCHIVIO);
  assert.equal(chiamate.length, 0);
  await Promise.all(attese);
  assert.ok(cache.has(CHIAVE));
});

test('una tessera coperta ma senza oggetto è vuota, non si chiede a Overpass', async () => {
  rispondi = buona;
  const archivio = r2Finto({ [CHIAVE_MANIFESTO]: JSON.stringify(manifesto()) });
  const r = await chiediConArchivio(archivio);
  assert.equal(r.status, 200);
  assert.equal(r.headers.get('x-gdanav-salvata'), String(Date.parse(ESTRATTO)));
  assert.deepEqual(await r.json(), { v: 1, z: 14, x: X, y: Y, strade: [], nodi: [], alberi: [], filari: [] });
  assert.equal(chiamate.length, 0);
});

test('fuori dalla copertura, senza manifesto o con R2 rotto: Overpass come prima', async () => {
  rispondi = buona;
  // Fuori dalla copertura e senza oggetto.
  const fuori = r2Finto({ [CHIAVE_MANIFESTO]: JSON.stringify(manifesto({ copertura: {} })) });
  let r = await chiediConArchivio(fuori);
  assert.equal((await r.json()).strade.length, 3);
  assert.equal(chiamate.length, 1);
  assert.deepEqual(fuori.letti, [CHIAVE_MANIFESTO, chiaveArchivio(X, Y)]);

  // Senza manifesto l'archivio non si usa, nemmeno l'oggetto che c'è.
  cache.clear();
  const senza = r2Finto({ [chiaveArchivio(X, Y)]: gzipSync('{"v":1,"strade":"sbagliata"}') });
  r = await chiediConArchivio(senza);
  assert.equal((await r.json()).strade.length, 3);
  assert.equal(chiamate.length, 2);
  assert.deepEqual(senza.letti, [CHIAVE_MANIFESTO]);

  // Un manifesto rotto vale come nessuno.
  cache.clear();
  r = await chiediConArchivio(r2Finto({ [CHIAVE_MANIFESTO]: '{non è json', [chiaveArchivio(X, Y)]: gzipSync(TESSERA_ARCHIVIO) }));
  assert.equal(r.status, 200);
  assert.equal(chiamate.length, 3);

  // R2 che non risponde.
  cache.clear();
  r = await chiediConArchivio(r2Finto({}, { rotto: true }));
  assert.equal(r.status, 200);
  assert.equal(chiamate.length, 4);

  // Un oggetto di un'altra tessera (o rovinato) non si serve.
  cache.clear();
  const altra = JSON.stringify(daElementiOsm([], { x: X + 1, y: Y }));
  r = await chiediConArchivio(r2Finto({ [CHIAVE_MANIFESTO]: JSON.stringify(manifesto()), [chiaveArchivio(X, Y)]: gzipSync(altra) }));
  assert.equal((await r.json()).x, X);
  assert.equal(chiamate.length, 5);

  // Senza bucket (il binding non c'è): come prima.
  cache.clear();
  r = await chiediConArchivio(null);
  assert.equal(r.status, 200);
  assert.equal(chiamate.length, 6);
});

test('anche un oggetto non compresso, e la cache fresca passa davanti all\'archivio', async () => {
  rispondi = buona;
  const archivio = r2Finto({ [CHIAVE_MANIFESTO]: JSON.stringify(manifesto()), [chiaveArchivio(X, Y)]: TESSERA_ARCHIVIO });
  assert.equal(await (await chiediConArchivio(archivio)).text(), TESSERA_ARCHIVIO);
  await Promise.all(attese);
  const letti = archivio.letti.length;
  const seconda = await chiediConArchivio(archivio);
  assert.equal(await seconda.text(), TESSERA_ARCHIVIO);
  // Dalla cache: né R2 né Overpass.
  assert.equal(archivio.letti.length, letti);
  assert.equal(chiamate.length, 0);
});

test('il manifesto si rilegge solo ogni tanto', async () => {
  rispondi = buona;
  const archivio = r2Finto({ [CHIAVE_MANIFESTO]: JSON.stringify(manifesto()) });
  await chiediConArchivio(archivio, `/v1/corsie/14/${X}/${Y}`);
  await chiediConArchivio(archivio, `/v1/corsie/14/${X + 1}/${Y}`);
  assert.equal(archivio.letti.filter((k) => k === CHIAVE_MANIFESTO).length, 1);
  assert.equal(chiamate.length, 0);
});

test('Overpass lento: in tutto meno del tempo dato, poi 502 o la copia vecchia', async () => {
  assert.ok(TEMPO_OVERPASS_MS < 30000);
  // Un server che non risponde mai: si ferma solo col tempo scaduto.
  globalThis.fetch = (server, opzioni) =>
    new Promise((_, no) => {
      chiamate.push({ server });
      opzioni.signal.addEventListener('abort', () => no(opzioni.signal.reason));
    });
  // I tempi di AbortSignal.timeout non tengono acceso node: qui sì.
  const acceso = setInterval(() => {}, 50);
  const inizio = Date.now();
  const r = await corsie(new Request(`https://r.dev/v1/corsie/14/${X}/${Y}`), ctx, { attesaMs: 0, tempoMs: 400 });
  const durata = Date.now() - inizio;
  clearInterval(acceso);
  assert.equal(r.status, 502);
  assert.ok(durata >= 350 && durata < 1000, `durata ${durata}`);
  // Il primo server ha avuto la metà, il secondo il resto.
  assert.deepEqual(
    chiamate.map((c) => c.server),
    [SERVER_OVERPASS[0], SERVER_OVERPASS[1]],
  );
});

test('server occupato e poco tempo: non si aspetta, si passa al secondo', async () => {
  let n = 0;
  globalThis.fetch = async (server) => {
    chiamate.push({ server });
    n++;
    return server === SERVER_OVERPASS[0] ? new Response('troppe', { status: 429 }) : buona();
  };
  const inizio = Date.now();
  const r = await corsie(new Request(`https://r.dev/v1/corsie/14/${X}/${Y}`), ctx, { attesaMs: 5000, tempoMs: 3000 });
  assert.equal(r.status, 200);
  assert.ok(Date.now() - inizio < 1000);
  assert.equal(n, 2);
  assert.deepEqual(
    chiamate.map((c) => c.server),
    [SERVER_OVERPASS[0], SERVER_OVERPASS[1]],
  );
});

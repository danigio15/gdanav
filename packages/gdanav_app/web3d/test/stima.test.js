// Le corsie stimate dalle tessere vettoriali (`stima.js`), per la vista
// «Corsie» senza i dati veri; su strade inventate: nessun posto vero.
import assert from 'node:assert/strict';
import test from 'node:test';
import { normalizza, tessereConCorsieVere } from '../src/corsie.js';
import { ESTENSIONE, latDaMerc, lonDaMerc } from '../src/geo.js';
import { decodifica } from '../src/messaggi.js';
import { trattini, trattiniAdattati } from '../src/segnaletica.js';
import { classeStimata, corsieStimate, idStimato, preparaStimate, tagStimati } from '../src/stima.js';
import { costruisciTessera, stimaTriangoli } from '../src/tessera.js';
import { byteTessera, cavalcavia, strato } from './finte.js';

const X = 8605;
const Y = 5860;

test('la classe e i tag stimati, dalle proprietà di OpenMapTiles', () => {
  assert.equal(classeStimata({ class: 'motorway' }), 'motorway');
  assert.equal(classeStimata({ class: 'motorway', ramp: 1 }), 'motorway_link');
  assert.equal(classeStimata({ class: 'trunk', ramp: 1 }), 'trunk_link');
  assert.equal(classeStimata({ class: 'primary' }), 'primary');
  assert.equal(classeStimata({ class: 'secondary', ramp: 1 }), 'secondary_link');
  assert.equal(classeStimata({ class: 'tertiary' }), 'tertiary');
  // Una superstrada: corsie larghe, niente marciapiedi.
  assert.equal(classeStimata({ class: 'primary', expressway: 1 }), 'trunk');
  assert.equal(classeStimata({ class: 'minor' }), 'residential');
  for (const c of ['service', 'track', 'path', 'rail', 'transit', 'ferry', 'busway', 'raceway']) assert.equal(classeStimata({ class: c }), null, c);
  assert.deepEqual(tagStimati({ class: 'primary', oneway: 1 }), { oneway: 'yes' });
  assert.deepEqual(tagStimati({ class: 'primary', oneway: -1 }), { oneway: '-1' });
  assert.deepEqual(tagStimati({ class: 'primary', oneway: 0 }), {});
  assert.deepEqual(tagStimati({ class: 'primary', brunnel: 'bridge', layer: 1 }), { bridge: 'yes', layer: '1' });
  assert.deepEqual(tagStimati({ class: 'primary', brunnel: 'tunnel', layer: -1 }), { tunnel: 'yes', layer: '-1' });
  assert.deepEqual(tagStimati({ class: 'minor', brunnel: 'ford' }), {});
});

/** Una tessera con una strada di ogni tipo, e quelle che non hanno corsie. */
function quartiere() {
  return {
    transportation: strato([
      { p: { class: 'motorway', oneway: 1 }, g: [[[0, 600], [4096, 600]]] },
      { p: { class: 'motorway', ramp: 1, oneway: 1 }, g: [[[2000, 600], [2600, 900]]] },
      { p: { class: 'primary' }, g: [[[0, 2048], [4096, 2048]]] },
      // Due linee in una feature (le tessere le uniscono così).
      { p: { class: 'minor' }, g: [[[1000, 2048], [1000, 4096]], [[3000, 2048], [3000, 4096]]] },
      { p: { class: 'minor', oneway: -1 }, g: [[[1000, 3000], [3000, 3000]]] },
      { p: { class: 'secondary', brunnel: 'bridge', layer: 1 }, g: [[[2048, 1500], [2048, 0]]] },
      { p: { class: 'tertiary_construction' }, g: [[[200, 3500], [900, 3500]]] },
      { p: { class: 'service' }, g: [[[1500, 2048], [1500, 2500]]] },
      { p: { class: 'path', subclass: 'footway' }, g: [[[100, 100], [400, 400]]] },
      { p: { class: 'rail', subclass: 'rail' }, g: [[[0, 4000], [4096, 4000]]] },
    ]),
  };
}

test('le corsie stimate: il formato del messaggio `corsie`, senza corsie scritte, nodi né alberi', () => {
  const d = corsieStimate({ z: 14, x: X, y: Y, livelli: { '0,0': quartiere() } });
  assert.equal(d.v, 1);
  assert.deepEqual([d.z, d.x, d.y], [14, X, Y]);
  assert.ok(decodifica({ v: 1, tipo: 'corsie', dati: d }), 'la pagina lo prenderebbe come quello del relay');
  assert.deepEqual([d.nodi, d.alberi, d.filari], [[], [], []]);
  const per = (hw) => d.strade.filter((s) => s.hw === hw);
  assert.equal(per('motorway').length, 1);
  assert.equal(per('motorway')[0].oneway, 'yes');
  assert.equal(per('motorway_link').length, 1);
  assert.equal(per('primary').length, 1);
  assert.equal(per('primary')[0].oneway, undefined);
  assert.equal(per('residential').length, 3);
  assert.equal(per('residential').filter((s) => s.oneway === '-1').length, 1);
  assert.equal(per('secondary')[0].bridge, 'yes');
  assert.equal(per('secondary')[0].layer, '1');
  assert.equal(per('tertiary').length, 1, 'la strada in costruzione, come la disegna la scena');
  assert.equal(d.strade.length, 8, 'niente strade di servizio, sentieri, binari');
  for (const s of d.strade) {
    assert.ok(!('lanes' in s) && !('turn:lanes' in s), 'le corsie le dà la classe');
    assert.ok(s.id < 0 && Number.isSafeInteger(s.id));
    assert.equal(s.t, `14/${X}/${Y}`);
    // Sei decimali, come dal relay.
    for (const v of s.g) assert.equal(Math.round(v * 1e6) / 1e6, v);
  }
  assert.equal(new Set(d.strade.map((s) => s.id)).size, d.strade.length, 'gli id non si ripetono');
  // Le corsie di sempre della classe: una per senso in città, due in autostrada.
  const v = (hw) => normalizza(per(hw)[0]);
  assert.deepEqual([v('primary').avanti, v('primary').indietro], [1, 1]);
  assert.deepEqual([v('motorway').avanti, v('motorway').indietro], [2, 0]);
});

test('gli id stimati: negativi, diversi per tessera, linea e pezzo, sempre interi esatti', () => {
  const visti = new Set();
  for (const [x, y, l, k] of [
    [X, Y, 0, 0],
    [X + 1, Y, 0, 0],
    [X, Y + 1, 0, 0],
    [X, Y, 1, 0],
    [X, Y, 0, 1],
    [2 ** 14 - 1, 2 ** 14 - 1, 2 ** 18 - 1, 63],
  ]) {
    const id = idStimato(14, x, y, l, k);
    assert.ok(id < 0 && Number.isSafeInteger(id), String(id));
    assert.ok(!visti.has(id));
    visti.add(id);
  }
});

/** La tessera X/Y e quella a est: una strada da ovest a est che passa il bordo, e una che ci arriva da sud. */
function dueTessere() {
  const ovest = {
    transportation: strato([
      // Come nelle tessere vere: la linea va un poco oltre il bordo, coi
      // punti di là che sono gli stessi della tessera vicina.
      { p: { class: 'primary' }, g: [[[1000, 2048], [3000, 2100], [4096 + 200, 2140]]] },
      { p: { class: 'motorway', oneway: 1 }, g: [[[0, 500], [4096 + 200, 520]]] },
    ]),
  };
  const est = {
    transportation: strato([
      { p: { class: 'primary' }, g: [[[3000 - 4096, 2100], [200, 2140], [900, 2160], [2000, 2048]]] },
      // Una strada che il bordo non lo tocca, lontana.
      { p: { class: 'minor' }, g: [[[900, 4096], [900, 2160]]] },
      { p: { class: 'motorway', oneway: 1 }, g: [[[-4096, 500], [200, 520], [3000, 540]]] },
    ]),
  };
  return { ovest, est };
}

test('sul bordo fra due tessere: lo stesso pezzo con lo stesso id da tutte e due, niente buchi né doppioni', () => {
  const { ovest, est } = dueTessere();
  const daOvest = corsieStimate({ z: 14, x: X, y: Y, livelli: { '0,0': ovest, '1,0': est } });
  const daEst = corsieStimate({ z: 14, x: X + 1, y: Y, livelli: { '-1,0': ovest, '0,0': est } });
  const chiave = (s) => JSON.stringify(s);
  // I pezzi vicini al bordo: gli stessi, uguali in tutto, guardando dall'una o
  // dall'altra (le vie lontane della vicina non si prendono).
  const lontana = daEst.strade.filter((s) => s.hw === 'residential');
  assert.equal(lontana.length, 1);
  assert.ok(!daOvest.strade.some((s) => s.hw === 'residential'));
  assert.deepEqual(daOvest.strade.map(chiave).sort(), daEst.strade.filter((s) => s !== lontana[0]).map(chiave).sort());
  // Ogni pezzo sta tutto nella sua tessera.
  const bordo = lonDaMerc((X + 1) / 2 ** 14);
  for (const s of daOvest.strade) {
    for (let i = 0; i < s.g.length; i += 2) {
      if (s.t === `14/${X}/${Y}`) assert.ok(s.g[i] <= bordo + 1e-6);
      else assert.ok(s.g[i] >= bordo - 1e-6);
    }
  }
  // La strada passa il bordo: il pezzo di ovest finisce dove comincia quello di est.
  const primarie = daOvest.strade.filter((s) => s.hw === 'primary');
  assert.equal(primarie.length, 2);
  const [a, b] = primarie.sort((p, q) => p.g[0] - q.g[0]);
  assert.deepEqual(a.g.slice(-2), b.g.slice(0, 2));
  assert.ok(Math.abs(a.g.at(-2) - bordo) < 1e-6);
  const autostrade = daOvest.strade.filter((s) => s.hw === 'motorway').sort((p, q) => p.g[0] - q.g[0]);
  assert.deepEqual(autostrade[0].g.slice(-2), autostrade[1].g.slice(0, 2));
  assert.notEqual(a.id, b.id);
});

test('i pezzi sul bordo, disegnati: le tessere vicine si toccano senza sovrapporsi', () => {
  const { ovest, est } = dueTessere();
  const fai = (x, livelli) =>
    costruisciTessera({ z: 14, x, y: Y, livelli, datiCorsie: preparaStimate(corsieStimate({ z: 14, x, y: Y, livelli })), vistaCorsie: true });
  const tO = fai(X, { '0,0': ovest, '1,0': est });
  const tE = fai(X + 1, { '-1,0': ovest, '0,0': est });
  for (const t of [tO, tE]) {
    const meta = t.centro.lato / 2;
    const p = t.corsie.asfalto.posizioni;
    let fuori = 0;
    for (let i = 0; i < p.length; i += 3) if (Math.abs(p[i]) > meta + 12 || Math.abs(p[i + 1]) > meta + 12) fuori++;
    // Solo i capi tondi delle vie sul bordo (mezzo cerchio, meno largo della strada) escono di poco.
    assert.equal(fuori, 0);
  }
  // L'asfalto della strada che passa il bordo, da tutte e due le parti, fino al bordo.
  const fino = (t, lato) => {
    const meta = t.centro.lato / 2;
    const p = t.corsie.asfalto.posizioni;
    let m = -Infinity;
    for (let i = 0; i < p.length; i += 3) if (Math.abs(p[i + 1]) < 200) m = Math.max(m, lato * p[i]);
    return m - meta;
  };
  assert.ok(Math.abs(fino(tO, 1)) < 8, `a ovest fino al bordo: ${fino(tO, 1)}`);
  assert.ok(Math.abs(fino(tE, -1)) < 8, `a est dal bordo: ${fino(tE, -1)}`);
});

test('il tratteggio dei pezzi stimati: un numero intero di trattini, mezzo vuoto ai capi', () => {
  for (const L of [6, 40, 133.7, 500]) {
    const t = trattiniAdattati(L, 4.5, 7.5);
    const n = Math.max(1, Math.round(L / 12));
    assert.equal(t.length, n, `L ${L}`);
    const k = L / (n * 12);
    assert.ok(Math.abs(t[0][0] - (7.5 * k) / 2) < 1e-9);
    assert.ok(Math.abs(L - t.at(-1)[1] - (7.5 * k) / 2) < 1e-9);
    // Fra due pezzi in fila, sul bordo, un vuoto intero.
    assert.ok(Math.abs(L - t.at(-1)[1] + trattiniAdattati(L, 4.5, 7.5)[0][0] - 7.5 * k) < 1e-9);
  }
  // Le vie vere restano contate dall'inizio.
  assert.deepEqual(trattini(30, 3, 3)[0], [0, 3]);
});

test('la tessera con le corsie stimate: asfalto, righe e marciapiedi; niente semafori né strisce', () => {
  const livelli = { '0,0': cavalcavia() };
  const senza = costruisciTessera({ z: 14, x: X, y: Y, livelli, vistaCorsie: true });
  assert.equal(senza.corsie, null);
  const dati = corsieStimate({ z: 14, x: X, y: Y, livelli });
  assert.deepEqual(
    dati.strade.map((s) => s.hw),
    ['motorway', 'primary', 'primary', 'primary'],
  );
  const pronte = preparaStimate(dati);
  assert.ok(pronte.strade.every((v) => v.stimata));
  const con = costruisciTessera({ z: 14, x: X, y: Y, livelli, datiCorsie: pronte, vistaCorsie: true });
  assert.ok(con.corsie.asfalto.indici.length > 0);
  assert.ok(con.corsie.vernice.indici.length > 0, 'le righe');
  assert.ok(con.corsie.marciapiedi.indici.length > 0, 'i marciapiedi della strada di città');
  assert.equal(con.corsie.segnali, null, 'niente semafori inventati');
  assert.equal(con.semafori.length, 0);
  // I nastri di sempre sotto le corsie non ci sono più (a terra; il ponte e i
  // parapetti restano quelli).
  assert.ok((con.strade.motorway?.indici.length ?? 0) < senza.strade.motorway.indici.length / 4);
  assert.ok((con.strade.primary2?.indici.length ?? 0) < (senza.strade.primary2?.indici.length ?? 0) / 4);
  assert.deepEqual(con.conti.edificiFatti, senza.conti.edificiFatti);
  // Le corsie contano nel budget (sulle vie stimate, dritte, sono pochi
  // triangoli: anche meno dei nastri di sempre che tolgono).
  const triCorsie = Object.values(con.corsie).reduce((n, g) => n + (g ? g.indici.length / 3 : 0), 0);
  assert.ok(triCorsie > 0);
  assert.equal(con.conti.triangoli, stimaTriangoli({ ...con, corsie: null }) + triCorsie, 'le corsie contano nel budget');
  // L'autostrada stimata: due corsie, la riga tratteggiata in mezzo; il ponte
  // a 8 m (layer 1) anche con le corsie.
  const ponte = pronte.strade.find((v) => v.ponte);
  assert.ok(ponte && ponte.livello === 1);
  let alto = 0;
  const p = con.corsie.asfalto.posizioni;
  for (let i = 2; i < p.length; i += 3) alto = Math.max(alto, p[i]);
  assert.ok(alto > 7, `l'asfalto sul ponte, in quota: ${alto}`);
});

test('le tessere che hanno le corsie vere: quella del relay, o dove stanno le vie; vuote nessuna', () => {
  assert.deepEqual(tessereConCorsieVere({ v: 1, z: 14, x: X, y: Y, strade: [{ id: 1, hw: 'primary', g: [0, 0, 1, 1] }] }), [`14/${X}/${Y}`]);
  assert.deepEqual(tessereConCorsieVere({ v: 1, z: 14, x: X, y: Y, strade: [] }), []);
  assert.deepEqual(tessereConCorsieVere({ errore: 'overpass' }), []);
  // Senza la tessera (le prove): quelle delle vie.
  const n = 2 ** 14;
  const lon = (px) => lonDaMerc((X + px) / n);
  const lat = latDaMerc((Y + 0.5) / n);
  assert.deepEqual(tessereConCorsieVere({ v: 1, strade: [{ id: 1, hw: 'primary', g: [lon(0.5), lat, lon(1.5), lat] }] }).sort(), [`14/${X + 1}/${Y}`, `14/${X}/${Y}`].sort());
});

test('il lavoratore: nella vista «Corsie» senza corsie vere le stima; nel 3D aumentato la tessera è la stessa di prima', async () => {
  const risposte = [];
  globalThis.self = { postMessage: (m) => risposte.push(m) };
  await import('../src/lavoratore.js');
  const strati = {
    transportation: [
      { p: { class: 'primary' }, g: [[[0, 2048], [4096, 2048]]] },
      { p: { class: 'minor', oneway: 1 }, g: [[[2048, 2048], [2048, 4096]]] },
      { p: { class: 'service' }, g: [[[1000, 2048], [1000, 2600]]] },
    ],
  };
  const dati = await byteTessera(strati);
  const chiedi = async (piu) => {
    risposte.length = 0;
    self.onmessage({ data: { id: 1, z: 14, x: X, y: Y, tessere: { '0,0': { chiave: `14/${X}/${Y}`, dati: dati.slice(0) } }, dettaglio: 'pieno', edifici: null, ...piu } });
    assert.equal(risposte.length, 1);
    assert.equal(risposte[0].errore, undefined, risposte[0].errore);
    return risposte[0];
  };
  const senzaTempi = (t) => ({ ...t, conti: { ...t.conti, ms: 0, msGrafo: 0 } });
  // Il 3D aumentato: come prima, chieda o no di stimare.
  const prima = costruisciTessera({ z: 14, x: X, y: Y, livelli: { '0,0': { transportation: strato(strati.transportation) } } });
  const aumentato = await chiedi({ corsie: null, vistaCorsie: false, stimaCorsie: false });
  assert.deepEqual(senzaTempi(aumentato.tessera), senzaTempi(prima));
  assert.equal(aumentato.stimate, null);
  const anche = await chiedi({ corsie: null, vistaCorsie: false, stimaCorsie: true });
  assert.deepEqual(senzaTempi(anche.tessera), senzaTempi(prima));
  // La vista «Corsie» senza le corsie vere: stimate, e la pagina le riceve.
  const stimata = await chiedi({ corsie: null, vistaCorsie: true, stimaCorsie: true });
  assert.ok(stimata.tessera.corsie?.asfalto);
  assert.deepEqual(stimata.stimate.map((s) => s.hw).sort(), ['primary', 'residential']);
  assert.ok(stimata.stimate.every((s) => s.id < 0 && s.t === `14/${X}/${Y}`));
  // Con le corsie vere (anche di una tessera vicina) si usano quelle, non si stima.
  const vere = await chiedi({ corsie: { strade: [], nodi: [], alberi: [], filari: [] }, vistaCorsie: true, stimaCorsie: false });
  assert.equal(vere.tessera.corsie, null);
  assert.equal(vere.stimate, null);
  // La tessera di mezzo deve essere quella vera: il pezzo è fatto da quella.
  assert.equal(ESTENSIONE, 4096);
  delete globalThis.self;
});

// Il convertitore dell'archivio delle corsie (strumenti/corsie/archivio.mjs):
// dalle righe OPL di osmium alle tessere, che devono essere le stesse che il
// relay fa da Overpass. Tutto inventato, in mezzo al mare all'incrocio fra
// equatore e meridiano zero, come in corsie.test.js.

import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { gunzipSync } from 'node:zlib';

import { CHIAVE_MANIFESTO, chiaveArchivio, daElementiOsm, dentroCopertura, riquadroTessera } from '../src/corsie.js';
import {
  coperturaDaAnelli,
  costruisci,
  filtriOsmium,
  leggiPoly,
  leggiRigaOpl,
  tessereDelPunto,
  tessereDellaLinea,
  trattoTocca,
} from '../../strumenti/corsie/archivio.mjs';

const X = 8192;
const Y = 8191;

test('le righe OPL di osmium, coi caratteri speciali e i luoghi sulle vie', () => {
  assert.deepEqual(leggiRigaOpl('n7 Thighway=crossing,name=Via%20%Uno%2c%%20%Due x0.0010000049 y0.0020000449'), {
    tipo: 'n',
    id: 7,
    tags: { highway: 'crossing', name: 'Via Uno, Due' },
    lon: 0.0010000049,
    lat: 0.0020000449,
  });
  assert.deepEqual(leggiRigaOpl('w30 Thighway=primary,turn:lanes=left%7c%through Nn1x0.001y0.002,n2x-0.5y0.25,n3xy'), {
    tipo: 'w',
    id: 30,
    tags: { highway: 'primary', 'turn:lanes': 'left|through' },
    nodi: [
      { id: 1, lon: 0.001, lat: 0.002 },
      { id: 2, lon: -0.5, lat: 0.25 },
      { id: 3, lon: NaN, lat: NaN },
    ],
  });
  assert.deepEqual(leggiRigaOpl('n8 T x1 y2'), { tipo: 'n', id: 8, tags: {}, lon: 1, lat: 2 });
  assert.equal(leggiRigaOpl('r5 Ttype=route Mw1@'), null);
  assert.equal(leggiRigaOpl(''), null);
  assert.ok(filtriOsmium().some((f) => f.startsWith('w/highway=motorway,') && f.endsWith(',service')));
});

test('le tessere toccate: col riquadro del relay, anche da un tratto senza nodi dentro', () => {
  const r = riquadroTessera(X, Y);
  assert.ok(trattoTocca(-1, 0.01, 1, 0.01, r));
  assert.ok(!trattoTocca(-1, 0.5, 1, 0.5, r));
  // Sul bordo (orlo compreso) conta.
  assert.ok(trattoTocca(r[1], -1, r[1], 1, r));
  // Un punto sul bordo fra due tessere sta in tutte e due (l'orlo).
  assert.deepEqual(tessereDelPunto(360 / 16384, 0.01).sort(), [
    [X, Y],
    [X + 1, Y],
  ]);
  // Un tratto lungo da una tessera a tre più in là le tocca tutte.
  const t = tessereDellaLinea([
    [-0.01, 0.01],
    [0.05, 0.01],
  ]).sort((a, b) => a[0] - b[0]);
  assert.deepEqual(t, [
    [X - 1, Y],
    [X, Y],
    [X + 1, Y],
    [X + 2, Y],
  ]);
});

test('la copertura: le tessere tutte dentro il poligono, i buchi e il confine fuori', () => {
  const poly = [
    'prova',
    'uno',
    '   0.0E+00   -0.1E+00',
    '   0.1   -0.1',
    '   0.1   0.1',
    '   0.0   0.1',
    'END',
    '!buco',
    '   0.044   0.044',
    '   0.066   0.044',
    '   0.066   0.066',
    '   0.044   0.066',
    'END',
    'END',
    '',
  ].join('\n');
  const anelli = leggiPoly(poly);
  assert.equal(anelli.length, 2);
  const c = coperturaDaAnelli(anelli);
  // Le tessere in mezzo sì; quelle sul lato a lon 0 (l'orlo esce) e a lon 0,1 no.
  assert.ok(dentroCopertura(c, X + 1, Y));
  assert.ok(dentroCopertura(c, X + 3, Y));
  assert.ok(!dentroCopertura(c, X, Y));
  assert.ok(!dentroCopertura(c, X + 4, Y));
  assert.ok(!dentroCopertura(c, X - 1, Y));
  // Il buco (fra 0,044° e 0,066°): la tessera che ci sta dentro e quelle che lo toccano, fuori.
  const yBuco = 8192 - 3; // lat 0,055° circa
  assert.ok(!dentroCopertura(c, X + 2, yBuco));
  assert.ok(dentroCopertura(c, X + 1, Y));
  // Ogni tessera coperta ha il riquadro dentro il quadrato.
  for (const [y, intervalli] of Object.entries(c)) {
    for (const [x0, x1] of intervalli) {
      for (let x = x0; x <= x1; x++) {
        const [s, o, n, e] = riquadroTessera(x, Number(y));
        assert.ok(o > 0 && e < 0.1 && s > -0.1 && n < 0.1, `${x}/${y}`);
      }
    }
  }
});

// Le stesse cose in OPL (come le scrive osmium) e in forma Overpass.
const OPL = [
  'n1 Thighway=crossing,crossing=marked,kerb=lowered x0.001 y0.002',
  'n2 Thighway=traffic_signals x0.005 y0.005', // su nessuna via scelta: niente
  'n3 Tnatural=tree,species=Inventata x0.003 y0.004',
  'n4 Thighway=give_way,natural=tree x0.0031 y0.0041', // albero, su nessuna via
  'n5 Thighway=stop,natural=tree x0.0006 y0.0021', // albero e stop su una via
  'n6 Thighway=stop x0.0081 y0.0081', // su una via di parcheggio: niente
  'w30 Thighway=primary,lanes=3,name=Via%20%Inventata,surface=asphalt Nn10x0.0005y0.002,n5x0.0006y0.0021,n1x0.001y0.002,n11x0.0015y0.0025',
  'w31 Thighway=service,service=parking_aisle Nn6x0.0081y0.0081,n13x0.009y0.009',
  'w32 Thighway=motorway,lanes=2,oneway=yes Nn20x-0.01y0.01,n21x0.05y0.01',
  'w33 Tnatural=tree_row Nn30x0.002y0.003,n31x0.0025y0.0035',
  'w34 Thighway=residential,area=yes Nn40x0.004y0.004,n41x0.0045y0.0045',
  'w35 Thighway=footway Nn42x0.004y0.004,n43x0.0045y0.0045',
  'w36 Thighway=residential Nn44x0.2y0.2,n45x0.2005y0.2005', // in un'altra tessera
  'r1 Ttype=restriction Mw30@from',
];

const COME_OVERPASS = [
  { type: 'way', id: 30, tags: { highway: 'primary', lanes: '3', name: 'Via Inventata', surface: 'asphalt' }, geometry: [{ lat: 0.002, lon: 0.0005 }, { lat: 0.0021, lon: 0.0006 }, { lat: 0.002, lon: 0.001 }, { lat: 0.0025, lon: 0.0015 }] },
  { type: 'way', id: 32, tags: { highway: 'motorway', lanes: '2', oneway: 'yes' }, geometry: [{ lat: 0.01, lon: -0.01 }, { lat: 0.01, lon: 0.05 }] },
  { type: 'way', id: 34, tags: { highway: 'residential', area: 'yes' }, geometry: [{ lat: 0.004, lon: 0.004 }, { lat: 0.0045, lon: 0.0045 }] },
  { type: 'node', id: 1, lat: 0.002, lon: 0.001, tags: { highway: 'crossing', crossing: 'marked', kerb: 'lowered' } },
  { type: 'node', id: 5, lat: 0.0021, lon: 0.0006, tags: { highway: 'stop', natural: 'tree' } },
  { type: 'node', id: 3, lat: 0.004, lon: 0.003, tags: { natural: 'tree', species: 'Inventata' } },
  { type: 'node', id: 4, lat: 0.0041, lon: 0.0031, tags: { highway: 'give_way', natural: 'tree' } },
  { type: 'node', id: 5, lat: 0.0021, lon: 0.0006, tags: { highway: 'stop', natural: 'tree' } },
  { type: 'way', id: 33, tags: { natural: 'tree_row' }, geometry: [{ lat: 0.003, lon: 0.002 }, { lat: 0.0035, lon: 0.0025 }] },
];

test('dalle righe OPL all\'archivio: lo stesso JSON del percorso Overpass', async () => {
  const cartella = mkdtempSync(join(tmpdir(), 'archivio-corsie-'));
  try {
    const uscita = join(cartella, 'uscita');
    const riassunto = await costruisci(OPL, { uscita, appoggio: join(cartella, 'appoggio'), estratto: '2026-01-02T03:04:05.000Z' });
    const leggi = (x, y) => gunzipSync(readFileSync(join(uscita, chiaveArchivio(x, y)))).toString('utf8');

    const attesa = daElementiOsm(COME_OVERPASS, { x: X, y: Y });
    assert.equal(leggi(X, Y), JSON.stringify(attesa));
    // Lo stop sulla via arriva coi nodi da disegnare, e l'albero-stop prima
    // dell'altro albero (come nell'ordine di Overpass).
    assert.deepEqual(attesa.nodi.map((n) => n.id), [1, 4, 5]);
    assert.deepEqual(attesa.alberi, [[0.0006, 0.0021], [0.003, 0.004], [0.0031, 0.0041]]);
    assert.deepEqual(attesa.strade.map((s) => s.id), [30, 32]);

    // L'autostrada passa anche dalle tessere accanto, intera.
    for (const x of [X - 1, X + 1, X + 2]) {
      const d = JSON.parse(leggi(x, Y));
      assert.deepEqual(d.strade.map((s) => s.id), [32]);
      assert.deepEqual(d.strade[0].g, [-0.01, 0.01, 0.05, 0.01]);
    }
    assert.equal(JSON.parse(leggi(X + 9, Y - 9)).strade[0].id, 36);
    assert.equal(riassunto.tessere, 5);
    assert.ok(!existsSync(join(cartella, 'appoggio')));

    const m = JSON.parse(readFileSync(join(uscita, CHIAVE_MANIFESTO), 'utf8'));
    assert.equal(m.v, 1);
    assert.equal(m.z, 14);
    assert.equal(m.estratto, '2026-01-02T03:04:05.000Z');
    assert.equal(m.tessere, 5);
    assert.equal(m.copertura, null);
  } finally {
    rmSync(cartella, { recursive: true, force: true });
  }
});

test('con la copertura si scrivono solo le tessere tutte dentro', async () => {
  const cartella = mkdtempSync(join(tmpdir(), 'archivio-corsie-'));
  try {
    const uscita = join(cartella, 'uscita');
    const copertura = { [Y]: [[X, X + 1]] };
    const riassunto = await costruisci(OPL, { uscita, appoggio: join(cartella, 'appoggio'), copertura });
    assert.ok(existsSync(join(uscita, chiaveArchivio(X, Y))));
    assert.ok(existsSync(join(uscita, chiaveArchivio(X + 1, Y))));
    assert.ok(!existsSync(join(uscita, chiaveArchivio(X - 1, Y))));
    assert.equal(riassunto.tessere, 2);
    assert.equal(riassunto.fuoriCopertura, 3);
    assert.deepEqual(JSON.parse(readFileSync(join(uscita, CHIAVE_MANIFESTO), 'utf8')).copertura, copertura);
  } finally {
    rmSync(cartella, { recursive: true, force: true });
  }
});

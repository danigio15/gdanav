import assert from 'node:assert/strict';
import test from 'node:test';
import { ALTEZZA_LIVELLO, PENDENZA, altezzaLivello, grafoStrade, larghezzaStrada, livelloStrada, uniscIBordi } from '../src/elevazione.js';

// Metri = pixel, per semplicità.
const metri = (x, y) => [x, -y];

test('il livello: un ponte almeno 1, una galleria 0', () => {
  assert.equal(livelloStrada({ brunnel: 'bridge' }), 1);
  assert.equal(livelloStrada({ brunnel: 'bridge', layer: 2 }), 2);
  assert.equal(livelloStrada({ brunnel: 'bridge', layer: -1 }), 1);
  assert.equal(livelloStrada({ brunnel: 'tunnel', layer: -1 }), 0);
  assert.equal(livelloStrada({}), 0);
  assert.equal(altezzaLivello(2), 2 * ALTEZZA_LIVELLO);
});

test('le larghezze: rampe strette, autostrade a doppio senso larghe', () => {
  assert.equal(larghezzaStrada({ class: 'motorway', ramp: 1 }), 6.5);
  assert.equal(larghezzaStrada({ class: 'motorway', oneway: 1 }), 11.5);
  assert.ok(larghezzaStrada({ class: 'motorway' }) > 20);
});

/** Una strada a terra che sale su un ponte e riscende. */
function ponte() {
  return [
    { p: { class: 'primary' }, g: [[0, 0], [400, 0]] },
    { p: { class: 'primary', brunnel: 'bridge', layer: 1 }, g: [[400, 0], [700, 0]] },
    { p: { class: 'primary' }, g: [[700, 0], [1100, 0]] },
  ];
}

const quotaA = (g, x) => {
  let meglio = null;
  for (const n of g.nodi) if (!meglio || Math.abs(n.x - x) < Math.abs(meglio.x - x)) meglio = n;
  return meglio.h;
};

test('il ponte sta al suo livello, e la rampa sale piano', () => {
  const g = grafoStrade(ponte(), metri);
  assert.ok(Math.abs(quotaA(g, 550) - ALTEZZA_LIVELLO) < 0.05, 'in mezzo al ponte 7 m');
  assert.equal(quotaA(g, 0), 0, 'lontano, a terra');
  const salita = quotaA(g, 340);
  assert.ok(salita > 1 && salita < ALTEZZA_LIVELLO, `a 60 m dal ponte a metà salita (${salita})`);
  // Mai più ripida di quanto serve: la rampa è lunga almeno h/pendenza.
  assert.equal(quotaA(g, 400 - ALTEZZA_LIVELLO / PENDENZA - 30), 0);
  // E sale sempre, verso il ponte.
  let prima = -1;
  for (let x = 200; x <= 400; x += 10) {
    const h = quotaA(g, x);
    assert.ok(h >= prima - 0.05, `sale (${x}: ${h} dopo ${prima})`);
    prima = h;
  }
});

test('la strada che passa sotto resta a terra', () => {
  const strade = [...ponte(), { p: { class: 'motorway', oneway: 1 }, g: [[550, -500], [550, 500]] }];
  const g = grafoStrade(strade, metri);
  const sotto = g.nodi.filter((n) => Math.abs(n.x - 550) < 0.5 && Math.abs(n.y) > 3);
  assert.ok(sotto.length > 10);
  for (const n of sotto) assert.equal(n.h, 0);
});

test('due ponti di livello diverso si raccordano', () => {
  const strade = [
    { p: { class: 'motorway', brunnel: 'bridge', layer: 1, ramp: 1 }, g: [[0, 0], [300, 0]] },
    { p: { class: 'motorway', brunnel: 'bridge', layer: 2, ramp: 1 }, g: [[300, 0], [700, 0]] },
  ];
  const g = grafoStrade(strade, metri);
  assert.ok(Math.abs(quotaA(g, 600) - 14) < 0.1);
  const giunto = quotaA(g, 300);
  assert.ok(giunto > 7.5 && giunto < 13.5, `al giunto fra 7 e 14 (${giunto})`);
});

test('i capi tagliati sul bordo delle tessere si uniscono', () => {
  const strade = [
    { p: {}, g: [[100, 200], [4096, 1000]] },
    { p: {}, g: [[4096, 1002.5], [5000, 1500]] },
  ];
  assert.equal(uniscIBordi(strade), 1);
  assert.deepEqual(strade[0].g[1], strade[1].g[0]);
});

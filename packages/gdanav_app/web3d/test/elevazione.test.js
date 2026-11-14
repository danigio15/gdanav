import assert from 'node:assert/strict';
import test from 'node:test';
import { ALTEZZA_LIVELLO, PENDENZA, altezzaLivello, grafoStrade, larghezzaStrada, livelloStrada, segnaRotonde, uniscIBordi } from '../src/elevazione.js';

// Metri = pixel, per semplicità.
const metri = (x, y) => [x, -y];

test('il livello: un ponte almeno 1, una galleria 0', () => {
  assert.equal(livelloStrada({ brunnel: 'bridge' }), 1);
  assert.equal(livelloStrada({ brunnel: 'bridge', layer: 2 }), 2);
  assert.equal(livelloStrada({ brunnel: 'bridge', layer: -1 }), 1);
  assert.equal(livelloStrada({ brunnel: 'tunnel', layer: -1 }), 0);
  assert.equal(livelloStrada({}), 0);
  assert.equal(livelloStrada({ brunnel: 'bridge', layer: 0 }), 1, 'un ponte a layer 0 sta comunque in alto');
  assert.equal(livelloStrada({ brunnel: 'bridge', layer: 'x' }), 1);
  assert.equal(livelloStrada({ brunnel: 'bridge', layer: 9 }), 5);
  assert.equal(livelloStrada({ layer: 1 }), 0, 'un layer senza ponte resta a terra');
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
  const L = ALTEZZA_LIVELLO;
  assert.ok(Math.abs(quotaA(g, 600) - 2 * L) < 0.1);
  const giunto = quotaA(g, 300);
  assert.ok(giunto > L + 0.5 && giunto < 2 * L - 0.5, `al giunto fra un livello e due (${giunto})`);
});

test('i capi tagliati sul bordo delle tessere si uniscono', () => {
  const strade = [
    { p: {}, g: [[100, 200], [4096, 1000]] },
    { p: {}, g: [[4096, 1002.5], [5000, 1500]] },
  ];
  assert.equal(uniscIBordi(strade), 1);
  assert.deepEqual(strade[0].g[1], strade[1].g[0]);
});

/** Un anello di raggio [r] attorno a [cx, cy], a [n] lati, come strada a sé. */
function anello(cx, cy, r, n = 16, p = { class: 'secondary' }) {
  const g = [];
  for (let k = 0; k <= n; k++) {
    const a = (2 * Math.PI * (k % n)) / n;
    g.push([cx + r * Math.cos(a), cy + r * Math.sin(a)]);
  }
  return { p, g };
}

/*
 * «Mi è capitato in due rotonde che erano a livello strada ma le faceva
 * vedere sopraelevate.» Una rotonda a terra, coi suoi bracci, a una
 * quarantina di metri dal capo di un cavalcavia: il rilassamento la tirava su
 * quasi all'altezza del ponte (era a sei, sette metri).
 */
function rotondaVicinoAlPonte() {
  return [
    // Il cavalcavia, da 100 a 400, a terra dopo.
    { p: { class: 'primary', brunnel: 'bridge', layer: 1 }, g: [[100, 0], [400, 0]] },
    { p: { class: 'primary' }, g: [[400, 0], [800, 0]] },
    // Il braccio verso la rotonda (centro a 0,0, raggio 18): 82 m dal ponte all'anello.
    { p: { class: 'primary' }, g: [[18, 0], [100, 0]] },
    anello(0, 0, 18),
    // Gli altri bracci, corti, verso le case.
    { p: { class: 'secondary' }, g: [[-18, 0], [-120, 0]] },
    { p: { class: 'secondary' }, g: [[0, 18], [0, 120]] },
    { p: { class: 'secondary' }, g: [[0, -18], [0, -120]] },
    // E un isolato fra i bracci, che chiude il giro.
    { p: { class: 'minor' }, g: [[-120, 0], [-120, 120], [0, 120]] },
  ];
}

test('una rotonda a terra vicino a un cavalcavia resta a terra; la salita è nel braccio', () => {
  const g = grafoStrade(rotondaVicinoAlPonte(), metri);
  const sullAnello = g.nodi.filter((n) => Math.abs(Math.hypot(n.x, n.y) - 18) < 0.5);
  assert.ok(sullAnello.length >= 16);
  for (const n of sullAnello) assert.ok(n.h < 0.05, `l'anello a terra (${n.x.toFixed(0)},${n.y.toFixed(0)}: ${n.h.toFixed(2)} m)`);
  // Il ponte resta in quota, e il braccio sale da terra al ponte.
  assert.ok(Math.abs(quotaA(g, 250) - ALTEZZA_LIVELLO) < 0.05);
  const meta = g.nodi.filter((n) => Math.abs(n.y) < 0.5 && n.x > 50 && n.x < 70)[0];
  assert.ok(meta.h > 1 && meta.h < ALTEZZA_LIVELLO - 1, `a metà braccio a metà salita (${meta.h})`);
  // Gli altri bracci, oltre la rotonda, a terra.
  for (const n of g.nodi.filter((q) => q.x < -20 && Math.abs(q.y) < 0.5)) assert.equal(n.h, 0);
});

test('una rotonda con un pezzo di ponte suo resta in quota', () => {
  // L'anello passa sopra una strada: metà è ponte.
  const sopra = { class: 'secondary', brunnel: 'bridge', layer: 1 };
  const a = anello(0, 0, 25, 16).g;
  const strade = [
    { p: { class: 'secondary' }, g: a.slice(0, 9) },
    { p: sopra, g: a.slice(8) },
    { p: { class: 'primary' }, g: [[0, -300], [0, 300]] },
  ];
  const g = grafoStrade(strade, metri);
  const sullAnello = g.nodi.filter((n) => Math.abs(Math.hypot(n.x, n.y) - 25) < 1 && n.y < -5);
  assert.ok(sullAnello.length > 3);
  for (const n of sullAnello) assert.ok(n.h > ALTEZZA_LIVELLO - 0.5, `la metà sul ponte in quota (${n.h})`);
});

test('le rotonde: un anello tondo sì, un isolato quadrato no', () => {
  const g = grafoStrade([anello(0, 0, 15, 12), { p: { class: 'minor' }, g: [[200, 0], [260, 0], [260, 60], [200, 60], [200, 0]] }], metri);
  assert.ok(g.nodi.filter((n) => n.rotonda).every((n) => Math.hypot(n.x, n.y) < 16));
  assert.ok(g.nodi.some((n) => n.rotonda));
  assert.equal(segnaRotonde([], []), 0);
});

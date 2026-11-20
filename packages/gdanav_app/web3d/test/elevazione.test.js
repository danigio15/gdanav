import assert from 'node:assert/strict';
import test from 'node:test';
import { ALTEZZA_LIVELLO, PENDENZA, SCAVALCO_M, altezzaLivello, grafoStrade, larghezzaStrada, livelloStrada, segnaRotonde, uniscIBordi } from '../src/elevazione.js';

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

test('un ponte sta sopra quello che scavalca (luce e impalcato), non otto metri per livello', () => {
  // Una strada a terra (x = 300), un cavalcavia al primo livello che la
  // scavalca (y = 0), e un viadotto al secondo che scavalca il cavalcavia
  // (x = 500) e poi scende sulla rampa a terra.
  const strade = [
    { p: { class: 'primary' }, g: [[300, -400], [300, 400]] },
    { p: { class: 'primary', brunnel: 'bridge', layer: 1 }, g: [[150, 0], [700, 0]] },
    { p: { class: 'primary' }, g: [[0, 0], [150, 0]] },
    { p: { class: 'primary' }, g: [[700, 0], [900, 0]] },
    { p: { class: 'motorway', brunnel: 'bridge', layer: 2 }, g: [[500, -300], [500, 200]] },
    { p: { class: 'motorway' }, g: [[500, 200], [500, 700]] },
  ];
  const g = grafoStrade(strade, metri);
  const L = ALTEZZA_LIVELLO;
  const vicino = (x, y) => g.nodi.reduce((m, n) => (Math.hypot(n.x - x, n.y - y) < Math.hypot(m.x - x, m.y - y) ? n : m));
  assert.ok(Math.abs(vicino(300, 0).h - L) < 0.3, `il cavalcavia sopra la strada (${vicino(300, 0).h})`);
  const sopra = vicino(500, -1).h;
  assert.ok(Math.abs(sopra - (L + SCAVALCO_M)) < 0.5, `il viadotto sopra il cavalcavia (${sopra})`);
  // Altrove il viadotto non sta più in alto del necessario, e scende sulla rampa senza scalini.
  // (Solo i nodi del viadotto e della sua rampa, non quelli del cavalcavia che incrocia.)
  const lungo = g.nodi.filter((n) => Math.abs(n.x - 500) < 0.01).sort((p, q) => p.y - q.y);
  let ripida = 0;
  for (let k = 1; k < lungo.length; k++) ripida = Math.max(ripida, Math.abs(lungo[k].h - lungo[k - 1].h) / Math.max(1, lungo[k].y - lungo[k - 1].y));
  assert.ok(ripida <= PENDENZA + 0.01, `al più del ${PENDENZA * 100}% (${(ripida * 100).toFixed(1)}%)`);
  assert.equal(vicino(500, -690).h, 0, 'in fondo alla rampa a terra');
});

test('i capi tagliati sul bordo delle tessere si uniscono', () => {
  const strade = [
    { p: {}, g: [[100, 200], [4096, 1000]] },
    { p: {}, g: [[4096, 1002.5], [5000, 1500]] },
  ];
  assert.equal(uniscIBordi(strade), 1);
  assert.deepEqual(strade[0].g[1], strade[1].g[0]);
});

test('sul bordo della tessera il viadotto non si unisce alla rampa a terra che gli passa sotto', () => {
  // Il bordo (x = 4096) passa dove un viadotto al terzo livello corre sopra
  // una rampa a terra, a un pixel e mezzo in pianta: ognuno col suo seguito.
  const viadotto = { class: 'trunk', brunnel: 'bridge', layer: 3, ramp: 1 };
  const rampa = { class: 'motorway', ramp: 1 };
  const strade = [
    { p: viadotto, g: [[3000, 1000], [4096, 1000]] },
    { p: viadotto, g: [[4096, 1001], [5200, 1000]] },
    { p: rampa, g: [[3000, 1003], [4096, 1002.5]] },
    { p: rampa, g: [[4096, 1002], [5200, 1100]] },
  ];
  assert.equal(uniscIBordi(strade), 2);
  assert.deepEqual(strade[0].g[1], strade[1].g[0]);
  assert.deepEqual(strade[2].g[1], strade[3].g[0]);
  assert.ok(Math.abs(strade[0].g[1][1] - strade[2].g[1][1]) > 1, 'i due capi restano dove sono');
  // E nel grafo la rampa resta a terra lontano dal viadotto.
  const g = grafoStrade(strade, metri);
  const L = ALTEZZA_LIVELLO;
  for (const n of g.nodi) if (Math.abs(n.x - 4096) < 300 && n.y < -1001.2) assert.ok(n.h < L, `la rampa sotto il viadotto (${n.x.toFixed(0)}, ${n.y.toFixed(1)}: ${n.h.toFixed(1)})`);
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

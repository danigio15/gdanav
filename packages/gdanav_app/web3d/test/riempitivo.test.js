// I blocchi e i filari della vista «Corsie» (`riempitivo.js`), su strade
// inventate in metri: nessun posto vero.
import assert from 'node:assert/strict';
import test from 'node:test';
import { alberiLungoLeStrade, bloccoTocca, blocchiLungoLeStrade, semeDi, siToccano } from '../src/riempitivo.js';
import { distanzaSegmento, puntoDentroPoligono } from '../src/ritaglio.js';

const quadrato = (cx, cy, l) => [
  [cx - l, cy - l],
  [cx + l, cy - l],
  [cx + l, cy + l],
  [cx - l, cy + l],
];

test('il seme di una strada: sempre lo stesso, diverso per strade diverse', () => {
  assert.equal(semeDi(12, 34, 1), semeDi(12, 34, 1));
  assert.notEqual(semeDi(12, 34, 1), semeDi(12, 34, -1));
  assert.notEqual(semeDi(12, 34), semeDi(34, 12));
});

test('quando due blocchi o un blocco e una strada si toccano', () => {
  assert.ok(siToccano(quadrato(0, 0, 5), quadrato(8, 0, 5)));
  assert.ok(!siToccano(quadrato(0, 0, 5), quadrato(11, 0, 5)));
  assert.ok(siToccano(quadrato(0, 0, 5), quadrato(11, 0, 5), 1.5), 'col margine sì');
  // Una strada che passa in mezzo (nessun capo dentro, nessun angolo vicino).
  assert.ok(bloccoTocca(quadrato(0, 0, 10), [-50, 0], [50, 0], 0.5));
  assert.ok(!bloccoTocca(quadrato(0, 0, 10), [-50, 20], [50, 20], 5));
  assert.ok(bloccoTocca(quadrato(0, 0, 10), [-50, 13], [50, 13], 4), 'vicina entro il margine');
});

/** Una via dritta da ovest a est, larga 8 m, con case ai due lati. */
const via = { pts: [[-200, 0], [200, 0]], mezza: 4, seme: 77 };

test('i blocchi lungo una via: ai due lati, arretrati, staccati, sempre gli stessi', () => {
  const blocchi = blocchiLungoLeStrade({ strade: [via], zona: () => 'residenziale' });
  assert.ok(blocchi.length >= 20, `${blocchi.length} blocchi`);
  assert.ok(blocchi.some((b) => b.pts[0][1] > 0) && blocchi.some((b) => b.pts[0][1] < 0), 'dai due lati');
  for (const b of blocchi) {
    assert.equal(b.pts.length, 4);
    // Oltre l'asfalto, il marciapiede e almeno un metro.
    for (const [, y] of b.pts) assert.ok(Math.abs(y) >= 4 + 2.5 + 1 - 1e-6, `troppo vicino: ${y}`);
    assert.ok(b.h >= 2 * 3.1 && b.h <= 6 * 3.1 + 0.6 + 1e-9, `altezza ${b.h}`);
  }
  for (let i = 0; i < blocchi.length; i++) for (let j = i + 1; j < blocchi.length; j++) assert.ok(!siToccano(blocchi[i].pts, blocchi[j].pts), 'due blocchi uno sull’altro');
  assert.deepEqual(blocchiLungoLeStrade({ strade: [via], zona: () => 'residenziale' }), blocchi, 'lo stesso seme, gli stessi blocchi');
});

test('mai su un edificio vero, una strada che incrocia, un parco; solo nella tessera', () => {
  const vero = [
    [-20, 8],
    [20, 8],
    [20, 25],
    [-20, 25],
  ];
  const traversa = { pts: [[60, -200], [60, 200]], mezza: 3.5, seme: 5 };
  const blocchi = blocchiLungoLeStrade({
    strade: [via],
    ostacoli: [via, traversa],
    edifici: [vero],
    // A sud un parco: lì niente case.
    zona: (x, y) => (y < 0 ? null : 'residenziale'),
    dentro: (x) => x < 150,
  });
  assert.ok(blocchi.length > 5);
  for (const b of blocchi) {
    assert.ok(b.pts.every(([, y]) => y > 0), 'niente nel parco');
    assert.ok(!siToccano(b.pts, vero), 'niente sull’edificio vero');
    assert.ok(!bloccoTocca(b.pts, traversa.pts[0], traversa.pts[1], 3.5), 'niente sulla traversa');
    const cx = b.pts.reduce((s, p) => s + p[0], 0) / 4;
    assert.ok(cx < 150, 'solo i blocchi di questa tessera');
  }
});

test('nelle zone industriali capannoni larghi e bassi, e più indietro', () => {
  const blocchi = blocchiLungoLeStrade({ strade: [via], zona: () => 'industriale' });
  assert.ok(blocchi.length > 3);
  for (const b of blocchi) {
    const largo = Math.hypot(b.pts[1][0] - b.pts[0][0], b.pts[1][1] - b.pts[0][1]);
    assert.ok(largo >= 22 * 0.9, `largo ${largo}`);
    assert.ok(b.h < 9, `basso ${b.h}`);
    for (const [, y] of b.pts) assert.ok(Math.abs(y) >= 4 + 2.5 + 5 - 1e-6);
  }
});

test('le corsie vere più larghe della strada spingono indietro i blocchi', () => {
  const stretti = blocchiLungoLeStrade({ strade: [via], zona: () => 'residenziale' });
  const larghi = blocchiLungoLeStrade({ strade: [via], zona: () => 'residenziale', mezzaQui: () => 9 });
  const vicino = (bb) => Math.min(...bb.flatMap((b) => b.pts.map(([, y]) => Math.abs(y))));
  assert.ok(vicino(larghi) >= 9 + 2.5 + 1 - 1e-6 && vicino(larghi) > vicino(stretti));
});

test('i filari: sul marciapiede, ogni dieci metri circa, non agli incroci né negli edifici', () => {
  const casa = quadrato(100, 8, 6);
  const alberi = alberiLungoLeStrade({
    strade: [via],
    incroci: [[0, 0]],
    occupato: (x, y) => puntoDentroPoligono(x, y, [casa]),
  });
  assert.ok(alberi.length > 40 && alberi.length < 100, `${alberi.length} alberi`);
  for (const [x, y, s] of alberi) {
    assert.ok(Math.abs(y) > 4 + 1.2 && Math.abs(y) < 4 + 2.5, `sul marciapiede: ${y}`);
    assert.ok(Math.hypot(x, y) >= 22, 'lontano dall’incrocio');
    assert.ok(!puntoDentroPoligono(x, y, [casa]));
    assert.ok(s > 0.4 && s < 0.7, 'alberi di città, piccoli');
    assert.ok(distanzaSegmento(x, y, -200, 0, 200, 0) > 4);
  }
  // Lungo un lato, uno ogni otto-dodici metri.
  const nord = alberi.filter(([, y]) => y > 0 && Math.abs(y) < 10).map(([x]) => x).sort((a, b) => a - b);
  for (let k = 1; k < nord.length; k++) {
    const d = nord[k] - nord[k - 1];
    assert.ok(d >= 8 - 1e-6, `troppo fitti: ${d}`);
  }
});

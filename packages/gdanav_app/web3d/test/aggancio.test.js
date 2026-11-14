import assert from 'node:assert/strict';
import test from 'node:test';
import { AggancioStrada } from '../src/aggancio.js';
import { IndiceSegmenti } from '../src/percorso.js';

// Una strada dritta verso nord (x = 0), a doppio senso.
const nordSud = { x0: 0, y0: -500, x1: 0, y1: 500, senso: 0 };

test('il GPS a 5, 10, 15 m di lato finisce sulla strada', () => {
  for (const lato of [5, -10, 15]) {
    const r = new AggancioStrada().aggancia(lato, 0, 2, 12, [nordSud]);
    assert.ok(r, `a ${lato} m`);
    assert.ok(Math.abs(r.x) < 1e-9 && Math.abs(r.y) < 1e-9);
    assert.ok(Math.abs(r.rotta) < 1e-9);
  }
});

test('troppo lontano, di traverso o contromano su un senso unico: niente', () => {
  assert.equal(new AggancioStrada().aggancia(30, 0, 0, 12, [nordSud]), null);
  assert.equal(new AggancioStrada().aggancia(5, 0, 90, 12, [nordSud]), null);
  assert.equal(new AggancioStrada().aggancia(5, 0, 180, 12, [{ ...nordSud, senso: 1 }]), null);
  const giu = new AggancioStrada().aggancia(5, 0, 181, 12, [nordSud]);
  assert.equal(Math.round(giu.rotta), 180);
});

test('fra due parallele a 20 m non salta, e passa quando si è davvero sull\'altra', () => {
  const prima = { x0: 0, y0: -500, x1: 0, y1: 1000, senso: 0 };
  const seconda = { x0: 20, y0: -500, x1: 20, y1: 1000, senso: 0 };
  const a = new AggancioStrada();
  [3, 8, 12, 6, 11, 4, 12.5, 9, 2, 11].forEach((lato, i) => {
    const r = a.aggancia(lato, i * 14, 0, 14, [seconda, prima]);
    assert.ok(Math.abs(r.x) < 1e-9, `lettura ${i}: resta sulla prima`);
  });
  let r;
  for (let i = 0; i < 3; i++) r = a.aggancia(18, 200 + i * 14, 0, 14, [seconda, prima]);
  assert.equal(r.x, 20);
});

test("all'incrocio la traversa più vicina non ruba l'auto", () => {
  const traversa = { x0: -300, y0: 0, x1: 300, y1: 0, senso: 0 };
  const a = new AggancioStrada();
  for (let y = -63; y <= 57; y += 12) assert.ok(Math.abs(a.aggancia(8, y, 0, 12, [traversa, nordSud]).x) < 1e-9, `a ${y} m`);
  assert.ok(Math.abs(a.aggancia(30, 4, 88, 8, [traversa, nordSud]).y) < 1e-9, 'svoltando si passa alla traversa');
});

test('le strade vicine dalle tessere costruite, senza i binari', () => {
  const i = new IndiceSegmenti();
  // x0 y0 z0 x1 y1 z1 larghezza codice: una strada a senso unico (128) e un binario (8).
  i.aggiungi('t', new Float32Array([0, -50, 0, 0, 50, 0, 7, 3 + 128, 10, -50, 0, 10, 50, 0, 4, 8]), 0, 0, 1);
  const v = i.vicini(4, 0, 25);
  assert.equal(v.length, 1);
  assert.equal(v[0].senso, 1);
  const r = new AggancioStrada().aggancia(4, 0, 0, 10, v);
  assert.equal(r.x, 0);
});

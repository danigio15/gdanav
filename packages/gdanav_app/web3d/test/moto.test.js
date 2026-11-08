import assert from 'node:assert/strict';
import test from 'node:test';
import { Moto, angoloVerso, smorza } from '../src/moto.js';

test('smorza e angoloVerso', () => {
  assert.equal(smorza(0, 10, 0, 100), 0);
  assert.ok(smorza(0, 10, 100, 100) > 6);
  assert.equal(angoloVerso(350, 10, 0.5), 0);
  assert.equal(angoloVerso(10, 350, 1), 350);
});

test("l'auto va avanti con la velocità fra una lettura e l'altra", () => {
  const m = new Moto();
  m.posizione({ metri: 100, v: 20, quando: 0 });
  assert.equal(m.passo(0).s, 100);
  let s = 100;
  for (let t = 33; t <= 1000; t += 33) s = m.passo(t).s;
  assert.ok(s > 105 && s <= 120, `avanti (${s})`);
});

test('non torna mai indietro per poco, salta per tanto', () => {
  const m = new Moto();
  m.posizione({ metri: 100, v: 0, quando: 0 });
  m.passo(0);
  m.posizione({ metri: 95, v: 0, quando: 100 });
  assert.equal(m.passo(200).s, 100, 'resta lì');
  m.posizione({ metri: 400, v: 0, quando: 300 });
  assert.equal(m.passo(300).s, 400, 'salta avanti');
});

test('ferma e arrivata', () => {
  const m = new Moto();
  assert.ok(m.fermo);
  m.posizione({ metri: 10, v: 0, quando: 0 });
  m.passo(0);
  assert.ok(m.fermo);
  m.posizione({ metri: 10, v: 5, quando: 0 });
  assert.ok(!m.fermo);
});

test('senza percorso: x, y e la rotta', () => {
  const m = new Moto();
  m.posizione({ metri: null, v: 10, x: 0, y: 0, rotta: 90, quando: 0 });
  const p = m.passo(1000);
  assert.ok(Math.abs(p.x - 10) < 1e-6 && Math.abs(p.y) < 1e-6);
});

import assert from 'node:assert/strict';
import test from 'node:test';
import { marginiAiLati } from '../src/geo.js';

test("l'auto sta in mezzo alla parte libera, anche quando è meno di metà schermo", () => {
  // Lo schermo intero: le schede di Android Auto a sinistra, per un terzo.
  assert.deepEqual(marginiAiLati(300, 0, 900), [300, 0]);
  // Lo schermo diviso, con la mappa in un pannello stretto: la parte libera è
  // il 38% a sinistra. Tagliando ogni lato a 0,45 l'auto finiva al 27% invece
  // che al 19%, fuori dal mezzo della parte libera.
  const [s, d] = marginiAiLati(0, 558, 900);
  assert.equal(s, 0);
  assert.equal(d, 558);
  assert.ok(Math.abs((s + (900 - d)) / 2 - 171) < 1e-9, 'il mezzo della parte libera');
  // Misure sbagliate (più della superficie): tagliate insieme, in proporzione.
  const [a, b] = marginiAiLati(900, 300, 900);
  assert.ok(Math.abs(a + b - 630) < 1e-9);
  assert.ok(Math.abs(a / b - 3) < 1e-9);
  assert.deepEqual(marginiAiLati(Number.NaN, -5, 900), [0, 0]);
});

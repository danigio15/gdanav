import assert from 'node:assert/strict';
import test from 'node:test';
import { codaDi, marginiAiLati } from '../src/geo.js';

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

test('la coda di una traccia: gli ultimi metri, non tutta', () => {
  // Diecimila punti verso est, uno ogni otto metri circa all'equatore.
  const passo = 8 / 111195;
  const lonlat = [];
  for (let i = 0; i < 10000; i++) lonlat.push(i * passo, 0);
  const c = codaDi(lonlat, 1800);
  assert.equal(c.length % 2, 0);
  assert.deepEqual(c.slice(-2), lonlat.slice(-2), "finisce dove finisce la traccia");
  const metri = (c.at(-2) - c[0]) * 111195;
  assert.ok(metri >= 1799.9 && metri < 1820, `${metri}`);
  // Più corta: tutta.
  assert.equal(codaDi(lonlat.slice(0, 40), 1800).length, 40);
  assert.deepEqual(codaDi([], 100), []);
});

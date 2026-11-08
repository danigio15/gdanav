import assert from 'node:assert/strict';
import test from 'node:test';
import { BUDGET, daDisegnare, distanzaTessera, pianoTessere } from '../src/budget.js';

const T = (chiave, cx, cy) => ({ chiave, cx, cy, lato: 1700 });

test('la distanza da una tessera: zero dentro', () => {
  assert.equal(distanzaTessera(0, 0, 0, 0, 1700), 0);
  assert.equal(distanzaTessera(1850, 0, 0, 0, 1700), 1000);
});

test('vicino pieno, lontano ridotto, oltre niente; prima le vicine', () => {
  const d = [T('lontana', 6000, 0), T('media', 2700, 0), T('qui', 0, 0)];
  const p = pianoTessere(d, new Map(), 0, 0);
  assert.deepEqual(p.richieste.map((r) => [r.chiave, r.dettaglio]), [['qui', 'pieno'], ['media', 'ridotto']]);
});

test('una ridotta si rifà piena quando ci si avvicina', () => {
  const costruite = new Map([['qui', { ...T('qui', 0, 0), dettaglio: 'ridotto', triangoli: 1000 }]]);
  const p = pianoTessere([T('qui', 0, 0)], costruite, 0, 0);
  assert.equal(p.richieste[0].dettaglio, 'pieno');
  const ok = pianoTessere([T('qui', 0, 0)], new Map([['qui', { ...T('qui', 0, 0), dettaglio: 'pieno', triangoli: 1 }]]), 0, 0);
  assert.equal(ok.richieste.length, 0);
});

test('le lontane si buttano, e oltre il budget dei triangoli', () => {
  const costruite = new Map([
    ['qui', { ...T('qui', 0, 0), dettaglio: 'pieno', triangoli: 500000 }],
    ['via', { ...T('via', 20000, 0), dettaglio: 'pieno', triangoli: 10 }],
    ['troppo', { ...T('troppo', 5000, 0), dettaglio: 'ridotto', triangoli: 600000 }],
  ]);
  const p = pianoTessere([], costruite, 0, 0, { ...BUDGET, triangoli: 900000 });
  assert.deepEqual(p.butta.sort(), ['troppo', 'via']);
});

test('si disegnano le vicine finché stanno nel budget', () => {
  const costruite = new Map([
    ['a', { ...T('a', 0, 0), triangoli: 600000 }],
    ['b', { ...T('b', 1700, 0), triangoli: 400000 }],
  ]);
  const d = daDisegnare(costruite, 0, 0, { ...BUDGET, triangoli: 900000 });
  assert.deepEqual([...d.si], ['a']);
});

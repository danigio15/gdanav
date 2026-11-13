import assert from 'node:assert/strict';
import test from 'node:test';
import { Condivise, dallaScorta, nellaScorta } from '../src/scorte.js';

test('le tele hanno un tetto: se ne va la meno usata di recente', () => {
  const s = new Map();
  nellaScorta(s, 'a', 1, 2);
  nellaScorta(s, 'b', 2, 2);
  // «a» usata adesso: torna fra le recenti, e oltre il tetto se ne va «b».
  assert.equal(dallaScorta(s, 'a'), 1);
  nellaScorta(s, 'c', 3, 2);
  assert.deepEqual([...s.keys()], ['a', 'c']);
  assert.equal(dallaScorta(s, 'b'), undefined);
  // Guidando per ore non cresce mai oltre il tetto.
  for (let i = 0; i < 1000; i++) nellaScorta(s, `nome ${i}`, i, 120);
  assert.equal(s.size, 120);
});

test('una trama per immagine, contata: si butta quando nessun segno la usa più', () => {
  const buttate = [];
  const t = new Condivise((img) => ({ img }), (x) => buttate.push(x.img));
  const a = t.prendi('autovelox');
  assert.equal(t.prendi('autovelox'), a, 'due segni con la stessa icona: una trama');
  t.prendi('bandiera');
  t.lascia('autovelox');
  assert.deepEqual(buttate, [], 'un segno la usa ancora');
  t.lascia('autovelox');
  assert.deepEqual(buttate, ['autovelox']);
  assert.equal(t.size, 1);
  t.lascia('mai vista');
  assert.notEqual(t.prendi('autovelox'), a, 'ritorna: una trama nuova');
});

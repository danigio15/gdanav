import assert from 'node:assert/strict';
import { test } from 'node:test';

import { leggiRiquadro, richiestaOverpass, rispostaBuona } from '../src/colonnine.js';

test('il riquadro dal percorso', () => {
  assert.deepEqual(leggiRiquadro('GET', 'https://r.dev/v1/colonnine/90/18'), { riga: 90, colonna: 18 });
  assert.deepEqual(leggiRiquadro('GET', 'https://r.dev/v1/colonnine/-68/-1'), { riga: -68, colonna: -1 });
  assert.equal(leggiRiquadro('POST', 'https://r.dev/v1/colonnine/90/18').stato, 405);
  assert.equal(leggiRiquadro('GET', 'https://r.dev/v1/colonnine/90').stato, 404);
  assert.equal(leggiRiquadro('GET', 'https://r.dev/v1/colonnine/200/18').stato, 400);
});

test('la richiesta a Overpass copre il mezzo grado', () => {
  const q = richiestaOverpass(90, 18);
  assert.ok(q.startsWith('[out:json]'));
  assert.ok(q.includes('(45,9,45.5,9.5)'));
  assert.equal(q.match(/nwr/g).length, 3);
});

test('una risposta in tempo scaduto non è «nessuna colonnina»', () => {
  assert.ok(rispostaBuona('{"elements":[]}'));
  assert.ok(!rispostaBuona('{"remark":"runtime error: Query timed out","elements":[]}'));
  assert.ok(!rispostaBuona('<html>too many requests</html>'));
});

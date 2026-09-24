import assert from 'node:assert/strict';
import { test } from 'node:test';

import { DURATA_CODICE_MS, bustaValida, codiceVivo, leggiIndirizzoCodice } from '../src/codici.js';

const id = 'Aokg8cEJWWLnEZN4Bfqk3Q';

test("l'indirizzo dei codici", () => {
  assert.deepEqual(leggiIndirizzoCodice('GET', `https://r.dev/v1/codici/${id}`), { azione: 'prendi', id });
  assert.deepEqual(leggiIndirizzoCodice('PUT', `https://r.dev/v1/codici/${id}`), { azione: 'lascia', id });
  assert.equal(leggiIndirizzoCodice('DELETE', `https://r.dev/v1/codici/${id}`).stato, 405);
  assert.equal(leggiIndirizzoCodice('GET', 'https://r.dev/v1/codici/corto').stato, 404);
  assert.equal(leggiIndirizzoCodice('GET', `https://r.dev/v1/codici/${id}/altro`).stato, 404);
});

test('solo buste piccole e fatte bene', () => {
  assert.ok(bustaValida('{"v":1,"n":"AAEC","c":"xyz"}'));
  assert.ok(!bustaValida('{"v":2,"n":"AAEC","c":"xyz"}'));
  assert.ok(!bustaValida('non json'));
  assert.ok(!bustaValida(`{"v":1,"n":"A","c":"${'x'.repeat(3000)}"}`));
  assert.ok(!bustaValida(undefined));
});

test('dieci minuti di vita', () => {
  const salvato = { busta: '{}', scade: 1000 + DURATA_CODICE_MS };
  assert.ok(codiceVivo(salvato, 1000));
  assert.ok(!codiceVivo(salvato, 1000 + DURATA_CODICE_MS));
  assert.ok(!codiceVivo(undefined, 1000));
});

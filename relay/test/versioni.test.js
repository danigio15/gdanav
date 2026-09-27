import assert from 'node:assert/strict';
import { test } from 'node:test';

import { DURATA_CACHE_VERSIONI_S, versioneMinima, versioni } from '../src/versioni.js';

const chiedi = (metodo = 'GET') => new Request('https://r.dev/v1/versioni', { method: metodo });

test('la versione minima: di base 0, nessun blocco', async () => {
  const r = versioni(chiedi(), {});
  assert.equal(r.status, 200);
  assert.deepEqual(await r.json(), { gdanav: { minima: 0 } });
});

test('la versione minima viene da VERSIONE_MINIMA_APP', async () => {
  const r = versioni(chiedi(), { VERSIONE_MINIMA_APP: '412' });
  assert.deepEqual(await r.json(), { gdanav: { minima: 412 } });
  assert.equal(r.headers.get('content-type'), 'application/json');
  assert.equal(r.headers.get('access-control-allow-origin'), '*');
  assert.equal(r.headers.get('cache-control'), `public, max-age=${DURATA_CACHE_VERSIONI_S}`);
  assert.ok(DURATA_CACHE_VERSIONI_S <= 600);
});

test('valori strani non bloccano nessuno', () => {
  for (const v of ['', 'abc', '-3', '1.5', '99999999999', undefined, null]) {
    assert.equal(versioneMinima({ VERSIONE_MINIMA_APP: v }), 0, String(v));
  }
  assert.equal(versioneMinima({ VERSIONE_MINIMA_APP: ' 7 ' }), 7);
  assert.equal(versioneMinima({ VERSIONE_MINIMA_APP: 9 }), 9);
  assert.equal(versioneMinima(undefined), 0);
});

test('CORS e metodi', async () => {
  const pre = versioni(chiedi('OPTIONS'), {});
  assert.equal(pre.status, 204);
  assert.equal(pre.headers.get('access-control-allow-origin'), '*');
  const post = versioni(chiedi('POST'), {});
  assert.equal(post.status, 405);
});

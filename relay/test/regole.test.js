import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

import { MASSIMO_APP, destinatari, impronta, leggiRichiesta, presenza, puoEntrare } from '../src/regole.js';

const vettore = JSON.parse(readFileSync(new URL('../../docs/vettore_prova.json', import.meta.url)));
const base = 'wss://relay.esempio.dev';

test("legge l'indirizzo scritto da app e casa", () => {
  const r = leggiRichiesta(`${base}/v1/canale/${vettore.canale}?ruolo=casa&accesso=${vettore.accesso}`);
  assert.deepEqual(r, { canale: vettore.canale, ruolo: 'casa', accesso: vettore.accesso });
});

test('rifiuta indirizzi sbagliati', () => {
  const ok = `ruolo=app&accesso=${vettore.accesso}`;
  assert.equal(leggiRichiesta(`${base}/altro`).stato, 404);
  assert.equal(leggiRichiesta(`${base}/v1/canale/corto?${ok}`).stato, 400);
  assert.equal(leggiRichiesta(`${base}/v1/canale/${vettore.canale}?ruolo=ospite&accesso=${vettore.accesso}`).stato, 400);
  assert.equal(leggiRichiesta(`${base}/v1/canale/${vettore.canale}?ruolo=app`).stato, 400);
  assert.equal(leggiRichiesta(`${base}/v1/canale/${vettore.canale}?ruolo=app&accesso=x`).stato, 400);
});

test('la prima casa crea la stanza', () => {
  assert.deepEqual(puoEntrare({ improntaSalvata: null, improntaNuova: 'a', ruolo: 'casa', appCollegate: 0 }), {
    ok: true,
    salva: true,
  });
});

test("un'app non crea stanze", () => {
  const e = puoEntrare({ improntaSalvata: null, improntaNuova: 'a', ruolo: 'app', appCollegate: 0 });
  assert.equal(e.ok, false);
  assert.equal(e.stato, 404);
});

test('con un altro gettone non si entra, nemmeno come casa', () => {
  for (const ruolo of ['casa', 'app']) {
    const e = puoEntrare({ improntaSalvata: 'a', improntaNuova: 'b', ruolo, appCollegate: 0 });
    assert.equal(e.stato, 403);
  }
});

test('i telefoni per auto sono limitati', () => {
  const ok = puoEntrare({ improntaSalvata: 'a', improntaNuova: 'a', ruolo: 'app', appCollegate: MASSIMO_APP - 1 });
  const troppi = puoEntrare({ improntaSalvata: 'a', improntaNuova: 'a', ruolo: 'app', appCollegate: MASSIMO_APP });
  assert.equal(ok.ok, true);
  assert.equal(troppi.stato, 429);
});

test("l'impronta è SHA-256 in esadecimale e non è il gettone", async () => {
  const i = await impronta(vettore.accesso);
  assert.match(i, /^[0-9a-f]{64}$/);
  assert.notEqual(i, vettore.accesso);
});

test('i messaggi vanno dall\'altra parte', () => {
  assert.equal(destinatari('casa'), 'app');
  assert.equal(destinatari('app'), 'casa');
});

test('la presenza ha la forma che leggono app e casa', () => {
  assert.deepEqual(JSON.parse(presenza('app', true)), { relay: 'presente', ruolo: 'app' });
  assert.deepEqual(JSON.parse(presenza('casa', false)), { relay: 'assente', ruolo: 'casa' });
});

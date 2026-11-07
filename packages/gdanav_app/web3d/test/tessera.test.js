import assert from 'node:assert/strict';
import test from 'node:test';
import { LIMITI, TIPI_STRADA, costruisciTessera, stimaTriangoli, bufferDellaTessera } from '../src/tessera.js';
import { cavalcavia } from './finte.js';

const X = 8605;
const Y = 5860;

test('una tessera con un cavalcavia: strade, ponte, piloni, edificio, alberi', () => {
  const t = costruisciTessera({ z: 14, x: X, y: Y, livelli: { '0,0': cavalcavia() } });
  assert.equal(t.chiave, `14/${X}/${Y}`);
  for (const k of Object.keys(t.strade)) assert.ok(TIPI_STRADA.includes(k));
  assert.ok(t.strade.motorway, 'il nastro dell’autostrada');
  assert.ok(t.opere && t.opere.indici.length > 0, 'parapetti e travi');
  assert.ok(t.capitelli.length / 16 > 3, 'i piloni sotto il ponte');
  assert.equal(t.conti.edificiFatti, 1);
  assert.ok(t.conti.alberi > 10, 'gli alberi nel parco');
  // I segmenti: il ponte a 7 m sopra l’autostrada, che resta a terra.
  const s = t.segmenti;
  let sopra = 0;
  let terra = 0;
  for (let i = 0; i < s.length; i += 8) {
    const mx = (s[i] + s[i + 3]) / 2;
    const my = (s[i + 1] + s[i + 4]) / 2;
    if (Math.abs(mx) < 3 && Math.abs(my) < 40) sopra = Math.max(sopra, s[i + 2]);
    if (Math.abs(my) < 1 && Math.abs(mx) > 20 && Math.abs(mx) < 200) terra = Math.max(terra, s[i + 2]);
  }
  assert.ok(sopra > 7, `il ponte in quota (${sopra})`);
  assert.ok(terra < 0.5, `l’autostrada a terra (${terra})`);
  // Nessun pilone in mezzo all’autostrada.
  for (let i = 0; i < t.fusti.length; i += 16) assert.ok(Math.abs(t.fusti[i + 13]) > 6, 'pilone fuori dalla carreggiata');
  assert.equal(t.conti.triangoli, stimaTriangoli(t));
  assert.ok(bufferDellaTessera(t).length > 10);
});

test('sempre la stessa tessera: gli alberi nascono negli stessi posti', () => {
  const a = costruisciTessera({ z: 14, x: X, y: Y, livelli: { '0,0': cavalcavia() } });
  const b = costruisciTessera({ z: 14, x: X, y: Y, livelli: { '0,0': cavalcavia() } });
  assert.deepEqual([...a.alberi.tronchi], [...b.alberi.tronchi]);
  const c = costruisciTessera({ z: 14, x: X + 1, y: Y, livelli: { '0,0': cavalcavia() } });
  assert.notDeepEqual([...a.alberi.tronchi.slice(0, 32)], [...c.alberi.tronchi.slice(0, 32)]);
});

test('ridotta: niente alberi né lampioni, meno triangoli', () => {
  const pieno = costruisciTessera({ z: 14, x: X, y: Y, livelli: { '0,0': cavalcavia() } });
  const ridotto = costruisciTessera({ z: 14, x: X, y: Y, livelli: { '0,0': cavalcavia() }, dettaglio: 'ridotto' });
  assert.equal(ridotto.conti.alberi, 0);
  assert.equal(ridotto.conti.lampioni, 0);
  assert.ok(ridotto.conti.triangoli < pieno.conti.triangoli);
  assert.equal(LIMITI.ridotto.alberi, 0);
});

test('i limiti: gli alberi non passano il tetto della tessera', () => {
  const t = costruisciTessera({ z: 14, x: X, y: Y, livelli: { '0,0': cavalcavia() }, limiti: { alberi: 5 } });
  assert.ok(t.conti.alberi <= 5);
});

test('senza la tessera di mezzo non si fa niente', () => {
  assert.throws(() => costruisciTessera({ z: 14, x: X, y: Y, livelli: {} }));
});

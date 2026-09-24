import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  DURATA_MIN,
  crea,
  leggiIndirizzo,
  leggiNuova,
  pubblica,
  viva,
  vota,
  zona,
  zoneVicine,
} from '../src/segnalazioni.js';

test('le zone sono una griglia di 0,2 gradi', () => {
  assert.equal(zona(45.4642, 9.19), '227_45');
  assert.equal(zona(-33.9, 18.4), '-170_92');
  const vicine = zoneVicine(45.4642, 9.19);
  assert.equal(vicine.length, 9);
  assert.ok(vicine.includes('227_45'));
  assert.ok(vicine.includes('226_44'));
  assert.ok(vicine.includes('228_46'));
});

test('una segnalazione nuova si controlla e si arrotonda', () => {
  assert.deepEqual(leggiNuova({ tipo: 'polizia', lat: 45.123456789, lon: 9.987654321 }), {
    tipo: 'polizia',
    lat: 45.12346,
    lon: 9.98765,
  });
  assert.ok(leggiNuova({ tipo: 'ufo', lat: 1, lon: 1 }).errore);
  assert.ok(leggiNuova({ tipo: 'polizia', lat: '1', lon: 1 }).errore);
  assert.ok(leggiNuova({ tipo: 'polizia', lat: 95, lon: 1 }).errore);
  assert.ok(leggiNuova(null).errore);
});

test('scade da sola, le conferme la allungano, le smentite la tolgono', () => {
  const ora = 1_000_000;
  const s = crea({ tipo: 'polizia', lat: 45, lon: 9 }, ora, '225_45~abcdefgh');
  assert.ok(viva(s, ora + (DURATA_MIN.polizia - 1) * 60_000));
  assert.ok(!viva(s, ora + (DURATA_MIN.polizia + 1) * 60_000));

  const confermata = vota(s, true, ora + 10 * 60_000);
  assert.equal(confermata.conferme, 1);
  assert.ok(confermata.scade > s.scade);

  const unaSmentita = vota(s, false, ora);
  assert.equal(unaSmentita.smentite, 1);
  assert.equal(vota(unaSmentita, false, ora), null);
  // Con una conferma ne servono tre.
  let c = vota(confermata, false, ora);
  c = vota(c, false, ora);
  assert.notEqual(c, null);
  assert.equal(vota(c, false, ora), null);
});

test('al telefono va solo quello che serve', () => {
  const s = crea({ tipo: 'incidente', lat: 45, lon: 9 }, 5, 'z~abcdefgh');
  assert.deepEqual(Object.keys(pubblica(s)).sort(), ['conferme', 'creata', 'id', 'lat', 'lon', 'tipo']);
});

test('gli indirizzi delle segnalazioni', () => {
  const base = 'https://relay.esempio.dev';
  assert.deepEqual(leggiIndirizzo('GET', `${base}/v1/segnalazioni?lat=45.1&lon=9.2`), {
    azione: 'elenco',
    lat: 45.1,
    lon: 9.2,
  });
  assert.equal(leggiIndirizzo('GET', `${base}/v1/segnalazioni`).stato, 400);
  assert.deepEqual(leggiIndirizzo('POST', `${base}/v1/segnalazioni`), { azione: 'nuova' });
  assert.deepEqual(leggiIndirizzo('POST', `${base}/v1/segnalazioni/227_45~abcdefgh12/voto`), {
    azione: 'voto',
    zona: '227_45',
    id: '227_45~abcdefgh12',
  });
  assert.equal(leggiIndirizzo('POST', `${base}/v1/segnalazioni/xx~abcdefgh12/voto`).stato, 400);
  assert.equal(leggiIndirizzo('DELETE', `${base}/v1/segnalazioni`).stato, 405);
  assert.equal(leggiIndirizzo('GET', `${base}/altro`).stato, 404);
});
